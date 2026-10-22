import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/inventory_rules.dart';
import '../data/progression.dart';
import '../data/srd.dart';
import '../game/dice.dart';

int stableHashOf(String s) => s.codeUnits.fold<int>(17, (a, c) => (a * 31 + c) & 0x3fffffff);

String newId() => '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${math.Random().nextInt(1 << 30).toRadixString(36)}';

int abilityMod(int score) => ((score - 10) / 2).floor();

/// Parameters for the procedural portrait painter.
class PortraitSpec {
  PortraitSpec({
    required this.seed,
    required this.skin,
    required this.hair,
    required this.eyes,
    this.hairStyle = 0,
    this.beard = 0,
    this.scar = false,
    this.accessory = 0,
    this.background = 0,
    this.feminine = 0.5,
    this.aiImagePath,
    List<String>? aiHistory,
  }) : aiHistory = aiHistory ?? [];

  int seed;
  Color skin;
  Color hair;
  Color eyes;
  int hairStyle; // 0..7
  int beard; // 0 none .. 3
  bool scar;
  int accessory; // 0 none, 1 circlet, 2 hood, 3 earring, 4 eyepatch, 5 warpaint
  int background; // palette index
  double feminine;
  String? aiImagePath;

  /// Every AI portrait made for this character, oldest first, so an earlier
  /// one can be chosen again.
  List<String> aiHistory;

  /// Shows [path] and keeps it in the history.
  void useAiImage(String path) {
    aiImagePath = path;
    aiHistory.remove(path);
    aiHistory.add(path);
    if (aiHistory.length > 24) aiHistory.removeAt(0);
  }

  /// Past portraits, newest first (including the one in use).
  List<String> get portraitHistory => [
        for (final p in aiHistory.reversed) p,
        if (aiImagePath != null && !aiHistory.contains(aiImagePath)) aiImagePath!,
      ];

  static PortraitSpec random(String raceId, {int? seed}) {
    final s = seed ?? math.Random().nextInt(1 << 30);
    final r = Rng(s);
    final race = raceById(raceId);
    final skins = race.skinTones.isEmpty ? [const Color(0xFFE0AC85)] : race.skinTones;
    final hairs = race.hairColors.isEmpty ? [const Color(0xFF3B2416)] : race.hairColors;
    const eyes = [Color(0xFF4F7FC9), Color(0xFF5E9E4F), Color(0xFF6A4325), Color(0xFFC9A55C), Color(0xFFB3202A), Color(0xFF8A8A9A), Color(0xFF7B4FC9)];
    return PortraitSpec(
      seed: s,
      skin: r.pick(skins),
      hair: r.pick(hairs),
      eyes: race.id == 'tiefling' ? r.pick(const [Color(0xFFE0C068), Color(0xFFB3202A), Color(0xFFEDE3D1)]) : r.pick(eyes),
      hairStyle: r.nextInt(8),
      beard: race.id == 'dwarf' ? r.range(1, 3) : (r.chance(0.3) ? r.range(1, 3) : 0),
      scar: r.chance(0.25),
      accessory: r.chance(0.5) ? r.range(1, 5) : 0,
      background: r.nextInt(6),
      feminine: r.nextDouble(),
    );
  }

  PortraitSpec copy() => PortraitSpec.fromJson(toJson());

  Map<String, dynamic> toJson() => {
        'seed': seed,
        'skin': skin.toARGB32(),
        'hair': hair.toARGB32(),
        'eyes': eyes.toARGB32(),
        'hairStyle': hairStyle,
        'beard': beard,
        'scar': scar,
        'accessory': accessory,
        'background': background,
        'feminine': feminine,
        'ai': aiImagePath,
        if (aiHistory.isNotEmpty) 'aiHist': aiHistory,
      };

  factory PortraitSpec.fromJson(Map<String, dynamic> j) => PortraitSpec(
        seed: j['seed'] ?? 0,
        skin: Color(j['skin'] ?? 0xFFE0AC85),
        hair: Color(j['hair'] ?? 0xFF3B2416),
        eyes: Color(j['eyes'] ?? 0xFF4F7FC9),
        hairStyle: j['hairStyle'] ?? 0,
        beard: j['beard'] ?? 0,
        scar: j['scar'] ?? false,
        accessory: j['accessory'] ?? 0,
        background: j['background'] ?? 0,
        feminine: (j['feminine'] ?? 0.5).toDouble(),
        aiImagePath: j['ai'],
        aiHistory: List<String>.from(j['aiHist'] ?? const []),
      );
}

class InventoryItem {
  InventoryItem({required this.name, this.itemId, this.qty = 1, this.equipped = false, this.description = '', this.attuned = false});
  String? itemId;
  String name;
  int qty;
  bool equipped;
  String description;
  bool attuned;

