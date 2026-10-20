// Rules content adapted from the 5e System Reference Document (CC-BY-4.0).
import 'package:flutter/material.dart';

enum Ability { str, dex, con, int_, wis, cha }

extension AbilityX on Ability {
  String get short => const ['STR', 'DEX', 'CON', 'INT', 'WIS', 'CHA'][index];
  String get full => const ['Strength', 'Dexterity', 'Constitution', 'Intelligence', 'Wisdom', 'Charisma'][index];
  static Ability fromShort(String s) {
    final u = s.toUpperCase();
    for (final a in Ability.values) {
      if (a.short == u || a.full.toUpperCase() == u) return a;
    }
    return Ability.str;
  }
}

enum Skill {
  acrobatics, animalHandling, arcana, athletics, deception, history, insight, intimidation, investigation,
  medicine, nature, perception, performance, persuasion, religion, sleightOfHand, stealth, survival
}

extension SkillX on Skill {
  String get label => const {
        Skill.acrobatics: 'Acrobatics',
        Skill.animalHandling: 'Animal Handling',
        Skill.arcana: 'Arcana',
        Skill.athletics: 'Athletics',
        Skill.deception: 'Deception',
        Skill.history: 'History',
        Skill.insight: 'Insight',
        Skill.intimidation: 'Intimidation',
        Skill.investigation: 'Investigation',
        Skill.medicine: 'Medicine',
        Skill.nature: 'Nature',
        Skill.perception: 'Perception',
        Skill.performance: 'Performance',
        Skill.persuasion: 'Persuasion',
        Skill.religion: 'Religion',
        Skill.sleightOfHand: 'Sleight of Hand',
        Skill.stealth: 'Stealth',
        Skill.survival: 'Survival',
      }[this]!;

  Ability get ability => switch (this) {
        Skill.athletics => Ability.str,
        Skill.acrobatics || Skill.sleightOfHand || Skill.stealth => Ability.dex,
        Skill.arcana || Skill.history || Skill.investigation || Skill.nature || Skill.religion => Ability.int_,
        Skill.animalHandling || Skill.insight || Skill.medicine || Skill.perception || Skill.survival => Ability.wis,
        _ => Ability.cha,
      };

  static Skill? parse(String? s) {
    if (s == null) return null;
    final k = s.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    for (final sk in Skill.values) {
      if (sk.label.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '') == k) return sk;
    }
    return null;
  }
}

class SubraceDef {
  const SubraceDef(this.id, this.name, this.bonuses, this.traits);
  final String id;
  final String name;
  final Map<Ability, int> bonuses;
  final List<String> traits;
}

class RaceDef {
  const RaceDef({
    required this.id,
    required this.name,
    required this.description,
    required this.speed,
    required this.traits,
    this.subraces = const [],
    this.darkvision = false,
    this.skinTones = const [],
    this.hairColors = const [],
    this.earStyle = 0,
    this.horns = false,
    this.tusks = false,
    this.scales = false,
    this.size = 'Medium',
  });
  final String id;
  final String name;
  final String description;
  final int speed;
  final List<String> traits;
  final List<SubraceDef> subraces;
  final bool darkvision;
  final List<Color> skinTones;
  final List<Color> hairColors;
  /// 0 human, 1 half-pointed, 2 long-pointed
  final int earStyle;
  final bool horns;
  final bool tusks;
  final bool scales;
  final String size;
}

const _humanSkins = [Color(0xFFF1C9A5), Color(0xFFE0AC85), Color(0xFFC68B59), Color(0xFF8D5524), Color(0xFF5C3A21), Color(0xFFFFDBAC)];
const _hair = [Color(0xFF1B1210), Color(0xFF3B2416), Color(0xFF6A4325), Color(0xFFA56B34), Color(0xFFD9B46A), Color(0xFFB8442A), Color(0xFFE8E3D8), Color(0xFF8A8A8A)];

const races = <RaceDef>[
  RaceDef(
    id: 'human',
    name: 'Human',
    description: 'Ambitious and adaptable, humans are found in every corner of the realms.',
    speed: 30,
    traits: ['Versatile: +1 to every ability (variant: free +2/+1)', 'Extra language'],
    skinTones: _humanSkins,
    hairColors: _hair,
  ),
  RaceDef(
    id: 'elf',
    name: 'Elf',
    description: 'Graceful, long-lived and attuned to magic and the wild.',
    speed: 30,
    darkvision: true,
    earStyle: 2,
    traits: ['Darkvision 60 ft', 'Fey Ancestry: advantage vs charm', 'Trance: 4 hours of rest', 'Keen Senses: Perception proficiency'],
    subraces: [
      SubraceDef('high', 'High Elf', {Ability.int_: 1}, ['Wizard cantrip', 'Elf weapon training']),
      SubraceDef('wood', 'Wood Elf', {Ability.wis: 1}, ['Fleet of Foot: 35 ft', 'Mask of the Wild']),
      SubraceDef('drow', 'Drow', {Ability.cha: 1}, ['Superior Darkvision 120 ft', 'Drow Magic', 'Sunlight Sensitivity']),
    ],
    skinTones: [Color(0xFFF3D9C1), Color(0xFFD9B99B), Color(0xFFB98A64), Color(0xFF6C5B7B), Color(0xFF4B4462)],
    hairColors: [Color(0xFFEFE6D2), Color(0xFFD9B46A), Color(0xFF2B1B14), Color(0xFF7A3B2E), Color(0xFFCFD8E3), Color(0xFF3E5A3C)],
  ),
  RaceDef(
    id: 'dwarf',
    name: 'Dwarf',
    description: 'Stout and stubborn folk of stone halls, forge and ale.',
    speed: 25,
    darkvision: true,
    traits: ['Darkvision 60 ft', 'Dwarven Resilience: advantage vs poison', 'Stonecunning', 'Combat training with axes and hammers'],
    subraces: [
      SubraceDef('hill', 'Hill Dwarf', {Ability.wis: 1}, ['Dwarven Toughness: +1 HP per level']),
      SubraceDef('mountain', 'Mountain Dwarf', {Ability.str: 2}, ['Light and medium armor proficiency']),
    ],
    skinTones: [Color(0xFFE6B996), Color(0xFFC98E62), Color(0xFF9A6240), Color(0xFF6B4029)],
    hairColors: [Color(0xFF7A2E1C), Color(0xFF3B2416), Color(0xFF1B1210), Color(0xFFB8B2A7), Color(0xFFC0702E)],
  ),
  RaceDef(
    id: 'halfling',
    name: 'Halfling',
    description: 'Cheerful, nimble wanderers with uncanny luck.',
    speed: 25,
    size: 'Small',
    earStyle: 1,
    traits: ['Lucky: reroll natural 1s', 'Brave: advantage vs fright', 'Halfling Nimbleness'],
    subraces: [
      SubraceDef('lightfoot', 'Lightfoot', {Ability.cha: 1}, ['Naturally Stealthy']),
      SubraceDef('stout', 'Stout', {Ability.con: 1}, ['Stout Resilience: poison resistance']),
    ],
    skinTones: _humanSkins,
    hairColors: _hair,
  ),
  RaceDef(
    id: 'gnome',
    name: 'Gnome',
    description: 'Curious tinkerers and illusionists brimming with energy.',
    speed: 25,
    size: 'Small',
    darkvision: true,
    earStyle: 1,
    traits: ['Darkvision 60 ft', 'Gnome Cunning: advantage on INT/WIS/CHA saves vs magic'],
    subraces: [
      SubraceDef('forest', 'Forest Gnome', {Ability.dex: 1}, ['Minor Illusion', 'Speak with Small Beasts']),
      SubraceDef('rock', 'Rock Gnome', {Ability.con: 1}, ["Artificer's Lore", 'Tinker']),
    ],
    skinTones: _humanSkins,
    hairColors: [Color(0xFFE8E3D8), Color(0xFFD06A2E), Color(0xFF6FB3C9), Color(0xFFC94F8A), Color(0xFF3B2416)],
  ),
  RaceDef(
    id: 'half-elf',
    name: 'Half-Elf',
    description: 'Walking between two worlds, charismatic and versatile.',
    speed: 30,
    darkvision: true,
    earStyle: 1,
    traits: ['Darkvision 60 ft', 'Fey Ancestry', 'Skill Versatility: two extra skills'],
    subraces: [
      SubraceDef('high', 'High Half-Elf', {}, ['Wizard cantrip']),
      SubraceDef('wood', 'Wood Half-Elf', {}, ['Fleet of Foot']),
      SubraceDef('drow', 'Drow Half-Elf', {}, ['Drow Magic']),
    ],
    skinTones: [Color(0xFFF1C9A5), Color(0xFFD9B99B), Color(0xFFB98A64), Color(0xFF7E6A8C), Color(0xFF8D5524)],
    hairColors: _hair,
  ),
  RaceDef(
    id: 'half-orc',
    name: 'Half-Orc',
    description: 'Fierce and enduring, forged by hardship.',
    speed: 30,
    darkvision: true,
    tusks: true,
    earStyle: 1,
    traits: ['Darkvision 60 ft', 'Relentless Endurance: drop to 1 HP instead of 0 once per rest', 'Savage Attacks', 'Menacing: Intimidation proficiency'],
    skinTones: [Color(0xFF8DA068), Color(0xFF6E8A52), Color(0xFF9C9C7A), Color(0xFF5B6B48), Color(0xFFA8A08A)],
    hairColors: [Color(0xFF1B1210), Color(0xFF2E2A26), Color(0xFF4A3426)],
  ),
  RaceDef(
    id: 'tiefling',
    name: 'Tiefling',
    description: 'Bearers of an infernal bloodline, distrusted yet determined.',
    speed: 30,
    darkvision: true,
    horns: true,
    earStyle: 2,
    traits: ['Darkvision 60 ft', 'Hellish Resistance: fire resistance', 'Infernal Legacy: Thaumaturgy, Hellish Rebuke'],
    subraces: [
      SubraceDef('asmodeus', 'Asmodeus', {Ability.int_: 1}, ['Infernal Legacy']),
      SubraceDef('zariel', 'Zariel', {Ability.str: 1}, ['Legacy of Avernus']),
      SubraceDef('mephistopheles', 'Mephistopheles', {Ability.int_: 1}, ['Legacy of Cania']),
    ],
    skinTones: [Color(0xFFB3423E), Color(0xFF8E2F3A), Color(0xFF6B3F7C), Color(0xFFD08770), Color(0xFF4A3B5E), Color(0xFFC9A18B)],
    hairColors: [Color(0xFF1B1210), Color(0xFF3A1F4A), Color(0xFF6E1E24), Color(0xFF2B2B3A)],
  ),
  RaceDef(
    id: 'dragonborn',
    name: 'Dragonborn',
    description: 'Proud draconic humanoids with a breath of elemental fury.',
    speed: 30,
    scales: true,
    traits: ['Breath Weapon (2d6, DEX save)', 'Damage resistance by ancestry'],
    subraces: [
      SubraceDef('red', 'Red (Fire)', {}, ['Fire breath']),
      SubraceDef('blue', 'Blue (Lightning)', {}, ['Lightning breath']),
      SubraceDef('green', 'Green (Poison)', {}, ['Poison breath']),
      SubraceDef('gold', 'Gold (Fire)', {}, ['Fire breath']),
      SubraceDef('silver', 'Silver (Cold)', {}, ['Cold breath']),
    ],
    skinTones: [Color(0xFFA33A2C), Color(0xFF2E5C9A), Color(0xFF3F7A45), Color(0xFFC9A04A), Color(0xFFA9B4C2), Color(0xFF3A3A3A)],
    hairColors: [Color(0xFF3B2416)],
  ),
];

RaceDef raceById(String id) => races.firstWhere((r) => r.id == id, orElse: () => races.first);

class ClassFeature {
  const ClassFeature(this.level, this.name, this.text);
  final int level;
  final String name;
  final String text;
}

