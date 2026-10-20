import '../data/srd.dart';
import 'character.dart';
import 'world.dart';

enum LogKind { narration, dialogue, player, system, roll, combat, loot, levelup, companion, oracle }

class LogEntry {
  LogEntry({required this.kind, required this.text, this.speaker, DateTime? at, this.meta = const {}}) : at = at ?? DateTime.now();
  final LogKind kind;
  String text;
  final String? speaker;
  final DateTime at;
  final Map<String, dynamic> meta;

  Map<String, dynamic> toJson() => {'k': kind.name, 't': text, 's': speaker, 'at': at.millisecondsSinceEpoch, 'm': meta};
  factory LogEntry.fromJson(Map<String, dynamic> j) => LogEntry(
        kind: LogKind.values.firstWhere((k) => k.name == j['k'], orElse: () => LogKind.narration),
        text: j['t'] ?? '',
        speaker: j['s'],
        at: DateTime.fromMillisecondsSinceEpoch(j['at'] ?? 0),
        meta: Map<String, dynamic>.from(j['m'] ?? {}),
      );
}

class CheckSpec {
  CheckSpec({required this.ability, this.skill, required this.dc, this.save = false});
  final Ability ability;
  final Skill? skill;
  final int dc;

  /// A saving throw (resisting danger) rather than an ability check.
  final bool save;

  String get label => save ? '${ability.short} save' : (skill?.label ?? ability.full);

  Map<String, dynamic> toJson() => {'a': ability.short, 's': skill?.label, 'dc': dc, if (save) 'save': true};
  factory CheckSpec.fromJson(Map<String, dynamic> j) {
    final save = j['save'] == true || j['type'] == 'save';
    final sk = save ? null : SkillX.parse(j['s'] ?? j['skill']);
    final abRaw = j['a'] ?? j['ability'];
    return CheckSpec(
      ability: abRaw != null ? AbilityX.fromShort(abRaw.toString()) : (sk?.ability ?? Ability.str),
      skill: sk,
      dc: ((j['dc'] ?? 12) as num).toInt().clamp(5, 30),
      save: save,
    );
  }
}

enum ChoiceType { action, dialogue, explore, combat, stealth, magic, rest, leave }

ChoiceType parseChoiceType(String? s) => ChoiceType.values.firstWhere((t) => t.name == s, orElse: () => ChoiceType.action);

class Choice {
  Choice({required this.text, this.type = ChoiceType.action, this.check, this.data = const {}});
  final String text;
  final ChoiceType type;
  final CheckSpec? check;
  /// Opaque data used by the offline story engine.
  final Map<String, dynamic> data;

  Map<String, dynamic> toJson() => {'t': text, 'ty': type.name, 'c': check?.toJson(), 'd': data};
  factory Choice.fromJson(Map<String, dynamic> j) => Choice(
        text: j['t'] ?? j['text'] ?? '...',
        type: parseChoiceType(j['ty'] ?? j['type']),
        check: (j['c'] ?? j['check']) is Map ? CheckSpec.fromJson(Map<String, dynamic>.from(j['c'] ?? j['check'])) : null,
        data: Map<String, dynamic>.from(j['d'] ?? {}),
      );
}

class SceneInfo {
  SceneInfo({this.title = '', this.location = 'forest', this.time = 'day', this.mood = 'calm', this.imagePrompt = '', this.seed = 0, this.weather = ''});
  String title;

  /// clear | rain | storm | snow | fog | wind. Empty means "decide from the place".
  String weather;
  String location;
  String time;
  String mood;
  String imagePrompt;
  int seed;

  Map<String, dynamic> toJson() => {'title': title, 'loc': location, 'time': time, 'mood': mood, 'img': imagePrompt, 'seed': seed, if (weather.isNotEmpty) 'wx': weather};
  factory SceneInfo.fromJson(Map<String, dynamic> j) => SceneInfo(
        title: j['title'] ?? '',
        location: j['loc'] ?? 'forest',
        time: j['time'] ?? 'day',
        mood: j['mood'] ?? 'calm',
        imagePrompt: j['img'] ?? '',
        seed: j['seed'] ?? 0,
        weather: j['wx'] ?? '',
      );