  /// Magic properties apply when attuned (if required) or equipped/carried.
  bool get active {
    final d = def;
    if (d == null) return false;
    if (d.attune) return attuned;
    if (d.type == ItemType.wondrous) return true;
    return equipped;
  }

  ItemDef? get def => itemId == null ? null : itemById(itemId!);

  Map<String, dynamic> toJson() => {'id': itemId, 'name': name, 'qty': qty, 'eq': equipped, 'desc': description, 'att': attuned};
  factory InventoryItem.fromJson(Map<String, dynamic> j) =>
      InventoryItem(itemId: j['id'], name: j['name'] ?? 'Item', qty: j['qty'] ?? 1, equipped: j['eq'] ?? false, description: j['desc'] ?? '', attuned: j['att'] ?? false);

  static InventoryItem of(String id, {int qty = 1, bool equipped = false}) {
    final d = itemById(id);
    return InventoryItem(itemId: id, name: d?.name ?? id, qty: qty, equipped: equipped, description: d?.description ?? '');
  }
}

class Character {
  Character({
    required this.id,
    required this.name,
    required this.raceId,
    required this.classLevels,
    required this.backgroundId,
    required this.baseScores,
    required this.portrait,
    this.subraceId,
    this.title = '',
    this.plus2,
    this.plus1,
    Map<Ability, int>? asi,
    Set<Skill>? skills,
    Set<Skill>? expertise,
    this.maxHp = 10,
    this.hp = 10,
    this.tempHp = 0,
    this.xp = 0,
    this.gold = 10,
    List<InventoryItem>? inventory,
    List<String>? spells,
    List<String>? spellbook,
    this.silver = 0,
    this.copper = 0,
    this.platinum = 0,
    List<int>? slotsUsed,
    Set<String>? conditions,
    this.alignment = 'True Neutral',
    this.personality = '',
    this.ideal = '',
    this.bond = '',
    this.flaw = '',
    this.backstory = '',
    this.isCompanion = false,
    this.inspiration = false,
    this.hitDiceUsed = 0,
    this.deathSuccesses = 0,
    this.deathFailures = 0,
    this.pronouns = 'he/him',
    this.createdAt,
    this.voice = '',
    this.notes = '',
    Map<String, String>? subclasses,
    List<String>? feats,
    this.loyalty = 50,
    this.personalQuest = '',
    this.appearance = '',
    this.dead = false,
    this.concentration,
  })  : subclasses = subclasses ?? {},
        feats = feats ?? [],
        asi = asi ?? {},
        skills = skills ?? {},
        expertise = expertise ?? {},
        inventory = inventory ?? [],
        spells = spells ?? [],
        spellbook = spellbook ?? [],
        slotsUsed = slotsUsed ?? [],
        conditions = conditions ?? {};

  String id;
  String name;
  String title;
  String raceId;
  String? subraceId;
  /// Ordered class -> level. First entry is the starting class.
  Map<String, int> classLevels;
  String backgroundId;
  Map<Ability, int> baseScores;
  Ability? plus2;
  Ability? plus1;
  Map<Ability, int> asi;
  Set<Skill> skills;
  Set<Skill> expertise;
  int maxHp;
  int hp;
  int tempHp;
  int xp;
  int gold;
  int silver;
  int copper;
  int platinum;
  List<InventoryItem> inventory;
  /// Spells ready to cast (known spells, or today's prepared spells).
  List<String> spells;

  /// A wizard's spellbook: everything they can prepare from.
  List<String> spellbook;
  List<int> slotsUsed;
  Set<String> conditions;

  /// Condition name -> adventure turn when it wears off.
  Map<String, int> conditionUntil = {};
  PortraitSpec portrait;
  String alignment;
  String personality;
  String ideal;
  String bond;
  String flaw;
  String backstory;
  bool isCompanion;
  bool inspiration;
  int hitDiceUsed;
  int deathSuccesses;
  int deathFailures;
  String pronouns;
  DateTime? createdAt;
  String voice;
  String notes;

  /// classId -> subclassId
  Map<String, String> subclasses;
  List<String> feats;

  /// Companion approval, 0–100.
  int loyalty;
  String personalQuest;

  /// Physical description used to keep AI images consistent.
  String appearance;
  bool dead;

  /// Spell id being concentrated on.
  String? concentration;

  bool hasFeat(String id) => feats.contains(id);
  bool hasSub(String id) => subclasses.values.contains(id);
  List<SubclassDef> get subclassDefs => subclasses.values.map(subclassById).whereType<SubclassDef>().toList();
  Iterable<ItemDef> get activeMagic => inventory.where((i) => i.active).map((i) => i.def!);
  int get attunedCount => inventory.where((i) => i.attuned).length;