enum CasterType { none, full, half, pact }

class ClassDef {
  const ClassDef({
    required this.id,
    required this.name,
    required this.epithet,
    required this.description,
    required this.hitDie,
    required this.primary,
    required this.saves,
    required this.skillChoices,
    required this.numSkills,
    required this.armorBase,
    required this.weapon,
    required this.color,
    required this.features,
    this.caster = CasterType.none,
    this.spellAbility,
    this.recommendedStats = const {},
    this.optimalRaces = const [],
    this.startingItems = const [],
    this.icon = Icons.shield,
  });

  final String id;
  final String name;
  final String epithet;
  final String description;
  final int hitDie;
  final Ability primary;
  final List<Ability> saves;
  final List<Skill> skillChoices;
  final int numSkills;
  /// 0 = unarmored, otherwise base AC from starting armor; -1 = unarmored defense.
  final int armorBase;
  final String weapon;
  final Color color;
  final List<ClassFeature> features;
  final CasterType caster;
  final Ability? spellAbility;
  final Map<Ability, int> recommendedStats;
  final List<String> optimalRaces;
  final List<String> startingItems;
  final IconData icon;
}

const classes = <ClassDef>[
  ClassDef(
    id: 'barbarian',
    name: 'Barbarian',
    epithet: 'Fury of the Wilds',
    description: 'A fierce warrior who channels primal rage into devastating blows.',
    hitDie: 12,
    primary: Ability.str,
    saves: [Ability.str, Ability.con],
    skillChoices: [Skill.animalHandling, Skill.athletics, Skill.intimidation, Skill.nature, Skill.perception, Skill.survival],
    numSkills: 2,
    armorBase: -1,
    weapon: 'greataxe',
    color: Color(0xFFB0462C),
    caster: CasterType.none,
    recommendedStats: {Ability.str: 15, Ability.dex: 13, Ability.con: 14, Ability.int_: 8, Ability.wis: 12, Ability.cha: 10},
    optimalRaces: ['half-orc', 'dwarf', 'dragonborn'],
    startingItems: ['greataxe', 'handaxe', 'potion_healing', 'explorers_pack'],
    features: [
      ClassFeature(1, 'Rage', 'Bonus damage and resistance to physical damage while raging.'),
      ClassFeature(1, 'Unarmored Defense', 'AC = 10 + DEX + CON without armor.'),
      ClassFeature(2, 'Reckless Attack', 'Gain advantage on attacks; enemies gain advantage against you.'),
      ClassFeature(3, 'Primal Path', 'Choose a path that shapes your rage.'),
      ClassFeature(5, 'Extra Attack', 'Attack twice when you take the Attack action.'),
    ],
  ),
  ClassDef(
    id: 'bard',
    name: 'Bard',
    epithet: 'Weaver of Songs',
    description: 'An inspiring magician whose power echoes the music of creation.',
    hitDie: 8,
    primary: Ability.cha,
    saves: [Ability.dex, Ability.cha],
    skillChoices: Skill.values,
    numSkills: 3,
    armorBase: 11,
    weapon: 'rapier',
    color: Color(0xFFC0508A),
    caster: CasterType.full,
    spellAbility: Ability.cha,
    recommendedStats: {Ability.str: 8, Ability.dex: 14, Ability.con: 14, Ability.int_: 10, Ability.wis: 10, Ability.cha: 16},
    optimalRaces: ['half-elf', 'tiefling', 'halfling'],
    startingItems: ['rapier', 'leather_armor', 'lute', 'potion_healing'],
    features: [
      ClassFeature(1, 'Bardic Inspiration', 'Grant an ally a d6 to add to a roll.'),
      ClassFeature(2, 'Jack of All Trades', 'Add half proficiency to any check you are not proficient in.'),
      ClassFeature(2, 'Song of Rest', 'Allies regain extra HP during a short rest.'),
      ClassFeature(3, 'Bard College', 'Choose your college.'),
      ClassFeature(5, 'Font of Inspiration', 'Regain inspiration on a short rest.'),
    ],
  ),
  ClassDef(
    id: 'cleric',
    name: 'Cleric',
    epithet: 'Hand of the Divine',
    description: 'A priestly champion who wields divine magic in service of a higher power.',
    hitDie: 8,
    primary: Ability.wis,
    saves: [Ability.wis, Ability.cha],
    skillChoices: [Skill.history, Skill.insight, Skill.medicine, Skill.persuasion, Skill.religion],
    numSkills: 2,
    armorBase: 16,
    weapon: 'mace',
    color: Color(0xFFE0C068),
    caster: CasterType.full,
    spellAbility: Ability.wis,
    recommendedStats: {Ability.str: 14, Ability.dex: 8, Ability.con: 14, Ability.int_: 10, Ability.wis: 16, Ability.cha: 10},
    optimalRaces: ['dwarf', 'human', 'half-elf'],
    startingItems: ['mace', 'chain_mail', 'shield', 'holy_symbol', 'potion_healing'],
    features: [
      ClassFeature(1, 'Divine Domain', 'Your god grants you domain powers.'),
      ClassFeature(2, 'Channel Divinity', 'Turn Undead and domain channel.'),
      ClassFeature(5, 'Destroy Undead', 'Weak undead are destroyed by your Turn.'),
    ],
  ),
  ClassDef(
    id: 'druid',
    name: 'Druid',
    epithet: 'Voice of the Grove',
    description: 'A priest of the Old Faith, wielding the powers of nature and taking animal forms.',
    hitDie: 8,
    primary: Ability.wis,
    saves: [Ability.int_, Ability.wis],
    skillChoices: [Skill.arcana, Skill.animalHandling, Skill.insight, Skill.medicine, Skill.nature, Skill.perception, Skill.religion, Skill.survival],
    numSkills: 2,
    armorBase: 11,
    weapon: 'quarterstaff',
    color: Color(0xFF5E9E4F),
    caster: CasterType.full,
    spellAbility: Ability.wis,
    recommendedStats: {Ability.str: 8, Ability.dex: 14, Ability.con: 14, Ability.int_: 10, Ability.wis: 16, Ability.cha: 10},
    optimalRaces: ['elf', 'gnome', 'halfling'],
    startingItems: ['quarterstaff', 'leather_armor', 'herbalism_kit', 'potion_healing'],
    features: [
      ClassFeature(1, 'Druidic', 'Secret language of druids.'),
      ClassFeature(2, 'Wild Shape', 'Transform into a beast you have seen.'),
      ClassFeature(2, 'Druid Circle', 'Choose your circle.'),
    ],
  ),
  ClassDef(
    id: 'fighter',
    name: 'Fighter',
    epithet: 'Master of Arms',
    description: 'A master of martial combat, skilled with a variety of weapons and armor.',
    hitDie: 10,
    primary: Ability.str,
    saves: [Ability.str, Ability.con],
    skillChoices: [Skill.acrobatics, Skill.animalHandling, Skill.athletics, Skill.history, Skill.insight, Skill.intimidation, Skill.perception, Skill.survival],
    numSkills: 2,
    armorBase: 16,
    weapon: 'longsword',
    color: Color(0xFFB07A3A),
    recommendedStats: {Ability.str: 16, Ability.dex: 12, Ability.con: 15, Ability.int_: 8, Ability.wis: 12, Ability.cha: 8},
    optimalRaces: ['human', 'half-orc', 'dwarf'],
    startingItems: ['longsword', 'chain_mail', 'shield', 'light_crossbow', 'potion_healing'],
    features: [
      ClassFeature(1, 'Fighting Style', 'Adopt a particular style of fighting.'),
      ClassFeature(1, 'Second Wind', 'Regain 1d10 + level HP as a bonus action.'),
      ClassFeature(2, 'Action Surge', 'Take one additional action.'),
      ClassFeature(3, 'Martial Archetype', 'Choose your archetype.'),
      ClassFeature(5, 'Extra Attack', 'Attack twice.'),
    ],
  ),
  ClassDef(
    id: 'monk',
    name: 'Monk',
    epithet: 'Disciple of the Open Hand',
    description: 'A master of martial arts, harnessing the power of body and soul.',
    hitDie: 8,
    primary: Ability.dex,
    saves: [Ability.str, Ability.dex],
    skillChoices: [Skill.acrobatics, Skill.athletics, Skill.history, Skill.insight, Skill.religion, Skill.stealth],
    numSkills: 2,
    armorBase: -2,
    weapon: 'shortsword',
    color: Color(0xFF3FA3A0),
    recommendedStats: {Ability.str: 10, Ability.dex: 16, Ability.con: 14, Ability.int_: 8, Ability.wis: 15, Ability.cha: 8},
    optimalRaces: ['elf', 'human', 'halfling'],
    startingItems: ['shortsword', 'darts', 'potion_healing'],
    features: [
      ClassFeature(1, 'Unarmored Defense', 'AC = 10 + DEX + WIS.'),
      ClassFeature(1, 'Martial Arts', 'Unarmed strikes use DEX and a bonus attack.'),
      ClassFeature(2, 'Ki', 'Flurry of Blows, Patient Defense, Step of the Wind.'),
      ClassFeature(5, 'Stunning Strike', 'Spend ki to stun a target.'),
    ],
  ),
  ClassDef(
    id: 'paladin',
    name: 'Paladin',
    epithet: 'Oathsworn Champion',
    description: 'A holy warrior bound to a sacred oath.',
    hitDie: 10,
    primary: Ability.str,
    saves: [Ability.wis, Ability.cha],
    skillChoices: [Skill.athletics, Skill.insight, Skill.intimidation, Skill.medicine, Skill.persuasion, Skill.religion],
    numSkills: 2,
    armorBase: 16,
    weapon: 'longsword',
    color: Color(0xFFE8D27A),
    caster: CasterType.half,
    spellAbility: Ability.cha,
    recommendedStats: {Ability.str: 16, Ability.dex: 8, Ability.con: 14, Ability.int_: 8, Ability.wis: 10, Ability.cha: 15},
    optimalRaces: ['human', 'dragonborn', 'half-elf'],
    startingItems: ['longsword', 'chain_mail', 'shield', 'holy_symbol', 'potion_healing'],
    features: [
      ClassFeature(1, 'Divine Sense', 'Detect celestials, fiends and undead.'),
      ClassFeature(1, 'Lay on Hands', 'Heal from a pool of 5 × level HP.'),
      ClassFeature(2, 'Divine Smite', 'Expend a spell slot to deal 2d8 radiant damage.'),
      ClassFeature(3, 'Sacred Oath', 'Swear your oath.'),
      ClassFeature(5, 'Extra Attack', 'Attack twice.'),
    ],
  ),
  ClassDef(
    id: 'ranger',
    name: 'Ranger',
    epithet: 'Warden of the Wilds',
    description: 'A warrior who combats threats on the edges of civilization.',
    hitDie: 10,
    primary: Ability.dex,
    saves: [Ability.str, Ability.dex],
    skillChoices: [Skill.animalHandling, Skill.athletics, Skill.insight, Skill.investigation, Skill.nature, Skill.perception, Skill.stealth, Skill.survival],
    numSkills: 3,
    armorBase: 14,
    weapon: 'longbow',
    color: Color(0xFF4F8A3C),
    caster: CasterType.half,
    spellAbility: Ability.wis,
    recommendedStats: {Ability.str: 10, Ability.dex: 16, Ability.con: 14, Ability.int_: 8, Ability.wis: 15, Ability.cha: 8},
    optimalRaces: ['elf', 'half-elf', 'halfling'],
    startingItems: ['longbow', 'shortsword', 'scale_mail', 'potion_healing'],
    features: [
      ClassFeature(1, 'Favored Enemy', 'Advantage tracking chosen foes.'),
      ClassFeature(1, 'Natural Explorer', 'Expertise in a favored terrain.'),
      ClassFeature(2, 'Fighting Style', 'Archery, Dueling or Two-Weapon.'),
      ClassFeature(3, 'Ranger Archetype', 'Hunter or Beast Master.'),
      ClassFeature(5, 'Extra Attack', 'Attack twice.'),
    ],
  ),
  ClassDef(
    id: 'rogue',
    name: 'Rogue',
    epithet: 'Shadow of the Alleys',
    description: 'A scoundrel who uses stealth and trickery to overcome obstacles.',
    hitDie: 8,
    primary: Ability.dex,
    saves: [Ability.dex, Ability.int_],
    skillChoices: [Skill.acrobatics, Skill.athletics, Skill.deception, Skill.insight, Skill.intimidation, Skill.investigation, Skill.perception, Skill.performance, Skill.persuasion, Skill.sleightOfHand, Skill.stealth],
    numSkills: 4,
    armorBase: 11,
    weapon: 'rapier',
    color: Color(0xFF6B6F7A),
    recommendedStats: {Ability.str: 8, Ability.dex: 16, Ability.con: 14, Ability.int_: 12, Ability.wis: 12, Ability.cha: 10},
    optimalRaces: ['halfling', 'elf', 'tiefling'],
    startingItems: ['rapier', 'shortbow', 'leather_armor', 'thieves_tools', 'potion_healing'],
    features: [
      ClassFeature(1, 'Sneak Attack', 'Extra 1d6 damage per two levels when you have advantage.'),
      ClassFeature(1, 'Expertise', 'Double proficiency on two skills.'),
      ClassFeature(2, 'Cunning Action', 'Dash, Disengage or Hide as a bonus action.'),
      ClassFeature(3, 'Roguish Archetype', 'Thief, Assassin or Arcane Trickster.'),
      ClassFeature(5, 'Uncanny Dodge', 'Halve damage from an attack.'),
    ],
  ),
  ClassDef(
    id: 'sorcerer',
    name: 'Sorcerer',
    epithet: 'Blood of Storms',
    description: 'A spellcaster who draws on inherent magic from a gift or bloodline.',
    hitDie: 6,
    primary: Ability.cha,
    saves: [Ability.con, Ability.cha],
    skillChoices: [Skill.arcana, Skill.deception, Skill.insight, Skill.intimidation, Skill.persuasion, Skill.religion],
    numSkills: 2,
    armorBase: 0,
    weapon: 'dagger',
    color: Color(0xFFC0352B),
    caster: CasterType.full,
    spellAbility: Ability.cha,
    recommendedStats: {Ability.str: 8, Ability.dex: 14, Ability.con: 14, Ability.int_: 10, Ability.wis: 10, Ability.cha: 16},
    optimalRaces: ['tiefling', 'dragonborn', 'half-elf'],
    startingItems: ['dagger', 'arcane_focus', 'potion_healing'],
    features: [
      ClassFeature(1, 'Sorcerous Origin', 'Draconic or Wild Magic bloodline.'),
      ClassFeature(2, 'Font of Magic', 'Sorcery points to fuel your magic.'),
      ClassFeature(3, 'Metamagic', 'Twin, quicken or empower spells.'),
    ],
  ),
  ClassDef(
    id: 'warlock',
    name: 'Warlock',
    epithet: 'Pactbound Seeker',
    description: 'A wielder of magic derived from a bargain with an extraplanar entity.',
    hitDie: 8,
    primary: Ability.cha,
    saves: [Ability.wis, Ability.cha],
    skillChoices: [Skill.arcana, Skill.deception, Skill.history, Skill.intimidation, Skill.investigation, Skill.nature, Skill.religion],
    numSkills: 2,
    armorBase: 11,
    weapon: 'dagger',
    color: Color(0xFF7B4FC9),
    caster: CasterType.pact,
    spellAbility: Ability.cha,
    recommendedStats: {Ability.str: 8, Ability.dex: 14, Ability.con: 14, Ability.int_: 10, Ability.wis: 12, Ability.cha: 16},
    optimalRaces: ['tiefling', 'half-elf', 'human'],
    startingItems: ['dagger', 'leather_armor', 'arcane_focus', 'potion_healing'],
    features: [
      ClassFeature(1, 'Otherworldly Patron', 'Fiend, Archfey or Great Old One.'),
      ClassFeature(1, 'Pact Magic', 'Spell slots recharge on a short rest.'),
      ClassFeature(2, 'Eldritch Invocations', 'Agonizing Blast, Devil\'s Sight and more.'),
      ClassFeature(3, 'Pact Boon', 'Blade, Chain or Tome.'),
    ],
  ),
  ClassDef(
    id: 'wizard',
    name: 'Wizard',
    epithet: 'Keeper of the Arcane',
    description: 'A scholarly magic-user capable of manipulating the structures of reality.',
    hitDie: 6,
    primary: Ability.int_,
    saves: [Ability.int_, Ability.wis],
    skillChoices: [Skill.arcana, Skill.history, Skill.insight, Skill.investigation, Skill.medicine, Skill.religion],
    numSkills: 2,
    armorBase: 0,
    weapon: 'quarterstaff',
    color: Color(0xFF4F7FC9),
    caster: CasterType.full,
    spellAbility: Ability.int_,
    recommendedStats: {Ability.str: 8, Ability.dex: 14, Ability.con: 14, Ability.int_: 16, Ability.wis: 12, Ability.cha: 8},
    optimalRaces: ['elf', 'gnome', 'human'],
    startingItems: ['quarterstaff', 'spellbook', 'arcane_focus', 'potion_healing'],
    features: [
      ClassFeature(1, 'Arcane Recovery', 'Recover spell slots on a short rest.'),
      ClassFeature(2, 'Arcane Tradition', 'Choose your school of magic.'),
    ],
  ),
];

