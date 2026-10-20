import 'dart:math' as math;

import '../data/srd.dart';
import '../models/adventure.dart';
import '../models/character.dart';
import '../data/inventory_rules.dart';
import 'dice.dart';

enum CombatFx { hit, miss, crit, spell, heal, death, buff, flee, roar, victory, defeat }

class CombatEvent {
  CombatEvent(this.text, this.fx, {this.actorId, this.targetId, this.amount = 0, this.roll, this.details});
  final String text;
  final CombatFx fx;
  final String? actorId;
  final String? targetId;
  final int amount;
  final D20Result? roll;

  /// Structured breakdown shown when the player taps the log entry.
  final Map<String, dynamic>? details;
}

// ---------------------------------------------------------------- details

/// Dice group for a d20 test.
Map<String, dynamic> d20Group(String label, D20Result r, {String? against}) {
  final kept = r.rolls.length < 2 ? 0 : (r.mode == RollMode.advantage ? (r.rolls[0] >= r.rolls[1] ? 0 : 1) : (r.rolls[0] <= r.rolls[1] ? 0 : 1));
  return {
    'label': label,
    'dice': [
      for (var i = 0; i < r.rolls.length; i++) {'s': 20, 'v': r.rolls[i], 'drop': r.rolls.length > 1 && i != kept},
    ],
    'mod': r.modifier,
    'total': r.total,
    'against': ?against,
    'mode': r.mode.name,
  };
}

/// Dice group for a damage / healing roll.
Map<String, dynamic> diceGroup(String label, DiceResult r, {String? suffix}) => {
      'label': label,
      'dice': [for (final d in r.rolls) {'s': d.sides, 'v': d.value, 'drop': d.dropped}],
      'mod': r.modifier,
      'total': r.total,
      'expr': r.expression,
      'suffix': ?suffix,
    };

const ruleAttack = 'Attack roll: d20 + attack bonus. If the total equals or beats the target\'s Armor Class (AC), it hits. A natural 20 always hits and is a critical hit (damage dice are rolled twice). A natural 1 always misses.';
const ruleAdvantage = 'Advantage: roll two d20s and keep the higher. Disadvantage: keep the lower. They cancel each other out.';
const ruleSave = 'Saving throw: the target rolls a d20 + its modifier against the caster\'s spell save DC. On a success it usually takes half damage.';
const ruleInitiative = 'Initiative: everyone rolls a d20 + Dexterity modifier. Turns go from highest to lowest. Surprised creatures act with a −10 penalty in this game.';
const ruleHeal = 'Healing restores hit points up to the creature\'s maximum. A creature at 0 HP that is healed regains consciousness.';
const ruleDeathSave = 'Death saving throw: at 0 HP, roll a d20 each turn. 10 or higher is a success, below 10 a failure, a natural 1 counts as two failures and a natural 20 restores 1 HP. Three failures and you fall.';
const ruleRows = 'Battle grid: each square is 5 feet. You can move up to your speed each turn (diagonals count as one square). Melee attacks need you next to the target; you step in automatically if it is within reach of your movement. Creatures standing between an attacker and its target give half cover (+2 AC). Ranged attacks with an enemy next to you have disadvantage, and leaving an enemy\'s reach provokes an opportunity attack. An ally on the opposite side of a foe flanks it (advantage).';
const ruleConcentration = 'Concentration: some spells last while you concentrate. Casting another concentration spell ends the first. When you take damage, make a CON save (DC 10 or half the damage, whichever is higher) or lose the spell.';
const ruleFlee = 'Fleeing: an Athletics or Acrobatics check against DC 8 + 2 per standing enemy.';

String hpChange(int before, int after, int max) => '$before → $after / $max';

class EnemySpec {
  EnemySpec({required this.name, this.monsterId, this.hp, this.ac, this.attackBonus, this.damage, this.count = 1, this.cr, this.attackName});
  final String name;
  final String? monsterId;
  final int? hp;
  final int? ac;
  final int? attackBonus;
  final String? damage;
  final int count;
  final double? cr;
  final String? attackName;

  Map<String, dynamic> toJson() => {'name': name, 'mid': monsterId, 'hp': hp, 'ac': ac, 'ab': attackBonus, 'dmg': damage, 'count': count, 'cr': cr, 'an': attackName};

  factory EnemySpec.fromJson(Map<String, dynamic> j) => EnemySpec(
        name: (j['name'] ?? 'Foe').toString(),
        monsterId: j['mid'] ?? j['monster'] ?? j['type'],
        hp: (j['hp'] as num?)?.toInt(),
        ac: (j['ac'] as num?)?.toInt(),
        attackBonus: ((j['ab'] ?? j['attack_bonus']) as num?)?.toInt(),
        damage: (j['dmg'] ?? j['damage'])?.toString(),
        count: ((j['count'] ?? 1) as num).toInt().clamp(1, 6),
        cr: (j['cr'] as num?)?.toDouble(),
        attackName: (j['an'] ?? j['attack_name'] ?? j['attack'])?.toString(),
      );
}

MonsterDef? matchMonster(String nameOrId) {
  final k = nameOrId.toLowerCase();
  final byId = monsterById(k.replaceAll(' ', '_'));
  if (byId != null) return byId;
  for (final m in monsters) {
    if (k.contains(m.name.toLowerCase()) || k.contains(m.id.replaceAll('_', ' '))) return m;
  }
  for (final m in monsters) {
    final w = m.name.toLowerCase().split(' ').last;
    if (w.length > 3 && k.contains(w)) return m;
  }
  return null;
}

double difficultyScale(String difficulty) => switch (difficulty) {
      'Story' => 0.7,
      'Hard' => 1.25,
      'Deadly' => 1.5,
      _ => 1.0,
    };

class CombatEngine {
  CombatEngine(this.adventure);
  final Adventure adventure;

  CombatState get state => adventure.combat!;

  Character? characterFor(Combatant c) {
    if (c.characterId == null) return null;
    for (final p in adventure.party) {
      if (p.id == c.characterId) return p;
    }
    return null;
  }

  List<String> abilitiesOf(Combatant c) => c.monsterId == null ? const [] : (monsterById(c.monsterId!)?.abilities ?? const []);

  /// Full ability code (e.g. "poison:11") if the monster has it.
  String? ability(Combatant c, String code) => abilitiesOf(c).where((a) => a == code || a.startsWith('$code:')).firstOrNull;

  bool _isRanged(Combatant c) {
    final ch = characterFor(c);
    if (ch != null) return ch.equippedWeapon?.def?.ranged ?? false;
    return ability(c, 'ranged') != null;
  }

  // --------------------------------------------------------------- grid

  static const gridW = 8;
  static const gridH = 5;

  /// Distance in squares (5e: diagonals count as one square).
  int dist(Combatant a, Combatant b) => math.max((a.x - b.x).abs(), (a.y - b.y).abs());
  bool adjacent(Combatant a, Combatant b) => dist(a, b) <= 1;

  List<Combatant> get _active => state.combatants.where((c) => !c.down && !c.conditions.contains('Banished')).toList();

  Combatant? occupant(int x, int y, {Combatant? except}) => _active.where((c) => c != except && c.x == x && c.y == y).firstOrNull;

  bool _incapacitated(Combatant c) => c.conditions.any((x) => const ['Paralyzed', 'Stunned', 'Charmed', 'Turned', 'Banished'].contains(x));

  /// Saves from before the grid have everyone on one square: spread them out.
  void ensureLayout() {
    final pos = state.combatants.map((c) => '${c.x},${c.y}').toSet();
    if (pos.length > 1 || state.combatants.length <= 1) return;
    var pi = 0, ei = 0;
    for (final c in state.combatants) {
      if (c.isEnemy) {
        c.x = c.back ? gridW - 1 : gridW - 3;
        c.y = ei++ % gridH;
      } else {
        c.x = c.back ? 0 : 1;
        c.y = pi++ % gridH;
      }
    }
  }

  /// Squares this creature can move per turn.
  int speedSquares(Combatant c) {
    final ch = characterFor(c);
    if (ch != null) return (ch.speed / 5).floor().clamp(1, 20);
    if (c.conditions.contains('Restrained') || c.conditions.contains('Slowed')) return 1;
    return c.type == 'beast' ? 8 : 6;
  }

  int movesLeft(Combatant c) {
    if (c.conditions.contains('Restrained') || c.conditions.contains('Paralyzed')) return 0;
    return speedSquares(c) - c.conditions.where((x) => x.startsWith('Step')).length;
  }

  /// Shortest path (excluding the start) to a free square, or null.
  List<math.Point<int>>? pathTo(Combatant c, int tx, int ty) {
    if (tx < 0 || ty < 0 || tx >= gridW || ty >= gridH) return null;
    if (occupant(tx, ty, except: c) != null) return null;
    final start = math.Point(c.x, c.y);
    final prev = <math.Point<int>, math.Point<int>>{};
    final seen = {start};
    final queue = [start];
    while (queue.isNotEmpty) {
      final cur = queue.removeAt(0);
      if (cur.x == tx && cur.y == ty) {
        final out = <math.Point<int>>[];
        var p = cur;
        while (p != start) {
          out.insert(0, p);
          p = prev[p]!;
        }
        return out;
      }
      for (var dx = -1; dx <= 1; dx++) {
        for (var dy = -1; dy <= 1; dy++) {
          final n = math.Point(cur.x + dx, cur.y + dy);
          if ((dx == 0 && dy == 0) || n.x < 0 || n.y < 0 || n.x >= gridW || n.y >= gridH || seen.contains(n)) continue;
          final occ = occupant(n.x, n.y, except: c);
          // Allies can be passed through, foes cannot.
          if (occ != null && occ.isEnemy != c.isEnemy) continue;
          seen.add(n);
          prev[n] = cur;
          queue.add(n);
        }
      }
    }
    return null;
  }

  /// Squares reachable this turn (for the move overlay).
  Set<math.Point<int>> reachable(Combatant c) {
    final left = movesLeft(c);
    final out = <math.Point<int>>{};
    for (var x = 0; x < gridW; x++) {
      for (var y = 0; y < gridH; y++) {
        final p = pathTo(c, x, y);
        if (p != null && p.isNotEmpty && p.length <= left) out.add(math.Point(x, y));
      }
    }
    return out;
  }

  /// Moves along a path, provoking opportunity attacks when leaving a foe's reach.
  List<CombatEvent> moveTo(Combatant c, int tx, int ty, {bool free = false}) {
    final events = <CombatEvent>[];
    final path = pathTo(c, tx, ty);
    if (path == null || path.isEmpty) return events;
    final budget = free ? path.length : math.min(path.length, movesLeft(c));
    final ch = characterFor(c);
    var steps = 0;
    for (final p in path.take(budget)) {
      final threats = _active.where((h) => h.isEnemy != c.isEnemy && adjacent(h, c) && !_incapacitated(h) && !h.conditions.contains('ReactionUsed') && !_isRangedOnly(h)).toList();
      final fromX = c.x, fromY = c.y;
      c.x = p.x;
      c.y = p.y;
      steps++;
      if (!free) c.conditions.add('Step${c.conditions.where((x) => x.startsWith('Step')).length}');
      if (c.conditions.contains('Disengaged') || (ch?.hasFeat('mobile') ?? false)) continue;
      for (final h in threats) {
        if (adjacent(h, c)) continue; // still in reach
        h.conditions.add('ReactionUsed');
        final mx = c.x, my = c.y;
        c.x = fromX;
        c.y = fromY; // the attack lands as they leave
        events.addAll(attack(h, c, opportunity: true));
        c.x = mx;
        c.y = my;
        if (c.down) return events;
      }
    }
    if (steps > 0) {
      events.insert(0, CombatEvent('${c.name} moves ${steps * 5} ft.', CombatFx.buff, actorId: c.id, details: {
        'title': 'Move',
        'outcome': '${steps * 5} ft · ${movesLeft(c) * 5} ft left',
        'ok': true,
        'rule': ruleRows,
      }));
    }
    return events;
  }