  static const interiors = {'dungeon', 'cave', 'crypt', 'tavern', 'sewer', 'temple', 'tower', 'castle'};

  /// Weather for outdoor scenes: explicit, or a stable pick from place, mood and seed.
  String get effectiveWeather {
    if (interiors.contains(location)) return 'indoors';
    if (weather.isNotEmpty) return weather;
    if (location == 'tundra') return 'snow';
    if (mood == 'eerie' || mood == 'mystery') return seed % 2 == 0 ? 'fog' : 'wind';
    if (mood == 'sad') return 'rain';
    if (mood == 'tense' && seed % 3 == 0) return 'storm';
    return switch (seed % 7) { 0 => 'rain', 1 => 'wind', _ => 'clear' };
  }

  /// The ambient soundscape that fits this scene.
  String get ambience {
    switch (location) {
      case 'tavern':
        return 'crowd';
      case 'camp':
        return 'fire';
      case 'dungeon' || 'cave' || 'crypt' || 'sewer':
        return 'cave';
      case 'temple' || 'tower' || 'castle':
        return 'wind';
      case 'coast':
        return effectiveWeather == 'storm' ? 'storm' : 'surf';
    }
    return switch (effectiveWeather) {
      'rain' => 'rain',
      'storm' => 'storm',
      'snow' => 'snow',
      'wind' || 'fog' => 'wind',
      _ => const {'forest', 'swamp', 'plains', 'road'}.contains(location) ? 'forest' : (location == 'town' ? 'crowd' : 'wind'),
    };
  }
}

class Npc {
  Npc({required this.id, required this.name, this.role = '', this.disposition = 0, this.description = '', required this.portrait, this.notes = '', this.raceId = 'human', this.alive = true});
  final String id;
  String name;
  String role;
  /// -100 hostile .. 100 devoted
  int disposition;
  String description;
  PortraitSpec portrait;
  String notes;
  String raceId;
  bool alive;

  String get attitude => disposition >= 60
      ? 'Devoted'
      : disposition >= 25
          ? 'Friendly'
          : disposition > -25
              ? 'Neutral'
              : disposition > -60
                  ? 'Wary'
                  : 'Hostile';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'role': role,
        'disp': disposition,
        'desc': description,
        'portrait': portrait.toJson(),
        'notes': notes,
        'race': raceId,
        'alive': alive,
      };
  factory Npc.fromJson(Map<String, dynamic> j) => Npc(
        id: j['id'] ?? newId(),
        name: j['name'] ?? 'Stranger',
        role: j['role'] ?? '',
        disposition: j['disp'] ?? 0,
        description: j['desc'] ?? '',
        portrait: PortraitSpec.fromJson(Map<String, dynamic>.from(j['portrait'] ?? {})),
        notes: j['notes'] ?? '',
        raceId: j['race'] ?? 'human',
        alive: j['alive'] ?? true,
      );
}

enum QuestStatus { active, completed, failed }

class Quest {
  Quest({required this.id, required this.title, this.description = '', this.status = QuestStatus.active});
  final String id;
  String title;
  String description;
  QuestStatus status;

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'desc': description, 'st': status.name};
  factory Quest.fromJson(Map<String, dynamic> j) => Quest(
        id: j['id'] ?? newId(),
        title: j['title'] ?? 'Quest',
        description: j['desc'] ?? '',
        status: QuestStatus.values.firstWhere((s) => s.name == j['st'], orElse: () => QuestStatus.active),
      );
}