ClassDef classById(String id) => classes.firstWhere((c) => c.id == id, orElse: () => classes.first);

class BackgroundDef {
  const BackgroundDef(this.id, this.name, this.skills, this.feature, this.description, this.gold);
  final String id;
  final String name;
  final List<Skill> skills;
  final String feature;
  final String description;
  final int gold;
}

const backgrounds = <BackgroundDef>[
  BackgroundDef('acolyte', 'Acolyte', [Skill.insight, Skill.religion], 'Shelter of the Faithful', 'Raised in service to a temple.', 15),
  BackgroundDef('charlatan', 'Charlatan', [Skill.deception, Skill.sleightOfHand], 'False Identity', 'A smooth-talking con artist.', 15),
  BackgroundDef('criminal', 'Criminal', [Skill.deception, Skill.stealth], 'Criminal Contact', 'Experienced in breaking the law.', 15),
  BackgroundDef('entertainer', 'Entertainer', [Skill.acrobatics, Skill.performance], 'By Popular Demand', 'You thrive in front of an audience.', 15),
  BackgroundDef('folk_hero', 'Folk Hero', [Skill.animalHandling, Skill.survival], 'Rustic Hospitality', 'A humble champion of common folk.', 10),
  BackgroundDef('guild_artisan', 'Guild Artisan', [Skill.insight, Skill.persuasion], 'Guild Membership', 'A skilled member of an artisan guild.', 15),
  BackgroundDef('hermit', 'Hermit', [Skill.medicine, Skill.religion], 'Discovery', 'You lived in seclusion seeking truth.', 5),
  BackgroundDef('noble', 'Noble', [Skill.history, Skill.persuasion], 'Position of Privilege', 'Born to wealth and title.', 25),
  BackgroundDef('outlander', 'Outlander', [Skill.athletics, Skill.survival], 'Wanderer', 'Raised in the wilds, far from civilization.', 10),
  BackgroundDef('sage', 'Sage', [Skill.arcana, Skill.history], 'Researcher', 'Years spent studying lore.', 10),
  BackgroundDef('soldier', 'Soldier', [Skill.athletics, Skill.intimidation], 'Military Rank', 'You served in an army.', 10),
  BackgroundDef('urchin', 'Urchin', [Skill.sleightOfHand, Skill.stealth], 'City Secrets', 'You grew up alone on the streets.', 10),
];

BackgroundDef backgroundById(String id) => backgrounds.firstWhere((b) => b.id == id, orElse: () => backgrounds.first);

enum ItemType { weapon, armor, shield, potion, gear, treasure, scroll, food, wondrous }

class ItemDef {
  const ItemDef(this.id, this.name, this.type,
      {this.damage,
      this.damageType,
      this.finesse = false,
      this.ranged = false,
      this.ac,
      this.dexCap,
      this.value = 1,
      this.heal,
      this.description = '',
      this.twoHanded = false,
      this.rarity = 'common',
      this.attune = false,
      this.bonus = 0,
      this.extraDice,
      this.extraType,
      this.setAbility,
      this.setScore = 0,
      this.acBonus = 0,
      this.saveBonus = 0,
      this.speedBonus = 0,
      this.heavy = false,
      this.effect});
  final String id;
  final String name;
  final ItemType type;
  final String? damage;
  final String? damageType;
  final bool finesse;
  final bool ranged;
  final int? ac;
  final int? dexCap;
  final int value;
  final String? heal;
  final String description;
  final bool twoHanded;

  /// common | uncommon | rare | very rare | legendary
  final String rarity;
  final bool attune;

  /// +N to attack and damage (weapons) or AC (armor, shields).
  final int bonus;
  final String? extraDice;
  final String? extraType;

  /// Sets an ability score to [setScore] (e.g. Gauntlets of Ogre Power).
  final Ability? setAbility;
  final int setScore;
  final int acBonus;
  final int saveBonus;
  final int speedBonus;
  final bool heavy;

  /// Consumable effect id (fire_breath, invisibility, resistance, strength…).
  final String? effect;

  bool get isMagic => rarity != 'common' || bonus > 0 || attune;
}