  /// Steps next to [target] if it isn't already within reach.
  List<CombatEvent> approach(Combatant c, Combatant target) {
    if (adjacent(c, target)) return const [];
    math.Point<int>? best;
    var bestLen = 1 << 20;
    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        if (dx == 0 && dy == 0) continue;
        final p = pathTo(c, target.x + dx, target.y + dy);
        if (p != null && p.length < bestLen) {
          bestLen = p.length;
          best = math.Point(target.x + dx, target.y + dy);
        }
      }
    }
    if (best == null) return const [];
    return moveTo(c, best.x, best.y);
  }

  /// Retreats ranged creatures out of melee when they can.
  List<CombatEvent> _kite(Combatant c) {
    final foes = _active.where((h) => h.isEnemy != c.isEnemy).toList();
    if (!foes.any((f) => adjacent(f, c))) return const [];
    math.Point<int>? best;
    var bestScore = -1;
    for (final p in reachable(c)) {
      final d = foes.map((f) => math.max((f.x - p.x).abs(), (f.y - p.y).abs())).reduce(math.min);
      if (d > bestScore) {
        bestScore = d;
        best = p;
      }
    }
    if (best == null || bestScore <= 1) return const [];
    return moveTo(c, best.x, best.y);
  }

  bool _isRangedOnly(Combatant c) => characterFor(c) == null && ability(c, 'ranged') != null;

  /// Foes in order of distance; melee attacks walk in automatically.
  List<Combatant> meleeTargets(Combatant attacker) {
    final foes = _active.where((x) => x.isEnemy != attacker.isEnemy).toList()..sort((a, b) => dist(attacker, a).compareTo(dist(attacker, b)));
    return foes;
  }

  /// Squares on the straight line between two creatures (excluding both).
  Iterable<math.Point<int>> _line(Combatant a, Combatant b) sync* {
    final n = dist(a, b);
    for (var i = 1; i < n; i++) {
      yield math.Point((a.x + (b.x - a.x) * i / n).round(), (a.y + (b.y - a.y) * i / n).round());
    }
  }

  int _saveMod(Combatant c, Ability a) {
    final ch = characterFor(c);
    if (ch != null) return ch.saveMod(a);
    return a == Ability.dex ? c.dexMod : (c.maxHp > 60 ? 3 : 1);
  }

  /// Spells that need the caster to be in melee (touch or point-blank).
  static const touchSpells = {'shocking_grasp', 'booming_blade', 'vampiric_touch', 'thunderous_smite', 'searing_smite', 'branding_smite', 'inflict_wounds', 'chill_touch_melee'};

  /// Concentration spells that keep hurting a foe at the start of the caster's turn.
  static const persistentSpells = {'moonbeam': 'Moonbeam', 'call_lightning': 'Call Lightning', 'spirit_guardians': 'Spirit Guardians', 'flaming_sphere': 'Flaming Sphere', 'cloud_of_daggers': 'Daggers', 'witch_bolt': 'Witch Bolt'};

  /// Light weapons usable for two-weapon fighting.
  static const lightWeapons = {'dagger', 'shortsword', 'handaxe', 'scimitar', 'light_hammer', 'sickle', 'club', 'rapier_1'};

  /// An off-hand weapon for two-weapon fighting, if the character can use one.
  InventoryItem? offhandWeapon(Character ch) {
    if (ch.hasShield) return null;
    final main = ch.equippedWeapon;
    if (main == null || main.def?.twoHanded == true || main.def?.ranged == true) return null;
    if (!lightWeapons.contains(main.itemId) && !ch.hasFeat('dual_wielder')) return null;
    return ch.inventory.where((i) => i != main && i.def?.type == ItemType.weapon && !(i.def?.twoHanded ?? false) && !(i.def?.ranged ?? false) && (lightWeapons.contains(i.itemId) || ch.hasFeat('dual_wielder'))).firstOrNull;
  }

  int kiMax(Character ch) => (ch.classLevels['monk'] ?? 0) >= 2 ? ch.classLevels['monk']! : 0;
  int kiLeft(Character ch) => kiMax(ch) - ch.conditions.where((c) => c.startsWith('KiUsed')).length;

  Combatant? byId(String id) {
    for (final c in state.combatants) {
      if (c.id == id) return c;
    }
    return null;
  }

  static List<Combatant> buildEnemies(List<EnemySpec> specs, {String difficulty = 'Normal', int partyLevel = 1}) {
    final out = <Combatant>[];
    final scale = difficultyScale(difficulty);
    for (final s in specs) {
      final m = s.monsterId != null ? (monsterById(s.monsterId!) ?? matchMonster(s.monsterId!)) : null;
      final def = m ?? matchMonster(s.name);
      for (var i = 0; i < s.count; i++) {
        final baseHp = s.hp ?? def?.hp ?? (8 + partyLevel * 6);
        final hp = math.max(1, (baseHp * scale).round());
        final suffix = s.count > 1 ? ' ${String.fromCharCode(65 + i)}' : '';
        out.add(Combatant(
          id: newId(),
          name: '${s.name}$suffix',
          hp: hp,
          maxHp: hp,
          ac: s.ac ?? def?.ac ?? 12,
          attackBonus: s.attackBonus ?? def?.attackBonus ?? (3 + partyLevel ~/ 2),
          damage: s.damage ?? def?.damage ?? '1d8+${1 + partyLevel ~/ 3}',
          monsterId: def?.id,
          dexMod: def?.dexMod ?? 1,
          multi: def?.multi ?? 1,
          xp: def?.xp ?? (50 * partyLevel),
          attackName: s.attackName ?? def?.attackName ?? 'Strike',
          colorValue: def?.color.toARGB32() ?? 0xFF8C7246,
          type: def?.type ?? 'monstrosity',
        ));
      }
    }
    return out;
  }

  /// Creates combat state; returns initiative events.
  List<CombatEvent> begin(List<Combatant> enemies, {bool partySurprised = false, bool enemiesSurprised = false}) {
    final list = <Combatant>[];
    for (final ch in adventure.party) {
      if (ch.hp <= 0 && ch.isCompanion) continue;
      list.add(Combatant(
        id: 'pc_${ch.id}',
        name: ch.name,
        hp: ch.hp,
        maxHp: ch.maxHp,
        ac: ch.armorClass,
        attackBonus: ch.attackBonus,
        damage: ch.weaponDamage,
        isPlayer: ch.id == adventure.hero.id,
        isAlly: ch.id != adventure.hero.id,
        characterId: ch.id,
        dexMod: ch.initiative,
        multi: ch.attacksPerTurn,
        attackName: ch.weaponName,
        colorValue: ch.primaryClass.color.toARGB32(),
        type: 'humanoid',
        back: (ch.equippedWeapon?.def?.ranged ?? false) || (['wizard', 'sorcerer', 'warlock'].contains(ch.classLevels.keys.first) && ch.mod(ch.weaponAbility) < 3),
      ));
    }
    for (final e in enemies) {
      final abil = e.monsterId == null ? const <String>[] : (monsterById(e.monsterId!)?.abilities ?? const <String>[]);
      e.back = abil.contains('ranged');
    }
    // Lay out the battlefield: melee in front, ranged behind, sides facing.
    final taken = <String>{};
    void place(Combatant c, int col, int dir) {
      for (var off = 0; off < gridW; off++) {
        final x = (col + dir * off).clamp(0, gridW - 1);
        for (final dy in const [2, 1, 3, 0, 4]) {
          if (taken.add('$x,$dy')) {
            c.x = x;
            c.y = dy;
            return;
          }
        }
      }
    }

    for (final c in list) {
      place(c, c.back ? 0 : 1, 1);
    }
    for (final e in enemies) {
      place(e, e.back ? gridW - 1 : gridW - 3, e.back ? -1 : 1);
    }
    list.addAll(enemies);
    final rows = <List<String>>[];
    final groups = <Map<String, dynamic>>[];
    for (final c in list) {
      final d = rollDie(20);
      final surprised = (partySurprised && !c.isEnemy) || (enemiesSurprised && c.isEnemy);
      c.initiative = d + c.dexMod - (surprised ? 10 : 0);
      groups.add({
        'label': '${c.name}${surprised ? ' (surprised)' : ''}',
        'dice': [
          {'s': 20, 'v': d},
        ],
        'mod': c.dexMod - (surprised ? 10 : 0),
        'total': c.initiative,
      });
    }
    list.sort((a, b) => b.initiative.compareTo(a.initiative));
    for (final (i, c) in list.indexed) {
      rows.add(['${i + 1}. ${c.name}', '${c.initiative}${c.isEnemy ? ' · enemy' : (c.isPlayer ? ' · you' : ' · ally')}']);
    }
    adventure.combat = CombatState(combatants: list, environment: adventure.scene.location);
    final extra = <CombatEvent>[];
    // Frightful presence and opening wards.
    for (final foe in enemies) {
      final fr = ability(foe, 'frighten');
      if (fr == null) continue;
      final dc = int.tryParse(fr.split(':').last) ?? 12;
      for (final a in list.where((x) => !x.isEnemy)) {
        final sv = rollDie(20) + _saveMod(a, Ability.wis);
        if (sv < dc) {
          a.conditions.add('Frightened');
          characterFor(a)?.conditions.add('Frightened');
        }
      }
      extra.add(CombatEvent('${foe.name}\'s presence is terrifying!', CombatFx.roar, actorId: foe.id, details: {
        'title': 'Frightful presence',
        'subtitle': foe.name,
        'outcome': '${list.where((x) => !x.isEnemy && x.conditions.contains('Frightened')).map((x) => x.name).join(', ').ifEmpty('Nobody')} frightened',
        'ok': false,
        'lines': [
          ['Save', 'WIS DC $dc'],
        ],
        'rule': '${monsterAbilityText(fr)} Frightened creatures attack with disadvantage and can try a WIS save at the start of each of their turns to shake it off.',
      }));
    }
    for (final a in list.where((x) => !x.isEnemy)) {
      final ch = characterFor(a);
      if (ch == null) continue;
      if (ch.hasSub('abjuration')) {
        final ward = 2 * (ch.classLevels['wizard'] ?? 1) + ch.mod(Ability.int_);
        ch.tempHp = math.max(ch.tempHp, ward);
        extra.add(CombatEvent('${ch.name}\'s Arcane Ward shimmers into place ($ward temporary HP).', CombatFx.buff, actorId: a.id));
      }
      if (ch.hasSub('moon') && ch.classLevels.containsKey('druid')) {
        ch.tempHp = math.max(ch.tempHp, 10);
        ch.conditions.add('Wild Shape');
        extra.add(CombatEvent('${ch.name} shifts into a fearsome beast form (+10 temporary HP).', CombatFx.buff, actorId: a.id));
      }
      if (ch.hasSub('light')) a.conditions.add('Warding Flare');
    }
    if (enemiesSurprised) {
      for (final e in enemies) {
        e.conditions.add('Surprised');
      }
    }
    final e = CombatEvent(
      'Roll for initiative! ${list.map((c) => '${c.name} ${c.initiative}').join(' · ')}',
      CombatFx.roar,
      details: {
        'title': 'Initiative',
        'subtitle': '${enemies.length} ${enemies.length == 1 ? 'enemy' : 'enemies'} · ${list.length - enemies.length} in your party',
        'outcome': partySurprised ? 'You were surprised' : (enemiesSurprised ? 'You caught them off guard' : 'Battle begins'),
        'groups': groups,
        'lines': [
          ['Turn order', ''],
          ...rows,
        ],
        'rule': ruleInitiative,
      },
    );
    state.log.add(e.text);
    state.log.addAll(extra.map((x) => x.text));
    return [e, ...extra];
  }

  void _syncFromCharacter(Combatant c) {
    final ch = characterFor(c);
    if (ch != null) {
      c.hp = ch.hp;
      c.maxHp = ch.maxHp;
      c.ac = ch.armorClass;
    }
  }

  /// Pending side effects (concentration checks, reactions) produced while applying damage.
  final List<CombatEvent> _side = [];

  int _applyDamage(Combatant target, int amount, {bool weapon = false, bool magical = false}) {
    final ch = characterFor(target);
    if (ch != null) {
      var a = amount;
      if (ch.conditions.contains('Raging')) a = (a / 2).ceil();
      if (weapon && ch.hasFeat('heavy_armor_master') && (ch.equippedArmor?.def?.heavy ?? false)) a = math.max(0, a - 3);
      final dealt = ch.takeDamage(a);
      _syncFromCharacter(target);
      if (dealt > 0 && ch.concentration != null && ch.hp > 0) _concentrationCheck(target, ch, dealt);
      if (ch.hp <= 0 && ch.concentration != null) _dropConcentration(target, ch, reason: 'falls unconscious');
      return dealt;
    }
    var a = amount;
    if (weapon && !magical && ability(target, 'resist') != null) a = (a / 2).floor();
    target.hp = math.max(0, target.hp - a);
    return a;
  }

  void _concentrationCheck(Combatant c, Character ch, int damage) {
    final dc = math.max(10, damage ~/ 2);
    final mode = ch.hasFeat('war_caster') ? RollMode.advantage : RollMode.normal;
    final r = rollD20(modifier: ch.saveMod(Ability.con), mode: mode, dc: dc, label: 'Concentration');
    final spell = spellById(ch.concentration!);
    if (r.success) {
      _side.add(CombatEvent('${ch.name} keeps concentration on ${spell?.name ?? 'the spell'}. [CON ${r.total} vs DC $dc]', CombatFx.buff, actorId: c.id, roll: r, details: {
        'title': 'Concentration held',
        'subtitle': spell?.name ?? '',
        'outcome': 'Success',
        'ok': true,
        'groups': [d20Group('CON save', r, against: 'DC $dc')],
        'rule': ruleConcentration,
      }));
    } else {
      _dropConcentration(c, ch, reason: 'loses concentration', roll: r, dc: dc);
    }
  }

  static const _concConditions = {
    'bless': 'Blessed',
    'hex': 'Hexed',
    'hunters_mark': 'Hunter',
    'haste': 'Hasted',
    'blur': 'Blurred',
    'heroism': 'Heroic',
    'greater_invisibility': 'Invisible',
    'faerie_fire': 'Outlined',
    'hold_person': 'Paralyzed',
    'hypnotic_pattern': 'Paralyzed',
    'web': 'Restrained',
    'entangle': 'Restrained',
    'banishment': 'Banished',
    'witch_bolt': 'Witch Bolt',
    'flaming_sphere': 'Flaming Sphere',
    'call_lightning': 'Call Lightning',
    'cloud_of_daggers': 'Daggers',
    'moonbeam': 'Moonbeam',
    'spirit_guardians': 'Spirit Guardians',
  };

  void _dropConcentration(Combatant c, Character ch, {required String reason, D20Result? roll, int? dc}) {
    final id = ch.concentration;
    if (id == null) return;
    ch.concentration = null;
    final cond = _concConditions[id];
    if (cond != null) {
      for (final x in state.combatants) {
        x.conditions.remove(cond);
        characterFor(x)?.conditions.remove(cond);
      }
      ch.conditions.remove(cond);
    }
    final spell = spellById(id);
    _side.add(CombatEvent('${ch.name} $reason — ${spell?.name ?? 'the spell'} ends.', CombatFx.miss, actorId: c.id, roll: roll, details: {
      'title': 'Concentration broken',
      'subtitle': spell?.name ?? '',
      'outcome': '${spell?.name ?? 'Spell'} ends',
      'ok': false,
      if (roll != null) 'groups': [d20Group('CON save', roll, against: 'DC $dc')],
      'rule': ruleConcentration,
    }));
  }

  /// Flushes side events (concentration, reactions) into [events].
  void _flush(List<CombatEvent> events) {
    if (_side.isEmpty) return;
    events.addAll(_side);
    _side.clear();
  }

  void _applyHeal(Combatant target, int amount) {
    final ch = characterFor(target);
    if (ch != null) {
      ch.heal(amount);
      _syncFromCharacter(target);
    } else {
      target.hp = math.min(target.maxHp, target.hp + amount);
    }
  }

  bool _packHelp(Combatant attacker) => ability(attacker, 'pack') != null && state.combatants.any((x) => x.isEnemy == attacker.isEnemy && x.id != attacker.id && !x.down);

  /// An ally on the far side of the target flanks it.
  bool _flanking(Combatant attacker, Combatant target) {
    if (_isRanged(attacker) || !adjacent(attacker, target)) return false;
    final ox = target.x - (attacker.x - target.x), oy = target.y - (attacker.y - target.y);
    final ally = occupant(ox, oy);
    return ally != null && ally.isEnemy == attacker.isEnemy && !_incapacitated(ally);
  }

  bool _engaged(Combatant c) => _active.any((h) => h.isEnemy != c.isEnemy && adjacent(h, c) && !_incapacitated(h));

  bool _rangedInMelee(Combatant attacker) => _isRanged(attacker) && _engaged(attacker);

  bool _strongestFoe(Combatant attacker, Combatant target) {
    final ch = characterFor(attacker);
    if (ch == null || !ch.hasSub('vengeance')) return false;
    final foes = state.combatants.where((x) => x.isEnemy != attacker.isEnemy && !x.down).toList()..sort((a, b) => b.maxHp.compareTo(a.maxHp));
    return foes.isNotEmpty && foes.first.id == target.id;
  }

  bool _assassinate(Combatant attacker) => (characterFor(attacker)?.hasSub('assassin') ?? false) && state.round <= 1;

  List<(String, bool)> _modeFactors(Combatant attacker, Combatant target) => [
        if (attacker.conditions.contains('Hidden')) ('attacker was hidden', true),
        if (attacker.conditions.contains('Invisible')) ('attacker is invisible', true),
        if (attacker.conditions.contains('Heroic') && attacker.isEnemy == false) ('', false),
        if (target.conditions.contains('Prone')) ('target is prone', true),
        if (target.conditions.contains('Restrained')) ('target is restrained', true),
        if (target.conditions.contains('Paralyzed')) ('target is paralyzed', true),
        if (target.conditions.contains('Stunned')) ('target is stunned', true),
        if (attacker.conditions.contains('Blinded')) ('attacker is blinded', false),
        if (target.conditions.contains('Blinded')) ('target is blinded', true),
        if (target.conditions.contains('Outlined')) ('target is outlined by faerie fire', true),
        if (target.conditions.contains('Surprised')) ('target is surprised', true),
        if (_packHelp(attacker)) ('pack tactics', true),
        if (_flanking(attacker, target)) ('flanking', true),
        if (_strongestFoe(attacker, target)) ('Vow of Enmity', true),
        if (_assassinate(attacker)) ('Assassinate (first round)', true),
        if (target.conditions.contains('Dodging')) ('target is dodging', false),
        if (target.conditions.contains('Blurred')) ('target is blurred', false),
        if (target.conditions.contains('Invisible')) ('target is invisible', false),
        if (attacker.conditions.contains('Poisoned')) ('attacker is poisoned', false),
        if (attacker.conditions.contains('Frightened')) ('attacker is frightened', false),
        if (attacker.conditions.contains('Prone')) ('attacker is prone', false),
        if ((characterFor(attacker)?.encumbrance ?? 0) >= 2) ('attacker is heavily encumbered', false),
        if (_rangedInMelee(attacker)) ('ranged attack while engaged in melee', false),
        if (target.conditions.contains('Warding Flare') && attacker.isEnemy && state.round <= 1) ('Warding Flare', false),
      ].where((f) => f.$1.isNotEmpty).toList();

  bool _hasAdvantage(Combatant attacker, Combatant target) => _modeFactors(attacker, target).any((f) => f.$2);

  bool _hasDisadvantage(Combatant attacker, Combatant target) => _modeFactors(attacker, target).any((f) => !f.$2);

  List<String> _modeReasons(Combatant attacker, Combatant target) => [for (final f in _modeFactors(attacker, target)) '${f.$1} (${f.$2 ? 'advantage' : 'disadvantage'})'];

  /// Half cover for back-row targets protected by their front line.
  int coverBonus(Combatant attacker, Combatant target) {
    if (adjacent(attacker, target)) return 0;
    if (characterFor(attacker)?.hasFeat('sharpshooter') ?? false) return 0;
    return _line(attacker, target).any((p) => occupant(p.x, p.y, except: attacker) != null) ? 2 : 0;
  }

  RollMode rollModeFor(Combatant attacker, Combatant target) {
    final adv = _hasAdvantage(attacker, target);
    final dis = _hasDisadvantage(attacker, target);
    if (adv && !dis) return RollMode.advantage;
    if (dis && !adv) return RollMode.disadvantage;
    return RollMode.normal;
  }

  /// Weapon attack. [natural] lets the UI supply the visible d20 result.
  List<CombatEvent> attack(Combatant attacker, Combatant target, {int? natural, String? damageOverride, bool opportunity = false}) {
    final events = <CombatEvent>[];
    final ch = characterFor(attacker);
    // Ranged weapons spend ammunition; half is recovered after the fight.
    final wdef = ch?.equippedWeapon?.def;
    if (ch != null && wdef != null && damageOverride == null && wdef.ammo != null) {
      final ammo = ch.ammoFor(wdef);
      if (ammo == null) {
        final e = CombatEvent('${ch.name} reaches for ${wdef.ammo} and finds the quiver empty!', CombatFx.miss, actorId: attacker.id, details: {
          'title': 'Out of ammunition',
          'outcome': 'No ${wdef.ammo} left',
          'ok': false,
          'rule': 'Ranged weapons need ammunition. Buy more from a merchant, or equip a melee weapon from your inventory.',
        });
        state.log.add(e.text);
        return [e];
      }
      ammo.qty--;
      if (ammo.qty <= 0) ch.inventory.remove(ammo);
      attacker.conditions.add('AmmoSpent${attacker.conditions.where((c) => c.startsWith('AmmoSpent')).length}');
    }
    var mode = rollModeFor(attacker, target);
    final reasons = _modeReasons(attacker, target);
    if (opportunity && (ch?.hasFeat('sentinel') ?? false)) {
      mode = mode == RollMode.disadvantage ? RollMode.normal : RollMode.advantage;
      reasons.add('Sentinel (advantage)');
    }
    if (!opportunity && !_isRanged(attacker) && !_isRangedOnly(attacker) && !adjacent(attacker, target)) {
      events.addAll(approach(attacker, target));
      if (attacker.down) return events;
      if (!adjacent(attacker, target)) {
        final e = CombatEvent('${attacker.name} can\'t reach ${target.name} this turn.', CombatFx.miss, actorId: attacker.id, targetId: target.id, details: {
          'title': 'Out of reach',
          'outcome': '${dist(attacker, target) * 5} ft away',
          'ok': false,
          'rule': ruleRows,
        });
        events.add(e);
        state.log.addAll(events.map((x) => x.text));
        return events;
      }
    }
    var bonus = attacker.attackBonus;
    if (ch != null) bonus = ch.attackBonus;
    var blessBonus = 0;
    if (attacker.conditions.contains('Blessed')) {
      blessBonus = rollDie(4);
      bonus += blessBonus;
    }
    final devoted = ch != null && ch.isCompanion && ch.loyalty >= 80;
    if (devoted) bonus += 1;
    var inspiredBonus = 0;
    if (attacker.conditions.remove('Inspired')) {
      inspiredBonus = rollDie(6);
      bonus += inspiredBonus;
    }
    final cover = coverBonus(attacker, target);
    var ac = target.ac + cover;
    final roll0 = rollD20(modifier: bonus, mode: mode, dc: ac, label: '${attacker.name} → ${target.name}', forcedNatural: natural);
    final critAt = ch?.critRange ?? 20;
    var crit = roll0.natural >= critAt && !roll0.isFumble;
    if (_assassinate(attacker) && target.conditions.contains('Surprised')) crit = true;
    if (target.conditions.contains('Paralyzed') && !_isRanged(attacker)) crit = true;
    var hit = crit || roll0.success;
    // Reaction: Shield.
    final tch = characterFor(target);
    if (hit && !crit && tch != null && target.isPlayer && !target.conditions.contains('ReactionUsed') && tch.knows('shield') && tch.availableSlot(1) != null && roll0.total < ac + 5) {
      tch.spendSlot(tch.availableSlot(1)!);
      tch.conditions.add('Shielded');
      target.conditions.add('ReactionUsed');
      _syncFromCharacter(target);
      ac = target.ac + cover;
      hit = false;
      events.add(CombatEvent('${tch.name} reacts with Shield! (+5 AC)', CombatFx.buff, actorId: target.id, details: {
        'title': 'Reaction: Shield',
        'outcome': 'The attack is deflected',
        'ok': true,
        'lines': [
          ['Attack total', '${roll0.total}'],
          ['New AC', '$ac'],
          ['Slot', 'Level 1 · ${tch.slotsRemaining(1)} left'],
        ],
        'rule': 'Shield is a reaction: when you would be hit, add +5 to your AC until your next turn. The app uses it automatically when it would turn a hit into a miss.',
      }));
    }
    // Reaction: Counterspell against spellcasting monsters.
    if (hit && attacker.isEnemy && ability(attacker, 'spellcaster') != null) {
      final counter = state.combatants.where((x) => !x.isEnemy && !x.down && !x.conditions.contains('ReactionUsed')).map((x) => (x, characterFor(x))).where((p) => p.$2 != null && p.$2!.knows('counterspell') && p.$2!.availableSlot(3) != null).firstOrNull;
      if (counter != null) {
        final (cx, cch) = counter;
        cch!.spendSlot(cch.availableSlot(3)!);
        cx.conditions.add('ReactionUsed');
        final cr = rollD20(modifier: cch.mod(cch.spellAbility ?? Ability.int_), dc: 13, label: 'Counterspell');
        if (cr.success) {
          hit = false;
          events.add(CombatEvent('${cch.name} snuffs out ${attacker.name}\'s spell with Counterspell!', CombatFx.spell, actorId: cx.id, targetId: attacker.id, roll: cr, details: {
            'title': 'Reaction: Counterspell',
            'outcome': 'Spell countered',
            'ok': true,
            'groups': [d20Group('Spellcasting check', cr, against: 'DC 13')],
            'rule': 'Counterspell interrupts a creature casting a spell. Against powerful magic you make a spellcasting check; on a success the spell fails.',
          }));
        } else {
          events.add(CombatEvent('${cch.name}\'s Counterspell fails to unravel the magic.', CombatFx.miss, actorId: cx.id, roll: cr));
        }
      }
    }
    final roll = roll0;
    final hidden = attacker.conditions.remove('Hidden');
    attacker.conditions.remove('Invisible');
    final weapon = ch?.weaponName ?? attacker.attackName;
    final hpBefore = target.hp;
    final lines = <List<String>>[
      ['Weapon', weapon],
      ['Attack bonus', '${signed(bonus)}${blessBonus > 0 ? ' (includes Bless +$blessBonus)' : ''}${inspiredBonus > 0 ? ' (Bardic Inspiration +$inspiredBonus)' : ''}${devoted ? ' (devoted +1)' : ''}'],
      ['Target AC', cover > 0 ? '$ac (${target.ac} + 2 half cover, back row)' : '$ac'],
      if (opportunity) ['Opportunity attack', 'Triggered by moving out of reach'],
      if (critAt < 20) ['Critical range', '$critAt–20'],
      if (reasons.isNotEmpty) ['Roll mode', reasons.join(', ')],
    ];
    final groups = <Map<String, dynamic>>[d20Group('Attack roll', roll, against: 'AC $ac')];
    if (hit) {
      final dmgExpr = damageOverride ?? (ch?.weaponDamage ?? attacker.damage);
      var res = DiceExpression.parse(dmgExpr).roll(critical: crit);
      if (ch != null && ch.hasFeat('savage_attacker') && !_isRanged(attacker)) {
        final again = DiceExpression.parse(dmgExpr).roll(critical: crit);
        if (again.total > res.total) res = again;
      }
      var dmg = math.max(1, res.total);
      final damageType = ch?.equippedWeapon?.def?.damageType;
      groups.add(diceGroup(crit ? 'Damage (critical: dice doubled)' : 'Damage', res, suffix: damageType));
      final extras = <String>[];
      void bonusDice(String label, String expr, {String? type}) {
        final r = DiceExpression.parse(expr).roll(critical: crit);
        dmg += r.total;
        extras.add('$label +${r.total}');
        groups.add(diceGroup(label, r, suffix: type));
      }

      if (ch != null) {
        if (ch.conditions.contains('Raging')) {
          dmg += 2;
          extras.add('rage +2');
        }
        if (ch.weaponExtraDice != null) bonusDice(ch.equippedWeapon!.name, ch.weaponExtraDice!, type: ch.weaponExtraType);
        if (ch.sneakAttackDice > 0 && (hidden || roll.mode == RollMode.advantage || adventure.companions.isNotEmpty) && !attacker.conditions.contains('SneakUsed')) {
          attacker.conditions.add('SneakUsed');
          bonusDice('Sneak Attack', '${ch.sneakAttackDice}d6');
        }
        if (ch.conditions.contains('Hunter') || ch.conditions.contains('Hexed')) bonusDice(ch.conditions.contains('Hunter') ? "Hunter's Mark" : 'Hex', '1d6', type: ch.conditions.contains('Hexed') ? 'necrotic' : null);
        if (ch.hasSub('hunter') && target.hp < target.maxHp && !attacker.conditions.contains('ColossusUsed')) {
          attacker.conditions.add('ColossusUsed');
          bonusDice('Colossus Slayer', '1d8');
        }
        if (ch.hasSub('beast_master')) {
          final r = DiceExpression.parse('1d6').roll();
          dmg += r.total + ch.proficiency;
          extras.add('beast companion +${r.total + ch.proficiency}');
        }
        if (ch.hasSub('battle_master') && ch.superiorityDice > 0 && !attacker.conditions.contains('ManeuverUsed')) {
          ch.superiorityDice--;
          attacker.conditions.add('ManeuverUsed');
          bonusDice('Superiority die', '1d8');
        }
        if (ch.conditions.contains('Wild Shape')) {
          dmg += 2;
          extras.add('beast form +2');
        }
        if (ch.conditions.contains('Smite') && !_isRanged(attacker)) {
          ch.conditions.remove('Smite');
          bonusDice('Divine Smite', '${2 + (crit ? 0 : 0)}d8', type: 'radiant');
        }
        if (adventure.companions.isNotEmpty && state.combatants.any((x) => !x.isEnemy && !x.down && (characterFor(x)?.hasSub('valor') ?? false)) && !ch.hasSub('valor')) {
          bonusDice('Combat Inspiration', '1d6');
        }
      } else {
        final drain = ability(attacker, 'drain');
        if (drain != null) bonusDice('Life drain', drain.split(':')[1], type: 'necrotic');
        final charge = ability(attacker, 'charge');
        if (charge != null && !attacker.conditions.contains('Charged')) {
          attacker.conditions.add('Charged');
          bonusDice('Charge', charge.split(':')[1]);
        }
      }
      if (state.combatants.any((x) => !x.isEnemy && !x.down && (characterFor(x)?.hasSub('lore') ?? false)) && attacker.isEnemy && !attacker.conditions.contains('CutUsed')) {
        attacker.conditions.add('CutUsed');
        final r = rollDie(6);
        dmg = math.max(1, dmg - r);
        extras.add('Cutting Words −$r');
      }
      final magical = (ch?.weaponMagic ?? 0) > 0 || ch?.weaponExtraDice != null;
      final tc = characterFor(target);
      if (tc != null && (tc.classLevels['rogue'] ?? 0) >= 5 && !target.conditions.contains('ReactionUsed') && dmg >= 4) {
        target.conditions.add('ReactionUsed');
        dmg = (dmg / 2).ceil();
        extras.add('Uncanny Dodge halves it');
      }
      final dealt = _applyDamage(target, dmg, weapon: true, magical: magical);
      if (extras.isNotEmpty) lines.add(['Bonus damage', extras.join(', ')]);
      if (dealt != dmg) lines.add(['Damage taken', '$dealt (after resistance/temp HP)']);
      lines.add(['${target.name} HP', hpChange(hpBefore, target.hp, target.maxHp)]);
      final verb = crit ? 'CRITICALLY strikes' : 'hits';
      final t = '${attacker.name} $verb ${target.name} with $weapon for $dealt damage${extras.isEmpty ? '' : ' (${extras.join(', ')})'}. [${roll.natural}${signed(bonus)}=${roll.total} vs AC $ac]';
      events.add(CombatEvent(t, crit ? CombatFx.crit : CombatFx.hit,
          actorId: attacker.id,
          targetId: target.id,
          amount: dealt,
          roll: roll,
          details: {
            'title': '${opportunity ? 'Opportunity attack · ' : ''}${attacker.name} attacks',
            'subtitle': '$weapon → ${target.name}',
            'outcome': crit ? 'Critical hit · $dealt damage' : 'Hit · $dealt damage',
            'ok': !attacker.isEnemy,
            'groups': groups,
            'lines': lines,
            'rule': '$ruleAttack${mode != RollMode.normal ? '\n\n$ruleAdvantage' : ''}${cover > 0 ? '\n\n$ruleRows' : ''}',
          }));
      _flush(events);
      // On-hit monster riders.
      if (attacker.isEnemy && !target.down) {
        for (final code in ['poison', 'paralyze']) {
          final ab = ability(attacker, code);
          if (ab == null) continue;
          final dc = int.tryParse(ab.split(':').last) ?? 11;
          final sv = rollD20(modifier: _saveMod(target, Ability.con), dc: dc, label: 'CON save');
          if (!sv.success) {
            final cond = code == 'poison' ? 'Poisoned' : 'Paralyzed';
            target.conditions.add(cond);
            tch?.conditions.add(cond);
            events.add(CombatEvent('${target.name} is ${cond.toLowerCase()}! [CON ${sv.total} vs DC $dc]', CombatFx.hit, actorId: attacker.id, targetId: target.id, roll: sv, details: {
              'title': cond,
              'subtitle': '${attacker.name}\'s ${code == 'poison' ? 'venom' : 'touch'}',
              'outcome': '${target.name} is $cond',
              'ok': false,
              'groups': [d20Group('CON save', sv, against: 'DC $dc')],
              'rule': '${monsterAbilityText(ab)} ${conditionText(cond)}',
            }));
          }
        }
        // Reaction: Hellish Rebuke.
        if (tch != null && target.isPlayer && !target.conditions.contains('ReactionUsed') && tch.knows('hellish_rebuke') && tch.availableSlot(1) != null && !attacker.down) {
          tch.spendSlot(tch.availableSlot(1)!);
          target.conditions.add('ReactionUsed');
          final r = DiceExpression.parse('2d10').roll();
          final sv = rollDie(20) + _saveMod(attacker, Ability.dex);
          final dealtR = _applyDamage(attacker, sv >= tch.spellDc ? r.total ~/ 2 : r.total);
          events.add(CombatEvent('${tch.name} retaliates with Hellish Rebuke: ${attacker.name} is engulfed in flames for $dealtR fire damage!', CombatFx.spell, actorId: target.id, targetId: attacker.id, amount: dealtR, details: {
            'title': 'Reaction: Hellish Rebuke',
            'outcome': '$dealtR fire damage',
            'ok': true,
            'groups': [diceGroup('Fire damage', r, suffix: 'fire')],
            'lines': [
              ['DEX save', '$sv vs DC ${tch.spellDc}${sv >= tch.spellDc ? ' (half)' : ''}'],
            ],
            'rule': 'Hellish Rebuke is a reaction: when a creature damages you, it takes 2d10 fire damage (DEX save for half).',
          }));
          if (attacker.down) events.add(_downed(attacker));
        }
      }
      if (ch != null && ch.hasSub('open_hand') && !target.down && !target.conditions.contains('Prone') && rollDie(20) + _saveMod(target, Ability.dex) < ch.monkDc) {
        target.conditions.add('Prone');
        events.add(CombatEvent('${target.name} is knocked prone by the Open Hand.', CombatFx.buff, actorId: attacker.id, targetId: target.id));
      }
      if (target.down) {
        events.add(_downed(target));
        if (ch != null && ch.hasSub('fiend') && target.isEnemy) {
          final thp = math.max(1, ch.mod(Ability.cha) + (ch.classLevels['warlock'] ?? 1));
          ch.tempHp = math.max(ch.tempHp, thp);
          events.add(CombatEvent('Dark One\'s Blessing: ${ch.name} gains $thp temporary HP.', CombatFx.buff, actorId: attacker.id, amount: thp));
        }
      }
    } else {
      final t = roll.isFumble
          ? '${attacker.name} fumbles the attack against ${target.name}! [natural 1]'
          : '${attacker.name} misses ${target.name}. [${roll.natural}${signed(bonus)}=${roll.total} vs AC $ac]';
      events.add(CombatEvent(t, CombatFx.miss,
          actorId: attacker.id,
          targetId: target.id,
          roll: roll,
          details: {
            'title': '${opportunity ? 'Opportunity attack · ' : ''}${attacker.name} attacks',
            'subtitle': '$weapon → ${target.name}',
            'outcome': roll.isFumble ? 'Natural 1 · automatic miss' : 'Miss · ${roll.total} is below AC $ac',
            'ok': attacker.isEnemy,
            'groups': groups,
            'lines': lines,
            'rule': '$ruleAttack${mode != RollMode.normal ? '\n\n$ruleAdvantage' : ''}${cover > 0 ? '\n\n$ruleRows' : ''}',
          }));
    }
    state.log.addAll(events.map((e) => e.text));
    return events;
  }

  CombatEvent _downed(Combatant c) {
    final d = {
      'title': c.isEnemy ? '${c.name} is defeated' : '${c.name} falls unconscious',
      'outcome': c.isEnemy ? 'Enemy down' : '0 hit points',
      'ok': c.isEnemy,
      'lines': [
        ['HP', '0 / ${c.maxHp}'],
        if (c.isEnemy) ['XP value', '${c.xp}'],
      ],
      'rule': c.isEnemy ? 'Enemies reduced to 0 HP are defeated. XP is awarded to the whole party when the battle ends.' : ruleDeathSave,
    };
    if (c.isEnemy) return CombatEvent('${c.name} falls!', CombatFx.death, targetId: c.id, details: d);
    return CombatEvent('${c.name} collapses, unconscious!', CombatFx.death, targetId: c.id, details: d);
  }

  List<CombatEvent> castSpell(Combatant caster, SpellDef spell, List<Combatant> targets, {int? natural}) {
    final ch = characterFor(caster);
    final events = <CombatEvent>[];
    if (ch == null) return events;
    var slotLevel = 0;
    if (spell.level > 0) {
      final slot = ch.availableSlot(spell.level);
      if (slot == null) {
        return [CombatEvent('${ch.name} has no spell slots left for ${spell.name}.', CombatFx.miss)];
      }
      ch.spendSlot(slot);
      slotLevel = slot;
    }
    final upcast = math.max(0, slotLevel - spell.level);
    final spellBonus = spell.kind == SpellKind.heal ? 0 : ch.spellDamageBonus(spell);
    String scaledDice(String base) {
      final e = DiceExpression.parse(base);
      if (e.terms.isEmpty) return base;
      var count = e.terms.first.count;
      if (spell.level == 0 && spell.scaling) {
        count *= ch.level >= 11 ? 3 : (ch.level >= 5 ? 2 : 1);
      } else if (count > 0) {
        count += upcast;
      }
      // Keep every extra dice term (e.g. Ice Knife 1d10 + 2d6).
      return DiceExpression([DiceTerm(count, e.terms.first.sides), ...e.terms.skip(1)], e.modifier + spellBonus).toString();
    }

    // Concentration: a new concentration spell ends the previous one.
    if (spell.concentration) {
      if (ch.concentration != null && ch.concentration != spell.id) _dropConcentration(caster, ch, reason: 'switches concentration');
      ch.concentration = spell.id;
    }
    // Wild Magic surge.
    if (ch.hasSub('wild_magic') && spell.level > 0 && rollDie(20) == 1) {
      final surge = rollDie(4);
      switch (surge) {
        case 1:
          ch.tempHp = math.max(ch.tempHp, 2 * ch.level);
          events.add(CombatEvent('Wild Magic surge! ${ch.name} is wreathed in protective light (${2 * ch.level} temp HP).', CombatFx.buff, actorId: caster.id));
        case 2:
          ch.heal(ch.level + 4);
          events.add(CombatEvent('Wild Magic surge! Flowers bloom around ${ch.name}, healing ${ch.level + 4} HP.', CombatFx.heal, actorId: caster.id));
        case 3:
          for (final f in state.enemies.where((e) => !e.down)) {
            _applyDamage(f, rollDie(6));
          }
          events.add(CombatEvent('Wild Magic surge! A burst of raw force ripples through the enemies.', CombatFx.spell, actorId: caster.id));
        default:
          caster.conditions.add('Invisible');
          events.add(CombatEvent('Wild Magic surge! ${ch.name} blinks out of sight.', CombatFx.buff, actorId: caster.id));
      }
    }

    final baseLines = <List<String>>[
      ['Spell', '${spell.name} (${spell.level == 0 ? 'cantrip' : 'level ${spell.level}'})'],
      if (slotLevel > 0) ['Slot used', 'Level $slotLevel${upcast > 0 ? ' (upcast +$upcast dice)' : ''} · ${ch.slotsRemaining(slotLevel)} left'],
      ['Effect', spell.description],
    ];
    Map<String, dynamic> det(String outcome, bool ok, List<Map<String, dynamic>> groups, List<List<String>> lines, String rule) => {
          'title': '${ch.name} casts ${spell.name}',
          'subtitle': targets.map((t) => t.name).join(', '),
          'outcome': outcome,
          'ok': ok,
          'groups': groups,
          'lines': [...baseLines, ...lines],
          'rule': rule,
        };

    switch (spell.kind) {
      case SpellKind.attack:
        final t = targets.first;
        final touch = touchSpells.contains(spell.id);
        if (touch) events.addAll(approach(caster, t));
        var mode = rollModeFor(caster, t);
        final engaged = !touch && _engaged(caster);
        if (engaged && !_rangedInMelee(caster)) {
          mode = mode == RollMode.advantage ? RollMode.normal : (mode == RollMode.normal ? RollMode.disadvantage : mode);
        }
        final roll = rollD20(modifier: ch.spellAttack, mode: mode, dc: t.ac + (touch ? 0 : coverBonus(caster, t)), label: spell.name, forcedNatural: natural);
        final groups = <Map<String, dynamic>>[d20Group('Spell attack', roll, against: 'AC ${t.ac}')];
        if (roll.success) {
          final res = DiceExpression.parse(scaledDice(spell.dice ?? '1d8')).roll(critical: roll.isCrit);
          final before = t.hp;
          final dealt = _applyDamage(t, math.max(1, res.total));
          groups.add(diceGroup('Damage', res, suffix: spell.damageType));
          if (spell.id == 'vampiric_touch') {
            _applyHeal(caster, dealt ~/ 2);
          }
          if (spell.id == 'witch_bolt') caster.conditions.add('Witch Bolt');
          if (spell.id == 'ray_of_frost' || spell.id == 'chill_touch') t.conditions.add('Slowed');
          events.add(CombatEvent('${ch.name} casts ${spell.name}${roll.isCrit ? ' — a critical hit!' : ''} ${t.name} takes $dealt ${spell.damageType ?? ''} damage. [${roll.total} vs AC ${t.ac}]', roll.isCrit ? CombatFx.crit : CombatFx.spell,
              actorId: caster.id,
              targetId: t.id,
              amount: dealt,
              roll: roll,
              details: det(roll.isCrit ? 'Critical hit · $dealt damage' : 'Hit · $dealt damage', true, groups, [
                ['${t.name} HP', hpChange(before, t.hp, t.maxHp)],
              ], ruleAttack)));
          if (t.down) events.add(_downed(t));
        } else {
          events.add(CombatEvent('${ch.name}\'s ${spell.name} misses ${t.name}. [${roll.total} vs AC ${t.ac}]', CombatFx.miss,
              actorId: caster.id, targetId: t.id, roll: roll, details: det('Miss', false, groups, const [], ruleAttack)));
        }
      case SpellKind.save:
        final dice = spell.dice == null ? null : scaledDice(spell.dice!);
        final dmgRes = dice == null ? null : DiceExpression.parse(dice).roll();
        final dmgRoll = dmgRes?.total ?? 0;
        for (final t in targets) {
          final natSave = rollDie(20);
          final saveMod = t.isEnemy ? _saveMod(t, spell.save ?? Ability.dex) : 0;
          final save = natSave + saveMod;
          var saved = save >= ch.spellDc;
          var legRes = false;
          if (!saved && t.isEnemy && _useLegendaryResistance(t)) {
            saved = true;
            legRes = true;
          }
          final saveGroup = {
            'label': '${t.name}\'s ${spell.save?.short ?? ''} save',
            'dice': [
              {'s': 20, 'v': natSave},
            ],
            'mod': saveMod,
            'total': save,
            'against': 'DC ${ch.spellDc}',
          };
          if (dice == null && spell.save != null) {
            final cond = spell.condition ?? 'Paralyzed';
            if (!saved) t.conditions.add(cond);
            events.add(CombatEvent('${t.name} ${saved ? 'resists' : 'is affected by'} ${spell.name}${saved ? '' : ' (${cond.toLowerCase()})'}. [save $save vs DC ${ch.spellDc}]', saved ? CombatFx.miss : CombatFx.spell,
                actorId: caster.id,
                targetId: t.id,
                details: det(saved ? 'Resisted' : '${t.name} is $cond', !saved, [saveGroup], const [], '$ruleSave\n\n${conditionText(cond)}${spell.concentration ? '\n\n$ruleConcentration' : ''}')));
            continue;
          }
          if (legRes) {
            events.add(CombatEvent('${t.name} shrugs off the magic with Legendary Resistance!', CombatFx.roar, actorId: t.id, details: {
              'title': 'Legendary Resistance',
              'outcome': 'Failed save turned into a success',
              'ok': false,
              'rule': 'Legendary creatures can choose to succeed on a failed saving throw a few times per fight.',
            }));
          }
          final before = t.hp;
          final dmg = saved ? (spell.id == 'disintegrate' ? 0 : dmgRoll ~/ 2) : dmgRoll;
          final dealt = _applyDamage(t, dmg);
          if (spell.id == 'disintegrate' && t.down) t.conditions.add('Dust');
          if (spell.condition != null && !saved) t.conditions.add(spell.condition!);
          events.add(CombatEvent('${spell.name} engulfs ${t.name} for $dealt ${spell.damageType ?? ''} damage${saved ? ' (saved for half)' : ''}. [save $save vs DC ${ch.spellDc}]', CombatFx.spell,
              actorId: caster.id,
              targetId: t.id,
              amount: dealt,
              details: det(saved ? 'Saved · half damage ($dealt)' : 'Failed save · $dealt damage', true, [saveGroup, if (dmgRes != null) diceGroup(saved ? 'Damage (halved)' : 'Damage', dmgRes, suffix: spell.damageType)], [
                ['${t.name} HP', hpChange(before, t.hp, t.maxHp)],
                if (spell.aoe) ['Area', 'Hits up to 3 enemies with the same damage roll'],
              ], ruleSave)));
          if (t.down) events.add(_downed(t));
        }
        final persist = persistentSpells[spell.id];
        if (persist != null) {
          caster.conditions.add(persist);
          events.add(CombatEvent('${spell.name} lingers. It strikes again at the start of each of ${ch.name}\'s turns while concentration holds.', CombatFx.buff, actorId: caster.id));
        }
      case SpellKind.heal:
        final healTargets = (spell.id.startsWith('mass_') || spell.id == 'prayer_of_healing') ? state.combatants.where((x) => x.isEnemy == caster.isEnemy && (!x.down || spell.id == 'mass_heal')).toList() : targets;
        for (final t in healTargets) {
          if (spell.id == 'lesser_restoration') {
            final cured = t.conditions.where((c) => const ['Poisoned', 'Paralyzed', 'Blinded', 'Frightened', 'Restrained'].contains(c)).toList();
            t.conditions.removeAll(cured);
            characterFor(t)?.conditions.removeAll(cured);
            events.add(CombatEvent('${ch.name} cleanses ${t.name}${cured.isEmpty ? ', but nothing ails them' : ' of ${cured.join(', ').toLowerCase()}'}.', CombatFx.heal,
                actorId: caster.id, targetId: t.id, details: det(cured.isEmpty ? 'No conditions' : 'Cured ${cured.join(', ')}', true, const [], const [], 'Lesser Restoration ends one disease or condition: blinded, deafened, paralyzed or poisoned.')));
            continue;
          }
          if (spell.id == 'revivify' && !t.down) {
            events.add(CombatEvent('${t.name} is not in need of revival.', CombatFx.miss, actorId: caster.id));
            continue;
          }
          final res = DiceExpression.parse(scaledDice(spell.dice ?? '1d8')).roll();
          final mod = (ch.spellAbility == null || spell.id == 'aid' || spell.id == 'revivify') ? 0 : ch.mod(ch.spellAbility!);
          final amt = math.max(1, res.total + mod + (spell.id == 'revivify' ? 0 : ch.healBonus + (ch.hasSub('life') ? spell.level : 0)));
          final before = t.hp;
          if (spell.id == 'aid') {
            final tc = characterFor(t);
            if (tc != null) tc.maxHp += 5 + 5 * upcast;
            t.maxHp += 5 + 5 * upcast;
          }
          _applyHeal(t, amt);
          events.add(CombatEvent('${ch.name} casts ${spell.name}: ${t.name} regains $amt HP.', CombatFx.heal,
              actorId: caster.id,
              targetId: t.id,
              amount: amt,
              details: det('Healed $amt HP', true, [diceGroup('Healing', res)], [
                ['Spellcasting modifier', signed(mod)],
                ['${t.name} HP', hpChange(before, t.hp, t.maxHp)],
              ], ruleHeal)));
        }
      case SpellKind.buff:
        final t = targets.first;
        final cond = switch (spell.id) {
          'shield' => 'Shielded',
          'bless' => 'Blessed',
          'hex' => 'Hexed',
          'hunters_mark' => 'Hunter',
          'haste' => 'Hasted',
          'blur' => 'Blurred',
          'mirror_image' => 'Blurred',
          'heroism' => 'Heroic',
          'greater_invisibility' => 'Invisible',
          'mage_armor' => 'Mage Armor',
          'divine_favor' => 'Divine Favor',
          'armor_of_agathys' => 'Agathys',
          'false_life' => 'False Life',
          'guidance' => 'Guided',
          _ => 'Blessed',
        };
        if (cond == 'False Life' || cond == 'Agathys' || cond == 'Heroic') {
          final thp = cond == 'False Life' ? DiceExpression.parse('1d4+4').roll().total + 5 * upcast : (cond == 'Agathys' ? 5 + 5 * upcast : math.max(1, ch.mod(ch.spellAbility ?? Ability.cha)));
          ch.tempHp = math.max(ch.tempHp, thp);
          if (cond == 'Heroic') ch.conditions.add('Heroic');
        } else if (cond == 'Hasted' || cond == 'Invisible' || cond == 'Blurred') {
          t.conditions.add(cond);
          characterFor(t)?.conditions.add(cond);
          _syncFromCharacter(t);
        } else if (cond == 'Hexed' || cond == 'Hunter') {
          ch.conditions.add(cond);
          caster.conditions.add(cond);
        } else if (spell.id == 'bless') {
          for (final a in state.allies) {
            a.conditions.add('Blessed');
          }
        } else {
          ch.conditions.add(cond);
          _syncFromCharacter(caster);
        }
        events.add(CombatEvent('${ch.name} casts ${spell.name}. ${spell.description}', CombatFx.buff,
            actorId: caster.id, targetId: t.id, details: det('$cond active', true, const [], const [], 'Buffs last for the rest of the battle unless noted. ${conditionText(cond)}')));
      case SpellKind.utility:
        if (spell.id == 'magic_missile') {
          final t = targets.first;
          final res = DiceExpression.parse('${3 + upcast}d4+${3 + upcast}').roll();
          final before = t.hp;
          final dealt = _applyDamage(t, res.total);
          events.add(CombatEvent('Glowing darts streak from ${ch.name}\'s fingers — ${t.name} takes $dealt force damage.', CombatFx.spell,
              actorId: caster.id,
              targetId: t.id,
              amount: dealt,
              details: det('$dealt force damage', true, [diceGroup('Darts', res, suffix: 'force')], [
                ['${t.name} HP', hpChange(before, t.hp, t.maxHp)],
              ], 'Magic Missile never misses: each dart deals 1d4 + 1 force damage.')));
          if (t.down) events.add(_downed(t));
        } else if (spell.id == 'cloud_of_daggers' || spell.id == 'flaming_sphere') {
          final t = targets.first;
          final res = DiceExpression.parse(scaledDice(spell.dice ?? '4d4')).roll();
          final before = t.hp;
          final dealt = _applyDamage(t, res.total);
          caster.conditions.add(persistentSpells[spell.id]!);
          events.add(CombatEvent('${spell.name} shreds ${t.name} for $dealt damage.', CombatFx.spell,
              actorId: caster.id, targetId: t.id, amount: dealt, details: det('$dealt damage', true, [diceGroup('Damage', res, suffix: spell.damageType)], [
                ['${t.name} HP', hpChange(before, t.hp, t.maxHp)],
              ], spell.description)));
          if (t.down) events.add(_downed(t));
        } else if (spell.id == 'power_word_kill' || spell.id == 'power_word_stun') {
          final t = targets.first;
          final kill = spell.id == 'power_word_kill';
          final limit = kill ? 100 : 150;
          final works = t.hp <= limit;
          if (works) {
            if (kill) {
              t.hp = 0;
            } else {
              t.conditions.add('Stunned');
            }
          }
          events.add(CombatEvent(works ? (kill ? '${ch.name} speaks a word of power. ${t.name} simply dies.' : '${ch.name} speaks a word of power. ${t.name} is stunned!') : '${t.name} has too much life left for the word to take hold.', works ? CombatFx.spell : CombatFx.miss,
              actorId: caster.id, targetId: t.id, details: det(works ? (kill ? 'Slain' : 'Stunned') : 'No effect (${t.hp} HP > $limit)', works, const [], [
                ['${t.name} HP', '${t.hp}'],
              ], spell.description)));
          if (t.down) events.add(_downed(t));
        } else if (spell.id == 'sleep') {
          final res = DiceExpression.parse('${5 + upcast * 2}d8').roll();
          var pool = res.total;
          final sorted = state.enemies.where((e) => !e.down).toList()..sort((a, b) => a.hp.compareTo(b.hp));
          final slept = <String>[];
          for (final e in sorted) {
            if (e.hp <= pool) {
              pool -= e.hp;
              e.conditions.add('Paralyzed');
              slept.add(e.name);
            }
          }
          events.add(CombatEvent(slept.isEmpty ? 'The foes shrug off the drowsy magic.' : '${slept.join(', ')} slump into magical slumber.', CombatFx.spell,
              actorId: caster.id,
              details: det(slept.isEmpty ? 'No effect' : '${slept.length} asleep', slept.isNotEmpty, [diceGroup('Sleep pool (HP)', res)], [
                ['Asleep', slept.isEmpty ? 'None' : slept.join(', ')],
              ], 'Sleep affects creatures with the lowest current HP first, until the rolled pool runs out.')));
        } else {
          events.add(CombatEvent('${ch.name} casts ${spell.name}. ${spell.description}', CombatFx.buff, actorId: caster.id, details: det('Cast', true, const [], const [], spell.description)));
          if (spell.id == 'misty_step') {
            caster.conditions.add('Dodging');
            // Teleport 30 ft to the square farthest from enemies.
            final foes = _active.where((h) => h.isEnemy != caster.isEnemy).toList();
            math.Point<int>? best;
            var bestD = -1;
            for (var x = 0; x < gridW; x++) {
              for (var y = 0; y < gridH; y++) {
                if (occupant(x, y) != null || math.max((x - caster.x).abs(), (y - caster.y).abs()) > 6) continue;
                final d = foes.isEmpty ? 0 : foes.map((f) => math.max((f.x - x).abs(), (f.y - y).abs())).reduce(math.min);
                if (d > bestD) {
                  bestD = d;
                  best = math.Point(x, y);
                }
              }
            }
            if (best != null) {
              caster.x = best.x;
              caster.y = best.y;
            }
          }
        }
    }
    _flush(events);
    state.log.addAll(events.map((e) => e.text));
    return events;
  }

  List<CombatEvent> usePotion(Combatant user, Combatant target) {
    final ch = characterFor(user);
    if (ch == null) return [];
    final potion = ch.inventory.where((i) => i.def?.type == ItemType.potion && i.qty > 0).toList();
    if (potion.isEmpty) return [CombatEvent('No potions left!', CombatFx.miss)];
    potion.sort((a, b) => (a.def!.value).compareTo(b.def!.value));
    final p = potion.first;
    p.qty--;
    if (p.qty <= 0) ch.inventory.remove(p);
    final res = DiceExpression.parse(p.def!.heal ?? '2d4+2').roll();
    final before = target.hp;
    final healerBonus = ch.hasFeat('healer') ? 4 : 0;
    _applyHeal(target, res.total + healerBonus);
    final e = CombatEvent('${ch.name} ${user.id == target.id ? 'drinks' : 'feeds ${target.name}'} a ${p.name}, restoring ${res.total} HP.', CombatFx.heal,
        actorId: user.id,
        targetId: target.id,
        amount: res.total,
        details: {
          'title': p.name,
          'subtitle': '${ch.name} → ${target.name}',
          'outcome': 'Healed ${res.total} HP',
          'ok': true,
          'groups': [diceGroup('Healing', res)],
          'lines': [
            ['${target.name} HP', hpChange(before, target.hp, target.maxHp)],
            ['Potions left', '${ch.inventory.where((i) => i.def?.type == ItemType.potion).fold<int>(0, (a, i) => a + i.qty)}'],
          ],
          'rule': ruleHeal,
        });
    state.log.add(e.text);
    return [e];
  }

  List<CombatEvent> classAbility(Combatant user, String ability) {
    final ch = characterFor(user);
    if (ch == null) return [];
    CombatEvent e;
    final before = ch.hp;
    switch (ability) {
      case 'second_wind':
        final d = rollDie(10);
        final amt = d + ch.level;
        ch.heal(amt);
        ch.conditions.add('Second Wind Used');
        e = CombatEvent('${ch.name} catches a Second Wind, regaining $amt HP.', CombatFx.heal, actorId: user.id, amount: amt, details: {
          'title': 'Second Wind',
          'outcome': 'Healed $amt HP',
          'ok': true,
          'groups': [
            {
              'label': 'Healing',
              'dice': [
                {'s': 10, 'v': d},
              ],
              'mod': ch.level,
              'total': amt,
            },
          ],
          'lines': [
            ['HP', hpChange(before, ch.hp, ch.maxHp)],
            ['Uses', 'Once per rest'],
          ],
          'rule': 'Fighters can use a bonus action to regain 1d10 + fighter level HP once per rest.',
        });
      case 'rage':
        ch.conditions.add('Raging');
        ch.conditions.add('Rage Used');
        e = CombatEvent('${ch.name} flies into a RAGE! (+2 damage, resist physical damage)', CombatFx.roar, actorId: user.id, details: {
          'title': 'Rage',
          'outcome': 'Raging',
          'ok': true,
          'rule': 'While raging, a barbarian deals +2 damage with melee weapon attacks and takes half damage from physical attacks. Lasts the battle; once per rest.',
        });
      case 'lay_on_hands':
        final amt = math.min(ch.maxHp - ch.hp, 5 * ch.level);
        ch.heal(amt);
        ch.conditions.add('Lay Used');
        e = CombatEvent('${ch.name} lays hands upon their wounds, healing $amt HP.', CombatFx.heal, actorId: user.id, amount: amt, details: {
          'title': 'Lay on Hands',
          'outcome': 'Healed $amt HP',
          'ok': true,
          'lines': [
            ['Healing pool', '${5 * ch.level} (5 × level)'],
            ['HP', hpChange(before, ch.hp, ch.maxHp)],
          ],
          'rule': 'Paladins have a pool of healing equal to 5 × paladin level that refills on a long rest.',
        });
      case 'hide':
        user.conditions.add('Hidden');
        e = CombatEvent('${ch.name} melts into the shadows (advantage on next attack).', CombatFx.buff, actorId: user.id, details: {
          'title': 'Cunning Action: Hide',
          'outcome': 'Hidden',
          'ok': true,
          'rule': 'Rogues can hide as a bonus action. Your next attack has advantage and can trigger Sneak Attack.',
        });
      case 'smite':
        ch.conditions.add('Smite');
        ch.spendSlot(ch.availableSlot(1)!);
        e = CombatEvent('${ch.name}\'s weapon blazes with holy light (Divine Smite ready: +2d8 radiant on the next hit).', CombatFx.buff, actorId: user.id, details: {
          'title': 'Divine Smite',
          'outcome': 'Next melee hit deals +2d8 radiant',
          'ok': true,
          'rule': 'Paladins can expend a spell slot to deal extra radiant damage with a melee weapon hit.',
        });
      case 'fey_presence':
        ch.conditions.add('Fey Used');
        final foes = state.enemies.where((x) => !x.down).toList();
        for (final f in foes) {
          if (rollDie(20) + _saveMod(f, Ability.wis) < ch.spellDc) f.conditions.add('Frightened');
        }
        e = CombatEvent('${ch.name} unleashes a dazzling Fey Presence! ${foes.where((f) => f.conditions.contains('Frightened')).map((f) => f.name).join(', ').ifEmpty('No one')} cowers.', CombatFx.spell, actorId: user.id, details: {
          'title': 'Fey Presence',
          'ok': true,
          'outcome': 'Enemies frightened',
          'rule': 'Archfey warlocks can frighten nearby creatures once per rest (WIS save vs your spell DC).',
        });
      case 'action_surge':
        ch.conditions.add('Surge Used');
        ch.conditions.add('Surging');
        e = CombatEvent('${ch.name} surges with renewed vigor: one more action this turn!', CombatFx.buff, actorId: user.id, details: {
          'title': 'Action Surge',
          'outcome': 'Take an extra action',
          'ok': true,
          'rule': 'Fighters can push past their limits once per rest to take one additional action on their turn.',
        });
      case 'offhand':
        final off = offhandWeapon(ch)!;
        final foe = meleeTargets(user).where((x) => !x.down).firstOrNull;
        if (foe == null) return [];
        final mod = ch.hasFeat('dual_wielder') ? ch.weaponDamageBonus : math.min(0, ch.mod(ch.weaponAbility));
        user.conditions.add('Offhand Used');
        final evs = attack(user, foe, damageOverride: '${off.def!.damage}${mod == 0 ? '' : (mod > 0 ? '+$mod' : '$mod')}');
        return [
          CombatEvent('${ch.name} strikes with the off-hand ${off.name}.', CombatFx.buff, actorId: user.id, details: {
            'title': 'Two-weapon fighting',
            'outcome': 'Bonus attack with ${off.name}',
            'ok': true,
            'rule': 'When you attack with a light melee weapon in one hand, you can use a bonus action to attack with a different light weapon in the other. You don\'t add your ability modifier to its damage unless it is negative.',
          }),
          ...evs,
        ];
      case 'flurry':
        ch.conditions.add('KiUsed${kiMax(ch) - kiLeft(ch)}');
        ch.conditions.add('Flurry Used');
        final evs = <CombatEvent>[CombatEvent('${ch.name} unleashes a Flurry of Blows! (1 ki, ${kiLeft(ch)} left)', CombatFx.buff, actorId: user.id, details: {
          'title': 'Flurry of Blows',
          'outcome': 'Two unarmed strikes',
          'ok': true,
          'rule': 'Monks can spend 1 ki point after attacking to make two unarmed strikes as a bonus action. Ki returns on a short rest.',
        })];
        final die = (ch.classLevels['monk'] ?? 1) >= 5 ? '1d6' : '1d4';
        for (var i = 0; i < 2; i++) {
          final foe = meleeTargets(user).where((x) => !x.down).firstOrNull;
          if (foe == null) break;
          final m = ch.mod(ch.weaponAbility);
          evs.addAll(attack(user, foe, damageOverride: '$die${m >= 0 ? '+$m' : '$m'}'));
        }
        return evs;
      case 'inspire':
        ch.conditions.add('Inspire Used');
        final allies = state.combatants.where((x) => !x.isEnemy && x.id != user.id && !x.down).toList();
        for (final a in allies) {
          a.conditions.add('Inspired');
        }
        e = CombatEvent('${ch.name} plays a stirring refrain. ${allies.isEmpty ? 'But nobody is there to hear it.' : '${allies.map((a) => a.name).join(', ')} feel${allies.length == 1 ? 's' : ''} inspired (+1d6 to the next attack).'}', CombatFx.buff, actorId: user.id, details: {
          'title': 'Bardic Inspiration',
          'outcome': 'Allies gain +1d6 on their next attack',
          'ok': true,
          'rule': 'Bards inspire others with words or music. An inspired creature adds a d6 to one attack roll.',
        });
      case 'turn_undead':
        ch.conditions.add('Channel Used');
        final undead = state.enemies.where((x) => !x.down && x.type == 'undead').toList();
        final turned = <String>[];
        for (final u in undead) {
          if (rollDie(20) + _saveMod(u, Ability.wis) < ch.spellDc) {
            u.conditions.add('Turned');
            turned.add(u.name);
          }
        }
        e = CombatEvent(turned.isEmpty ? '${ch.name} presents a holy symbol, but the dead hold their ground.' : '${ch.name} presents a holy symbol! ${turned.join(', ')} recoil${turned.length == 1 ? 's' : ''} in terror.', CombatFx.spell, actorId: user.id, details: {
          'title': 'Channel Divinity: Turn Undead',
          'outcome': turned.isEmpty ? 'No undead turned' : '${turned.length} turned',
          'ok': turned.isNotEmpty,
          'lines': [
            ['Save', 'WIS vs DC ${ch.spellDc}'],
          ],
          'rule': 'Once per rest, clerics and paladins can force undead to make a Wisdom save or be turned: they flee and can\'t attack.',
        });
      case 'shove':
        final foe = meleeTargets(user).where((x) => !x.down).firstOrNull;
        if (foe == null) return [];
        final mine = rollD20(modifier: ch.skillMod(Skill.athletics), label: 'Athletics');
        final theirs = rollDie(20) + math.max(_saveMod(foe, Ability.str), foe.dexMod);
        final ok = mine.total >= theirs;
        if (ok) foe.conditions.add('Prone');
        e = CombatEvent(ok ? '${ch.name} shoves ${foe.name} to the ground!' : '${foe.name} braces and doesn\'t budge.', ok ? CombatFx.hit : CombatFx.miss, actorId: user.id, targetId: foe.id, roll: mine, details: {
          'title': 'Shove',
          'outcome': ok ? '${foe.name} is prone' : 'Resisted',
          'ok': ok,
          'groups': [d20Group('Athletics', mine, against: 'contest $theirs')],
          'rule': 'Shove: an Athletics check contested by the target\'s Athletics or Acrobatics. On a win the target is knocked prone, and melee attacks against it have advantage.',
        });
      case 'disengage':
        user.conditions.add('Disengaged');
        e = CombatEvent('${ch.name} disengages, ready to slip away safely.', CombatFx.buff, actorId: user.id, details: {
          'title': 'Disengage',
          'outcome': 'No opportunity attacks this turn',
          'ok': true,
          'rule': 'Taking the Disengage action means your movement doesn\'t provoke opportunity attacks for the rest of the turn.',
        });
      case 'dodge':
        user.conditions.add('Dodging');
        e = CombatEvent('${ch.name} takes a defensive stance (attacks against them have disadvantage).', CombatFx.buff, actorId: user.id, details: {
          'title': 'Dodge',
          'outcome': 'Dodging until your next turn',
          'ok': true,
          'rule': 'Attack rolls against a dodging creature have disadvantage. $ruleAdvantage',
        });
      default:
        e = CombatEvent('Nothing happens.', CombatFx.miss);
    }
    _syncFromCharacter(user);
    state.log.add(e.text);
    return [e];
  }

  List<String> availableAbilities(Character ch) {
    final out = <String>['dodge'];
    if (ch.classLevels.containsKey('fighter') && !ch.conditions.contains('Second Wind Used')) out.add('second_wind');
    if (ch.classLevels.containsKey('barbarian') && !ch.conditions.contains('Rage Used')) out.add('rage');
    if (ch.classLevels.containsKey('paladin') && !ch.conditions.contains('Lay Used') && ch.hp < ch.maxHp) out.add('lay_on_hands');
    if (ch.classLevels.containsKey('rogue') || ch.hasSub('shadow')) out.add('hide');
    if (ch.classLevels.containsKey('paladin') && (ch.classLevels['paladin'] ?? 0) >= 2 && ch.availableSlot(1) != null && !ch.conditions.contains('Smite')) out.add('smite');
    if (ch.hasSub('archfey') && !ch.conditions.contains('Fey Used')) out.add('fey_presence');
    if ((ch.classLevels['fighter'] ?? 0) >= 2 && !ch.conditions.contains('Surge Used')) out.add('action_surge');
    if (offhandWeapon(ch) != null && !ch.conditions.contains('Offhand Used')) out.add('offhand');
    if (kiLeft(ch) > 0 && !ch.conditions.contains('Flurry Used')) out.add('flurry');
    if (ch.classLevels.containsKey('bard') && !ch.conditions.contains('Inspire Used')) out.add('inspire');
    if (((ch.classLevels['cleric'] ?? 0) >= 2 || (ch.classLevels['paladin'] ?? 0) >= 3) && !ch.conditions.contains('Channel Used') && state.enemies.any((e) => !e.down && e.type == 'undead')) out.add('turn_undead');
    out.add('shove');
    out.add('disengage');
    return out;
  }

  /// Attempt to flee. Returns true on success.
  (bool, CombatEvent) flee(Combatant user, {int? natural}) {
    final ch = characterFor(user)!;
    final standing = state.enemies.where((e) => !e.down).length;
    final dc = 8 + standing * 2;
    final skill = ch.skillMod(Skill.athletics) >= ch.skillMod(Skill.acrobatics) ? Skill.athletics : Skill.acrobatics;
    final r = rollD20(modifier: ch.skillMod(skill), dc: dc, label: skill.label, forcedNatural: natural);
    final e = CombatEvent(r.success ? 'You break away and escape! [${r.total} vs DC $dc]' : 'You fail to escape! [${r.total} vs DC $dc]', r.success ? CombatFx.flee : CombatFx.miss, roll: r, details: {
      'title': 'Flee',
      'subtitle': '${skill.label} check',
      'outcome': r.success ? 'Escaped' : 'Couldn\'t get away',
      'ok': r.success,
      'groups': [d20Group('${skill.label} check', r, against: 'DC $dc')],
      'lines': [
        ['Enemies standing', '$standing'],
      ],
      'rule': ruleFlee,
    });
    state.log.add(e.text);
    return (r.success, e);
  }

  /// Advances to the next living combatant. Clears per-turn conditions.
  void nextTurn() {
    final n = state.combatants.length;
    for (var i = 0; i < n; i++) {
      state.turn++;
      if (state.turn >= n) {
        state.turn = 0;
        state.round++;
      }
      final c = state.current;
      c.conditions.remove('Dodging');
      c.conditions.remove('SneakUsed');
      c.conditions.remove('ColossusUsed');
      c.conditions.removeWhere((x) => x.startsWith('Step'));
      final cc = characterFor(c);
      cc?.conditions.removeAll(const ['Offhand Used', 'Flurry Used', 'Surging']);
      c.conditions.remove('ReactionUsed');
      c.conditions.remove('Disengaged');
      c.conditions.remove('Surprised');
      if (!c.down) {
        if (c.conditions.contains('Paralyzed') && !c.conditions.contains('Banished') && rollDie(20) >= 12) {
          c.conditions.remove('Paralyzed');
          state.log.add('${c.name} shakes off the paralysis.');
        }
        if (c.conditions.contains('Frightened') && rollDie(20) + _saveMod(c, Ability.wis) >= 13) {
          c.conditions.remove('Frightened');
          characterFor(c)?.conditions.remove('Frightened');
          state.log.add('${c.name} steels their nerve.');
        }
        if (c.conditions.contains('Prone')) c.conditions.remove('Prone');
        c.conditions.remove('Slowed');
        final ch = characterFor(c);
        if (ch != null) ch.conditions.remove('Shielded');
        return;
      }
    }
  }

  bool _useLegendaryResistance(Combatant c) {
    final lr = ability(c, 'legres');
    if (lr == null) return false;
    final max = int.tryParse(lr.split(':').last) ?? 1;
    final used = c.conditions.where((x) => x.startsWith('LegRes')).length;
    if (used >= max) return false;
    c.conditions.add('LegRes$used');
    return true;
  }

  /// After a non-legendary creature's turn, legendary foes may act out of turn.
  List<CombatEvent> legendaryActions() {
    final out = <CombatEvent>[];
    final just = state.current;
    for (final boss in state.enemies.where((e) => !e.down && e.id != just.id && !e.conditions.any((x) => const ['Paralyzed', 'Stunned', 'Charmed', 'Banished', 'Turned'].contains(x)))) {
      final la = ability(boss, 'legendary');
      if (la == null) continue;
      final max = int.tryParse(la.split(':').last) ?? 1;
      final used = boss.conditions.where((x) => x.startsWith('LegAct')).length;
      if (used >= max || rollDie(100) > 60) continue;
      final foes = state.allies.where((a) => !a.down).toList();
      if (foes.isEmpty) break;
      boss.conditions.add('LegAct$used');
      final target = foes[rollDie(foes.length) - 1];
      out.add(CombatEvent('${boss.name} takes a legendary action!', CombatFx.roar, actorId: boss.id, details: {
        'title': 'Legendary action',
        'subtitle': boss.name,
        'outcome': '${used + 1} of $max this round',
        'ok': false,
        'rule': monsterAbilityText(la),
      }));
      out.addAll(attack(boss, target, damageOverride: _secondaryDamage(boss.damage)));
    }
    state.log.addAll(out.where((e) => e.text.contains('legendary')).map((e) => e.text));
    return out;
  }

  /// Effects at the start of the current creature's turn (regeneration, breath recharge).
  List<CombatEvent> startOfTurn() {
    final c = state.current;
    final out = <CombatEvent>[];
    c.conditions.removeWhere((x) => x.startsWith('LegAct'));
    if (c.down) return out;
    final regen = ability(c, 'regen');
    if (regen != null && c.hp < c.maxHp) {
      final n = int.tryParse(regen.split(':')[1]) ?? 5;
      final before = c.hp;
      c.hp = math.min(c.maxHp, c.hp + n);
      out.add(CombatEvent('${c.name} regenerates ${c.hp - before} HP.', CombatFx.heal, actorId: c.id, amount: c.hp - before, details: {
        'title': 'Regeneration',
        'outcome': '+${c.hp - before} HP',
        'ok': false,
        'lines': [
          ['HP', hpChange(before, c.hp, c.maxHp)],
        ],
        'rule': monsterAbilityText(regen),
      }));
    }
    if (ability(c, 'breath') != null && !c.breathReady) {
      final r = rollDie(6);
      if (r >= 5) {
        c.breathReady = true;
        out.add(CombatEvent('${c.name} draws a deep, crackling breath… (breath weapon recharged on a $r)', CombatFx.roar, actorId: c.id));
      }
    }
    for (final cond in persistentSpells.values) {
      if (!c.conditions.contains(cond)) continue;
      final ch = characterFor(c);
      if (ch == null || ch.concentration == null) {
        c.conditions.remove(cond);
        continue;
      }
      final foes = state.combatants.where((e) => e.isEnemy != c.isEnemy && !e.down && !e.conditions.contains('Banished')).toList();
      if (foes.isEmpty) continue;
      final hits = cond == 'Spirit Guardians' ? foes.where((f) => dist(c, f) <= 3).toList() : [foes.first];
      final dice = switch (cond) { 'Witch Bolt' => '1d12', 'Moonbeam' => '2d10', 'Call Lightning' => '3d10', 'Spirit Guardians' => '3d8', 'Flaming Sphere' => '2d6', _ => '4d4' };
      for (final foe in hits.isEmpty ? [foes.first] : hits) {
        final res = DiceExpression.parse(dice).roll();
        final dealt = _applyDamage(foe, res.total);
        out.add(CombatEvent('$cond strikes ${foe.name} for $dealt damage.', CombatFx.spell, actorId: c.id, targetId: foe.id, amount: dealt, details: {
          'title': cond,
          'subtitle': 'Concentration spell · ${foe.name}',
          'outcome': '$dealt damage',
          'ok': true,
          'groups': [diceGroup('Damage', res)],
          'rule': ruleConcentration,
        }));
        if (foe.down) out.add(_downed(foe));
      }
    }
    state.log.addAll(out.map((e) => e.text));
    return out;
  }

  /// Runs the automatic turn of the current non-player combatant.
  List<CombatEvent> autoTurn() {
    final c = state.current;
    if (c.down) return [];
    if (c.conditions.contains('Banished')) {
      final e = CombatEvent('${c.name} is banished to another plane.', CombatFx.miss, actorId: c.id);
      state.log.add(e.text);
      return [e];
    }
    if (c.conditions.contains('Turned')) {
      if (rollDie(20) >= 15) c.conditions.remove('Turned');
      final e = CombatEvent('${c.name} cowers from the holy light${c.conditions.contains('Turned') ? '' : ', then recovers'}.', CombatFx.miss, actorId: c.id, details: {
        'title': 'Turned',
        'outcome': '${c.name} loses its turn',
        'rule': 'Turned undead spend their turns fleeing and can\'t attack. Each turn they have a chance to shake it off.',
      });
      state.log.add(e.text);
      return [e];
    }
    final incap = const ['Paralyzed', 'Stunned', 'Charmed'].where(c.conditions.contains).firstOrNull;
    if (incap != null) {
      if (incap != 'Paralyzed' && rollDie(20) + _saveMod(c, Ability.wis) >= 15) c.conditions.remove(incap);
      final e = CombatEvent('${c.name} is unable to act!', CombatFx.miss, actorId: c.id, details: {
        'title': '${c.name} loses their turn',
        'outcome': incap,
        'rule': conditionText(incap).isEmpty ? '$incap creatures can\'t take actions. Each turn they may shake it off.' : conditionText(incap),
      });
      state.log.add(e.text);
      return [e];
    }
    if (c.isEnemy) return _enemyTurn(c);
    return _companionTurn(c);
  }

  List<CombatEvent> _enemyTurn(Combatant c) {
    final all = state.allies.where((a) => !a.down).toList();
    if (all.isEmpty) return [];
    final events = <CombatEvent>[];
    // Healing when bloodied (once).
    final heal = ability(c, 'heal');
    if (heal != null && c.hp < c.maxHp / 2 && !c.conditions.contains('Healed')) {
      c.conditions.add('Healed');
      final r = DiceExpression.parse(heal.split(':')[1]).roll();
      final before = c.hp;
      c.hp = math.min(c.maxHp, c.hp + r.total);
      final e = CombatEvent('${c.name} rallies and heals ${c.hp - before} HP.', CombatFx.heal, actorId: c.id, amount: c.hp - before, details: {
        'title': '${c.name} heals',
        'outcome': '+${c.hp - before} HP',
        'ok': false,
        'groups': [diceGroup('Healing', r)],
        'rule': monsterAbilityText(heal),
      });
      state.log.add(e.text);
      return [e];
    }
    // Breath weapon hits the whole party.
    final breath = ability(c, 'breath');
    if (breath != null && c.breathReady) {
      c.breathReady = false;
      final p = breath.split(':');
      final type = p[1];
      final dice = p[2];
      final saveAb = AbilityX.fromShort(p[3]);
      final dc = int.tryParse(p[4]) ?? 13;
      final res = DiceExpression.parse(dice).roll();
      final lines = <List<String>>[];
      for (final t in all) {
        final sv = rollDie(20) + _saveMod(t, saveAb);
        final before = t.hp;
        final tc = characterFor(t);
        final evasion = saveAb == Ability.dex && tc != null && ((tc.classLevels['rogue'] ?? 0) >= 7 || (tc.classLevels['monk'] ?? 0) >= 7);
        final dealt = _applyDamage(t, sv >= dc ? (evasion ? 0 : res.total ~/ 2) : (evasion ? res.total ~/ 2 : res.total));
        lines.add([t.name, '${sv >= dc ? 'saved' : 'failed'} ($sv) · $dealt damage · ${hpChange(before, t.hp, t.maxHp)}']);
      }
      events.add(CombatEvent('${c.name} unleashes its breath weapon! A torrent of $type washes over the party.', CombatFx.crit, actorId: c.id, amount: res.total, details: {
        'title': 'Breath weapon',
        'subtitle': c.name,
        'outcome': '${res.total} $type damage',
        'ok': false,
        'groups': [diceGroup('Damage', res, suffix: type)],
        'lines': [
          ['Save', '${saveAb.short} DC $dc for half'],
          ...lines,
        ],
        'rule': monsterAbilityText(breath),
      }));
      _flush(events);
      for (final t in all.where((t) => t.down)) {
        events.add(_downed(t));
      }
      state.log.addAll(events.map((e) => e.text));
      return events;
    }
    // Ranged monsters keep their distance; melee ones close in on the nearest foe.
    final ranged = _isRangedOnly(c);
    if (ranged) events.addAll(_kite(c));
    final targets = List<Combatant>.of(all)
      ..sort((a, b) {
        final d = ranged ? 0 : dist(c, a).compareTo(dist(c, b));
        return d != 0 ? d : (a.hp + a.ac * 2).compareTo(b.hp + b.ac * 2);
      });
    final target = rollDie(100) <= 70 ? targets.first : targets[rollDie(targets.length) - 1];
    for (var i = 0; i < c.multi; i++) {
      if (target.down) break;
      final dmg = i == 0 ? c.damage : _secondaryDamage(c.damage);
      events.addAll(attack(c, target, damageOverride: dmg));
    }
    return events;
  }

  String _secondaryDamage(String d) {
    final e = DiceExpression.parse(d);
    if (e.terms.isEmpty) return d;
    final t = e.terms.first;
    return DiceExpression([DiceTerm(math.max(1, t.count - (t.count > 1 ? 1 : 0)), math.max(4, t.sides - 2))], e.modifier).toString();
  }

  // ------------------------------------------------------- companion orders

  static const orders = {
    'free': ('Act freely', 'Fight however they think best.'),
    'focus': ('Attack my target', 'Go after the enemy you have selected.'),
    'defend': ('Protect me', 'Stay close and strike whatever threatens you.'),
    'heal': ('Keep us alive', 'Heal and use potions early.'),
    'hold': ('Hang back', 'Stay out of melee and use ranged attacks or spells.'),
  };

  String orderOf(Combatant c) => c.conditions.where((x) => x.startsWith('Order:')).map((x) => x.split(':')[1]).firstOrNull ?? 'free';
  String? _orderTarget(Combatant c) => c.conditions.where((x) => x.startsWith('Order:focus:')).map((x) => x.split(':')[2]).firstOrNull;

  void setOrder(Combatant c, String order, {String? targetId}) {
    c.conditions.removeWhere((x) => x.startsWith('Order:'));
    if (order != 'free') c.conditions.add(order == 'focus' && targetId != null ? 'Order:focus:$targetId' : 'Order:$order');
  }

  List<CombatEvent> _companionTurn(Combatant c) {
    final ch = characterFor(c);
    final foes = state.enemies.where((e) => !e.down && !e.conditions.contains('Banished')).toList();
    if (ch == null || foes.isEmpty) return [];
    final order = orderOf(c);
    final player = state.combatants.where((x) => x.isPlayer).firstOrNull;
    final events = <CombatEvent>[];
    if (order == 'focus') {
      final t = byId(_orderTarget(c) ?? '');
      if (t != null && !t.down) {
        foes
          ..remove(t)
          ..insert(0, t);
      } else {
        setOrder(c, 'free');
      }
    }
    if (order == 'defend' && player != null) {
      foes.sort((a, b) => dist(a, player).compareTo(dist(b, player)));
      if (!adjacent(c, player)) events.addAll(approach(c, player));
      if (foes.every((f) => dist(f, player) > 1) && events.isEmpty) {
        c.conditions.add('Dodging');
        return [CombatEvent('${c.name} guards ${player.name}.', CombatFx.buff, actorId: c.id)];
      }
    }
    final healAt = order == 'heal' ? 0.7 : 0.35;
    final wounded = state.allies.where((a) => !a.down || a.isPlayer).where((a) => a.hp / a.maxHp < healAt).toList()..sort((a, b) => (a.hp / a.maxHp).compareTo(b.hp / b.maxHp));
    final heals = ch.knownSpellDefs.where((s) => s.kind == SpellKind.heal && ch.availableSlot(s.level) != null).toList();
    if (wounded.isNotEmpty && heals.isNotEmpty) {
      return castSpell(c, heals.first, [wounded.first]);
    }
    if (ch.hp < ch.maxHp * 0.3 && ch.inventory.any((i) => i.def?.type == ItemType.potion)) {
      return usePotion(c, c);
    }
    if (order == 'free') foes.sort((a, b) => (dist(c, a) * 4 + a.hp ~/ 4).compareTo(dist(c, b) * 4 + b.hp ~/ 4));
    final target = foes.first;
    if (order == 'hold') events.addAll(_kite(c));
    final damaging = ch.knownSpellDefs.where((s) => (s.kind == SpellKind.attack || s.kind == SpellKind.save || s.id == 'magic_missile') && s.dice != null && !(order == 'hold' && touchSpells.contains(s.id))).toList();
    if (damaging.isNotEmpty && (order == 'hold' || ch.mod(ch.spellAbility!) >= ch.mod(ch.weaponAbility))) {
      final leveled = damaging.where((s) => s.level > 0 && ch.availableSlot(s.level) != null).toList();
      final useSlot = leveled.isNotEmpty && (foes.length >= 2 || target.hp > 15) && rollDie(100) <= 55;
      final spell = useSlot ? (leveled..sort((a, b) => b.level.compareTo(a.level))).first : damaging.where((s) => s.level == 0).firstOrNull;
      if (spell != null) {
        final tgts = spell.aoe ? foes.take(3).toList() : [target];
        return [...events, ...castSpell(c, spell, tgts)];
      }
    }
    if (order == 'hold' && !_isRanged(c)) {
      c.conditions.add('Dodging');
      return [...events, CombatEvent('${c.name} holds back, staying out of the fray.', CombatFx.buff, actorId: c.id)];
    }
    final reach = order == 'free' ? meleeTargets(c) : foes;
    for (var i = 0; i < ch.attacksPerTurn; i++) {
      final t = reach.firstWhere((f) => !f.down, orElse: () => target);
      if (t.down) break;
      events.addAll(attack(c, t));
    }
    return events;
  }

  int get xpReward => state.enemies.fold(0, (a, e) => a + e.xp);

  /// Half of the arrows and bolts fired can be gathered after a fight.
  String? recoverAmmo() {
    final parts = <String>[];
    for (final c in state.combatants.where((x) => !x.isEnemy)) {
      final ch = characterFor(c);
      final spent = c.conditions.where((x) => x.startsWith('AmmoSpent')).length;
      final kind = ch?.equippedWeapon?.def?.ammo;
      if (ch == null || spent == 0 || kind == null) continue;
      final back = spent ~/ 2;
      if (back == 0) continue;
      final have = ch.inventory.where((i) => i.itemId == kind).firstOrNull;
      if (have != null) {
        have.qty += back;
      } else {
        ch.inventory.add(InventoryItem.of(kind, qty: back));
      }
      parts.add('${ch.name} recovers $back $kind');
    }
    return parts.isEmpty ? null : '${parts.join(', ')}.';
  }

  /// Cleans transient combat conditions on characters.
  void finish() {
    for (final ch in adventure.party) {
      ch.conditions.removeWhere((c) => c.startsWith('LegAct') || const ['Stunned', 'Charmed', 'Blinded', 'Raging', 'Shielded', 'Hexed', 'Hunter', 'Blessed', 'Hasted', 'Blurred', 'Invisible', 'Heroic', 'Frightened', 'Wild Shape', 'Smite', 'Divine Favor', 'Witch Bolt', 'Moonbeam', 'Call Lightning', 'Guided', 'Fey Used', 'Paralyzed', 'Restrained', 'Prone'].contains(c));
      ch.concentration = null;
    }
    adventure.combat = null;
  }
}

extension _IfEmpty on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
