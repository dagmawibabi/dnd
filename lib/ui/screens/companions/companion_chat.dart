import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../story/story_extras.dart';
import '../../../data/modules.dart';
import '../../../data/tales/tales.dart';
import '../../../models/companion.dart';
import '../../../models/world.dart';
import '../../../services/ai/companion_ai.dart';
import '../../../services/companion_life.dart';
import '../../../services/companion_store.dart';
import '../../../services/image_service.dart';
import '../../../services/narrator.dart';
import '../../../services/settings.dart';
import '../../../theme/ui.dart';
import '../../widgets/image_attach.dart';
import '../../widgets/voice_input_button.dart';
import '../adventure/new_adventure_screen.dart';
import '../tales/tales_hub.dart';
import 'companion_profile.dart';
import 'companions_screen.dart';

/// Texting with a companion.
class CompanionChatScreen extends StatefulWidget {
  const CompanionChatScreen({super.key, required this.companionId});
  final String companionId;

  @override
  State<CompanionChatScreen> createState() => _CompanionChatScreenState();
}

class _CompanionChatScreenState extends State<CompanionChatScreen> {
  final _input = TextEditingController();
  final _pics = PendingImages();
  bool _busy = false;
  bool _painting = false;
  String? _error;
  Narrator? _narrator;
  String? Function(String)? _prevVoice;
  String Function(String)? _prevGender;
  void Function(String, String)? _prevAssign;

  Companion? get _c => CompanionStore.instance.byId(widget.companionId);

  @override
  void initState() {
    super.initState();
    final c = _c;
    if (c != null && c.unread) {
      c.unread = false;
      CompanionStore.instance.changed();
    }
    // Their replies are read in their own voice while this chat is open.
    final n = _narrator = context.read<Narrator>();
    _prevVoice = n.voiceResolver;
    _prevGender = n.genderResolver;
    _prevAssign = n.onAutoAssign;
    n
      ..voiceResolver = ((s) => s == _c?.name && (_c?.voice.isNotEmpty ?? false) ? _c!.voice : _prevVoice?.call(s))
      ..genderResolver = ((s) => s == _c?.name ? (_c?.gender ?? '') : (_prevGender?.call(s) ?? ''))
      ..onAutoAssign = (s, v) {
        final c = _c;
        if (c != null && s == c.name && c.voice.isEmpty) {
          c.voice = v;
          CompanionStore.instance.changed();
        } else {
          _prevAssign?.call(s, v);
        }
      };
  }

  @override
  void dispose() {
    _narrator
      ?..voiceResolver = _prevVoice
      ..genderResolver = _prevGender
      ..onAutoAssign = _prevAssign;
    _input.dispose();
    _pics.dispose();
    super.dispose();
  }