const items = <ItemDef>[
  ItemDef('dagger', 'Dagger', ItemType.weapon, damage: '1d4', damageType: 'piercing', finesse: true, value: 2),
  ItemDef('shortsword', 'Shortsword', ItemType.weapon, damage: '1d6', damageType: 'piercing', finesse: true, value: 10),
  ItemDef('rapier', 'Rapier', ItemType.weapon, damage: '1d8', damageType: 'piercing', finesse: true, value: 25),
  ItemDef('longsword', 'Longsword', ItemType.weapon, damage: '1d8', damageType: 'slashing', value: 15),
  ItemDef('greatsword', 'Greatsword', ItemType.weapon, damage: '2d6', damageType: 'slashing', value: 50, twoHanded: true),
  ItemDef('greataxe', 'Greataxe', ItemType.weapon, damage: '1d12', damageType: 'slashing', value: 30, twoHanded: true),
  ItemDef('handaxe', 'Handaxe', ItemType.weapon, damage: '1d6', damageType: 'slashing', value: 5),
  ItemDef('mace', 'Mace', ItemType.weapon, damage: '1d6', damageType: 'bludgeoning', value: 5),
  ItemDef('warhammer', 'Warhammer', ItemType.weapon, damage: '1d8', damageType: 'bludgeoning', value: 15),
  ItemDef('quarterstaff', 'Quarterstaff', ItemType.weapon, damage: '1d6', damageType: 'bludgeoning', value: 1),
  ItemDef('longbow', 'Longbow', ItemType.weapon, damage: '1d8', damageType: 'piercing', ranged: true, value: 50, twoHanded: true),
  ItemDef('shortbow', 'Shortbow', ItemType.weapon, damage: '1d6', damageType: 'piercing', ranged: true, value: 25, twoHanded: true),
  ItemDef('light_crossbow', 'Light Crossbow', ItemType.weapon, damage: '1d8', damageType: 'piercing', ranged: true, value: 25, twoHanded: true),
  ItemDef('darts', 'Darts', ItemType.weapon, damage: '1d4', damageType: 'piercing', ranged: true, finesse: true, value: 1),
  ItemDef('leather_armor', 'Leather Armor', ItemType.armor, ac: 11, value: 10),
  ItemDef('studded_leather', 'Studded Leather', ItemType.armor, ac: 12, value: 45),
  ItemDef('scale_mail', 'Scale Mail', ItemType.armor, ac: 14, dexCap: 2, value: 50),
  ItemDef('chain_mail', 'Chain Mail', ItemType.armor, ac: 16, dexCap: 0, value: 75, heavy: true),
  ItemDef('plate', 'Plate Armor', ItemType.armor, ac: 18, dexCap: 0, value: 1500, heavy: true),
  ItemDef('shield', 'Shield', ItemType.shield, ac: 2, value: 10),
  ItemDef('potion_healing', 'Potion of Healing', ItemType.potion, heal: '2d4+2', value: 50, description: 'A red, glimmering liquid.'),
  ItemDef('potion_greater', 'Potion of Greater Healing', ItemType.potion, heal: '4d4+4', value: 150, description: 'Thick crimson draught.'),
  ItemDef('rations', 'Rations', ItemType.food, value: 1, description: 'Dried meat, hardtack and fruit.'),
  ItemDef('arrows', 'Arrows', ItemType.gear, value: 1, description: 'Ammunition for bows. Sold in bundles of 20.'),
  ItemDef('bolts', 'Crossbow Bolts', ItemType.gear, value: 1, description: 'Ammunition for crossbows. Sold in bundles of 20.'),
  ItemDef('torch', 'Torch', ItemType.gear, value: 1),
  ItemDef('rope', 'Hempen Rope (50 ft)', ItemType.gear, value: 1),
  ItemDef('thieves_tools', "Thieves' Tools", ItemType.gear, value: 25),
  ItemDef('holy_symbol', 'Holy Symbol', ItemType.gear, value: 5),
  ItemDef('arcane_focus', 'Arcane Focus', ItemType.gear, value: 10),
  ItemDef('spellbook', 'Spellbook', ItemType.gear, value: 50),
  ItemDef('lute', 'Lute', ItemType.gear, value: 35),
  ItemDef('herbalism_kit', 'Herbalism Kit', ItemType.gear, value: 5),
  ItemDef('explorers_pack', "Explorer's Pack", ItemType.gear, value: 10),
  ItemDef('scroll_fireball', 'Scroll of Fireball', ItemType.scroll, damage: '8d6', damageType: 'fire', value: 300),
  ItemDef('scroll_shield', 'Scroll of Shielding', ItemType.scroll, value: 80),
  // Extra mundane gear
  ItemDef('battleaxe', 'Battleaxe', ItemType.weapon, damage: '1d8', damageType: 'slashing', value: 10),
  ItemDef('spear', 'Spear', ItemType.weapon, damage: '1d6', damageType: 'piercing', value: 1),
  ItemDef('scimitar', 'Scimitar', ItemType.weapon, damage: '1d6', damageType: 'slashing', finesse: true, value: 25),
  ItemDef('heavy_crossbow', 'Heavy Crossbow', ItemType.weapon, damage: '1d10', damageType: 'piercing', ranged: true, twoHanded: true, value: 50),
  ItemDef('half_plate', 'Half Plate', ItemType.armor, ac: 15, dexCap: 2, value: 750),
  ItemDef('breastplate', 'Breastplate', ItemType.armor, ac: 14, dexCap: 2, value: 400),
  ItemDef('healers_kit', "Healer's Kit", ItemType.gear, value: 5, description: 'Stabilize a dying creature.'),
  ItemDef('antitoxin', 'Antitoxin', ItemType.potion, value: 50, effect: 'cure_poison', description: 'Cures the Poisoned condition.'),
  ItemDef('alchemist_fire', "Alchemist's Fire", ItemType.scroll, damage: '2d6', damageType: 'fire', value: 50, description: 'Thrown flask of sticky fire.'),
  // Potions
  ItemDef('potion_superior', 'Potion of Superior Healing', ItemType.potion, heal: '8d4+8', value: 450, rarity: 'rare'),
  ItemDef('potion_fire_breath', 'Potion of Fire Breath', ItemType.potion, value: 150, rarity: 'uncommon', effect: 'fire_breath', damage: '4d6', damageType: 'fire', description: 'Exhale fire at up to three foes (DEX save DC 13 for half).'),
  ItemDef('potion_invisibility', 'Potion of Invisibility', ItemType.potion, value: 180, rarity: 'very rare', effect: 'invisibility', description: 'Become invisible: advantage on your next attacks and enemies have disadvantage against you.'),
  ItemDef('potion_giant_strength', 'Potion of Hill Giant Strength', ItemType.potion, value: 200, rarity: 'uncommon', effect: 'strength', description: 'STR becomes 21 for the rest of the battle.'),
  ItemDef('potion_resistance', 'Potion of Resistance', ItemType.potion, value: 120, rarity: 'uncommon', effect: 'resistance', description: 'Take half damage for the rest of the battle.'),
  ItemDef('potion_heroism', 'Potion of Heroism', ItemType.potion, value: 180, rarity: 'rare', effect: 'heroism', description: 'Gain 10 temporary HP and Bless for the battle.'),
  // Magic weapons
  ItemDef('longsword_1', 'Longsword +1', ItemType.weapon, damage: '1d8', damageType: 'slashing', value: 500, rarity: 'uncommon', bonus: 1),
  ItemDef('rapier_1', 'Rapier +1', ItemType.weapon, damage: '1d8', damageType: 'piercing', finesse: true, value: 500, rarity: 'uncommon', bonus: 1),
  ItemDef('longbow_1', 'Longbow +1', ItemType.weapon, damage: '1d8', damageType: 'piercing', ranged: true, twoHanded: true, value: 500, rarity: 'uncommon', bonus: 1),
  ItemDef('greataxe_2', 'Greataxe +2', ItemType.weapon, damage: '1d12', damageType: 'slashing', twoHanded: true, value: 2000, rarity: 'rare', bonus: 2),
  ItemDef('flame_tongue', 'Flame Tongue', ItemType.weapon, damage: '1d8', damageType: 'slashing', value: 2500, rarity: 'rare', attune: true, extraDice: '2d6', extraType: 'fire', description: 'The blade bursts into flame on command.'),
  ItemDef('frost_brand', 'Frost Brand Dagger', ItemType.weapon, damage: '1d4', damageType: 'piercing', finesse: true, value: 2200, rarity: 'rare', attune: true, extraDice: '1d6', extraType: 'cold'),
  ItemDef('mace_disruption', 'Mace of Disruption', ItemType.weapon, damage: '1d6', damageType: 'bludgeoning', value: 3000, rarity: 'rare', attune: true, extraDice: '2d6', extraType: 'radiant', description: 'Deals extra radiant damage (best against undead and fiends).'),
  ItemDef('staff_power', 'Staff of Power', ItemType.weapon, damage: '1d6', damageType: 'bludgeoning', value: 15000, rarity: 'very rare', attune: true, bonus: 2, acBonus: 2, saveBonus: 2, description: '+2 to attacks, AC and saving throws.'),
  // Magic armor & wondrous items
  ItemDef('leather_1', 'Leather Armor +1', ItemType.armor, ac: 11, value: 400, rarity: 'uncommon', bonus: 1),
  ItemDef('chain_mail_1', 'Chain Mail +1', ItemType.armor, ac: 16, dexCap: 0, value: 1500, rarity: 'rare', bonus: 1, heavy: true),
  ItemDef('shield_1', 'Shield +1', ItemType.shield, ac: 2, value: 500, rarity: 'uncommon', bonus: 1),
  ItemDef('ring_protection', 'Ring of Protection', ItemType.wondrous, value: 3500, rarity: 'rare', attune: true, acBonus: 1, saveBonus: 1, description: '+1 to AC and saving throws.'),
  ItemDef('cloak_protection', 'Cloak of Protection', ItemType.wondrous, value: 3500, rarity: 'uncommon', attune: true, acBonus: 1, saveBonus: 1, description: '+1 to AC and saving throws.'),
  ItemDef('gauntlets_ogre', 'Gauntlets of Ogre Power', ItemType.wondrous, value: 8000, rarity: 'uncommon', attune: true, setAbility: Ability.str, setScore: 19, description: 'Your Strength score is 19.'),
  ItemDef('amulet_health', 'Amulet of Health', ItemType.wondrous, value: 8000, rarity: 'rare', attune: true, setAbility: Ability.con, setScore: 19, description: 'Your Constitution score is 19.'),
  ItemDef('headband_intellect', 'Headband of Intellect', ItemType.wondrous, value: 8000, rarity: 'uncommon', attune: true, setAbility: Ability.int_, setScore: 19, description: 'Your Intelligence score is 19.'),
  ItemDef('boots_elvenkind', 'Boots of Elvenkind', ItemType.wondrous, value: 2500, rarity: 'uncommon', description: 'Your steps make no sound (advantage on Stealth).', effect: 'stealth'),
  ItemDef('boots_speed', 'Boots of Striding', ItemType.wondrous, value: 5000, rarity: 'uncommon', attune: true, speedBonus: 10, description: '+10 ft speed.'),
  ItemDef('periapt_wound', 'Periapt of Wound Closure', ItemType.wondrous, value: 5000, rarity: 'uncommon', attune: true, description: 'Healing you receive from hit dice is doubled.', effect: 'wound_closure'),
  ItemDef('bag_holding', 'Bag of Holding', ItemType.wondrous, value: 4000, rarity: 'uncommon', description: 'Bigger on the inside.'),
  ItemDef('wand_missiles', 'Wand of Magic Missiles', ItemType.wondrous, value: 8000, rarity: 'uncommon', damage: '3d4+3', damageType: 'force', description: 'Unerring darts of force (usable in combat).', effect: 'wand'),
  ItemDef('scroll_fireball_2', 'Scroll of Lightning Bolt', ItemType.scroll, damage: '8d6', damageType: 'lightning', value: 300, rarity: 'uncommon'),
];

const rarityOrder = ['common', 'uncommon', 'rare', 'very rare', 'legendary'];

List<ItemDef> itemsOfRarity(String rarity) => items.where((i) => i.rarity == rarity && i.isMagic).toList();

ItemDef? itemById(String id) {
  for (final i in items) {
    if (i.id == id) return i;
  }
  return null;
}

enum SpellKind { attack, save, heal, buff, utility }

class SpellDef {
  const SpellDef(this.id, this.name, this.level, this.classes, this.kind,
      {this.dice, this.damageType, this.save, this.description = '', this.scaling = true, this.aoe = false, this.concentration = false, this.condition, this.reaction = false, this.school = 'evocation'});
  final String id;
  final String name;
  final int level;
  final List<String> classes;
  final SpellKind kind;
  final String? dice;
  final String? damageType;
  final Ability? save;
  final String description;
  final bool scaling;
  final bool aoe;

  /// Ends if the caster casts another concentration spell or fails a CON save.
  final bool concentration;

  /// Condition applied on a failed save / hit.
  final String? condition;

  /// Cast automatically in response to a trigger (Shield, Hellish Rebuke).
  final bool reaction;
  final String school;
}

