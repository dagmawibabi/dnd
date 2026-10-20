import '../data/modules.dart';
import '../data/srd.dart';
import '../models/adventure.dart';
import 'dice.dart';
import 'story.dart';

/// A choice inside a handcrafted adventure.
class ModChoice {
  const ModChoice(
    this.text, {
    this.type = ChoiceType.action,
    this.go,
    this.check,
    this.dc = 12,
    this.ok,
    this.fail,
    this.requires,
    this.unless,
    this.set,
    this.effects = const [],
    this.failEffects = const [],
    this.random,
    this.easierIf,
  });

  final String text;
  final ChoiceType type;

  /// Destination when there is no check.
  final String? go;

  /// Skill label ("Stealth") or ability ("DEX") for a check.
  final String? check;
  final int dc;
  final String? ok;
  final String? fail;

  /// Visibility gates: `flag`, `!flag`, `item:Name`, `gold:N`, `class:id`, `race:id`.
  final String? requires;
  final String? unless;

  /// Flag set when the choice is taken.
  final String? set;
  final List<Map<String, dynamic>> effects;
  final List<Map<String, dynamic>> failEffects;

  /// Pick one destination at random (cards, fate, coin flips).
  final List<String>? random;

  /// Flag that lowers the DC by 5 when set.
  final String? easierIf;
}

class ModCombat {
  const ModCombat(this.enemies, {required this.win, this.lose, this.boss = false, this.surprise = 'none'});
  final List<Map<String, dynamic>> enemies;
  final String win;
  final String? lose;
  final bool boss;
  final String surprise;
}

class ModNode {
  const ModNode({
    required this.title,
    required this.text,
    this.loc = 'forest',
    this.time = 'day',
    this.mood = 'calm',
    this.speaker,
    this.mapLoc,
    this.events = const [],
    this.choices = const [],
    this.combat,
    this.end,
    this.sets = const [],
  });

  /// Flags set when the scene is entered.
  final List<String> sets;
  final String title;
  final String text;
  final String loc;
  final String time;
  final String mood;
  final String? speaker;

  /// Name of the map location this node takes place at.
  final String? mapLoc;
  final List<Map<String, dynamic>> events;
  final List<ModChoice> choices;
  final ModCombat? combat;

  /// victory | bittersweet | defeat
  final String? end;
}

class AdventureModule {
  const AdventureModule({
    required this.id,
    required this.title,
    required this.tagline,
    required this.description,
    required this.levels,
    required this.minutes,
    required this.tone,
    required this.setting,
    required this.coverLoc,
    required this.coverTime,
    required this.mapKind,
    required this.mapName,
    required this.locations,
    required this.start,
    required this.nodes,
    this.tags = const [],
    this.seriesId,
    this.seriesName,
    this.part = 0,
    this.classes = const [],
  });

  /// Multi-part arcs: modules sharing a series id are played in [part] order.
  final String? seriesId;
  final String? seriesName;
  final int part;

  /// Classes this module is written for (empty = everyone).
  final List<String> classes;

  final String id;
  final String title;
  final String tagline;
  final String description;
  final String levels;
  final int minutes;
  final String tone;
  final String setting;
  final String coverLoc;
  final String coverTime;
  final MapKind mapKind;
  final String mapName;
  final List<String> locations;
  final String start;
  final Map<String, ModNode> nodes;
  final List<String> tags;

  int get endings => nodes.values.where((n) => n.end != null).length;
}

AdventureModule? moduleById(String id) => adventureModules.where((m) => m.id == id).firstOrNull;

/// Runs a handcrafted [AdventureModule] and produces the same [DmTurn]s as
/// the other story engines.
class ModuleEngine {
  ModuleEngine(this.a);
  final Adventure a;

  Map<String, dynamic> get st => a.offline;
  AdventureModule get mod => moduleById(st['module'] as String)!;
  Set<String> get flags => {...(st['flags'] as List? ?? const []).cast<String>()};

  static Map<String, dynamic> createState(String moduleId) => {'module': moduleId, 'node': null, 'flags': <String>[], 'visits': <String, int>{}};

  void _setFlag(String f) {
    final list = (st['flags'] as List? ?? []).cast<String>().toList();
    if (!list.contains(f)) list.add(f);
    st['flags'] = list;
  }

  String _fill(String s) {
    final h = a.hero;
    return s.replaceAll('{hero}', h.name).replaceAll('{first}', h.name.split(' ').first).replaceAll('{class}', h.primaryClass.name.toLowerCase()).replaceAll('{race}', h.raceLabel);
  }

  bool _gate(String? g) {
    if (g == null || g.isEmpty) return true;
    final h = a.hero;
    if (g.startsWith('!')) return !_gate(g.substring(1));
    if (g.startsWith('item:')) {
      final name = g.substring(5).toLowerCase();
      return h.inventory.any((i) => i.name.toLowerCase() == name);
    }
    if (g.startsWith('gold:')) return h.gold >= (int.tryParse(g.substring(5)) ?? 0);
    if (g.startsWith('class:')) return g.substring(6).split('|').any(h.classLevels.containsKey);
    if (g.startsWith('race:')) return g.substring(5).split('|').contains(h.raceId);
    return flags.contains(g);
  }

  CheckSpec? _check(ModChoice c) {
    if (c.check == null) return null;
    final dc0 = c.easierIf != null && flags.contains(c.easierIf) ? c.dc - 5 : c.dc;
    if (c.check!.toLowerCase().endsWith(' save')) {
      return CheckSpec(ability: AbilityX.fromShort(c.check!.split(' ').first), dc: dc0, save: true);
    }
    final skill = SkillX.parse(c.check);
    final ability = skill?.ability ?? AbilityX.fromShort(c.check!);
    final dc = c.easierIf != null && flags.contains(c.easierIf) ? c.dc - 5 : c.dc;
    return CheckSpec(ability: ability, skill: skill, dc: dc);
  }

