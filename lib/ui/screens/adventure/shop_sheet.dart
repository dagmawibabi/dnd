import 'package:flutter/material.dart';

import '../../../data/srd.dart';
import '../../../game/adventure_controller.dart';
import '../../../game/dice.dart';
import '../../../models/character.dart';
import '../../../theme/ui.dart';

/// Deterministic stock for a merchant, scaled to the hero's level.
List<ItemDef> shopStock(String kind, String name, int level, String adventureId) {
  final r = Rng(stableHashOf('$adventureId$name$kind'));
  final mundane = items.where((i) => !i.isMagic).toList();
  List<ItemDef> pick(Iterable<ItemDef> pool, int n) => r.sample(pool.toList(), n);
  final maxRarity = level >= 11 ? 3 : (level >= 5 ? 2 : 1);
  final magicPool = items.where((i) => i.isMagic && rarityOrder.indexOf(i.rarity) <= maxRarity && i.rarity != 'common').toList();
  switch (kind) {
    case 'smith':
      return [
        ...mundane.where((i) => i.type == ItemType.weapon || i.type == ItemType.armor || i.type == ItemType.shield),
        ...pick(magicPool.where((i) => i.type == ItemType.weapon || i.type == ItemType.armor || i.type == ItemType.shield), level >= 5 ? 2 : 1),
      ];
    case 'alchemist':
      return [
        ...items.where((i) => i.type == ItemType.potion && rarityOrder.indexOf(i.rarity) <= maxRarity),
        ...items.where((i) => i.id == 'antitoxin' || i.id == 'alchemist_fire' || i.id == 'healers_kit'),
      ];
    case 'magic':
      return [
        ...items.where((i) => i.type == ItemType.scroll),
        ...pick(magicPool, 6),
      ];
    default:
      return [
        ...mundane.where((i) => i.type == ItemType.gear || i.type == ItemType.food),
        ...items.where((i) => i.id == 'potion_healing'),
        ...pick(mundane.where((i) => i.type == ItemType.weapon), 4),
      ];
  }
}

String shopKindLabel(String kind) => switch (kind) {
      'smith' => 'Blacksmith',
      'alchemist' => 'Alchemist',
      'magic' => 'Arcane emporium',
      _ => 'General store',
    };

void showShopSheet(BuildContext context, AdventureController ctl, {required String kind, required String name}) {
  ctl.audio.play('door');
  showAppSheet(context, builder: (ctx) => _ShopSheet(ctl: ctl, kind: kind, name: name));
}

class _ShopSheet extends StatefulWidget {
  const _ShopSheet({required this.ctl, required this.kind, required this.name});
  final AdventureController ctl;
  final String kind;
  final String name;

  @override
  State<_ShopSheet> createState() => _ShopSheetState();
}

class _ShopSheetState extends State<_ShopSheet> {
  double _priceMod = 1.0;
  bool _haggled = false;
  String? _haggleText;

  late final List<ItemDef> _stock = shopStock(widget.kind, widget.name, widget.ctl.hero.level, widget.ctl.adventure.id);

  int _price(ItemDef d) => (d.value * _priceMod).round().clamp(1, 1 << 30);
  int _sellPrice(InventoryItem i) => ((i.def?.value ?? 1) / 2).floor().clamp(1, 1 << 30);