const spells = <SpellDef>[
  // Cantrips
  SpellDef('fire_bolt', 'Fire Bolt', 0, ['sorcerer', 'wizard'], SpellKind.attack, dice: '1d10', damageType: 'fire', description: 'Hurl a mote of fire.'),
  SpellDef('ray_of_frost', 'Ray of Frost', 0, ['sorcerer', 'wizard'], SpellKind.attack, dice: '1d8', damageType: 'cold', description: 'A frigid beam slows the target.'),
  SpellDef('eldritch_blast', 'Eldritch Blast', 0, ['warlock'], SpellKind.attack, dice: '1d10', damageType: 'force', description: 'A beam of crackling energy.'),
  SpellDef('sacred_flame', 'Sacred Flame', 0, ['cleric'], SpellKind.save, dice: '1d8', damageType: 'radiant', save: Ability.dex, description: 'Flame-like radiance descends on a foe.'),
  SpellDef('vicious_mockery', 'Vicious Mockery', 0, ['bard'], SpellKind.save, dice: '1d4', damageType: 'psychic', save: Ability.wis, description: 'A string of insults laced with enchantment.'),
  SpellDef('produce_flame', 'Produce Flame', 0, ['druid'], SpellKind.attack, dice: '1d8', damageType: 'fire', description: 'A flickering flame in your palm, hurled.'),
  SpellDef('shocking_grasp', 'Shocking Grasp', 0, ['sorcerer', 'wizard'], SpellKind.attack, dice: '1d8', damageType: 'lightning', description: 'Lightning springs from your hand.'),
  SpellDef('chill_touch', 'Chill Touch', 0, ['sorcerer', 'wizard', 'warlock'], SpellKind.attack, dice: '1d8', damageType: 'necrotic', description: 'A ghostly skeletal hand.'),
  SpellDef('guidance', 'Guidance', 0, ['cleric', 'druid'], SpellKind.buff, description: 'Add 1d4 to one ability check.'),
  SpellDef('light', 'Light', 0, ['bard', 'cleric', 'sorcerer', 'wizard'], SpellKind.utility, description: 'An object sheds bright light.'),
  SpellDef('mage_hand', 'Mage Hand', 0, ['bard', 'sorcerer', 'warlock', 'wizard'], SpellKind.utility, description: 'A spectral floating hand.'),
  SpellDef('minor_illusion', 'Minor Illusion', 0, ['bard', 'sorcerer', 'warlock', 'wizard'], SpellKind.utility, description: 'Create a sound or image.'),
  // Level 1
  SpellDef('magic_missile', 'Magic Missile', 1, ['sorcerer', 'wizard'], SpellKind.utility, dice: '3d4+3', damageType: 'force', description: 'Three glowing darts that never miss.'),
  SpellDef('burning_hands', 'Burning Hands', 1, ['sorcerer', 'wizard'], SpellKind.save, dice: '3d6', damageType: 'fire', save: Ability.dex, aoe: true, description: 'A thin sheet of flames.'),
  SpellDef('thunderwave', 'Thunderwave', 1, ['bard', 'druid', 'sorcerer', 'wizard'], SpellKind.save, dice: '2d8', damageType: 'thunder', save: Ability.con, aoe: true, description: 'A wave of thunderous force.'),
  SpellDef('cure_wounds', 'Cure Wounds', 1, ['bard', 'cleric', 'druid', 'paladin', 'ranger'], SpellKind.heal, dice: '1d8', description: 'Restore hit points with a touch.'),
  SpellDef('healing_word', 'Healing Word', 1, ['bard', 'cleric', 'druid'], SpellKind.heal, dice: '1d4', description: 'A word of power heals an ally at range.'),
  SpellDef('guiding_bolt', 'Guiding Bolt', 1, ['cleric'], SpellKind.attack, dice: '4d6', damageType: 'radiant', description: 'A flash of light streaks toward a foe.'),
  SpellDef('hex', 'Hex', 1, ['warlock'], SpellKind.buff, dice: '1d6', damageType: 'necrotic', description: 'Curse a target; your hits deal extra 1d6.', concentration: true, school: 'enchantment'),
  SpellDef('hellish_rebuke', 'Hellish Rebuke', 1, ['warlock'], SpellKind.save, dice: '2d10', damageType: 'fire', save: Ability.dex, description: 'Hellish flames engulf an attacker. Cast automatically as a reaction when you are hit.', reaction: true),
  SpellDef('shield', 'Shield', 1, ['sorcerer', 'wizard'], SpellKind.buff, description: '+5 AC until your next turn. Cast automatically as a reaction when a hit would land.', reaction: true, school: 'abjuration'),
  SpellDef('sleep', 'Sleep', 1, ['bard', 'sorcerer', 'wizard'], SpellKind.utility, dice: '5d8', aoe: true, description: 'Send creatures into magical slumber.'),
  SpellDef('bless', 'Bless', 1, ['cleric', 'paladin'], SpellKind.buff, description: 'Allies add 1d4 to attacks and saves.', concentration: true, school: 'enchantment'),
  SpellDef('hunters_mark', "Hunter's Mark", 1, ['ranger'], SpellKind.buff, dice: '1d6', description: 'Mark a quarry; deal extra 1d6.', concentration: true, school: 'divination'),
  SpellDef('ensnaring_strike', 'Ensnaring Strike', 1, ['ranger'], SpellKind.save, dice: '1d6', damageType: 'piercing', save: Ability.str, description: 'Thorny vines grasp the target.'),
  SpellDef('divine_favor', 'Divine Favor', 1, ['paladin'], SpellKind.buff, dice: '1d4', description: 'Weapon attacks deal +1d4 radiant.'),
  SpellDef('thunderous_smite', 'Thunderous Smite', 1, ['paladin'], SpellKind.attack, dice: '2d6', damageType: 'thunder', description: 'Your weapon rings with thunder.'),
  SpellDef('dissonant_whispers', 'Dissonant Whispers', 1, ['bard'], SpellKind.save, dice: '3d6', damageType: 'psychic', save: Ability.wis, description: 'A discordant melody only one creature hears.'),
  SpellDef('entangle', 'Entangle', 1, ['druid'], SpellKind.save, dice: '1d4', damageType: 'bludgeoning', save: Ability.str, aoe: true, description: 'Grasping weeds restrain foes.', concentration: true, condition: 'Restrained', school: 'conjuration'),
  SpellDef('chromatic_orb', 'Chromatic Orb', 1, ['sorcerer', 'wizard'], SpellKind.attack, dice: '3d8', damageType: 'acid', description: 'A sphere of elemental energy.'),
  // Level 2
  SpellDef('scorching_ray', 'Scorching Ray', 2, ['sorcerer', 'wizard'], SpellKind.attack, dice: '6d6', damageType: 'fire', description: 'Three rays of fire.'),
  SpellDef('shatter', 'Shatter', 2, ['bard', 'sorcerer', 'warlock', 'wizard'], SpellKind.save, dice: '3d8', damageType: 'thunder', save: Ability.con, aoe: true, description: 'A painfully loud ringing noise.'),
  SpellDef('spiritual_weapon', 'Spiritual Weapon', 2, ['cleric'], SpellKind.attack, dice: '1d8+3', damageType: 'force', description: 'A floating spectral weapon.'),
  SpellDef('moonbeam', 'Moonbeam', 2, ['druid'], SpellKind.save, dice: '2d10', damageType: 'radiant', save: Ability.con, description: 'A silvery beam of pale light.'),
  SpellDef('misty_step', 'Misty Step', 2, ['sorcerer', 'warlock', 'wizard'], SpellKind.utility, description: 'Teleport 30 feet.'),
  SpellDef('prayer_of_healing', 'Prayer of Healing', 2, ['cleric'], SpellKind.heal, dice: '2d8', description: 'Heal up to six allies.'),
  SpellDef('hold_person', 'Hold Person', 2, ['bard', 'cleric', 'druid', 'sorcerer', 'warlock', 'wizard'], SpellKind.save, save: Ability.wis, description: 'Paralyze a humanoid.', concentration: true, condition: 'Paralyzed', school: 'enchantment'),
  // Level 3
  SpellDef('fireball', 'Fireball', 3, ['sorcerer', 'wizard'], SpellKind.save, dice: '8d6', damageType: 'fire', save: Ability.dex, aoe: true, description: 'A bright streak blossoms into an explosion of flame.'),
  SpellDef('lightning_bolt', 'Lightning Bolt', 3, ['sorcerer', 'wizard'], SpellKind.save, dice: '8d6', damageType: 'lightning', save: Ability.dex, aoe: true, description: 'A stroke of lightning 100 feet long.'),
  SpellDef('spirit_guardians', 'Spirit Guardians', 3, ['cleric'], SpellKind.save, dice: '3d8', damageType: 'radiant', save: Ability.wis, aoe: true, description: 'Spirits protect you.'),
  SpellDef('mass_healing_word', 'Mass Healing Word', 3, ['cleric'], SpellKind.heal, dice: '1d4', description: 'Heal up to six creatures.'),
  SpellDef('hunger_of_hadar', 'Hunger of Hadar', 3, ['warlock'], SpellKind.save, dice: '2d6', damageType: 'cold', save: Ability.dex, aoe: true, description: 'A sphere of blackness and bitter cold.'),
  // Expanded spell list
  SpellDef('toll_the_dead', 'Toll the Dead', 0, ['cleric', 'warlock', 'wizard'], SpellKind.save, dice: '1d12', damageType: 'necrotic', save: Ability.wis, description: 'A mournful bell tolls for the target.'),
  SpellDef('thorn_whip', 'Thorn Whip', 0, ['druid'], SpellKind.attack, dice: '1d6', damageType: 'piercing', description: 'A vine lashes the target.'),
  SpellDef('booming_blade', 'Booming Blade', 0, ['sorcerer', 'warlock', 'wizard'], SpellKind.attack, dice: '1d8', damageType: 'thunder', description: 'Your strike reverberates with thunder.'),
  SpellDef('faerie_fire', 'Faerie Fire', 1, ['bard', 'druid'], SpellKind.save, save: Ability.dex, aoe: true, description: 'Outline foes in light; attacks against them have advantage.', concentration: true, condition: 'Outlined', school: 'evocation'),
  SpellDef('command', 'Command', 1, ['cleric', 'paladin'], SpellKind.save, save: Ability.wis, description: 'Speak a one-word command: the target falls prone.', condition: 'Prone', school: 'enchantment'),
  SpellDef('ice_knife', 'Ice Knife', 1, ['druid', 'sorcerer', 'wizard'], SpellKind.attack, dice: '1d10+2d6', damageType: 'cold', description: 'A shard of ice that explodes on impact.'),
  SpellDef('hail_of_thorns', 'Hail of Thorns', 1, ['ranger'], SpellKind.save, dice: '1d10', damageType: 'piercing', save: Ability.dex, aoe: true, description: 'Your arrow erupts into a hail of thorns.'),
  SpellDef('searing_smite', 'Searing Smite', 1, ['paladin'], SpellKind.attack, dice: '1d6+1d6', damageType: 'fire', description: 'Your weapon flares with white-hot heat.'),
  SpellDef('armor_of_agathys', 'Armor of Agathys', 1, ['warlock'], SpellKind.buff, description: 'Gain 5 temporary HP per slot level of spectral frost.', school: 'abjuration'),
  SpellDef('false_life', 'False Life', 1, ['sorcerer', 'wizard'], SpellKind.buff, description: 'Gain 1d4 + 4 temporary HP.', school: 'necromancy'),
  SpellDef('mage_armor', 'Mage Armor', 1, ['sorcerer', 'wizard'], SpellKind.buff, description: 'AC becomes 13 + DEX while unarmored.', school: 'abjuration'),
  SpellDef('heroism', 'Heroism', 1, ['bard', 'paladin'], SpellKind.buff, description: 'Immune to fear and gain temporary HP each turn.', concentration: true, school: 'enchantment'),
  SpellDef('witch_bolt', 'Witch Bolt', 1, ['sorcerer', 'warlock', 'wizard'], SpellKind.attack, dice: '1d12', damageType: 'lightning', description: 'A crackling beam of blue energy.', concentration: true),
  SpellDef('web', 'Web', 2, ['sorcerer', 'wizard'], SpellKind.save, save: Ability.dex, aoe: true, description: 'Sticky webs restrain creatures.', concentration: true, condition: 'Restrained', school: 'conjuration'),
  SpellDef('mirror_image', 'Mirror Image', 2, ['sorcerer', 'warlock', 'wizard'], SpellKind.buff, description: 'Illusory duplicates make attacks against you miss more often.', school: 'illusion'),
  SpellDef('blur', 'Blur', 2, ['sorcerer', 'wizard'], SpellKind.buff, description: 'Attacks against you have disadvantage.', concentration: true, school: 'illusion'),
  SpellDef('aid', 'Aid', 2, ['cleric', 'paladin'], SpellKind.heal, dice: '0d1+5', description: 'Bolster allies: +5 HP to the party.', school: 'abjuration'),
  SpellDef('lesser_restoration', 'Lesser Restoration', 2, ['bard', 'cleric', 'druid', 'paladin', 'ranger'], SpellKind.heal, dice: '0d1', description: 'End one disease or condition (poisoned, paralyzed, blinded).', school: 'abjuration'),
  SpellDef('branding_smite', 'Branding Smite', 2, ['paladin'], SpellKind.attack, dice: '1d8+2d6', damageType: 'radiant', description: 'Your weapon gleams with astral radiance.'),
  SpellDef('flaming_sphere', 'Flaming Sphere', 2, ['druid', 'wizard'], SpellKind.save, dice: '2d6', damageType: 'fire', save: Ability.dex, description: 'A rolling ball of fire.', concentration: true, school: 'conjuration'),
  SpellDef('cloud_of_daggers', 'Cloud of Daggers', 2, ['bard', 'sorcerer', 'warlock', 'wizard'], SpellKind.utility, dice: '4d4', damageType: 'slashing', description: 'Spinning daggers fill a cube.', concentration: true, school: 'conjuration'),
  SpellDef('counterspell', 'Counterspell', 3, ['sorcerer', 'warlock', 'wizard'], SpellKind.buff, description: 'Interrupt an enemy spell. Cast automatically as a reaction when an enemy caster attacks.', reaction: true, school: 'abjuration'),
  SpellDef('haste', 'Haste', 3, ['sorcerer', 'wizard'], SpellKind.buff, description: '+2 AC and an extra attack each turn.', concentration: true, school: 'transmutation'),
  SpellDef('call_lightning', 'Call Lightning', 3, ['druid'], SpellKind.save, dice: '3d10', damageType: 'lightning', save: Ability.dex, description: 'A storm cloud strikes your foe.', concentration: true, school: 'conjuration'),
  SpellDef('vampiric_touch', 'Vampiric Touch', 3, ['warlock', 'wizard'], SpellKind.attack, dice: '3d6', damageType: 'necrotic', description: 'Drain life; heal half the damage dealt.', concentration: true, school: 'necromancy'),
  SpellDef('revivify', 'Revivify', 3, ['cleric', 'paladin'], SpellKind.heal, dice: '0d1+1', description: 'Return a fallen ally to life with 1 HP.', school: 'necromancy'),
  SpellDef('hypnotic_pattern', 'Hypnotic Pattern', 3, ['bard', 'sorcerer', 'warlock', 'wizard'], SpellKind.save, save: Ability.wis, aoe: true, description: 'A twisting pattern of colors charms foes into a stupor.', concentration: true, condition: 'Paralyzed', school: 'illusion'),
  SpellDef('ice_storm', 'Ice Storm', 4, ['druid', 'sorcerer', 'wizard'], SpellKind.save, dice: '2d8+4d6', damageType: 'cold', save: Ability.dex, aoe: true, description: 'Hail pounds the area.'),
  SpellDef('blight', 'Blight', 4, ['druid', 'sorcerer', 'warlock', 'wizard'], SpellKind.save, dice: '8d8', damageType: 'necrotic', save: Ability.con, description: 'Necromantic energy withers a creature.', school: 'necromancy'),
  SpellDef('greater_invisibility', 'Greater Invisibility', 4, ['bard', 'sorcerer', 'wizard'], SpellKind.buff, description: 'You become invisible: advantage on attacks, enemies have disadvantage.', concentration: true, school: 'illusion'),
  SpellDef('banishment', 'Banishment', 4, ['cleric', 'paladin', 'sorcerer', 'warlock', 'wizard'], SpellKind.save, save: Ability.cha, description: 'Send a creature to a harmless demiplane for the fight.', concentration: true, condition: 'Banished', school: 'abjuration'),
  SpellDef('guardian_of_faith', 'Guardian of Faith', 4, ['cleric'], SpellKind.save, dice: '4d10', damageType: 'radiant', save: Ability.dex, aoe: true, description: 'A spectral guardian strikes nearby foes.', school: 'conjuration'),
  SpellDef('cone_of_cold', 'Cone of Cold', 5, ['sorcerer', 'wizard'], SpellKind.save, dice: '8d8', damageType: 'cold', save: Ability.con, aoe: true, description: 'A blast of freezing air.'),
  SpellDef('mass_cure_wounds', 'Mass Cure Wounds', 5, ['bard', 'cleric', 'druid'], SpellKind.heal, dice: '3d8', description: 'Heal the whole party.', school: 'evocation'),
  SpellDef('flame_strike', 'Flame Strike', 5, ['cleric'], SpellKind.save, dice: '8d6', damageType: 'fire', save: Ability.dex, aoe: true, description: 'A column of divine fire.'),
  SpellDef('synaptic_static', 'Synaptic Static', 5, ['bard', 'sorcerer', 'warlock', 'wizard'], SpellKind.save, dice: '8d6', damageType: 'psychic', save: Ability.int_, aoe: true, description: 'A psychic explosion.', school: 'enchantment'),
  SpellDef('destructive_wave', 'Destructive Wave', 5, ['paladin'], SpellKind.save, dice: '10d6', damageType: 'thunder', save: Ability.con, aoe: true, description: 'Strike the ground, releasing thunder and radiance.'),
  // ---- Levels 6–9
  SpellDef('chain_lightning', 'Chain Lightning', 6, ['sorcerer', 'wizard'], SpellKind.save, dice: '10d8', damageType: 'lightning', save: Ability.dex, aoe: true, description: 'A bolt leaps from foe to foe.', school: 'evocation'),
  SpellDef('disintegrate', 'Disintegrate', 6, ['sorcerer', 'wizard'], SpellKind.save, dice: '10d6+40', damageType: 'force', save: Ability.dex, description: 'A thin green ray. A successful save avoids it entirely; at 0 HP the target turns to dust.', school: 'transmutation'),
  SpellDef('harm', 'Harm', 6, ['cleric'], SpellKind.save, dice: '14d6', damageType: 'necrotic', save: Ability.con, description: 'Unleash a virulent disease on a creature.', school: 'necromancy'),
  SpellDef('heal', 'Heal', 6, ['cleric', 'druid'], SpellKind.heal, dice: '0d1+70', description: 'Restore 70 hit points and end blindness, deafness and disease.', school: 'evocation'),
  SpellDef('sunbeam', 'Sunbeam', 6, ['druid', 'sorcerer', 'wizard'], SpellKind.save, dice: '6d8', damageType: 'radiant', save: Ability.con, condition: 'Blinded', concentration: true, description: 'A beam of brilliant light that blinds those it burns.', school: 'evocation'),
  SpellDef('circle_of_death', 'Circle of Death', 6, ['sorcerer', 'warlock', 'wizard'], SpellKind.save, dice: '8d6', damageType: 'necrotic', save: Ability.con, aoe: true, description: 'A sphere of negative energy ripples outward.', school: 'necromancy'),
  SpellDef('finger_of_death', 'Finger of Death', 7, ['sorcerer', 'warlock', 'wizard'], SpellKind.save, dice: '7d8+30', damageType: 'necrotic', save: Ability.con, description: 'Negative energy tears through a creature.', school: 'necromancy'),
  SpellDef('fire_storm', 'Fire Storm', 7, ['cleric', 'druid', 'sorcerer'], SpellKind.save, dice: '7d10', damageType: 'fire', save: Ability.dex, aoe: true, description: 'A storm of roaring flame.', school: 'evocation'),
  SpellDef('prismatic_spray', 'Prismatic Spray', 7, ['sorcerer', 'wizard'], SpellKind.save, dice: '10d6', damageType: 'force', save: Ability.dex, aoe: true, description: 'Seven shimmering rays of every colour.', school: 'evocation'),
  SpellDef('regenerate', 'Regenerate', 7, ['bard', 'cleric', 'druid'], SpellKind.heal, dice: '4d8+15', description: 'Restore flesh and bone.', school: 'transmutation'),
  SpellDef('sunburst', 'Sunburst', 8, ['druid', 'sorcerer', 'wizard'], SpellKind.save, dice: '12d6', damageType: 'radiant', save: Ability.con, aoe: true, condition: 'Blinded', description: 'Brilliant sunlight flashes in a huge radius.', school: 'evocation'),
  SpellDef('feeblemind', 'Feeblemind', 8, ['bard', 'druid', 'warlock', 'wizard'], SpellKind.save, dice: '4d6', damageType: 'psychic', save: Ability.int_, condition: 'Stunned', description: 'Shatter a creature\'s intellect.', school: 'enchantment'),
  SpellDef('power_word_stun', 'Power Word Stun', 8, ['bard', 'sorcerer', 'warlock', 'wizard'], SpellKind.utility, description: 'A creature with 150 HP or fewer is stunned.', school: 'enchantment'),
  SpellDef('dominate_monster', 'Dominate Monster', 8, ['bard', 'sorcerer', 'warlock', 'wizard'], SpellKind.save, save: Ability.wis, condition: 'Charmed', concentration: true, description: 'Charm a creature so it cannot act against you.', school: 'enchantment'),
  SpellDef('meteor_swarm', 'Meteor Swarm', 9, ['sorcerer', 'wizard'], SpellKind.save, dice: '40d6', damageType: 'fire', save: Ability.dex, aoe: true, description: 'Blazing orbs of fire plummet to the ground.', school: 'evocation'),
  SpellDef('power_word_kill', 'Power Word Kill', 9, ['bard', 'sorcerer', 'warlock', 'wizard'], SpellKind.utility, description: 'A creature with 100 HP or fewer dies instantly.', school: 'enchantment'),
  SpellDef('mass_heal', 'Mass Heal', 9, ['cleric'], SpellKind.heal, dice: '0d1+100', description: 'A flood of healing energy for the whole party.', school: 'evocation'),
  SpellDef('psychic_scream', 'Psychic Scream', 9, ['bard', 'sorcerer', 'warlock', 'wizard'], SpellKind.save, dice: '14d6', damageType: 'psychic', save: Ability.int_, aoe: true, condition: 'Stunned', description: 'Unleash the power of your mind to blast foes.', school: 'enchantment'),
];

