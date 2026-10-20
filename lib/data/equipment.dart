// Starting equipment options (5e-inspired).
import 'srd.dart';

/// Average starting wealth when a class buys its own gear instead of a kit.
const classStartingGold = {
  'barbarian': 50,
  'bard': 125,
  'cleric': 125,
  'druid': 50,
  'fighter': 125,
  'monk': 13,
  'paladin': 125,
  'ranger': 125,
  'rogue': 100,
  'sorcerer': 75,
  'warlock': 100,
  'wizard': 100,
};

const _simpleWeapons = ['dagger', 'quarterstaff', 'mace', 'handaxe', 'spear', 'light_crossbow', 'darts', 'shortbow'];
const _martialClasses = {'barbarian', 'fighter', 'paladin', 'ranger'};

/// Weapons a class can start with (its proficiencies, simplified).
List<ItemDef> startingWeapons(String classId) {
  final all = items.where((i) => i.type == ItemType.weapon && !i.isMagic).toList();
  if (_martialClasses.contains(classId)) return all;
  final extra = switch (classId) {
    'rogue' || 'bard' => ['rapier', 'shortsword', 'longsword', 'shortbow'],
    'monk' => ['shortsword'],
    'druid' => ['scimitar'],
    _ => <String>[],
  };
  final ids = {..._simpleWeapons, ...extra};
  return all.where((i) => ids.contains(i.id)).toList();
}

/// Mundane gear a new hero can buy with starting gold.
List<ItemDef> starterShop() => items
    .where((i) => !i.isMagic && i.rarity == 'common' && const [ItemType.weapon, ItemType.armor, ItemType.shield, ItemType.gear, ItemType.food].contains(i.type) || i.id == 'potion_healing')
    .toList()
  ..sort((a, b) => a.type.index != b.type.index ? a.type.index.compareTo(b.type.index) : a.value.compareTo(b.value));