  void _haggle() {
    final h = widget.ctl.hero;
    final roll = rollD20(modifier: h.skillMod(Skill.persuasion), dc: 14);
    widget.ctl.audio.play(roll.success ? 'success' : 'fail');
    setState(() {
      _haggled = true;
      if (roll.isCrit) {
        _priceMod = 0.7;
        _haggleText = 'Natural 20! The merchant laughs and knocks 30% off everything.';
      } else if (roll.success) {
        _priceMod = 0.85;
        _haggleText = 'Persuasion ${roll.total}: 15% off for a charming customer.';
      } else {
        _priceMod = 1.1;
        _haggleText = 'Persuasion ${roll.total}: the merchant is offended. Prices go up 10%.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ctl = widget.ctl;
    final hero = ctl.hero;
    return DefaultTabController(
      length: 3,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: ListenableBuilder(
          listenable: ctl,
          builder: (context, _) => Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(widget.name, style: T.h2()),
                    Text(shopKindLabel(widget.kind), style: T.small()),
                  ]),
                ),
                Tag('${hero.gold} gp', icon: Icons.paid_outlined, color: AppColors.warning),
              ]),
            ),
            const TabBar(tabAlignment: TabAlignment.center, tabs: [Tab(text: 'Buy'), Tab(text: 'Sell'), Tab(text: 'Downtime')]),
            Expanded(
              child: TabBarView(children: [
                ListView(padding: const EdgeInsets.all(16), children: [
                  AppCard(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      const Icon(Icons.handshake_outlined, size: 18),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_haggleText ?? 'Try your luck haggling (Persuasion DC 14). One attempt per visit.', style: T.small(color: _haggleText == null ? AppColors.textMuted : AppColors.text))),
                      const SizedBox(width: 8),
                      AppButton(label: 'Haggle', kind: ButtonKind.secondary, expand: false, height: 36, onPressed: _haggled ? null : _haggle),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  RowGroup(children: [
                    for (final d in _stock)
                      ListRow(
                        leading: Icon(_icon(d), size: 20, color: d.isMagic ? _rarityColor(d.rarity) : AppColors.textMuted),
                        title: d.name,
                        subtitle: _subtitle(d),
                        trailing: AppButton(
                          label: '${_price(d)} gp',
                          kind: d.isMagic ? ButtonKind.accent : ButtonKind.secondary,
                          expand: false,
                          height: 34,
                          onPressed: hero.gold >= _price(d)
                              ? () {
                                  if (ctl.buyItem(d, _price(d))) showToast(context, 'Bought ${d.name}', icon: Icons.shopping_bag_outlined);
                                }
                              : null,
                        ),
                      ),
                  ]),
                ]),
                ListView(padding: const EdgeInsets.all(16), children: [
                  if (hero.inventory.where((i) => !i.equipped && i.def != null).isEmpty) const EmptyState(icon: Icons.backpack_outlined, title: 'Nothing to sell', message: 'Equipped items and quest items can\'t be sold.'),
                  RowGroup(children: [
                    for (final i in hero.inventory.where((i) => !i.equipped && i.def != null))
                      ListRow(
                        leading: Icon(_icon(i.def!), size: 20),
                        title: i.qty > 1 ? '${i.name} ×${i.qty}' : i.name,
                        subtitle: i.def!.isMagic ? i.def!.rarity : null,
                        trailing: AppButton(label: '+${_sellPrice(i)} gp', kind: ButtonKind.secondary, expand: false, height: 34, onPressed: () => ctl.sellItem(i, _sellPrice(i))),
                      ),
                  ]),
                ]),
                ListView(padding: const EdgeInsets.all(16), children: [
                  Text('Spend some time in town. One activity per turn.', style: T.small()),
                  const SizedBox(height: 12),
                  RowGroup(children: [
                    for (final (id, title, sub, icon) in const [
                      ('work', 'Work', 'Earn coin with your best skill', Icons.work_outline),
                      ('carouse', 'Carouse · 5 gp', 'Buy rounds, hear rumors', Icons.sports_bar_outlined),
                      ('train', 'Train', 'Gain Inspiration', Icons.fitness_center),
                      ('craft', 'Brew a potion · 25 gp', 'Medicine or Arcana DC 13', Icons.science_outlined),
                      ('research', 'Research', 'Look for clues about your quest', Icons.menu_book_outlined),
                    ])
                      ListRow(
                        leading: Icon(icon, size: 20),
                        title: title,
                        subtitle: sub,
                        onTap: ctl.canDowntime
                            ? () {
                                final msg = ctl.downtime(id);
                                showToast(context, msg, icon: Icons.hourglass_bottom);
                              }
                            : null,
                      ),
                  ]),
                  if (!ctl.canDowntime) Padding(padding: const EdgeInsets.only(top: 10), child: Text('You have already spent this stretch of time.', style: T.caption())),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  String _subtitle(ItemDef d) {
    final parts = <String>[
      if (d.isMagic) '${d.rarity}${d.attune ? ' · attunement' : ''}',
      if (d.damage != null) '${d.damage} ${d.damageType ?? ''}'.trim(),
      if (d.ac != null) d.type == ItemType.shield ? '+${d.ac} AC' : 'AC ${d.ac}',
      if (d.heal != null) 'heals ${d.heal}',
      if ((d.effect ?? '').isNotEmpty) d.effect!,
      if (d.description.isNotEmpty && (d.effect ?? '').isEmpty) d.description,
    ];
    return parts.join(' · ');
  }
}

IconData _icon(ItemDef d) => switch (d.type) {
      ItemType.weapon => Icons.gavel,
      ItemType.armor => Icons.shield_outlined,
      ItemType.shield => Icons.shield,
      ItemType.potion => Icons.science_outlined,
      ItemType.scroll => Icons.receipt_long_outlined,
      ItemType.food => Icons.restaurant_outlined,
      ItemType.treasure => Icons.diamond_outlined,
      ItemType.wondrous => Icons.auto_awesome,
      ItemType.gear => Icons.backpack_outlined,
    };

Color _rarityColor(String r) => switch (r) {
      'uncommon' => AppColors.success,
      'rare' => AppColors.info,
      'very rare' => AppColors.accent,
      'legendary' => AppColors.warning,
      _ => AppColors.textMuted,
    };