SpellDef? spellById(String id) {
  for (final s in spells) {
    if (s.id == id) return s;
  }
  return null;
}

List<SpellDef> spellsFor(String classId, {int maxLevel = 9}) =>
    spells.where((s) => s.classes.contains(classId) && s.level <= maxLevel).toList();

class MonsterDef {
  const MonsterDef(this.id, this.name, this.cr, this.hp, this.ac, this.attackBonus, this.damage, this.xp,
      {this.type = 'beast', this.attackName = 'Strike', this.multi = 1, this.description = '', this.environments = const [], this.dexMod = 1, this.color = const Color(0xFF8C7246), this.abilities = const []});
  final String id;
  final String name;
  final double cr;
  final int hp;
  final int ac;
  final int attackBonus;
  final String damage;
  final int xp;
  final String type;
  final String attackName;
  final int multi;
  final String description;
  final List<String> environments;
  final int dexMod;
  final Color color;

  /// Special abilities, encoded: `breath:type:dice:SAVE:dc`, `regen:n`, `pack`,
  /// `poison:dc`, `paralyze:dc`, `drain:dice`, `charge:dice`, `heal:dice`,
  /// `frighten:dc`, `ranged`, `resist`, `spellcaster`.
  final List<String> abilities;
}

String monsterAbilityText(String code) {
  final p = code.split(':');
  return switch (p.first) {
    'breath' => 'Breath weapon: ${p[2]} ${p[1]} damage to the party (${p[3]} save DC ${p[4]} for half). Recharges on a 5–6.',
    'regen' => 'Regeneration: regains ${p[1]} HP at the start of its turn.',
    'pack' => 'Pack tactics: advantage on attacks while an ally is standing.',
    'poison' => 'Venom: hits force a CON save (DC ${p[1]}) or the target is poisoned.',
    'paralyze' => 'Paralyzing touch: hits force a CON save (DC ${p[1]}) or the target is paralyzed.',
    'drain' => 'Life drain: hits deal an extra ${p[1]} necrotic damage.',
    'charge' => 'Charge: its first attack deals an extra ${p[1]} damage.',
    'heal' => 'Second wind: once, heals ${p[1]} when bloodied.',
    'frighten' => 'Frightful presence: WIS save (DC ${p[1]}) or frightened at the start of the fight.',
    'ranged' => 'Fights from the back row.',
    'resist' => 'Resistant: takes half damage from weapons.',
    'spellcaster' => 'Spellcaster: its attacks are spells (can be countered).',
    'legendary' => 'Legendary actions: after other creatures\' turns it can act ${p[1]} extra time${p[1] == '1' ? '' : 's'} per round.',
    'legres' => 'Legendary resistance: ${p[1]} time${p[1] == '1' ? '' : 's'} per fight it can choose to succeed on a failed save.',
    _ => code,
  };
}

