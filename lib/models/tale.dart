import 'adventure.dart';
import 'character.dart' show Character, PortraitSpec, newId;
import 'world.dart';

/// A non-D&D interactive story ("text adventure"): handcrafted or AI-narrated.
enum TaleEngine { preset, ai }

class TaleChoice {
  const TaleChoice(this.text, {this.data = const {}});
  final String text;

  /// Engine data: preset choices carry their destination and effects.
  final Map<String, dynamic> data;

  Map<String, dynamic> toJson() => {'t': text, 'd': data};
  factory TaleChoice.fromJson(Map<String, dynamic> j) => TaleChoice((j['t'] ?? '...').toString(), data: Map<String, dynamic>.from(j['d'] ?? const {}));
}

class Tale with WorldData implements StoryRecord {
  Tale({
    required this.id,
    required this.title,
    required this.genre,
    required this.engine,
    this.presetId,
    this.node = '',
    Set<String>? flags,
    List<String>? inventory,
    this.health = 100,
    List<LogEntry>? log,
    List<TaleChoice>? choices,
    List<String>? aiHistory,
    this.memory = '',
    this.protagonist = 'You',
    this.premise = '',
    this.turns = 0,
    this.finished = false,
    this.ending = '',
    this.status = '',
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, num>? usage,
    this.seed = 0,
    this.terminal = false,
    List<Npc>? npcs,
    List<CanonEntry>? canon,
    List<Quest>? goals,
    SceneInfo? scene,
    this.map,
    this.sceneImagePath,
    Map<String, String>? sceneImages,
    List<String>? pendingNotes,
  })  : npcs = npcs ?? [],
        canon = canon ?? [],
        goals = goals ?? [],
        scene = scene ?? SceneInfo(),
        sceneImages = sceneImages ?? {},
        pendingNotes = pendingNotes ?? [],
        flags = flags ?? {},
        inventory = inventory ?? [],
        log = log ?? [],
        choices = choices ?? [],
        aiHistory = aiHistory ?? [],
        usage = usage ?? {},
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  @override
  final String id;
  String title;
  String genre;
  final TaleEngine engine;
  final String? presetId;
  String node;
  Set<String> flags;
  List<String> inventory;

  /// 0–100. Reaching 0 ends the story.
  int health;
  List<LogEntry> log;
  List<TaleChoice> choices;
  List<String> aiHistory;
  String memory;
  String protagonist;
  String premise;
  int turns;
  bool finished;

  /// good | bad | neutral, once finished.
  String ending;

  /// Short state line from the narrator ("Bleeding", "Hunted", "Low on air").
  String status;
  DateTime createdAt;
  DateTime updatedAt;
  Map<String, num> usage;
  int seed;

  /// Played in the classic terminal layout instead of the book layout.
  bool terminal;

  /// Characters met along the way (talk to them from the journal or the story).
  List<Npc> npcs;

  /// Durable facts the narrator must respect.
  List<CanonEntry> canon;

  /// Objectives the story has set ("Find the keycard", "Get off the ship").
  List<Quest> goals;

  /// Where the story is now; drives scene art, music and the map.
  SceneInfo scene;
  MapState? map;
  @override
  String? sceneImagePath;
  @override
  Map<String, String> sceneImages;

  /// Things the player did outside the narrator's replies (private chats…).
  List<String> pendingNotes;

  List<Npc> get people => npcs;

  @override
  Character? companionNamed(String? name) => null;

