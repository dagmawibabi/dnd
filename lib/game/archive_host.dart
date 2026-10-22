import 'package:flutter/foundation.dart';

import '../data/tale_genres.dart';
import '../models/adventure.dart';
import '../models/companion.dart';
import '../models/tale.dart';
import '../models/world.dart';
import '../services/ai/ai_trace.dart';
import '../services/ai/dungeon_master.dart' show dmStateBlock;
import '../services/ai/tale_narrator.dart' show taleStateBlock;
import '../services/image_service.dart';
import '../services/companion_store.dart';
import '../services/narrator.dart';
import '../services/settings.dart';
import 'story_host.dart';

/// A saved story seen from outside (its cover page, the character history):
/// enough of a [StoryHost] to show cards, people and stats, without playing.
class ArchiveHost extends ChangeNotifier implements StoryHost {
  ArchiveHost(this.record, {required this.settings, this.images, this.narrator, this.onSave});

  @override
  final StoryRecord record;
  @override
  final SettingsController settings;
  @override
  final ImageService? images;
  @override
  final Narrator? narrator;

  /// Persists changes made here (pins, notes, memories).
  final Future<void> Function()? onSave;

  Adventure? get adventure => record is Adventure ? record as Adventure : null;
  Tale? get tale => record is Tale ? record as Tale : null;

  @override
  String get storyId => record.id;
  @override
  String get storyTitle => adventure?.title ?? tale!.title;
  @override
  String get storySubtitle => adventure != null ? '${adventure!.setting} · ${adventure!.tone}' : '${genreById(tale!.genre).name}${tale!.engine == TaleEngine.ai ? ' · AI' : ''}';
  @override
  WorldData get world => record as WorldData;
  @override
  List<Npc> get people => adventure?.people ?? tale!.npcs;
  @override
  String get playerName => adventure?.hero.name ?? (tale!.protagonist == 'You' ? 'you' : tale!.protagonist);
  @override
  List<CanonEntry> get canon => adventure?.canon ?? tale!.canon;
  @override
  String get summary => adventure?.memory ?? tale!.memory;
  @override
  set summary(String v) => adventure != null ? adventure!.memory = v : tale!.memory = v;
  @override
  Map<String, num> get usageTotals => adventure?.usage ?? tale!.usage;
  @override
  List<LogEntry> get log => adventure?.log ?? tale!.log;
  @override
  SceneInfo get scene => adventure?.scene ?? tale!.scene;
  @override
  MapState? get map => adventure?.map ?? tale!.map;
  @override
  int get turns => adventure?.turns ?? tale!.turns;
  @override
  bool get isAi => adventure != null ? adventure!.engine == StoryEngine.ai : tale!.engine == TaleEngine.ai;
  @override
  bool get busy => false;
  @override
  String get aiContext => adventure != null ? 'A solo ${adventure!.setting} D&D adventure, "${adventure!.title}": ${adventure!.premise}\n${dmStateBlock(adventure!)}' : 'A ${genreById(tale!.genre).name} interactive story, "${tale!.title}".\n${taleStateBlock(tale!)}';
  @override
  String get worldStyle => adventure != null ? 'The world is ${adventure!.setting} Dungeons & Dragons, with a ${adventure!.tone.toLowerCase()} tone.' : 'Genre: ${genreById(tale!.genre).name}. ${genreById(tale!.genre).style}';
  @override
  String get artStyle => adventure != null ? artStyleFor(adventure!.setting) : taleArtStyle(genreById(tale!.genre));

  @override
  Future<ChatLine> talkTo(Npc npc, String line, {List<String> images = const []}) => throw UnsupportedError('Open the story to talk to ${npc.name}.');
  @override
  String portraitKey(Npc npc) => 'npc_${record.id}_${npc.id}';
  @override
  Future<void> paintPortrait(Npc npc) async {}
  @override
  Future<void> paintScene() async {}
  @override
  Future<void> filmScene() async {}
  @override
  Future<void> generateMapImage() async {}
  @override
  bool canTravelTo(MapLocation location) => false;
  @override
  Future<void> travelTo(MapLocation location) async {}
  @override
  Npc meet(String name, {String role = '', String description = ''}) => people.firstWhere((p) => p.name == name, orElse: () => people.first);
  @override
  String? bringCompanion(Companion companion) {
    final why = bringCompanionTo(record, companion);
    if (why == null) save();
    return why;
  }
  @override
  Future<void> act(String text, {List<String> images = const []}) async {}
  @override
  Future<void> illustrate(String text, {bool video = false}) async {}
  @override
  bool get canRegenerate => false;
  @override
  Future<void> regenerate() async {}
  @override
  void note(String text) {}
  @override
  void save() => onSave?.call();
  @override
  void refresh() => notifyListeners();
  @override
  AiTrace? get aiTrace => null;
  @override
  void stopAi() {}
  @override
  Future<void> retryAi() async {}
}