  List<Choice> _choices(ModNode n) {
    final out = <Choice>[];
    for (final (i, c) in n.choices.indexed) {
      if (!_gate(c.requires)) continue;
      if (c.unless != null && _gate(c.unless)) continue;
      var text = c.text;
      if (c.requires != null && (c.requires!.startsWith('class:') || c.requires!.startsWith('race:'))) {
        final tag = c.requires!.split(':').last.split('|').map((x) => x.isEmpty ? x : x[0].toUpperCase() + x.substring(1)).join('/');
        text = '[$tag] $text';
      }
      out.add(Choice(text: _fill(text), type: c.type, check: _check(c), data: {'mi': i, 'node': st['node'], if (c.go != null) 'go': c.go}));
    }
    return out;
  }

  DmTurn begin() {
    final m = mod;
    final turn = _enter(m.start, extraEvents: [
      {'type': 'map', 'kind': m.mapKind.name, 'name': m.mapName, 'locations': m.locations},
    ]);
    return turn;
  }

  DmTurn _enter(String id, {List<Map<String, dynamic>> extraEvents = const [], String prefix = ''}) {
    final n = mod.nodes[id];
    if (n == null) return DmTurn(narration: 'The path fades into mist. (Missing scene "$id".)', choices: [Choice(text: 'Begin again', data: const {'restart': true})]);
    st['node'] = id;
    for (final f in n.sets) {
      _setFlag(f);
    }
    final visits = Map<String, dynamic>.from(st['visits'] as Map? ?? {});
    final firstVisit = (visits[id] ?? 0) == 0;
    visits[id] = (visits[id] ?? 0) + 1;
    st['visits'] = visits;
    final events = <Map<String, dynamic>>[
      ...extraEvents,
      if (n.mapLoc != null) {'type': 'move', 'location': n.mapLoc},
      if (firstVisit) ...n.events,
    ];
    if (n.combat != null) {
      st['combat'] = {'win': n.combat!.win, 'lose': n.combat!.lose, 'boss': n.combat!.boss};
      events.add({'type': 'combat', 'enemies': n.combat!.enemies, 'surprise': n.combat!.surprise, 'boss': n.combat!.boss});
    }
    if (n.end != null) {
      a.finished = true;
      events.add({'type': 'end', 'outcome': n.end});
    }
    final choices = n.end != null
        ? [
            Choice(text: 'Play this adventure again', type: ChoiceType.explore, data: const {'restart': true}),
          ]
        : _choices(n);
    return DmTurn(
      narration: _fill(prefix.isEmpty ? n.text : '$prefix\n\n${n.text}'),
      speaker: n.speaker,
      scene: SceneInfo(title: n.title, location: n.loc, time: n.time, mood: n.combat != null ? 'combat' : n.mood, seed: stableHash('${mod.id}${n.title}')),
      events: events,
      choices: n.combat != null ? [] : choices,
    );
  }

  DmTurn choose(Choice choice, D20Result? roll) {
    if (choice.data['restart'] == true) {
      a.offline = createState(mod.id);
      a.finished = false;
      return ModuleEngine(a).begin();
    }
    final node = mod.nodes[choice.data['node'] ?? st['node']];
    final mi = choice.data['mi'] as int?;
    if (node == null || mi == null || mi >= node.choices.length) return _enter(st['node'] as String? ?? mod.start);
    final c = node.choices[mi];
    if (c.set != null) _setFlag(c.set!);
    if (c.random != null && c.random!.isNotEmpty) {
      return _enter(Rng.unseeded().pick(c.random!), extraEvents: c.effects);
    }
    if (c.check != null && roll != null) {
      final ok = roll.success;
      final dest = ok ? (c.ok ?? c.go) : (c.fail ?? c.go);
      return _enter(dest ?? st['node'] as String, extraEvents: ok ? c.effects : c.failEffects);
    }
    return _enter(c.go ?? st['node'] as String, extraEvents: c.effects);
  }

  DmTurn afterCombat({required bool victory, required bool fled}) {
    final cb = Map<String, dynamic>.from(st['combat'] as Map? ?? {});
    st.remove('combat');
    final win = cb['win'] as String? ?? mod.start;
    final lose = cb['lose'] as String?;
    if (victory) return _enter(win, extraEvents: const [{'type': 'gold', 'amount': 5}]);
    if (fled) return _enter(lose ?? win, prefix: 'You break away from the fight and regroup.');
    return _enter(lose ?? win, prefix: 'Everything goes dark… When you come to, you are battered and bruised — but alive.');
  }
}

/// Matches typed input to a choice by number or shared keywords.
Choice? matchChoice(String text, List<Choice> choices) {
  final t = text.toLowerCase().trim();
  final n = int.tryParse(t);
  if (n != null && n >= 1 && n <= choices.length) return choices[n - 1];
  final words = t.split(RegExp(r'\W+')).where((w) => w.length > 2).toSet();
  Choice? best;
  var bestScore = 0;
  for (final c in choices) {
    final cw = c.text.toLowerCase().split(RegExp(r'\W+')).toSet();
    var score = words.intersection(cw).length;
    if ((t.contains('attack') || t.contains('fight')) && c.type == ChoiceType.combat) score += 3;
    if ((t.contains('sneak') || t.contains('hide')) && c.type == ChoiceType.stealth) score += 3;
    if ((t.contains('talk') || t.contains('say') || t.contains('ask')) && c.type == ChoiceType.dialogue) score += 2;
    if (score > bestScore) {
      bestScore = score;
      best = c;
    }
  }
  return bestScore > 0 ? best : null;
}
