import 'package:flutter/foundation.dart';

import '../models/adventure.dart';
import '../models/world.dart';
import '../services/image_service.dart';
import '../services/narrator.dart';
import '../services/settings.dart';

/// What the shared story tools (people, chat, memory, gallery, map, AI tools,
/// export) need from a running story. Implemented by the D&D adventure
/// controller and the text adventure controller.
abstract class StoryHost implements Listenable {
  String get storyId;
  String get storyTitle;

  /// "High Fantasy · Heroic" or "Sci-fi".
  String get storySubtitle;
  StoryRecord get record;
  WorldData get world;
  List<Npc> get people;
  String get playerName;
  List<CanonEntry> get canon;
  String get summary;
  set summary(String value);
  Map<String, num> get usageTotals;
  List<LogEntry> get log;
  SceneInfo get scene;
  MapState? get map;
  int get turns;
  bool get isAi;
  bool get busy;
  SettingsController get settings;
  ImageService? get images;
  Narrator? get narrator;

  /// Compact state of the story for AI tools.
  String get aiContext;

  /// Genre or setting guidance for characters and art.
  String get worldStyle;

  /// Illustration style for this story's images.
  String get artStyle;

  Future<ChatLine> talkTo(Npc npc, String line);
  String portraitKey(Npc npc);
  Future<void> paintPortrait(Npc npc);
  Future<void> paintScene();
  Future<void> filmScene();
  Future<void> generateMapImage();
  bool canTravelTo(MapLocation location);
  Future<void> travelTo(MapLocation location);

  /// Adds someone the player wants to talk to (or finds an existing match).
  Npc meet(String name, {String role = '', String description = ''});

  /// Sends a free-text action to the story.
  Future<void> act(String text);

  /// Paints (or films) a passage of the story into the feed.
  Future<void> illustrate(String text, {bool video = false});

  /// Whether the last AI turn can be written again.
  bool get canRegenerate;

  /// Undoes the last turn and asks the AI again with the same action.
  Future<void> regenerate();
  void note(String text);
  void save();
  void refresh();
}

/// Recent prose of a story, oldest first, for AI tools.
String recentStory(List<LogEntry> log, {int entries = 10, int maxChars = 2400}) {
  final picked = <String>[];
  var chars = 0;
  for (final e in log.reversed) {
    final line = switch (e.kind) {
      LogKind.narration => e.text,
      LogKind.dialogue || LogKind.companion => '${e.speaker ?? 'Someone'}: ${e.text}',
      LogKind.player => '> ${e.text}',
      LogKind.system when e.meta['scene'] != null => '[${e.text}]',
      _ => null,
    };
    if (line == null) continue;
    chars += line.length;
    if (chars > maxChars || picked.length >= entries) break;
    picked.add(line);
  }
  return picked.reversed.join('\n');
}