  String get loyaltyLabel => loyalty >= 80 ? 'Devoted' : loyalty >= 60 ? 'Loyal' : loyalty >= 40 ? 'Steady' : loyalty >= 20 ? 'Doubtful' : 'Disloyal';

  // ---- Derived rules ----
  RaceDef get race => raceById(raceId);
  SubraceDef? get subrace {
    if (subraceId == null) return null;
    for (final s in race.subraces) {
      if (s.id == subraceId) return s;
    }
    return null;
  }

  String get raceLabel => subrace?.name ?? race.name;
  ClassDef get primaryClass => classById(classLevels.keys.first);
  BackgroundDef get background => backgroundById(backgroundId);
  int get level => classLevels.values.fold(0, (a, b) => a + b).clamp(1, 20);
  int get proficiency => proficiencyForLevel(level);
  String get classSummary => classLevels.entries.map((e) => '${classById(e.key).name} ${e.value}').join(' / ');
  bool get isDown => hp <= 0;

  int score(Ability a) {
    var v = baseScores[a] ?? 10;
    if (plus2 == a) v += 2;
    if (plus1 == a) v += 1;
    v += asi[a] ?? 0;
    for (final f in feats) {
      if (featById(f)?.ability == a) v += 1;
    }
    v = v.clamp(1, 20);
    for (final m in activeMagic) {
      if (m.setAbility == a && m.setScore > v) v = m.setScore;
    }
    if (a == Ability.str && conditions.contains('Giant Strength')) v = math.max(v, 21);
    return v.clamp(1, 30);
  }

  int mod(Ability a) => abilityMod(score(a));

  bool proficientSave(Ability a) => primaryClass.saves.contains(a) || (a == Ability.con && hasFeat('resilient_con'));
  int get magicSaveBonus => activeMagic.fold(0, (t, m) => t + m.saveBonus);
  int saveMod(Ability a) => mod(a) + (proficientSave(a) ? proficiency : 0) + magicSaveBonus;

  bool proficientSkill(Skill s) => skills.contains(s);
  int skillMod(Skill s) {
    var v = mod(s.ability);
    if (expertise.contains(s)) {
      v += proficiency * 2;
    } else if (skills.contains(s)) {
      v += proficiency;
    } else if (classLevels.containsKey('bard') && (classLevels['bard'] ?? 0) >= 2) {
      v += proficiency ~/ 2;
    }
    return v;
  }

  int get passivePerception => 10 + skillMod(Skill.perception) + (hasFeat('observant') ? 5 : 0);
  int get initiative => mod(Ability.dex) + (hasFeat('alert') ? 5 : 0);
  int get speed {
    var s = race.speed + (hasFeat('mobile') ? 10 : 0) + activeMagic.fold<int>(0, (t, m) => t + m.speedBonus);
    if (subraceId == 'wood') s += 5;
    if (classLevels.containsKey('monk') && (classLevels['monk'] ?? 0) >= 2) s += 10;
    s -= encumbrance * 10;
    return s.clamp(5, 200);
  }

  InventoryItem? get equippedWeapon {
    for (final i in inventory) {
      if (i.equipped && i.def?.type == ItemType.weapon) return i;
    }
    for (final i in inventory) {
      if (i.def?.type == ItemType.weapon) return i;
    }
    return null;
  }

  InventoryItem? get equippedArmor {
    for (final i in inventory) {
      if (i.equipped && i.def?.type == ItemType.armor) return i;
    }
    return null;
  }

  bool get hasShield => inventory.any((i) => i.equipped && i.def?.type == ItemType.shield);

  int get armorClass {
    final armor = equippedArmor?.def;
    final dex = mod(Ability.dex);
    int ac;
    if (armor != null) {
      final cap = armor.dexCap;
      ac = armor.ac! + armor.bonus + (cap == null ? dex : math.min(dex, cap));
    } else if (hasSub('draconic') || conditions.contains('Mage Armor')) {
      ac = 13 + dex;
    } else if (classLevels.containsKey('barbarian')) {
      ac = 10 + dex + mod(Ability.con);
    } else if (classLevels.containsKey('monk')) {
      ac = 10 + dex + mod(Ability.wis);
    } else {
      ac = 10 + dex;
    }
    if (hasShield) {
      ac += 2 + (inventory.firstWhere((i) => i.equipped && i.def?.type == ItemType.shield).def?.bonus ?? 0);
    } else if (hasFeat('dual_wielder') && equippedWeapon?.def?.twoHanded == false) {
      ac += 1;
    }
    ac += activeMagic.fold(0, (t, m) => t + m.acBonus);
    if (conditions.contains('Shielded')) ac += 5;
    if (conditions.contains('Hasted')) ac += 2;
    return ac;
  }

