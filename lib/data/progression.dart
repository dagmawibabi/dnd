// Subclasses, feats and ability score improvements (5e SRD-inspired).
import 'srd.dart';

class SubclassFeature {
  const SubclassFeature(this.level, this.name, this.text);
  final int level;
  final String name;
  final String text;
}

class SubclassDef {
  const SubclassDef(this.id, this.classId, this.name, this.description, this.features);
  final String id;
  final String classId;
  final String name;
  final String description;
  final List<SubclassFeature> features;
}

/// Class level at which the subclass is chosen.
int subclassLevel(String classId) => switch (classId) {
      'cleric' || 'sorcerer' || 'warlock' => 1,
      'druid' || 'wizard' => 2,
      _ => 3,
    };

const subclasses = <SubclassDef>[
  SubclassDef('berserker', 'barbarian', 'Path of the Berserker', 'Rage becomes a frenzy of blows.', [
    SubclassFeature(3, 'Frenzy', 'While raging you make one extra attack each turn.'),
    SubclassFeature(6, 'Mindless Rage', 'You can\'t be charmed or frightened while raging.'),
  ]),
  SubclassDef('totem_bear', 'barbarian', 'Path of the Bear Totem', 'The spirit of the bear makes you nearly unbreakable.', [
    SubclassFeature(3, 'Bear Spirit', 'While raging you resist damage from spells and monsters alike (half damage from everything).'),
  ]),
  SubclassDef('lore', 'bard', 'College of Lore', 'Collector of secrets, songs and cutting words.', [
    SubclassFeature(3, 'Bonus Proficiencies', 'Gain proficiency in three more skills.'),
    SubclassFeature(3, 'Cutting Words', 'Enemy attacks against you have a 1d6 penalty once per round.'),
  ]),
  SubclassDef('valor', 'bard', 'College of Valor', 'Skalds who sing in the thick of battle.', [
    SubclassFeature(3, 'Combat Inspiration', 'Allies add 1d6 to damage while you are conscious.'),
    SubclassFeature(6, 'Extra Attack', 'Attack twice when you take the Attack action.'),
  ]),
  SubclassDef('life', 'cleric', 'Life Domain', 'Channel the positive energy that sustains all life.', [
    SubclassFeature(1, 'Disciple of Life', 'Healing spells restore an extra 2 + spell level HP.'),
    SubclassFeature(1, 'Heavy Armor', 'Proficiency with heavy armor.'),
  ]),
  SubclassDef('light', 'cleric', 'Light Domain', 'Burn away the darkness with radiant fire.', [
    SubclassFeature(1, 'Radiant Fury', 'Damaging spells deal +WIS radiant damage.'),
    SubclassFeature(1, 'Warding Flare', 'Attacks against you have disadvantage on the first round of combat.'),
  ]),
  SubclassDef('land', 'druid', 'Circle of the Land', 'Mystics who draw power from the land itself.', [
    SubclassFeature(2, 'Natural Recovery', 'Recover a spell slot on a short rest.'),
  ]),
  SubclassDef('moon', 'druid', 'Circle of the Moon', 'Shapeshifters who become fearsome beasts.', [
    SubclassFeature(2, 'Combat Wild Shape', 'Your Wild Shape adds +10 temporary HP and +2 damage for a battle.'),
  ]),
  SubclassDef('champion', 'fighter', 'Champion', 'Raw physical excellence.', [
    SubclassFeature(3, 'Improved Critical', 'Your weapon attacks score a critical hit on a roll of 19 or 20.'),
    SubclassFeature(7, 'Remarkable Athlete', 'Add half proficiency to STR, DEX and CON checks.'),
  ]),
  SubclassDef('battle_master', 'fighter', 'Battle Master', 'A tactician who wields martial maneuvers.', [
    SubclassFeature(3, 'Superiority Dice', 'Four times per rest, add 1d8 to a weapon hit\'s damage.'),
  ]),
  SubclassDef('open_hand', 'monk', 'Way of the Open Hand', 'Masters of unarmed martial arts.', [
    SubclassFeature(3, 'Open Hand Technique', 'Your hits can knock an enemy prone (attacks against it gain advantage).'),
  ]),
  SubclassDef('shadow', 'monk', 'Way of Shadow', 'Ninjas who strike from darkness.', [
    SubclassFeature(3, 'Shadow Arts', 'You can hide as a bonus action like a rogue.'),
  ]),
  SubclassDef('devotion', 'paladin', 'Oath of Devotion', 'The ideals of the shining knight.', [
    SubclassFeature(3, 'Sacred Weapon', 'Add your CHA modifier to weapon attack rolls.'),
  ]),
  SubclassDef('vengeance', 'paladin', 'Oath of Vengeance', 'Relentless punishers of great wickedness.', [
    SubclassFeature(3, 'Vow of Enmity', 'Advantage on attacks against the strongest enemy in a fight.'),
  ]),
  SubclassDef('hunter', 'ranger', 'Hunter', 'Protector against the terrors of the wild.', [
    SubclassFeature(3, 'Colossus Slayer', 'Deal an extra 1d8 damage to a wounded target once per turn.'),
  ]),
  SubclassDef('beast_master', 'ranger', 'Beast Master', 'Bonded to an animal companion.', [
    SubclassFeature(3, 'Ranger\'s Companion', 'A loyal beast adds 1d6 + proficiency damage to your hits.'),
  ]),
  SubclassDef('thief', 'rogue', 'Thief', 'Burglar, treasure hunter, explorer.', [
    SubclassFeature(3, 'Fast Hands', 'Use potions as a bonus action (keeps your turn).'),
    SubclassFeature(3, 'Second-Story Work', '+2 to Athletics and Acrobatics checks.'),
  ]),
  SubclassDef('assassin', 'rogue', 'Assassin', 'A master of deadly first strikes.', [
    SubclassFeature(3, 'Assassinate', 'Advantage on attacks in the first round; hits against surprised foes are critical.'),
  ]),
  SubclassDef('draconic', 'sorcerer', 'Draconic Bloodline', 'Dragon blood burns in your veins.', [
    SubclassFeature(1, 'Draconic Resilience', 'AC 13 + DEX without armor and +1 HP per level.'),
    SubclassFeature(6, 'Elemental Affinity', 'Add CHA to the damage of fire spells.'),
  ]),
  SubclassDef('wild_magic', 'sorcerer', 'Wild Magic', 'Chaos made flesh.', [
    SubclassFeature(1, 'Wild Surge', 'When you cast a leveled spell, roll d20: on a 1 something strange happens (random temp HP, heal or a burst of damage).'),
  ]),
  SubclassDef('fiend', 'warlock', 'The Fiend', 'You made a pact with a lord of the lower planes.', [
    SubclassFeature(1, 'Dark One\'s Blessing', 'Gain CHA + warlock level temporary HP when you drop an enemy to 0.'),
  ]),
  SubclassDef('archfey', 'warlock', 'The Archfey', 'Your patron is a lord of the fey.', [
    SubclassFeature(1, 'Fey Presence', 'Once per rest, frighten an enemy so it has disadvantage on attacks.'),
  ]),
  SubclassDef('evocation', 'wizard', 'School of Evocation', 'Sculpt raw elemental force.', [
    SubclassFeature(2, 'Sculpt Spells', 'Area spells never harm your allies.'),
    SubclassFeature(10, 'Empowered Evocation', 'Add INT to the damage of evocation spells.'),
  ]),
  SubclassDef('abjuration', 'wizard', 'School of Abjuration', 'Masters of wards and protection.', [
    SubclassFeature(2, 'Arcane Ward', 'Begin each battle with a ward of temporary HP equal to 2 × wizard level + INT.'),
  ]),
];