class Combatant {
  Combatant({
    required this.id,
    required this.name,
    required this.hp,
    required this.maxHp,
    required this.ac,
    required this.attackBonus,
    required this.damage,
    this.isPlayer = false,
    this.isAlly = false,
    this.characterId,
    this.monsterId,
    this.initiative = 0,
    this.dexMod = 0,
    this.multi = 1,
    this.xp = 0,
    this.attackName = 'Strike',
    this.colorValue = 0xFF8C7246,
    this.type = 'beast',
    Set<String>? conditions,
    this.back = false,
    this.breathReady = true,
    this.x = 0,
    this.y = 0,
  }) : conditions = conditions ?? {};

  /// Square on the battle grid (each square is 5 feet).
  int x;
  int y;

  /// Back row (ranged/caster) instead of front line.
  bool back;
  bool breathReady;

  final String id;
  String name;
  int hp;
  int maxHp;
  int ac;
  int attackBonus;
  String damage;
  bool isPlayer;
  bool isAlly;
  String? characterId;
  String? monsterId;
  int initiative;
  int dexMod;
  int multi;
  int xp;
  String attackName;
  int colorValue;
  String type;
  Set<String> conditions;

  bool get isEnemy => !isPlayer && !isAlly;
  bool get down => hp <= 0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'hp': hp,
        'max': maxHp,
        'ac': ac,
        'ab': attackBonus,
        'dmg': damage,
        'pl': isPlayer,
        'al': isAlly,
        'cid': characterId,
        'mid': monsterId,
        'ini': initiative,
        'dex': dexMod,
        'multi': multi,
        'xp': xp,
        'an': attackName,
        'col': colorValue,
        'type': type,
        'cond': conditions.toList(),
        'back': back,
        'breath': breathReady,
        'x': x,
        'y': y,
      };
  factory Combatant.fromJson(Map<String, dynamic> j) => Combatant(
        id: j['id'],
        name: j['name'] ?? '?',
        hp: j['hp'] ?? 1,
        maxHp: j['max'] ?? 1,
        ac: j['ac'] ?? 10,
        attackBonus: j['ab'] ?? 0,
        damage: j['dmg'] ?? '1d4',
        isPlayer: j['pl'] ?? false,
        isAlly: j['al'] ?? false,
        characterId: j['cid'],
        monsterId: j['mid'],
        initiative: j['ini'] ?? 0,
        dexMod: j['dex'] ?? 0,
        multi: j['multi'] ?? 1,
        xp: j['xp'] ?? 0,
        attackName: j['an'] ?? 'Strike',
        colorValue: j['col'] ?? 0xFF8C7246,
        type: j['type'] ?? 'beast',
        conditions: Set<String>.from(j['cond'] ?? []),
        back: j['back'] ?? false,
        breathReady: j['breath'] ?? true,
        x: j['x'] ?? 0,
        y: j['y'] ?? 0,
      );
}

class CombatState {
  CombatState({required this.combatants, this.round = 1, this.turn = 0, this.environment = 'dungeon', List<String>? log}) : log = log ?? [];
  List<Combatant> combatants;
  int round;
  int turn;
  String environment;
  List<String> log;

  Combatant get current => combatants[turn % combatants.length];
  List<Combatant> get enemies => combatants.where((c) => c.isEnemy).toList();
  List<Combatant> get allies => combatants.where((c) => !c.isEnemy).toList();
  bool get victory => enemies.every((e) => e.down);
  bool get defeat => combatants.where((c) => c.isPlayer).every((c) => c.down) && !victory;

  Map<String, dynamic> toJson() => {'c': combatants.map((c) => c.toJson()).toList(), 'r': round, 't': turn, 'env': environment, 'log': log};
  factory CombatState.fromJson(Map<String, dynamic> j) => CombatState(
        combatants: [for (final c in (j['c'] as List? ?? [])) Combatant.fromJson(Map<String, dynamic>.from(c))],
        round: j['r'] ?? 1,
        turn: j['t'] ?? 0,
        environment: j['env'] ?? 'dungeon',
        log: List<String>.from(j['log'] ?? []),
      );
}