  Ability get weaponAbility {
    final w = equippedWeapon?.def;
    if (w == null) return mod(Ability.str) >= mod(Ability.dex) ? Ability.str : Ability.dex;
    if (w.ranged) return Ability.dex;
    if (w.finesse || classLevels.containsKey('monk')) return mod(Ability.dex) > mod(Ability.str) ? Ability.dex : Ability.str;
    return Ability.str;
  }

  int get weaponMagic => equippedWeapon?.def?.bonus ?? 0;
  int get attackBonus => mod(weaponAbility) + proficiency + weaponMagic + (hasSub('devotion') ? math.max(0, mod(Ability.cha)) : 0);
  String get weaponName => equippedWeapon?.name ?? 'Unarmed Strike';
  int get weaponDamageBonus {
    final w = equippedWeapon?.def;
    var b = mod(weaponAbility) + weaponMagic;
    if (w != null && w.twoHanded && !w.ranged && hasFeat('great_weapon_master')) b += 3;
    if (w != null && w.ranged && hasFeat('sharpshooter')) b += 3;
    return b;
  }

  String get weaponDamage {
    final d = equippedWeapon?.def?.damage ?? (classLevels.containsKey('monk') ? '1d4' : '1');
    final m = weaponDamageBonus;
    return m == 0 ? d : '$d${m > 0 ? '+' : ''}$m';
  }

  /// Extra elemental dice from the weapon (e.g. Flame Tongue).
  String? get weaponExtraDice => equippedWeapon?.def?.extraDice;
  String? get weaponExtraType => equippedWeapon?.def?.extraType;

  /// Natural roll needed for a critical hit.
  int get critRange => hasSub('champion') ? 19 : 20;

  int get attacksPerTurn {
    var n = 1;
    for (final e in classLevels.entries) {
      if (['fighter', 'barbarian', 'paladin', 'ranger', 'monk'].contains(e.key) && e.value >= 5) n = 2;
    }
    if (hasSub('valor') && (classLevels['bard'] ?? 0) >= 6) n = 2;
    if (hasSub('berserker') && conditions.contains('Raging')) n += 1;
    if (conditions.contains('Hasted')) n += 1;
    return n;
  }

  /// Bonus damage added to damaging spells (Light domain, Evocation, Elemental Adept).
  int spellDamageBonus(SpellDef s) {
    var b = 0;
    if (hasSub('light')) b += math.max(0, mod(Ability.wis));
    if (hasSub('evocation') && (classLevels['wizard'] ?? 0) >= 10 && s.school == 'evocation') b += math.max(0, mod(Ability.int_));
    if (hasSub('draconic') && (classLevels['sorcerer'] ?? 0) >= 6 && s.damageType == 'fire') b += math.max(0, mod(Ability.cha));
    if (hasFeat('elemental_adept')) b += 2;
    return b;
  }

  /// Whether this character knows a spell.
  bool knows(String spellId) => spells.contains(spellId);

  /// Battle Master superiority dice left (stored as a condition counter; refills on rest).
  int get superiorityDice => hasSub('battle_master') ? 4 - conditions.where((c) => c.startsWith('SupUsed')).length : 0;
  set superiorityDice(int v) {
    final used = 4 - v;
    conditions.removeWhere((c) => c.startsWith('SupUsed'));
    for (var i = 0; i < used; i++) {
      conditions.add('SupUsed$i');
    }
  }

  /// Ki save DC for monk techniques.
  int get monkDc => 8 + proficiency + mod(Ability.wis);

  int get healBonus => (hasSub('life') ? 3 : 0) + (hasFeat('healer') ? 4 : 0);

  int get sneakAttackDice => classLevels.containsKey('rogue') ? ((classLevels['rogue']! + 1) ~/ 2) : 0;

  Ability? get spellAbility {
    for (final c in classLevels.keys) {
      final a = classById(c).spellAbility;
      if (a != null) return a;
    }
    return null;
  }

  bool get isCaster => spellAbility != null;
  int get spellAttack => spellAbility == null ? 0 : mod(spellAbility!) + proficiency;
  int get spellDc => spellAbility == null ? 0 : 8 + mod(spellAbility!) + proficiency;

  List<int> get spellSlots {
    // Simplified multiclass: use the best single-class progression.
    var best = <int>[];
    for (final e in classLevels.entries) {
      final s = spellSlotsFor(classById(e.key).caster, e.value);
      if (s.fold<int>(0, (a, b) => a + b) > best.fold<int>(0, (a, b) => a + b) || s.length > best.length) best = s;
    }
    return best;
  }

  int slotsRemaining(int spellLevel) {
    final slots = spellSlots;
    if (spellLevel < 1 || spellLevel > slots.length) return 0;
    final used = spellLevel - 1 < slotsUsed.length ? slotsUsed[spellLevel - 1] : 0;
    return math.max(0, slots[spellLevel - 1] - used);
  }

