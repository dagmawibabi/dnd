// Weight, encumbrance, ammunition and coins.
import '../models/character.dart';
import 'srd.dart';

const _weights = <String, double>{
  'dagger': 1, 'shortsword': 2, 'rapier': 2, 'longsword': 3, 'greatsword': 6, 'greataxe': 7, 'handaxe': 2, 'mace': 4, 'warhammer': 2,
  'quarterstaff': 4, 'longbow': 2, 'shortbow': 2, 'light_crossbow': 5, 'heavy_crossbow': 18, 'darts': 0.25, 'battleaxe': 4, 'spear': 3, 'scimitar': 3,
  'leather_armor': 10, 'studded_leather': 13, 'scale_mail': 45, 'chain_mail': 55, 'plate': 65, 'half_plate': 40, 'breastplate': 20, 'shield': 6,
  'rations': 2, 'torch': 1, 'rope': 10, 'thieves_tools': 1, 'holy_symbol': 1, 'arcane_focus': 1, 'spellbook': 3, 'lute': 2, 'herbalism_kit': 3,
  'explorers_pack': 59, 'healers_kit': 3, 'arrows': 0.05, 'bolts': 0.075,
};

extension ItemWeight on ItemDef {
  /// Weight in pounds (per unit).
  double get weight {
    final w = _weights[id];
    if (w != null) return w;
    return switch (type) {
      ItemType.potion => 0.5,
      ItemType.scroll => 0.1,
      ItemType.food => 1,
      ItemType.treasure => 1,
      ItemType.wondrous => 1,
      ItemType.armor => 20,
      ItemType.shield => 6,
      ItemType.weapon => 3,
      ItemType.gear => 1,
    };
  }

  /// Ammunition this ranged weapon consumes, if any.
  String? get ammo => switch (id) {
        'longbow' || 'shortbow' || 'longbow_1' => 'arrows',
        'light_crossbow' || 'heavy_crossbow' => 'bolts',
        _ => null,
      };
}

extension Encumbrance on Character {
  double get carriedWeight {
    var w = 0.0;
    for (final i in inventory) {
      final d = i.def;
      if (d != null && d.id == 'bag_holding') continue;
      w += (d?.weight ?? 1) * i.qty;
    }
    return w + coinWeight;
  }

  /// 50 coins weigh a pound.
  double get coinWeight => (gold + silver + copper + platinum) / 50;

  /// Carrying capacity: STR × 15 pounds.
  double get carryCapacity {
    var cap = score(Ability.str) * 15.0;
    if (raceId == 'halfling' || raceId == 'gnome') cap *= 0.75;
    if (inventory.any((i) => i.itemId == 'bag_holding')) cap += 500;
    return cap;
  }

  /// Standard 5e: carry up to STR × 15 freely. Beyond that you are encumbered
  /// (−10 ft); beyond STR × 20, heavily (−20 ft, disadvantage on physical rolls).
  int get encumbrance {
    final str = score(Ability.str) * ((raceId == 'halfling' || raceId == 'gnome') ? 0.75 : 1.0);
    final w = carriedWeight - (inventory.any((i) => i.itemId == 'bag_holding') ? 500 : 0);
    if (w > str * 20) return 2;
    if (w > str * 15) return 1;
    return 0;
  }

  String get encumbranceLabel => switch (encumbrance) { 2 => 'Heavily encumbered', 1 => 'Encumbered', _ => 'Unencumbered' };

  /// Total wealth in gold pieces.
  double get wealthGp => gold + platinum * 10 + silver / 10 + copper / 100;

  InventoryItem? ammoFor(ItemDef weapon) {
    final a = weapon.ammo;
    if (a == null) return null;
    return inventory.where((i) => i.itemId == a && i.qty > 0).firstOrNull;
  }
}