enum MapKind { dungeon, overworld, town }

class MapLocation {
  MapLocation({required this.name, this.type = 'place', this.visited = false});
  String name;
  String type;
  bool visited;

  Map<String, dynamic> toJson() => {'n': name, 'ty': type, 'v': visited};
  factory MapLocation.fromJson(Map<String, dynamic> j) => MapLocation(name: j['n'] ?? '?', type: j['ty'] ?? 'place', visited: j['v'] ?? false);
}

class MapState {
  MapState({required this.kind, required this.seed, required this.name, List<MapLocation>? locations, this.current = 0, this.aiImagePath})
      : locations = locations ?? [];
  MapKind kind;
  int seed;
  String name;
  List<MapLocation> locations;
  int current;
  String? aiImagePath;

  Map<String, dynamic> toJson() => {'k': kind.name, 'seed': seed, 'name': name, 'locs': locations.map((l) => l.toJson()).toList(), 'cur': current, 'ai': aiImagePath};
  factory MapState.fromJson(Map<String, dynamic> j) => MapState(
        kind: MapKind.values.firstWhere((k) => k.name == j['k'], orElse: () => MapKind.dungeon),
        seed: j['seed'] ?? 1,
        name: j['name'] ?? 'Unknown Lands',
        locations: [for (final l in (j['locs'] as List? ?? [])) MapLocation.fromJson(Map<String, dynamic>.from(l))],
        current: j['cur'] ?? 0,
        aiImagePath: j['ai'],
      );
}

enum StoryEngine { ai, offline, module }

/// A durable fact the story must remember (structured AI memory).
class CanonEntry {
  CanonEntry({required this.id, required this.kind, required this.name, this.text = '', this.turn = 0, this.pinned = false});
  final String id;

  /// npc | place | item | promise | clue | fact | quest | lore
  String kind;
  String name;
  String text;
  int turn;
  bool pinned;

  Map<String, dynamic> toJson() => {'id': id, 'k': kind, 'n': name, 't': text, 'turn': turn, 'pin': pinned};
  factory CanonEntry.fromJson(Map<String, dynamic> j) =>
      CanonEntry(id: j['id'] ?? newId(), kind: j['k'] ?? 'fact', name: j['n'] ?? '', text: j['t'] ?? '', turn: j['turn'] ?? 0, pinned: j['pin'] ?? false);
}

const canonKinds = ['npc', 'place', 'item', 'quest', 'promise', 'clue', 'lore', 'fact'];

class Adventure with WorldData implements StoryRecord {
  Adventure({
    required this.id,
    required this.title,
    required this.premise,
    required this.hero,
    required this.engine,
    this.setting = 'High Fantasy',
    this.tone = 'Heroic',
    this.difficulty = 'Normal',
    this.textMode = false,
    List<Character>? companions,
    List<LogEntry>? log,
    SceneInfo? scene,
    List<Choice>? choices,
    List<Npc>? npcs,
    List<Quest>? quests,
    this.map,
    this.combat,
    this.memory = '',
    Map<String, dynamic>? offline,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.turns = 0,
    this.finished = false,
    this.coverSeed = 0,
    this.sceneImagePath,
    List<String>? aiHistory,
    List<CanonEntry>? canon,
    this.chaos = 5,
    this.campaignId,
    this.hardcore = false,
    this.showDcs = true,
    Map<String, num>? usage,
    Map<String, String>? sceneImages,
    this.lastLongRestTurn = -100,
    List<String>? pendingNotes,
  })  : canon = canon ?? [],
        pendingNotes = pendingNotes ?? [],
        usage = usage ?? {},
        sceneImages = sceneImages ?? {},
        companions = companions ?? [],
        log = log ?? [],
        scene = scene ?? SceneInfo(),
        choices = choices ?? [],
        npcs = npcs ?? [],
        quests = quests ?? [],
        offline = offline ?? {},
        aiHistory = aiHistory ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  @override
  final String id;
  String title;
  String premise;
  Character hero;
  StoryEngine engine;
  String setting;
  String tone;
  String difficulty;
  bool textMode;
  List<Character> companions;
  List<LogEntry> log;
  SceneInfo scene;
  List<Choice> choices;
  List<Npc> npcs;
  List<Quest> quests;
  MapState? map;
  CombatState? combat;
  /// Rolling summary of older events for the AI DM.
  String memory;
  /// Offline engine state.
  Map<String, dynamic> offline;
  /// Raw JSON strings of recent AI exchanges (role:content).
  List<String> aiHistory;
  final DateTime createdAt;
  DateTime updatedAt;
  int turns;
  bool finished;
  int coverSeed;
  @override
  String? sceneImagePath;