  /// Lowest available slot level >= [minLevel], or null.
  int? availableSlot(int minLevel) {
    final slots = spellSlots;
    for (var l = math.max(1, minLevel); l <= slots.length; l++) {
      if (slotsRemaining(l) > 0) return l;
    }
    return null;
  }

  void spendSlot(int spellLevel) {
    while (slotsUsed.length < spellLevel) {
      slotsUsed.add(0);
    }
    slotsUsed[spellLevel - 1]++;
  }

  int get maxSpellLevel {
    final s = spellSlots;
    return s.length;
  }

  List<SpellDef> get knownSpellDefs => spells.map(spellById).whereType<SpellDef>().toList();

  int get xpForNext => level >= 20 ? xpThresholds.last : xpThresholds[level];
  int get xpForCurrent => xpThresholds[level - 1];
  bool get canLevelUp => level < 20 && xp >= xpForNext;

  int get hitDiceTotal => level;
  int get hitDiceRemaining => math.max(0, level - hitDiceUsed);

  void heal(int amount) => hp = math.min(maxHp, hp + amount);

  /// Returns actual damage taken after temp HP.
  int takeDamage(int amount) {
    var a = amount;
    if (tempHp > 0) {
      final absorb = math.min(tempHp, a);
      tempHp -= absorb;
      a -= absorb;
    }
    if (a > 0 && hp - a <= 0 && raceId == 'half-orc' && !conditions.contains('EnduranceUsed') && hp > 0) {
      hp = 1;
      conditions.add('EnduranceUsed');
      return a;
    }
    hp = math.max(0, hp - a);
    return a;
  }

  void longRest() {
    hp = maxHp;
    tempHp = 0;
    slotsUsed = [];
    hitDiceUsed = math.max(0, hitDiceUsed - math.max(1, level ~/ 2));
    conditions.removeWhere((c) => ['EnduranceUsed', 'Poisoned', 'Frightened', 'Shielded', 'Raging', 'Hexed', 'Blessed', 'Second Wind Used', 'Action Surge Used', 'Rage Used'].contains(c));
    deathSuccesses = 0;
    deathFailures = 0;
    concentration = null;
    conditions.removeWhere((c) => ['Hasted', 'Mage Armor', 'Battle Dice Used', 'Wild Shape Used', 'Fey Presence Used', 'Giant Strength', 'Invisible', 'Resistant', 'Blurred'].contains(c));
    conditions.removeWhere((c) => c.startsWith('SupUsed') || c.startsWith('KiUsed') || const ['Fey Used', 'Lay Used', 'Paralyzed', 'Restrained', 'Prone', 'Heroic', 'Wild Shape', 'Smite', 'Surge Used', 'Channel Used', 'Inspire Used', 'Surging'].contains(c));
    if (hasFeat('lucky')) inspiration = true;
  }

  /// Spend a hit die; returns HP healed or 0.
  int shortRestHitDie() {
    if (hitDiceRemaining <= 0 || hp >= maxHp) return 0;
    hitDiceUsed++;
    var healed = math.max(hasFeat('durable') ? 2 * mod(Ability.con) : 1, rollDie(primaryClass.hitDie) + mod(Ability.con));
    if (activeMagic.any((m) => m.effect == 'wound_closure')) healed *= 2;
    heal(healed);
    if (classLevels.containsKey('warlock')) slotsUsed = [];
    conditions.removeWhere((c) => c.startsWith('SupUsed') || c == 'Fey Used');
    conditions.removeWhere((c) => c == 'Second Wind Used' || c == 'Action Surge Used');
    return healed;
  }

  /// Apply one level in [classId]. Returns HP gained.
  int levelUp(String classId, {bool rollHp = false, bool learnSpells = true}) {
    final cls = classById(classId);
    classLevels[classId] = (classLevels[classId] ?? 0) + 1;
    final gain = math.max(1, (rollHp ? rollDie(cls.hitDie) : (cls.hitDie ~/ 2 + 1)) + mod(Ability.con) + (subraceId == 'hill' ? 1 : 0) + (hasFeat('tough') ? 2 : 0) + (hasSub('draconic') ? 1 : 0));
    maxHp += gain;
    hp += gain;
    // Companions and generated heroes learn automatically; players choose.
    if (classId == 'wizard' && learnSpells) {
      final book = spellsFor('wizard', maxLevel: maxSpellLevel).where((s) => s.level > 0 && !spellbook.contains(s.id)).toList()..sort((a, b) => b.level.compareTo(a.level));
      spellbook.addAll(book.take(2).map((s) => s.id));
    }
    if (cls.spellAbility != null && learnSpells) {
      final avail = spellsFor(classId, maxLevel: maxSpellLevel).where((s) => !spells.contains(s.id)).toList();
      if (avail.isNotEmpty) {
        avail.sort((a, b) => b.level.compareTo(a.level));
        spells.add(avail.first.id);
      }
    }
    return gain;
  }