SubclassDef? subclassById(String? id) => id == null ? null : subclasses.where((s) => s.id == id).firstOrNull;
List<SubclassDef> subclassesFor(String classId) => subclasses.where((s) => s.classId == classId).toList();

class FeatDef {
  const FeatDef(this.id, this.name, this.description, {this.ability, this.prereq});
  final String id;
  final String name;
  final String description;

  /// Ability raised by 1 (half-feats).
  final Ability? ability;
  final String? prereq;
}

const feats = <FeatDef>[
  FeatDef('alert', 'Alert', '+5 to initiative. You can\'t be surprised.'),
  FeatDef('tough', 'Tough', 'Your hit point maximum increases by 2 per level.'),
  FeatDef('lucky', 'Lucky', 'Start each long rest with Inspiration (advantage on your next check).'),
  FeatDef('great_weapon_master', 'Great Weapon Master', 'Two-handed weapon hits deal +3 damage.'),
  FeatDef('sharpshooter', 'Sharpshooter', 'Ranged weapon hits deal +3 damage and ignore cover.'),
  FeatDef('war_caster', 'War Caster', 'Advantage on concentration saves.', prereq: 'Spellcasting'),
  FeatDef('resilient_con', 'Resilient (Constitution)', '+1 CON and proficiency in CON saves.', ability: Ability.con),
  FeatDef('mobile', 'Mobile', '+10 speed. Moving out of melee never provokes opportunity attacks.'),
  FeatDef('observant', 'Observant', '+1 WIS and +5 to passive Perception.', ability: Ability.wis),
  FeatDef('sentinel', 'Sentinel', 'Your opportunity attacks are made with advantage.'),
  FeatDef('savage_attacker', 'Savage Attacker', 'Roll melee damage twice and keep the higher result.'),
  FeatDef('skilled', 'Skilled', 'Gain proficiency in three skills of your choice.'),
  FeatDef('durable', 'Durable', '+1 CON. Hit dice heal at least 2 × CON modifier.', ability: Ability.con),
  FeatDef('healer', 'Healer', 'Potions and healing you give restore an extra 4 HP.'),
  FeatDef('magic_initiate', 'Magic Initiate', 'Learn two cantrips from any class.'),
  FeatDef('athlete', 'Athlete', '+1 STR. Standing up and climbing cost you nothing.', ability: Ability.str),
  FeatDef('actor', 'Actor', '+1 CHA and advantage on Deception and Performance to pass as someone else.', ability: Ability.cha),
  FeatDef('dual_wielder', 'Dual Wielder', '+1 AC while wielding a one-handed weapon without a shield.'),
  FeatDef('heavy_armor_master', 'Heavy Armor Master', '+1 STR. Reduce physical damage you take by 3 while wearing heavy armor.', ability: Ability.str),
  FeatDef('shield_master', 'Shield Master', 'Add your shield\'s +2 to DEX saving throws.'),
  FeatDef('keen_mind', 'Keen Mind', '+1 INT. You always know the way out of a dungeon.', ability: Ability.int_),
  FeatDef('elemental_adept', 'Elemental Adept', 'Your damaging spells deal +2 damage.', prereq: 'Spellcasting'),
];