  Future<void> _send([String? text]) async {
    final c = _c;
    final line = (text ?? _input.text).trim();
    final pics = _pics.take();
    if (c == null || _busy || (line.isEmpty && pics.isEmpty)) return;
    _input.clear();
    final life = context.read<CompanionLife>();
    final images = context.read<ImageService>();
    final settings = context.read<SettingsController>();
    final narrator = context.read<Narrator>();
    final said = line.isEmpty ? '(sends a picture)' : line;
    c.chat.add(ChatLine(fromPlayer: true, text: said, images: pics));
    CompanionStore.instance.changed();
    setState(() {
      _busy = true;
      _error = null;
    });
    if (!life.canTalk) {
      c.chat.add(ChatLine(fromPlayer: false, text: '*${c.name} smiles.* (Add an AI key in Settings so I can really talk.)'));
      CompanionStore.instance.changed();
      setState(() => _busy = false);
      return;
    }
    try {
      final seen = pics.isEmpty ? const <String>[] : await images.dataUrls(pics);
      final r = await life.ai.reply(c, said, player: settings.playerName.isEmpty ? 'You' : settings.playerName, images: seen, ownStories: life.ownStories());
      CompanionAi.applyBond(c, r, 'Chatting: "${said.length > 50 ? '${said.substring(0, 50)}…' : said}"');
      var sent = <String>[];
      if (r.picture.isNotEmpty) {
        if (mounted) setState(() => _painting = true);
        final p = await life.paintPicture(c, r.picture);
        if (p != null) sent = [p];
      }
      c.chat.add(ChatLine(fromPlayer: false, text: r.text, tokens: r.tokens, cost: r.cost, images: sent, suggest: r.suggest));
      CompanionStore.instance.changed();
      if (c.speaks && settings.ttsEnabled && settings.speakChatReplies) narrator.say(r.text, speaker: c.name);
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _painting = false;
        });
      }
    }
  }

  void _openSuggestion(String title) {
    final t = title.toLowerCase();
    final module = adventureModules.where((m) => m.title.toLowerCase() == t || t.contains(m.title.toLowerCase())).firstOrNull;
    if (module != null) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => NewAdventureScreen(moduleId: module.id, companionIds: [widget.companionId])));
      return;
    }
    final tale = talePresets.any((p) => p.title.toLowerCase() == t || t.contains(p.title.toLowerCase()));
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => tale ? const TalesHub() : NewAdventureScreen(companionIds: [widget.companionId])));
  }

  @override
  Widget build(BuildContext context) {
    context.watch<CompanionStore>();
    final c = _c;
    if (c == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('This companion is gone.')));
    final settings = context.watch<SettingsController>();
    final spent = c.chat.fold<int>(0, (n, l) => n + l.tokens);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CompanionProfileScreen(companionId: c.id))),
          child: Row(children: [
            CompanionAvatar(companion: c, size: 36),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(c.name, style: T.h3(), overflow: TextOverflow.ellipsis),
                Text([c.bond.label, if (spent > 0) '${_k(spent)} tokens'].join(' · '), style: T.caption(), overflow: TextOverflow.ellipsis),
              ]),
            ),
          ]),
        ),
        actions: [
          IconButton(
            tooltip: 'Go on an adventure together',
            icon: const Icon(Icons.explore_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NewAdventureScreen(companionIds: [c.id]))),
          ),
          IconButton(tooltip: 'Profile', icon: const Icon(Icons.person_outline), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CompanionProfileScreen(companionId: c.id)))),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: ListView(reverse: true, padding: const EdgeInsets.all(16), children: [
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('No reply: $_error', style: T.small(color: AppColors.danger))),
            if (_busy)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(_painting ? '${c.name} is sending a picture…' : '${c.name} is typing…', style: T.bodyMuted()),
              ),
            for (final l in c.chat.reversed) _bubble(c, l, settings),
            if (c.chat.isEmpty && !_busy)
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Column(children: [
                  CompanionAvatar(companion: c, size: 84),
                  const SizedBox(height: 12),
                  Text('Say hi to ${c.name}', style: T.h3()),
                  const SizedBox(height: 4),
                  Text(c.subtitle, style: T.small()),
                  const SizedBox(height: 14),
                  CompactChips(child: Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
                    for (final s in ['Hey! How are you?', 'What should we play next?', 'Tell me about yourself.', 'Send me a selfie!'])
                      ActionChip(label: Text(s), onPressed: () => _send(s)),
                  ])),
                ]),
              ),
          ]),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const NowReading(),
              PendingImagesStrip(pending: _pics),
              ComposerBuilder(
                controller: _input,
                builder: (context, typing) => Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      style: T.body(),
                      minLines: 1,
                      maxLines: typing ? 6 : 1,
                      textInputAction: TextInputAction.send,
                      decoration: InputDecoration(
                        hintText: 'Message ${c.name.split(' ').first}',
                        suffixIcon: typing ? null : AttachImageButton(pending: _pics, flat: true, enabled: !_busy, model: settings.textModel),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (!typing) ...[
                    VoiceInputButton(controller: _input, onSubmit: _send, enabled: !_busy),
                    if (settings.voiceInput) const SizedBox(width: 8),
                  ],
                  CircleIconButton(icon: Icons.arrow_upward, size: 44, tooltip: 'Send', onPressed: _busy ? null : _send),
                ]),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _bubble(Companion c, ChatLine l, SettingsController settings) {
    final me = l.fromPlayer;
    return Align(
      alignment: me ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(crossAxisAlignment: me ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
        if (l.opener.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.waving_hand_outlined, size: 13, color: AppColors.accent),
              const SizedBox(width: 6),
              Text('${c.name.split(' ').first} · ${l.opener.toLowerCase()}', style: T.caption(color: AppColors.accent)),
            ]),
          ),
        if (l.images.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: SentImages(paths: l.images, size: me ? 120 : 200, alignEnd: me)),
        GestureDetector(
          onLongPress: () {
            Clipboard.setData(ClipboardData(text: l.text));
            showToast(context, 'Copied');
          },
          onTap: me ? null : () => context.read<Narrator>().speakNow(l.text, speaker: c.name),
          child: Container(
            margin: const EdgeInsets.only(top: 6, bottom: 2),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: const BoxConstraints(maxWidth: 320),
            decoration: BoxDecoration(color: me ? AppColors.text : AppColors.surface2, borderRadius: BorderRadius.circular(16)),
            child: Text(l.text, style: T.body(color: me ? AppColors.bg : AppColors.text)),
          ),
        ),
        if (l.suggest.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: ActionChip(avatar: const Icon(Icons.explore_outlined, size: 16), label: Text('Play "${l.suggest}"'), onPressed: () => _openSuggestion(l.suggest)),
          ),
        if (!me && l.tokens > 0)
          Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('${_k(l.tokens)} tokens${l.cost > 0 ? ' · \$${l.cost.toStringAsFixed(4)}' : ''}', style: T.caption())),
      ]),
    );
  }

  static String _k(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';
}