  /// Automatic subclass and ASI picks (companions, generated heroes).
  void autoProgress(String classId) {
    if (needsSubclass(classId)) {
      final subs = subclassesFor(classId);
      if (subs.isNotEmpty) chooseSubclass(classId, subs[stableHashOf(name) % subs.length].id);
    }
    if (asiLevels.contains(level) && feats.length + asi.values.fold<int>(0, (a, b) => a + b) ~/ 2 < asiLevels.where((l) => l <= level).length) {
      final primary = classById(classId).primary;
      if (score(primary) <= 18) {
        applyAsi(scores: {primary: 2});
      } else {
        applyAsi(scores: {Ability.con: 1, Ability.dex: 1});
      }
    }
  }

  /// Whether reaching this class level requires choosing a subclass.
  bool needsSubclass(String classId) => (classLevels[classId] ?? 0) >= subclassLevel(classId) && !subclasses.containsKey(classId);

  /// Apply an ability score improvement (+2 to one or +1 to two) or a feat.
  void applyAsi({Map<Ability, int>? scores, String? feat}) {
    if (feat != null) {
      feats.add(feat);
      if (feat == 'tough') {
        maxHp += 2 * level;
        hp += 2 * level;
      }
      if (feat == 'skilled') {
        final best = Skill.values.where((s) => !skills.contains(s)).toList()..sort((a, b) => mod(b.ability).compareTo(mod(a.ability)));
        skills.addAll(best.take(3));
      }
      if (feat == 'magic_initiate') {
        final cantrips = spells.isEmpty ? <SpellDef>[] : spellsFor(classLevels.keys.first, maxLevel: 0);
        for (final c in [...cantrips, ...spellsFor('wizard', maxLevel: 0)].where((s) => !spells.contains(s.id)).take(2)) {
          spells.add(c.id);
        }
      }
    }
    if (scores != null) {
      for (final e in scores.entries) {
        asi[e.key] = (asi[e.key] ?? 0) + e.value;
      }
    }
  }

  void chooseSubclass(String classId, String subclassId) {
    subclasses[classId] = subclassId;
    if (subclassId == 'lore') {
      final best = Skill.values.where((s) => !skills.contains(s)).toList()..sort((a, b) => mod(b.ability).compareTo(mod(a.ability)));
      skills.addAll(best.take(3));
    }
    if (subclassId == 'draconic') {
      maxHp += level;
      hp += level;
    }
  }

  List<ClassFeature> get features {
    final out = <ClassFeature>[];
    for (final e in classLevels.entries) {
      out.addAll(classById(e.key).features.where((f) => f.level <= e.value));
      final sub = subclassById(subclasses[e.key]);
      if (sub != null) {
        out.addAll(sub.features.where((f) => f.level <= e.value).map((f) => ClassFeature(f.level, '${f.name} (${sub.name})', f.text)));
      }
    }
    for (final f in feats.map(featById).whereType<FeatDef>()) {
      out.add(ClassFeature(0, 'Feat: ${f.name}', f.description));
    }
    return out;
  }

  /// One-paragraph description for AI prompts.
  String promptSummary() {
    final scores = Ability.values.map((a) => '${a.short} ${score(a)}').join(', ');
    final inv = inventory
        .map((i) => '${i.qty > 1 ? '${i.name} x${i.qty}' : i.name}${i.equipped ? ' [equipped]' : ''}${i.attuned ? ' [attuned]' : ''}${(i.def?.isMagic ?? false) ? ' (${i.def!.rarity} magic)' : ''}')
        .join(', ');
    final shown = conditions.where((c) => !c.endsWith('Used') && !c.startsWith('SupUsed')).toList();
    final slots = spellSlots;
    final slotText = [for (var l = 1; l <= slots.length; l++) if (slots[l - 1] > 0) 'L$l ${slotsRemaining(l)}/${slots[l - 1]}'].join(', ');
    return '$name${title.isNotEmpty ? ', "$title"' : ''} — level $level $raceLabel $classSummary${subclassDefs.isEmpty ? '' : ' (${subclassDefs.map((s) => s.name).join(', ')})'} ($pronouns). '
        '${appearance.isNotEmpty ? 'Looks: $appearance. ' : ''}${feats.isEmpty ? '' : 'Feats: ${feats.map((f) => featById(f)?.name ?? f).join(', ')}. '}'
        'HP $hp/$maxHp, AC $armorClass. $scores. Skills: ${skills.map((s) => s.label).join(', ')}. '
        '${spells.isNotEmpty ? 'Spells: ${knownSpellDefs.map((s) => s.name).join(', ')}. ' : ''}'
        '${slotText.isNotEmpty ? 'Spell slots: $slotText. ' : ''}${concentration != null ? 'Concentrating on ${spellById(concentration!)?.name ?? concentration}. ' : ''}${inspiration ? 'Has Inspiration. ' : ''}'
        'Gear: $inv. Gold: $gold. ${shown.isNotEmpty ? 'Conditions: ${shown.join(', ')}. ' : ''}'
        '${personality.isNotEmpty ? 'Personality: $personality. ' : ''}${backstory.isNotEmpty ? 'Backstory: $backstory' : ''}';
  }