const monsters = <MonsterDef>[
  MonsterDef('rat_swarm', 'Swarm of Rats', 0.25, 24, 10, 2, '2d6', 50, attackName: 'Bites', environments: ['dungeon', 'town', 'sewer'], color: Color(0xFF6E5A48)),
  MonsterDef('kobold', 'Kobold', 0.125, 5, 12, 4, '1d4+2', 25, type: 'humanoid', attackName: 'Dagger', environments: ['dungeon', 'cave', 'mountain'], dexMod: 2, color: Color(0xFFB0562C), abilities: ['pack']),
  MonsterDef('goblin', 'Goblin', 0.25, 7, 15, 4, '1d6+2', 50, type: 'humanoid', attackName: 'Scimitar', environments: ['forest', 'cave', 'dungeon', 'ruins'], dexMod: 2, color: Color(0xFF6E8A3A)),
  MonsterDef('bandit', 'Bandit', 0.125, 11, 12, 3, '1d6+1', 25, type: 'humanoid', attackName: 'Scimitar', environments: ['forest', 'road', 'town', 'coast'], dexMod: 1, color: Color(0xFF7A5A3A)),
  MonsterDef('wolf', 'Wolf', 0.25, 11, 13, 4, '2d4+2', 50, attackName: 'Bite', environments: ['forest', 'mountain', 'tundra'], dexMod: 2, color: Color(0xFF8A8A8A), abilities: ['pack']),
  MonsterDef('skeleton', 'Skeleton', 0.25, 13, 13, 4, '1d6+2', 50, type: 'undead', attackName: 'Shortsword', environments: ['dungeon', 'crypt', 'ruins'], dexMod: 2, color: Color(0xFFE8E0C8)),
  MonsterDef('zombie', 'Zombie', 0.25, 22, 8, 3, '1d6+1', 50, type: 'undead', attackName: 'Slam', environments: ['crypt', 'swamp', 'dungeon'], dexMod: -2, color: Color(0xFF6B7A52)),
  MonsterDef('cultist', 'Cultist', 0.125, 9, 12, 3, '1d6+1', 25, type: 'humanoid', attackName: 'Sacrificial Dagger', environments: ['temple', 'dungeon', 'town'], color: Color(0xFF7A1E24)),
  MonsterDef('giant_spider', 'Giant Spider', 1, 26, 14, 5, '1d8+3', 200, attackName: 'Venomous Bite', environments: ['forest', 'cave', 'dungeon'], dexMod: 3, color: Color(0xFF3A2A3A), abilities: ['poison:11']),
  MonsterDef('orc', 'Orc', 0.5, 15, 13, 5, '1d12+3', 100, type: 'humanoid', attackName: 'Greataxe', environments: ['mountain', 'forest', 'ruins'], color: Color(0xFF5B6B48)),
  MonsterDef('hobgoblin', 'Hobgoblin', 0.5, 11, 18, 3, '1d8+1', 100, type: 'humanoid', attackName: 'Longsword', environments: ['ruins', 'road', 'castle'], color: Color(0xFFB0462C)),
  MonsterDef('gnoll', 'Gnoll', 0.5, 22, 15, 4, '1d8+2', 100, type: 'humanoid', attackName: 'Spear', environments: ['desert', 'plains', 'ruins'], color: Color(0xFFA08050)),
  MonsterDef('shadow', 'Shadow', 0.5, 16, 12, 4, '2d6+2', 100, type: 'undead', attackName: 'Strength Drain', environments: ['crypt', 'dungeon', 'ruins'], color: Color(0xFF2A2440)),
  MonsterDef('dire_wolf', 'Dire Wolf', 1, 37, 14, 5, '2d6+3', 200, attackName: 'Bite', environments: ['forest', 'mountain', 'tundra'], dexMod: 2, color: Color(0xFF5A5048)),
  MonsterDef('bugbear', 'Bugbear', 1, 27, 16, 4, '2d8+2', 200, type: 'humanoid', attackName: 'Morningstar', environments: ['cave', 'forest', 'dungeon'], color: Color(0xFF8A5A2E)),
  MonsterDef('ghoul', 'Ghoul', 1, 22, 12, 4, '2d6+2', 200, type: 'undead', attackName: 'Claws', environments: ['crypt', 'swamp', 'dungeon'], color: Color(0xFF7A8A6A), abilities: ['paralyze:10']),
  MonsterDef('harpy', 'Harpy', 1, 38, 11, 3, '2d4+1', 200, type: 'monstrosity', attackName: 'Claws', environments: ['coast', 'mountain'], color: Color(0xFF8A6A9A)),
  MonsterDef('dark_acolyte', 'Dark Acolyte', 1, 22, 13, 4, '2d8', 200, type: 'humanoid', attackName: 'Necrotic Bolt', environments: ['temple', 'crypt', 'town'], color: Color(0xFF4A2D80), abilities: ['ranged', 'spellcaster', 'heal:2d8']),
  MonsterDef('animated_armor', 'Animated Armor', 1, 33, 18, 4, '1d6+2', 200, type: 'construct', attackName: 'Slam', multi: 2, environments: ['castle', 'dungeon', 'tower'], color: Color(0xFF8A8A9A)),
  MonsterDef('ogre', 'Ogre', 2, 59, 11, 6, '2d8+4', 450, type: 'giant', attackName: 'Greatclub', environments: ['mountain', 'forest', 'swamp', 'cave'], dexMod: -1, color: Color(0xFF8A7A52)),
  MonsterDef('gelatinous_cube', 'Gelatinous Cube', 2, 84, 6, 4, '3d6', 450, type: 'ooze', attackName: 'Pseudopod', environments: ['dungeon'], dexMod: -4, color: Color(0xFF6FC9B3)),
  MonsterDef('mimic', 'Mimic', 2, 58, 12, 5, '1d8+3', 450, type: 'monstrosity', attackName: 'Bite', environments: ['dungeon', 'castle', 'tower'], color: Color(0xFFA0703A)),
  MonsterDef('wererat', 'Wererat', 2, 33, 12, 4, '1d6+2', 450, type: 'humanoid', attackName: 'Bite', multi: 2, environments: ['sewer', 'town'], dexMod: 2, color: Color(0xFF5A4A3A)),
  MonsterDef('owlbear', 'Owlbear', 3, 59, 13, 7, '2d8+5', 700, type: 'monstrosity', attackName: 'Beak & Claws', multi: 2, environments: ['forest'], dexMod: 1, color: Color(0xFF8A6A42)),
  MonsterDef('wight', 'Wight', 3, 45, 14, 4, '1d8+2', 700, type: 'undead', attackName: 'Longsword', multi: 2, environments: ['crypt', 'ruins', 'tundra'], dexMod: 2, color: Color(0xFF6A7A8A)),
  MonsterDef('basilisk', 'Basilisk', 3, 52, 15, 5, '2d6+3', 700, type: 'monstrosity', attackName: 'Bite', environments: ['cave', 'desert', 'ruins'], color: Color(0xFF4E7A4F), abilities: ['paralyze:12']),
  MonsterDef('minotaur', 'Minotaur', 3, 76, 14, 6, '2d12+4', 700, type: 'monstrosity', attackName: 'Greataxe', environments: ['dungeon', 'ruins', 'labyrinth'], color: Color(0xFF6B3A2A), abilities: ['charge:2d8']),
  MonsterDef('wraith', 'Wraith', 5, 67, 13, 6, '4d8+3', 1800, type: 'undead', attackName: 'Life Drain', environments: ['crypt', 'ruins', 'castle'], dexMod: 3, color: Color(0xFF2A2A40), abilities: ['drain:2d6', 'resist']),
  MonsterDef('troll', 'Troll', 5, 84, 15, 7, '2d6+4', 1800, type: 'giant', attackName: 'Claws', multi: 3, environments: ['swamp', 'mountain', 'forest'], dexMod: 1, color: Color(0xFF4E6A42), abilities: ['regen:10']),
  MonsterDef('young_dragon', 'Young Red Dragon', 10, 178, 18, 10, '2d10+6', 5900, type: 'dragon', attackName: 'Bite', multi: 3, environments: ['mountain', 'castle', 'cave'], color: Color(0xFFB3202A), abilities: ['breath:fire:16d6:DEX:17', 'frighten:16', 'legendary:2', 'legres:1']),
  MonsterDef('lich_apprentice', 'Lich Apprentice', 4, 55, 13, 6, '3d8', 1100, type: 'undead', attackName: 'Necrotic Ray', environments: ['tower', 'crypt'], color: Color(0xFF3A2A5A), abilities: ['ranged', 'spellcaster', 'frighten:13', 'legendary:1']),
  // Expanded bestiary
  MonsterDef('giant_rat', 'Giant Rat', 0.125, 7, 12, 4, '1d4+2', 25, attackName: 'Bite', environments: ['sewer', 'dungeon', 'town'], dexMod: 2, color: Color(0xFF6E5A48), abilities: ['pack']),
  MonsterDef('goblin_archer', 'Goblin Archer', 0.25, 7, 13, 4, '1d6+2', 50, type: 'humanoid', attackName: 'Shortbow', environments: ['forest', 'cave', 'ruins'], dexMod: 2, color: Color(0xFF6E8A3A), abilities: ['ranged']),
  MonsterDef('bandit_captain', 'Bandit Captain', 2, 65, 15, 5, '1d8+3', 450, type: 'humanoid', attackName: 'Scimitar', multi: 2, environments: ['road', 'forest', 'coast'], dexMod: 3, color: Color(0xFF7A5A3A), abilities: ['heal:2d6']),
  MonsterDef('thug', 'Thug', 0.5, 32, 11, 4, '1d6+2', 100, type: 'humanoid', attackName: 'Mace', multi: 2, environments: ['town', 'sewer', 'road'], color: Color(0xFF5A4A3A), abilities: ['pack']),
  MonsterDef('scout', 'Scout', 0.5, 16, 13, 4, '1d8+2', 100, type: 'humanoid', attackName: 'Longbow', multi: 2, environments: ['forest', 'plains', 'mountain'], dexMod: 2, color: Color(0xFF4E6A42), abilities: ['ranged']),
  MonsterDef('cult_fanatic', 'Cult Fanatic', 2, 33, 13, 4, '2d8', 450, type: 'humanoid', attackName: 'Inflict Wounds', multi: 2, environments: ['temple', 'crypt', 'dungeon'], color: Color(0xFF7A1E24), abilities: ['ranged', 'spellcaster']),
  MonsterDef('worg', 'Worg', 0.5, 26, 13, 5, '2d6+3', 100, attackName: 'Bite', environments: ['forest', 'mountain'], dexMod: 1, color: Color(0xFF4A4038), abilities: ['pack']),
  MonsterDef('brown_bear', 'Brown Bear', 1, 34, 11, 6, '2d6+4', 200, attackName: 'Claws', multi: 2, environments: ['forest', 'mountain', 'tundra'], color: Color(0xFF6B4A2E)),
  MonsterDef('giant_crab', 'Giant Crab', 0.125, 13, 15, 3, '1d6+1', 25, attackName: 'Claw', environments: ['coast', 'swamp'], color: Color(0xFFB0462C)),
  MonsterDef('sahuagin', 'Sahuagin', 0.5, 22, 12, 3, '1d6+1', 100, type: 'humanoid', attackName: 'Spear', multi: 2, environments: ['coast', 'swamp'], color: Color(0xFF3F7A6A), abilities: ['pack']),
  MonsterDef('specter', 'Specter', 1, 22, 12, 4, '3d6', 200, type: 'undead', attackName: 'Life Drain', environments: ['crypt', 'ruins', 'castle'], dexMod: 2, color: Color(0xFF6A6A8A), abilities: ['resist']),
  MonsterDef('will_o_wisp', "Will-o'-Wisp", 2, 22, 19, 4, '2d8', 450, type: 'undead', attackName: 'Shock', environments: ['swamp', 'forest'], dexMod: 9, color: Color(0xFF8AB0FF), abilities: ['ranged', 'resist']),
  MonsterDef('imp', 'Imp', 1, 10, 13, 5, '1d4+3', 200, type: 'fiend', attackName: 'Sting', environments: ['temple', 'tower', 'town'], dexMod: 3, color: Color(0xFFB0302A), abilities: ['poison:11', 'resist']),
  MonsterDef('quasit', 'Quasit', 1, 7, 13, 4, '1d4+3', 200, type: 'fiend', attackName: 'Claws', environments: ['crypt', 'dungeon'], dexMod: 3, color: Color(0xFF4E6A42), abilities: ['poison:10', 'frighten:10']),
  MonsterDef('hell_hound', 'Hell Hound', 3, 45, 15, 5, '1d8+3', 700, type: 'fiend', attackName: 'Bite', environments: ['mountain', 'temple', 'castle'], dexMod: 1, color: Color(0xFF7A1E14), abilities: ['breath:fire:6d6:DEX:12', 'pack']),
  MonsterDef('gargoyle', 'Gargoyle', 2, 52, 15, 4, '1d6+2', 450, type: 'elemental', attackName: 'Claws', multi: 2, environments: ['castle', 'ruins', 'tower'], color: Color(0xFF5A5A63), abilities: ['resist']),
  MonsterDef('mummy', 'Mummy', 3, 58, 11, 5, '2d6+3', 700, type: 'undead', attackName: 'Rotting Fist', multi: 2, environments: ['crypt', 'desert', 'temple'], color: Color(0xFF9A8A6A), abilities: ['frighten:11', 'drain:3d6']),
  MonsterDef('phase_spider', 'Phase Spider', 3, 32, 13, 4, '1d10+2', 700, attackName: 'Bite', environments: ['cave', 'forest', 'dungeon'], dexMod: 3, color: Color(0xFF3A3A6A), abilities: ['poison:11']),
  MonsterDef('displacer_beast', 'Displacer Beast', 3, 85, 13, 6, '1d6+4', 700, type: 'monstrosity', attackName: 'Tentacles', multi: 2, environments: ['forest', 'mountain'], dexMod: 2, color: Color(0xFF2A2A40)),
  MonsterDef('manticore', 'Manticore', 3, 68, 14, 5, '1d8+3', 700, type: 'monstrosity', attackName: 'Tail Spikes', multi: 3, environments: ['mountain', 'desert', 'plains'], dexMod: 3, color: Color(0xFF8A5A2E), abilities: ['ranged']),
  MonsterDef('werewolf', 'Werewolf', 3, 58, 12, 4, '2d4+2', 700, type: 'humanoid', attackName: 'Bite', multi: 2, environments: ['forest', 'town'], dexMod: 1, color: Color(0xFF5A4A3A), abilities: ['resist', 'regen:5']),
  MonsterDef('ettin', 'Ettin', 4, 85, 12, 7, '2d8+5', 1100, type: 'giant', attackName: 'Battleaxe', multi: 2, environments: ['mountain', 'cave'], dexMod: -1, color: Color(0xFF6A5A42)),
  MonsterDef('banshee', 'Banshee', 4, 58, 12, 4, '3d6+2', 1100, type: 'undead', attackName: 'Corrupting Touch', environments: ['crypt', 'castle', 'swamp'], dexMod: 2, color: Color(0xFFCFD8E3), abilities: ['frighten:13', 'resist']),
  MonsterDef('flameskull', 'Flameskull', 4, 40, 13, 5, '3d6', 1100, type: 'undead', attackName: 'Fire Ray', multi: 2, environments: ['tower', 'crypt', 'dungeon'], dexMod: 3, color: Color(0xFFE0632B), abilities: ['ranged', 'spellcaster', 'regen:5']),
  MonsterDef('hill_giant', 'Hill Giant', 5, 105, 13, 8, '3d8+5', 1800, type: 'giant', attackName: 'Greatclub', multi: 2, environments: ['mountain', 'plains', 'forest'], dexMod: -1, color: Color(0xFF8A7A52), abilities: ['charge:2d8']),
  MonsterDef('vampire_spawn', 'Vampire Spawn', 5, 82, 15, 6, '2d6+3', 1800, type: 'undead', attackName: 'Bite', multi: 2, environments: ['castle', 'crypt', 'town'], dexMod: 3, color: Color(0xFF6A1E24), abilities: ['drain:2d6', 'regen:10']),
  MonsterDef('shambling_mound', 'Shambling Mound', 5, 136, 15, 7, '2d8+4', 1800, type: 'plant', attackName: 'Slam', multi: 2, environments: ['swamp', 'forest'], dexMod: -1, color: Color(0xFF3E5A3C), abilities: ['resist']),
  MonsterDef('young_green_dragon', 'Young Green Dragon', 8, 136, 18, 7, '2d10+4', 3900, type: 'dragon', attackName: 'Bite', multi: 3, environments: ['forest', 'swamp'], dexMod: 1, color: Color(0xFF3F7A45), abilities: ['breath:poison:12d6:CON:14', 'frighten:14', 'legendary:2']),
  MonsterDef('vampire', 'Vampire', 13, 144, 16, 9, '1d8+4', 10000, type: 'undead', attackName: 'Bite', multi: 2, environments: ['castle', 'crypt', 'town'], dexMod: 4, color: Color(0xFF5A1A2A), abilities: ['drain:3d6', 'regen:20', 'legendary:3', 'legres:3']),
  MonsterDef('adult_red_dragon', 'Adult Red Dragon', 17, 256, 19, 14, '2d10+8', 18000, type: 'dragon', attackName: 'Bite', multi: 3, environments: ['mountain', 'cave', 'castle'], color: Color(0xFF8E1A1A), abilities: ['breath:fire:18d6:DEX:21', 'frighten:19', 'legendary:3', 'legres:3']),
  MonsterDef('adult_black_dragon', 'Adult Black Dragon', 14, 195, 19, 11, '2d10+6', 11500, type: 'dragon', attackName: 'Bite', multi: 3, environments: ['swamp', 'ruins'], dexMod: 2, color: Color(0xFF1F2A1F), abilities: ['breath:acid:12d8:DEX:18', 'frighten:16', 'legendary:3', 'legres:3']),
  MonsterDef('lich', 'Lich', 21, 135, 17, 12, '3d6+6', 33000, type: 'undead', attackName: 'Paralyzing Touch', environments: ['tower', 'crypt'], dexMod: 3, color: Color(0xFF2A1F4A), abilities: ['ranged', 'spellcaster', 'paralyze:18', 'frighten:18', 'legendary:3', 'legres:3']),
];