FeatDef? featById(String id) => feats.where((f) => f.id == id).firstOrNull;

/// Minimum scores to multiclass into (or out of) each class. A list means all
/// are required; fighter accepts STR or DEX.
const multiclassRequirements = <String, List<Ability>>{
  'barbarian': [Ability.str],
  'bard': [Ability.cha],
  'cleric': [Ability.wis],
  'druid': [Ability.wis],
  'fighter': [Ability.str],
  'monk': [Ability.dex, Ability.wis],
  'paladin': [Ability.str, Ability.cha],
  'ranger': [Ability.dex, Ability.wis],
  'rogue': [Ability.dex],
  'sorcerer': [Ability.cha],
  'warlock': [Ability.cha],
  'wizard': [Ability.int_],
};

bool meetsMulticlass(String classId, int Function(Ability) score) {
  if (classId == 'fighter') return score(Ability.str) >= 13 || score(Ability.dex) >= 13;
  return (multiclassRequirements[classId] ?? const []).every((a) => score(a) >= 13);
}

String multiclassText(String classId) => classId == 'fighter' ? 'STR or DEX 13' : (multiclassRequirements[classId] ?? const []).map((a) => '${a.short} 13').join(' and ');

/// Character levels that grant an ability score improvement (or a feat).
const asiLevels = [4, 8, 12, 16, 19];