  /// Structured memory that is sent to the AI every turn.
  List<CanonEntry> canon;

  /// Oracle chaos factor, 1 (orderly) – 9 (chaotic).
  int chaos;
  String? campaignId;

  /// Permadeath: if the hero falls, the adventure ends.
  bool hardcore;
  bool showDcs;

  /// Token and cost totals: in, out, cost, calls, images, imageCost.
  Map<String, num> usage;

  /// Scene title -> generated image, so revisited places keep their art.
  @override
  Map<String, String> sceneImages;
  int lastLongRestTurn;

  /// Things that happened outside the AI's replies (shopping, rests, level-ups…),
  /// reported to it with the next player action.
  List<String> pendingNotes;

  CanonEntry? canonNamed(String name) {
    final n = name.toLowerCase();
    for (final c in canon) {
      if (c.name.toLowerCase() == n) return c;
    }
    return null;
  }

  /// Adds or updates a canon entry by name.
  void remember(String kind, String name, String text) {
    if (name.trim().isEmpty) return;
    final e = canonNamed(name);
    if (e == null) {
      canon.add(CanonEntry(id: newId(), kind: kind, name: name.trim(), text: text.trim(), turn: turns));
    } else {
      if (text.trim().isNotEmpty && !e.text.contains(text.trim())) e.text = e.text.isEmpty ? text.trim() : '${e.text} ${text.trim()}';
      e.turn = turns;
      if (kind != 'fact') e.kind = kind;
    }
  }

  List<Character> get party => [hero, ...companions];

  @override
  Character? companionNamed(String? name) => _named(companions, name, (c) => c.name);
  @override
  Npc? personNamed(String? name) => _named(people, name, (n) => n.name);

  /// Companions share their actual portrait with their conversation profile.
  List<Npc> get people => [
    for (final c in companions)
      Npc(id: c.id, name: c.name, role: 'Companion · ${c.classSummary}',
        raceId: c.raceId, portrait: c.portrait, disposition: bonds[c.id]?.friendship ?? 20,
        description: '${c.appearance} ${c.personality} ${c.backstory}',
        notes: c.notes, alive: !c.dead),
    for (final n in npcs)
      if (companionNamed(n.name) == null) n,
  ];