MonsterDef? monsterById(String id) {
  for (final m in monsters) {
    if (m.id == id) return m;
  }
  return null;
}

const xpThresholds = [0, 300, 900, 2700, 6500, 14000, 23000, 34000, 48000, 64000, 85000, 100000, 120000, 140000, 165000, 195000, 225000, 265000, 305000, 355000];

int levelForXp(int xp) {
  var lvl = 1;
  for (var i = 0; i < xpThresholds.length; i++) {
    if (xp >= xpThresholds[i]) lvl = i + 1;
  }
  return lvl.clamp(1, 20);
}

int proficiencyForLevel(int level) => 2 + ((level - 1) ~/ 4);

/// Spell slots per level for a full caster at character level (index 0 = 1st level slots).
const _fullCasterSlots = <List<int>>[
  [2],
  [3],
  [4, 2],
  [4, 3],
  [4, 3, 2],
  [4, 3, 3],
  [4, 3, 3, 1],
  [4, 3, 3, 2],
  [4, 3, 3, 3, 1],
  [4, 3, 3, 3, 2],
  [4, 3, 3, 3, 2, 1],
  [4, 3, 3, 3, 2, 1],
  [4, 3, 3, 3, 2, 1, 1],
  [4, 3, 3, 3, 2, 1, 1],
  [4, 3, 3, 3, 2, 1, 1, 1],
  [4, 3, 3, 3, 2, 1, 1, 1],
  [4, 3, 3, 3, 2, 1, 1, 1, 1],
  [4, 3, 3, 3, 3, 1, 1, 1, 1],
  [4, 3, 3, 3, 3, 2, 1, 1, 1],
  [4, 3, 3, 3, 3, 2, 2, 1, 1],
];

List<int> spellSlotsFor(CasterType type, int classLevel) {
  if (classLevel <= 0) return const [];
  switch (type) {
    case CasterType.none:
      return const [];
    case CasterType.full:
      return _fullCasterSlots[(classLevel - 1).clamp(0, _fullCasterSlots.length - 1)];
    case CasterType.half:
      if (classLevel < 2) return const [];
      return _fullCasterSlots[((classLevel / 2).ceil() - 1).clamp(0, _fullCasterSlots.length - 1)];
    case CasterType.pact:
      final slotLevel = ((classLevel + 1) ~/ 2).clamp(1, 5);
      final count = classLevel == 1 ? 1 : (classLevel < 11 ? 2 : 3);
      return List.generate(slotLevel, (i) => i == slotLevel - 1 ? count : 0);
  }
}

const conditions = ['Blinded', 'Charmed', 'Frightened', 'Grappled', 'Incapacitated', 'Invisible', 'Paralyzed', 'Poisoned', 'Prone', 'Restrained', 'Stunned', 'Blessed', 'Hexed', 'Raging', 'Inspired'];

const alignments = ['Lawful Good', 'Neutral Good', 'Chaotic Good', 'Lawful Neutral', 'True Neutral', 'Chaotic Neutral', 'Lawful Evil', 'Neutral Evil', 'Chaotic Evil'];

const conditionInfo = {
  'Blinded': "Can't see. Attacks against it have advantage; its attacks have disadvantage.",
  'Charmed': "Can't attack the charmer, who has advantage on social checks against it.",
  'Frightened': "Disadvantage on checks and attacks while the source of fear is in sight.",
  'Grappled': "Speed becomes 0.",
  'Incapacitated': "Can't take actions or reactions.",
  'Invisible': "Can't be seen. Its attacks have advantage; attacks against it have disadvantage.",
  'Paralyzed': "Can't move or act. Attacks against it have advantage and hits from close range are critical.",
  'Poisoned': "Disadvantage on attack rolls and ability checks.",
  'Prone': "Attacks against it from close range have advantage.",
  'Restrained': "Speed 0. Attacks against it have advantage; its attacks have disadvantage.",
  'Stunned': "Can't act or move and automatically fails STR and DEX saves.",
  'Blessed': "Adds 1d4 to attack rolls and saving throws.",
  'Hexed': "Your hits against the cursed target deal an extra 1d6 necrotic damage.",
  'Hunter': "Hunter's Mark: your hits deal an extra 1d6 damage.",
  'Raging': "+2 melee damage and half damage from physical attacks.",
  'Inspired': "Can add a Bardic Inspiration die to one roll.",
  'Shielded': "+5 AC until the start of your next turn.",
  'Hidden': "Your next attack has advantage.",
  'Dodging': "Attacks against you have disadvantage until your next turn.",
};

String conditionText(String c) => conditionInfo[c] ?? '';
