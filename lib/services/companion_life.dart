import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/companion.dart';
import '../models/world.dart';
import 'ai/companion_ai.dart';
import 'app_lifecycle.dart';
import 'companion_store.dart';
import 'game_store.dart';
import 'image_service.dart';
import 'settings.dart';
import 'tale_store.dart';

/// Companions between conversations: their pictures, and the messages they
/// send on their own after some time apart.
class CompanionLife {
  CompanionLife({required this.settings, required this.store, this.images, this.games, this.tales});

  final SettingsController settings;
  final CompanionStore store;
  final ImageService? images;
  final GameStore? games;
  final TaleStore? tales;

  /// Shows "Name sent you a message" (set by the app).
  void Function(Companion c, ChatLine line)? onText;

  bool _checking = false;
  DateTime? _lastCheck;

  CompanionAi get ai => CompanionAi(settings);

  bool get canTalk => settings.hasApiKey && settings.canUse(settings.fastModel.isEmpty ? settings.textModel : settings.fastModel);

  /// Titles of the player's own stories, so companions can talk about them.
  List<String> ownStories() => [
        for (final a in (games?.adventures ?? const []).take(6)) a.title,
        for (final t in (tales?.tales ?? const []).take(6)) t.title,
      ];

  void start() {
    AppLifecycle.instance.addResumeListener(() => unawaited(checkIn()));
    Future.delayed(const Duration(seconds: 20), () => unawaited(checkIn()));
  }

  /// How long before [c] texts first: 6 to 20 hours, steady per companion.
  static Duration patience(Companion c) => Duration(hours: 6 + c.id.hashCode.abs() % 15);

  static DateTime lastContact(Companion c) => c.chat.isEmpty ? (c.lastTextAt ?? c.created) : c.chat.last.at;

  /// Lets the companion who has waited longest send a message, if it's time.
  Future<void> checkIn({bool force = false}) async {
    if (_checking || !canTalk) return;
    final now = DateTime.now();
    if (!force && _lastCheck != null && now.difference(_lastCheck!) < const Duration(minutes: 10)) return;
    _lastCheck = now;
    final due = [
      for (final c in store.companions)
        if (c.proactive && !c.unread && (force || now.difference(lastContact(c)) > patience(c))) c,
    ]..sort((a, b) => lastContact(a).compareTo(lastContact(b)));
    if (due.isEmpty) return;
    _checking = true;
    final c = due.first;
    try {
      final r = await ai.opener(c, player: _player, since: now.difference(lastContact(c)), ownStories: ownStories());
      final pics = r.picture.isEmpty ? const <String>[] : [?await paintPicture(c, r.picture)];
      final line = ChatLine(fromPlayer: false, text: r.text, opener: 'Texted you', tokens: r.tokens, cost: r.cost, images: pics, suggest: r.suggest);
      c.chat.add(line);
      CompanionAi.applyBond(c, r, 'Reached out to you');
      c
        ..unread = true
        ..lastTextAt = now;
      store.changed();
      onText?.call(c, line);
    } catch (e) {
      debugPrint('Companion check-in failed: $e');
    } finally {
      _checking = false;
    }
  }

  String get _player => settings.playerName.isEmpty ? 'the player' : settings.playerName;

  /// A picture [c] sends, drawn to look like them.
  Future<String?> paintPicture(Companion c, String prompt) async {
    final img = images;
    if (img == null || !settings.canPaint) return null;
    final avatar = c.portrait.aiImagePath;
    return img.generate(
      'companion_pic_${c.id}_${DateTime.now().millisecondsSinceEpoch}',
      '$prompt\n${c.name}${c.appearance.isEmpty ? '' : ' looks like this: ${c.appearance}'}',
      category: 'companion',
      references: [if (avatar != null && avatar.isNotEmpty) (c.name, avatar)],
    );
  }

  /// Paints a new avatar for [c] and makes it current (older ones are kept).
  Future<String?> paintAvatar(Companion c) async {
    final img = images;
    if (img == null) return null;
    final what = c.kind.isEmpty || c.kind.toLowerCase() == 'human' ? 'a person' : 'a ${c.kind.toLowerCase()}';
    final path = await img.generate(
      'comp_avatar_${c.id}_${DateTime.now().millisecondsSinceEpoch}',
      'Portrait of ${c.name}, $what. ${c.appearance.isEmpty ? c.personality : c.appearance}. Friendly, characterful, expressive.',
      category: 'companion',
    );
    if (path != null) setAvatar(c, path);
    return path;
  }

  void setAvatar(Companion c, String path) {
    c.portrait.aiImagePath = path;
    if (!c.avatars.contains(path)) c.avatars.add(path);
    store.changed();
  }
}