  static T? _named<T>(Iterable<T> people, String? name, String Function(T) label) {
    if (name == null || name.trim().isEmpty) return null;
    String normalized(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), '').trim();
    final key = normalized(name);
    final exact = people.where((p) => normalized(label(p)) == key).firstOrNull;
    if (exact != null) return exact;
    final matches = people.where((p) {
      final full = normalized(label(p));
      return full.startsWith('$key ') || key.startsWith('$full ');
    }).toList();
    return matches.length == 1 ? matches.single : null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'premise': premise,
        'hero': hero.toJson(),
        'engine': engine.name,
        'setting': setting,
        'tone': tone,
        'diff': difficulty,
        'text': textMode,
        'comp': companions.map((c) => c.toJson()).toList(),
        'log': (log.length > 400 ? log.sublist(log.length - 400) : log).map((e) => e.toJson()).toList(),
        'scene': scene.toJson(),
        'choices': choices.map((c) => c.toJson()).toList(),
        'npcs': npcs.map((n) => n.toJson()).toList(),
        'quests': quests.map((q) => q.toJson()).toList(),
        'map': map?.toJson(),
        'combat': combat?.toJson(),
        'memory': memory,
        'offline': offline,
        'aiHistory': aiHistory.length > 24 ? aiHistory.sublist(aiHistory.length - 24) : aiHistory,
        'created': createdAt.toIso8601String(),
        'updated': updatedAt.toIso8601String(),
        'turns': turns,
        'finished': finished,
        'cover': coverSeed,
        'sceneImg': sceneImagePath,
        'canon': canon.map((c) => c.toJson()).toList(),
        'chaos': chaos,
        'campaign': campaignId,
        'hardcore': hardcore,
        'showDcs': showDcs,
        'usage': usage,
        'sceneImages': sceneImages,
        'lastRest': lastLongRestTurn,
        'notes': pendingNotes,
        ...worldToJson(),
      };

  factory Adventure.fromJson(Map<String, dynamic> j) => Adventure(
        id: j['id'],
        title: j['title'] ?? 'Adventure',
        premise: j['premise'] ?? '',
        hero: Character.fromJson(Map<String, dynamic>.from(j['hero'])),
        engine: StoryEngine.values.firstWhere((e) => e.name == j['engine'], orElse: () => StoryEngine.offline),
        setting: j['setting'] ?? 'High Fantasy',
        tone: j['tone'] ?? 'Heroic',
        difficulty: j['diff'] ?? 'Normal',
        textMode: j['text'] ?? false,
        companions: [for (final c in (j['comp'] as List? ?? [])) Character.fromJson(Map<String, dynamic>.from(c))],
        log: [for (final e in (j['log'] as List? ?? [])) LogEntry.fromJson(Map<String, dynamic>.from(e))],
        scene: SceneInfo.fromJson(Map<String, dynamic>.from(j['scene'] ?? {})),
        choices: [for (final c in (j['choices'] as List? ?? [])) Choice.fromJson(Map<String, dynamic>.from(c))],
        npcs: [for (final n in (j['npcs'] as List? ?? [])) Npc.fromJson(Map<String, dynamic>.from(n))],
        quests: [for (final q in (j['quests'] as List? ?? [])) Quest.fromJson(Map<String, dynamic>.from(q))],
        map: j['map'] == null ? null : MapState.fromJson(Map<String, dynamic>.from(j['map'])),
        combat: j['combat'] == null ? null : CombatState.fromJson(Map<String, dynamic>.from(j['combat'])),
        memory: j['memory'] ?? '',
        offline: Map<String, dynamic>.from(j['offline'] ?? {}),
        aiHistory: List<String>.from(j['aiHistory'] ?? []),
        createdAt: DateTime.tryParse(j['created'] ?? ''),
        updatedAt: DateTime.tryParse(j['updated'] ?? ''),
        turns: j['turns'] ?? 0,
        finished: j['finished'] ?? false,
        coverSeed: j['cover'] ?? 0,
        sceneImagePath: j['sceneImg'],
        canon: [for (final c in (j['canon'] as List? ?? [])) CanonEntry.fromJson(Map<String, dynamic>.from(c))],
        chaos: j['chaos'] ?? 5,
        campaignId: j['campaign'],
        hardcore: j['hardcore'] ?? false,
        showDcs: j['showDcs'] ?? true,
        usage: Map<String, num>.from(j['usage'] ?? {}),
        sceneImages: Map<String, String>.from(j['sceneImages'] ?? {}),
        lastLongRestTurn: j['lastRest'] ?? -100,
        pendingNotes: List<String>.from(j['notes'] ?? []),
      )..worldFromJson(j);
}