  Character clone() => Character.fromJson(toJson());

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'title': title,
        'race': raceId,
        'subrace': subraceId,
        'classes': classLevels,
        'bg': backgroundId,
        'base': {for (final e in baseScores.entries) e.key.short: e.value},
        'p2': plus2?.short,
        'p1': plus1?.short,
        'asi': {for (final e in asi.entries) e.key.short: e.value},
        'skills': skills.map((s) => s.name).toList(),
        'exp': expertise.map((s) => s.name).toList(),
        'maxHp': maxHp,
        'hp': hp,
        'tmp': tempHp,
        'xp': xp,
        'gold': gold,
        'inv': inventory.map((i) => i.toJson()).toList(),
        'spells': spells,
        'book': spellbook,
        'cu': conditionUntil,
        'sp': silver,
        'cp': copper,
        'pp': platinum,
        'slotsUsed': slotsUsed,
        'cond': conditions.toList(),
        'portrait': portrait.toJson(),
        'align': alignment,
        'pers': personality,
        'ideal': ideal,
        'bond': bond,
        'flaw': flaw,
        'story': backstory,
        'comp': isCompanion,
        'insp': inspiration,
        'hdu': hitDiceUsed,
        'ds': deathSuccesses,
        'df': deathFailures,
        'pron': pronouns,
        'created': createdAt?.toIso8601String(),
        'voice': voice,
        'notes': notes,
        'subs': subclasses,
        'feats': feats,
        'loyal': loyalty,
        'pq': personalQuest,
        'look': appearance,
        'dead': dead,
        'conc': concentration,
      };

  factory Character.fromJson(Map<String, dynamic> j) {
    Map<Ability, int> abil(dynamic m) => {
          if (m is Map)
            for (final e in m.entries) AbilityX.fromShort(e.key as String): (e.value as num).toInt(),
        };
    Set<Skill> sk(dynamic l) => {
          if (l is List)
            for (final n in l)
              ...Skill.values.where((s) => s.name == n),
        };
    final ch = Character(
      id: j['id'] ?? newId(),
      name: j['name'] ?? 'Adventurer',
      title: j['title'] ?? '',
      raceId: j['race'] ?? 'human',
      subraceId: j['subrace'],
      classLevels: Map<String, int>.from((j['classes'] as Map?)?.map((k, v) => MapEntry(k as String, (v as num).toInt())) ?? {'fighter': 1}),
      backgroundId: j['bg'] ?? 'folk_hero',
      baseScores: abil(j['base']),
      plus2: j['p2'] == null ? null : AbilityX.fromShort(j['p2']),
      plus1: j['p1'] == null ? null : AbilityX.fromShort(j['p1']),
      asi: abil(j['asi']),
      skills: sk(j['skills']),
      expertise: sk(j['exp']),
      maxHp: j['maxHp'] ?? 10,
      hp: j['hp'] ?? 10,
      tempHp: j['tmp'] ?? 0,
      xp: j['xp'] ?? 0,
      gold: j['gold'] ?? 0,
      inventory: [for (final i in (j['inv'] as List? ?? [])) InventoryItem.fromJson(Map<String, dynamic>.from(i))],
      spells: List<String>.from(j['spells'] ?? []),
      spellbook: List<String>.from(j['book'] ?? []),
      silver: j['sp'] ?? 0,
      copper: j['cp'] ?? 0,
      platinum: j['pp'] ?? 0,
      slotsUsed: List<int>.from(j['slotsUsed'] ?? []),
      conditions: Set<String>.from(j['cond'] ?? []),
      portrait: PortraitSpec.fromJson(Map<String, dynamic>.from(j['portrait'] ?? {})),
      alignment: j['align'] ?? 'True Neutral',
      personality: j['pers'] ?? '',
      ideal: j['ideal'] ?? '',
      bond: j['bond'] ?? '',
      flaw: j['flaw'] ?? '',
      backstory: j['story'] ?? '',
      isCompanion: j['comp'] ?? false,
      inspiration: j['insp'] ?? false,
      hitDiceUsed: j['hdu'] ?? 0,
      deathSuccesses: j['ds'] ?? 0,
      deathFailures: j['df'] ?? 0,
      pronouns: j['pron'] ?? 'he/him',
      createdAt: j['created'] == null ? null : DateTime.tryParse(j['created']),
      voice: j['voice'] ?? '',
      notes: j['notes'] ?? '',
      subclasses: Map<String, String>.from(j['subs'] ?? {}),
      feats: List<String>.from(j['feats'] ?? []),
      loyalty: j['loyal'] ?? 50,
      personalQuest: j['pq'] ?? '',
      appearance: j['look'] ?? '',
      dead: j['dead'] ?? false,
      concentration: j['conc'],
    );
    ch.conditionUntil = Map<String, int>.from(j['cu'] ?? const {});
    return ch;
  }

  /// Builds a fresh level-1 character with starting gear, HP and spells.
  static Character build({
    required String name,
    required String raceId,
    String? subraceId,
    required String classId,
    required String backgroundId,
    required Map<Ability, int> baseScores,
    Ability? plus2,
    Ability? plus1,
    Set<Skill>? skills,
    PortraitSpec? portrait,
    String title = '',
    int level = 1,
    String alignment = 'Neutral Good',
    String personality = '',
    String backstory = '',
    String pronouns = 'he/him',
  }) {
    final cls = classById(classId);
    final bg = backgroundById(backgroundId);
    final c = Character(
      id: newId(),
      name: name,
      title: title.isEmpty ? cls.epithet : title,
      raceId: raceId,
      subraceId: subraceId,
      classLevels: {classId: 1},
      backgroundId: backgroundId,
      baseScores: baseScores,
      plus2: plus2,
      plus1: plus1,
      portrait: portrait ?? PortraitSpec.random(raceId),
      gold: bg.gold + 10,
      alignment: alignment,
      personality: personality,
      backstory: backstory,
      pronouns: pronouns,
      createdAt: DateTime.now(),
    );
    final sk = <Skill>{...bg.skills, ...?skills};
    if (raceId == 'elf') sk.add(Skill.perception);
    if (raceId == 'half-orc') sk.add(Skill.intimidation);
    if (sk.length < bg.skills.length + cls.numSkills) {
      for (final s in cls.skillChoices) {
        if (sk.length >= bg.skills.length + cls.numSkills) break;
        sk.add(s);
      }
    }
    c.skills = sk;
    if (classId == 'rogue') c.expertise = sk.where((s) => s == Skill.stealth || s == Skill.sleightOfHand || s == Skill.perception).take(2).toSet();
    final hp = cls.hitDie + c.mod(Ability.con) + (subraceId == 'hill' ? 1 : 0);
    c.maxHp = math.max(1, hp);
    c.hp = c.maxHp;
    var firstWeapon = true;
    for (final id in cls.startingItems) {
      final def = itemById(id);
      final eq = def != null &&
          ((def.type == ItemType.weapon && firstWeapon) || def.type == ItemType.armor || def.type == ItemType.shield);
      if (def?.type == ItemType.weapon) firstWeapon = false;
      c.inventory.add(InventoryItem.of(id, equipped: eq, qty: id == 'potion_healing' ? 2 : (id == 'darts' ? 10 : 1)));
    }
    for (final w in c.inventory.where((i) => i.def?.type == ItemType.weapon).toList()) {
      final ammo = switch (w.itemId) { 'longbow' || 'shortbow' => 'arrows', 'light_crossbow' || 'heavy_crossbow' => 'bolts', _ => null };
      if (ammo != null && !c.inventory.any((i) => i.itemId == ammo)) c.inventory.add(InventoryItem.of(ammo, qty: 20));
    }
    c.inventory.add(InventoryItem.of('rations', qty: 5));
    c.inventory.add(InventoryItem.of('torch', qty: 3));
    // starting spells: up to 3 cantrips + 2 first-level
    if (cls.spellAbility != null) {
      final cantrips = spellsFor(classId, maxLevel: 0);
      final lvl1 = spellsFor(classId, maxLevel: 1).where((s) => s.level == 1).toList();
      c.spells = [
        ...cantrips.where((s) => s.kind == SpellKind.attack || s.kind == SpellKind.save).take(2).map((s) => s.id),
        ...cantrips.where((s) => s.kind != SpellKind.attack && s.kind != SpellKind.save).take(1).map((s) => s.id),
        ...lvl1.take(cls.caster == CasterType.half ? 2 : 3).map((s) => s.id),
      ];
      if (cls.caster == CasterType.half) c.spells.removeWhere((id) => spellById(id)?.level == 0);
      if (classId == 'wizard') {
        final lvl1 = spellsFor('wizard', maxLevel: 1).where((s) => s.level == 1).map((s) => s.id);
        c.spellbook = {...c.spells.where((id) => (spellById(id)?.level ?? 0) > 0), ...lvl1}.take(6).toList();
      }
    }
    for (var l = 1; l < level; l++) {
      c.xp = xpThresholds[l];
      c.levelUp(classId);
      c.autoProgress(classId);
    }
    return c;
  }
}