  @override
  Npc? personNamed(String? name) {
    if (name == null || name.trim().isEmpty) return null;
    String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), '').trim();
    final key = norm(name);
    final exact = npcs.where((n) => norm(n.name) == key).firstOrNull;
    if (exact != null) return exact;
    final partial = npcs.where((n) => norm(n.name).startsWith('$key ') || key.startsWith('${norm(n.name)} ')).toList();
    return partial.length == 1 ? partial.single : null;
  }

  /// Adds or updates a canon entry by name.
  void remember(String kind, String name, String text) {
    if (name.trim().isEmpty) return;
    final e = canon.where((c) => c.name.toLowerCase() == name.trim().toLowerCase()).firstOrNull;
    if (e == null) {
      canon.add(CanonEntry(id: newId(), kind: kind, name: name.trim(), text: text.trim(), turn: turns));
    } else if (text.trim().isNotEmpty && !e.text.contains(text.trim())) {
      e.text = e.text.isEmpty ? text.trim() : '${e.text} ${text.trim()}';
      e.turn = turns;
    }
  }

  Npc meet(String name, {String role = '', String description = ''}) {
    final known = personNamed(name);
    if (known != null) {
      if (description.isNotEmpty && known.description.isEmpty) known.description = description;
      if (role.isNotEmpty && known.role.isEmpty) known.role = role;
      return known;
    }
    final n = Npc(id: newId(), name: name.trim(), role: role, description: description, portrait: PortraitSpec.random('human'));
    npcs.add(n);
    return n;
  }

  static Tale create({required String title, required String genre, required TaleEngine engine, String? presetId, String protagonist = 'You', String premise = ''}) => Tale(
        id: newId(),
        title: title,
        genre: genre,
        engine: engine,
        presetId: presetId,
        protagonist: protagonist,
        premise: premise,
        seed: DateTime.now().millisecondsSinceEpoch & 0xffffff,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'genre': genre,
        'engine': engine.name,
        'preset': presetId,
        'node': node,
        'flags': flags.toList(),
        'inv': inventory,
        'hp': health,
        'log': log.map((e) => e.toJson()).toList(),
        'choices': choices.map((c) => c.toJson()).toList(),
        'ai': aiHistory,
        'mem': memory,
        'who': protagonist,
        'premise': premise,
        'turns': turns,
        'fin': finished,
        'end': ending,
        'status': status,
        'created': createdAt.toIso8601String(),
        'updated': updatedAt.toIso8601String(),
        'usage': usage,
        'seed': seed,
        'term': terminal,
        'npcs': npcs.map((n) => n.toJson()).toList(),
        'canon': canon.map((c) => c.toJson()).toList(),
        'goals': goals.map((q) => q.toJson()).toList(),
        'scene': scene.toJson(),
        'map': map?.toJson(),
        'sceneImg': sceneImagePath,
        'sceneImages': sceneImages,
        'notes': pendingNotes,
        ...worldToJson(),
      };

  factory Tale.fromJson(Map<String, dynamic> j) => Tale(
        id: j['id'] ?? newId(),
        title: j['title'] ?? 'Untitled',
        genre: j['genre'] ?? 'mystery',
        engine: TaleEngine.values.firstWhere((e) => e.name == j['engine'], orElse: () => TaleEngine.preset),
        presetId: j['preset'],
        node: j['node'] ?? '',
        flags: Set<String>.from(j['flags'] ?? const []),
        inventory: List<String>.from(j['inv'] ?? const []),
        health: j['hp'] ?? 100,
        log: [for (final e in (j['log'] as List? ?? const [])) LogEntry.fromJson(Map<String, dynamic>.from(e))],
        choices: [for (final c in (j['choices'] as List? ?? const [])) TaleChoice.fromJson(Map<String, dynamic>.from(c))],
        aiHistory: List<String>.from(j['ai'] ?? const []),
        memory: j['mem'] ?? '',
        protagonist: j['who'] ?? 'You',
        premise: j['premise'] ?? '',
        turns: j['turns'] ?? 0,
        finished: j['fin'] ?? false,
        ending: j['end'] ?? '',
        status: j['status'] ?? '',
        createdAt: DateTime.tryParse(j['created'] ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(j['updated'] ?? '') ?? DateTime.now(),
        usage: Map<String, num>.from(j['usage'] ?? const {}),
        seed: j['seed'] ?? 0,
        terminal: j['term'] ?? false,
        npcs: [for (final n in (j['npcs'] as List? ?? const [])) Npc.fromJson(Map<String, dynamic>.from(n))],
        canon: [for (final c in (j['canon'] as List? ?? const [])) CanonEntry.fromJson(Map<String, dynamic>.from(c))],
        goals: [for (final q in (j['goals'] as List? ?? const [])) Quest.fromJson(Map<String, dynamic>.from(q))],
        scene: j['scene'] == null ? null : SceneInfo.fromJson(Map<String, dynamic>.from(j['scene'])),
        map: j['map'] == null ? null : MapState.fromJson(Map<String, dynamic>.from(j['map'])),
        sceneImagePath: j['sceneImg'],
        sceneImages: Map<String, String>.from(j['sceneImages'] ?? const {}),
        pendingNotes: List<String>.from(j['notes'] ?? const []),
      )..worldFromJson(j);

  /// Lightweight info for lists.
  Map<String, dynamic> summary() => {
        'id': id,
        'title': title,
        'genre': genre,
        'engine': engine.name,
        'turns': turns,
        'fin': finished,
        'end': ending,
        'hp': health,
        'updated': updatedAt.toIso8601String(),
        'usage': usage,
        'preset': presetId,
      };
}

class TaleSummary {
  TaleSummary(this.j);
  final Map<String, dynamic> j;
  String get id => j['id'];
  String get title => j['title'] ?? '';
  String get genre => j['genre'] ?? 'mystery';
  bool get isAi => j['engine'] == 'ai';
  int get turns => j['turns'] ?? 0;
  bool get finished => j['fin'] ?? false;
  String get ending => j['end'] ?? '';
  int get health => j['hp'] ?? 100;
  String? get presetId => j['preset'];
  DateTime get updatedAt => DateTime.tryParse(j['updated'] ?? '') ?? DateTime.now();
  Map<String, num> get usage => Map<String, num>.from(j['usage'] ?? const {});
}
