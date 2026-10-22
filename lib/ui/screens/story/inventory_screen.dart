import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'story_extras.dart';
import '../../../data/inventory_rules.dart';
import '../../../data/srd.dart';
import '../../../game/adventure_controller.dart';
import '../../../game/dice.dart';
import '../../../game/story_host.dart';
import '../../../game/tale_controller.dart';
import '../../../models/character.dart';
import '../../../models/world.dart';
import '../../../services/achievements.dart';
import '../../../services/ai/story_ai.dart';
import '../../../services/audio/audio_service.dart';
import '../../../services/image_service.dart';
import '../../../services/narrator.dart';
import '../../../services/settings.dart';
import '../../../theme/ui.dart';
import '../../widgets/error_card.dart';
import '../../widgets/image_viewer.dart';
import '../../widgets/media_view.dart' show mediaActions;
import '../../widgets/media_import.dart';
import '../../widgets/portrait.dart';

/// One thing carried, from either kind of story.
class StoryItem {
  StoryItem({required this.name, this.qty = 1, this.dnd, this.owner});
  final String name;
  final int qty;

  /// The D&D item, with rules (absent in text adventures).
  final InventoryItem? dnd;

  /// Who carries it in a D&D party.
  final Character? owner;

  ItemDef? get def => dnd?.def;
  String get key => name.toLowerCase();
}

/// Opens the inventory: everything you carry, what it does, what's written in it.
Future<void> openInventory(BuildContext context, StoryHost host) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => InventoryScreen(host: host)));

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key, required this.host});
  final StoryHost host;

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

const _filters = [('all', 'All'), ('equipped', 'Equipped'), ('weapons', 'Weapons'), ('armor', 'Armor'), ('use', 'Consumables'), ('read', 'Readable'), ('magic', 'Magic'), ('other', 'Other')];

class _InventoryScreenState extends State<InventoryScreen> {
  String _filter = 'all';
  String _q = '';
  int _member = 0;

  StoryHost get host => widget.host;
  AdventureController? get dnd => host is AdventureController ? host as AdventureController : null;
  TaleController? get tale => host is TaleController ? host as TaleController : null;

  List<Character> get party => dnd?.adventure.party ?? const [];
  Character? get carrier => party.isEmpty ? null : party[_member.clamp(0, party.length - 1)];

  List<StoryItem> _items() {
    final c = carrier;
    if (c != null) return [for (final i in c.inventory) StoryItem(name: i.name, qty: i.qty, dnd: i, owner: c)];
    final t = tale;
    if (t == null) return const [];
    final counts = <String, int>{};
    for (final i in t.tale.inventory) {
      counts[i] = (counts[i] ?? 0) + 1;
    }
    return [for (final e in counts.entries) StoryItem(name: e.key, qty: e.value)];
  }

  bool _matches(StoryItem i) {
    if (_q.isNotEmpty && !'${i.name} ${host.world.itemNotes[i.key] ?? ''}'.toLowerCase().contains(_q)) return false;
    final t = i.def?.type;
    return switch (_filter) {
      'equipped' => i.dnd?.equipped ?? false,
      'weapons' => t == ItemType.weapon,
      'armor' => t == ItemType.armor || t == ItemType.shield,
      'use' => t == ItemType.potion || t == ItemType.food || t == ItemType.scroll || RegExp(r'potion|food|ration|medkit|stim|bandage|elixir|drink', caseSensitive: false).hasMatch(i.name),
      'read' => isReadableItem(i.name) || host.world.writings.containsKey(i.key),
      'magic' => i.def?.isMagic ?? false,
      'other' => t == null || t == ItemType.gear || t == ItemType.treasure || t == ItemType.wondrous,
      _ => true,
    };
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: host,
      builder: (context, _) {
        final items = _items();
        final shown = items.where(_matches).toList();
        final readable = items.where((i) => isReadableItem(i.name) || host.world.writings.containsKey(i.key)).length;
        final c = carrier;
        final value = items.fold<int>(0, (n, i) => n + (i.def?.value ?? 0) * i.qty);
        final usedFilters = _filters.where((f) => f.$1 == 'all' || items.any((i) {
              final old = _filter;
              _filter = f.$1;
              final ok = _matches(i);
              _filter = old;
              return ok;
            })).toList();
        return Scaffold(
          appBar: AppBar(
            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Inventory', style: T.h3()),
              Text(host.storyTitle, style: T.caption(), overflow: TextOverflow.ellipsis),
            ]),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _create(context),
            icon: const Icon(Icons.add),
            label: const Text('Create item'),
          ),
          body: ContentWidth(
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 96), children: [
              if (party.length > 1) ...[
                SizedBox(
                  height: 76,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    for (final (i, m) in party.indexed)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: GestureDetector(
                          onTap: () => setState(() => _member = i),
                          child: Column(children: [
                            Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: i == _member ? AppColors.accent : Colors.transparent, width: 2)),
                              child: CharacterPortrait(character: m, size: 44),
                            ),
                            const SizedBox(height: 4),
                            Text(m.name.split(' ').first, style: T.caption(color: i == _member ? AppColors.text : AppColors.textMuted)),
                          ]),
                        ),
                      ),
                  ]),
                ),
                const SizedBox(height: 8),
              ],
              Row(children: [
                Expanded(child: StatTile(label: 'Items', value: '${items.fold<int>(0, (n, i) => n + i.qty)}')),
                const SizedBox(width: 8),
                if (c != null) ...[
                  Expanded(child: StatTile(label: 'Weight', value: '${c.carriedWeight.toStringAsFixed(0)}/${c.carryCapacity.toStringAsFixed(0)} lb')),
                  const SizedBox(width: 8),
                  Expanded(child: StatTile(label: 'Worth', value: '$value gp')),
                ] else ...[
                  Expanded(child: StatTile(label: 'Kinds', value: '${items.length}')),
                  const SizedBox(width: 8),
                  Expanded(child: StatTile(label: 'Readable', value: '$readable')),
                ],
              ]),
              if (c != null) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: Bar(value: c.carriedWeight.round(), max: c.carryCapacity.round().clamp(1, 1 << 20), color: c.encumbrance > 0 ? AppColors.warning : AppColors.accent)),
                  const SizedBox(width: 10),
                  Text('${c.encumbranceLabel} · ${c.gold} gp${c.silver > 0 ? ' ${c.silver} sp' : ''}${c.copper > 0 ? ' ${c.copper} cp' : ''}', style: T.caption()),
                ]),
              ],
              const SizedBox(height: 12),
              TextField(style: T.body(), decoration: const InputDecoration(hintText: 'Search your things', prefixIcon: Icon(Icons.search, size: 18)), onChanged: (v) => setState(() => _q = v.toLowerCase())),
              const SizedBox(height: 8),
              SizedBox(
                height: 38,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  for (final (id, label) in usedFilters) Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: Text(label), selected: _filter == id, onSelected: (_) => setState(() => _filter = id))),
                ]),
              ),
              const SizedBox(height: 10),
              if (items.isEmpty) const EmptyState(icon: Icons.backpack_outlined, title: 'Empty pockets', message: 'Things you find, buy or make land here. Try "Create item" to add one.'),
              if (items.isNotEmpty && shown.isEmpty) EmptyState(icon: Icons.search_off, title: 'Nothing here', message: 'No ${_filters.firstWhere((f) => f.$1 == _filter).$2.toLowerCase()} items.'),
              LayoutBuilder(builder: (context, box) {
                final cols = box.maxWidth >= 640 ? 4 : (box.maxWidth >= 420 ? 3 : 2);
                final w = (box.maxWidth - (cols - 1) * 10) / cols;
                return Wrap(spacing: 10, runSpacing: 10, children: [
                  for (final i in shown) SizedBox(width: w, child: _ItemTile(host: host, item: i, onTap: () => showItemSheet(context, host, i))),
                ]);
              }),
            ]),
          ),
        );
      },
    );
  }

  Future<void> _create(BuildContext context) async {
    final made = await showCreateItemSheet(context, host, owner: carrier);
    if (made != null && context.mounted) showItemSheet(context, host, made);
  }
}

IconData itemIcon(String name, ItemDef? def) {
  switch (def?.type) {
    case ItemType.weapon:
      return Icons.hardware_outlined;
    case ItemType.armor:
      return Icons.checkroom_outlined;
    case ItemType.shield:
      return Icons.shield_outlined;
    case ItemType.potion:
      return Icons.science_outlined;
    case ItemType.food:
      return Icons.lunch_dining_outlined;
    case ItemType.scroll:
      return Icons.description_outlined;
    case ItemType.treasure:
      return Icons.diamond_outlined;
    case ItemType.wondrous:
      return Icons.auto_awesome_outlined;
    default:
      break;
  }
  final n = name.toLowerCase();
  if (isReadableItem(n)) return n.contains('map') ? Icons.map_outlined : Icons.menu_book_outlined;
  if (RegExp(r'key|card|pass').hasMatch(n)) return Icons.key_outlined;
  if (RegExp(r'gun|pistol|rifle|knife|blade|sword|axe').hasMatch(n)) return Icons.hardware_outlined;
  if (RegExp(r'phone|radio|device|chip|drive|tablet|scanner').hasMatch(n)) return Icons.memory_outlined;
  if (RegExp(r'flower|herb|plant|seed').hasMatch(n)) return Icons.local_florist_outlined;
  if (RegExp(r'ring|necklace|amulet|gem|coin|gold').hasMatch(n)) return Icons.diamond_outlined;
  if (RegExp(r'food|bread|water|ration|apple|drink|bottle').hasMatch(n)) return Icons.lunch_dining_outlined;
  return Icons.inventory_2_outlined;
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.host, required this.item, required this.onTap});
  final StoryHost host;
  final StoryItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final images = context.watch<ImageService>();
    final path = host.world.itemImages[item.key];
    final d = item.def;
    final magic = d?.isMagic ?? false;
    final icon = Container(color: AppColors.surface2, alignment: Alignment.center, child: Icon(itemIcon(item.name, d), size: 34, color: magic ? AppColors.accent : AppColors.textMuted));
    final readable = host.world.writings.containsKey(item.key) || isReadableItem(item.name);
    return AppCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      borderColor: magic ? AppColors.accent.withValues(alpha: 0.5) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
          child: AspectRatio(
            aspectRatio: 1.25,
            child: Stack(fit: StackFit.expand, children: [
              path == null ? icon : GeneratedImage(path: path, fallback: icon, service: images, cacheWidth: 360),
              if (item.qty > 1) Positioned(top: 6, right: 6, child: _Badge('×${item.qty}')),
              if (item.dnd?.equipped ?? false) const Positioned(top: 6, left: 6, child: _Badge('Equipped')),
              if (readable) const Positioned(bottom: 6, right: 6, child: Icon(Icons.chrome_reader_mode_outlined, size: 16, color: Colors.white70)),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: T.small(color: AppColors.text)),
            const SizedBox(height: 2),
            Text(_subtitle(), maxLines: 1, overflow: TextOverflow.ellipsis, style: T.caption()),
          ]),
        ),
      ]),
    );
  }

  String _subtitle() {
    final d = item.def;
    if (d == null) return host.world.itemNotes[item.key]?.split(RegExp(r'(?<=[.!?])\s')).first ?? 'Item';
    return [
      if (d.isMagic) d.rarity,
      if (d.damage != null) d.damage!,
      if (d.ac != null) 'AC ${d.type == ItemType.shield ? '+' : ''}${d.ac}',
      if (d.heal != null) 'Heals ${d.heal}',
      '${d.value} gp',
    ].join(' · ');
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: T.caption(color: Colors.white).copyWith(fontSize: 10)),
      );
}

// ------------------------------------------------------------------ details

/// Everything about one item, and what you can do with it.
Future<void> showItemSheet(BuildContext context, StoryHost host, StoryItem item) => showAppSheet(context, builder: (ctx) => _ItemSheet(host: host, item: item, outer: context));

class _ItemSheet extends StatefulWidget {
  const _ItemSheet({required this.host, required this.item, required this.outer});
  final StoryHost host;
  final StoryItem item;
  final BuildContext outer;

  @override
  State<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<_ItemSheet> {
  bool _painting = false;

  StoryHost get host => widget.host;
  StoryItem get item => widget.item;

  Future<void> _paint() async {
    final images = context.read<ImageService>();
    final key = 'item_${host.storyId}_${item.key.hashCode & 0x7fffffff}';
    setState(() => _painting = true);
    images.resume();
    final desc = host.world.itemNotes[item.key] ?? item.def?.description ?? '';
    final path = await images.generate(
      key,
      'A single item, shown alone and centered on a simple dark backdrop, like a game inventory icon painted in detail: ${item.name}. $desc ${host.worldStyle}',
      usageTarget: host.usageTotals,
      style: host.artStyle,
      category: 'items',
    );
    if (!mounted) return;
    setState(() => _painting = false);
    if (path == null) {
      final err = images.errors[key];
      if (err != null) showIssueSheet(context, err, label: 'Item picture');
      return;
    }
    host.world.itemImages[item.key] = path;
    host.world.addMedia(MediaItem(path: path, kind: 'item', caption: item.name, turn: host.turns, cost: images.costs[path] ?? 0));
    host.save();
    host.refresh();
  }

  void _remove({String? note}) {
    final d = item.dnd;
    if (d != null) {
      d.qty--;
      if (d.qty <= 0) item.owner?.inventory.remove(d);
    } else if (host is TaleController) {
      (host as TaleController).tale.inventory.remove(item.name);
    }
    if (note != null) host.note(note);
    host.save();
    host.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final images = context.watch<ImageService>();
    final settings = context.watch<SettingsController>();
    final d = item.def;
    final w = host.world;
    final path = w.itemImages[item.key];
    final note = w.itemNotes[item.key] ?? '';
    final writing = w.writings[item.key];
    final readable = writing != null || isReadableItem(item.name);
    final dnd = host is AdventureController ? host as AdventureController : null;
    final equipable = const [ItemType.weapon, ItemType.armor, ItemType.shield].contains(d?.type);
    final icon = Container(color: AppColors.surface2, alignment: Alignment.center, child: Icon(itemIcon(item.name, d), size: 64, color: AppColors.textMuted));
    final lines = <(String, String)>[
      if (d != null) ...[
        ('Type', '${d.type.name[0].toUpperCase()}${d.type.name.substring(1)}${d.isMagic ? ' · ${d.rarity}' : ''}'),
        if (d.damage != null) ('Damage', '${d.damage} ${d.damageType ?? ''}${d.bonus > 0 ? ' · +${d.bonus}' : ''}'),
        if (d.ac != null) ('Armor class', d.type == ItemType.shield ? '+${d.ac}' : '${d.ac}${d.dexCap != null ? ' + DEX (max ${d.dexCap})' : ''}'),
        if (d.heal != null) ('Heals', d.heal!),
        if ((d.effect ?? '').isNotEmpty) ('Effect', d.effect!),
        if (d.attune) ('Attunement', item.dnd!.attuned ? 'Attuned' : 'Required'),
        ('Weight', '${(d.weight * item.qty).toStringAsFixed(d.weight * item.qty < 1 ? 1 : 0)} lb'),
        ('Value', '${d.value} gp${item.qty > 1 ? ' each' : ''}'),
      ],
      ('Quantity', '${item.qty}'),
      if (item.owner != null) ('Carried by', item.owner!.name),
    ];
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.86,
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 28), children: [
        Center(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              GestureDetector(
                onTap: path == null ? null : () => openImageViewer(context, title: item.name, builder: (_) => GeneratedImage(path: path, fallback: icon, service: images, fit: BoxFit.contain), actions: mediaActions(context, path, name: item.name)),
                child: ClipRRect(borderRadius: BorderRadius.circular(20), child: SizedBox(width: 170, height: 170, child: path == null ? icon : GeneratedImage(path: path, fallback: icon, service: images))),
              ),
              if (settings.canPaint)
                Positioned(
                  right: -6,
                  bottom: -6,
                  child: CircleIconButton(
                    size: 32,
                    icon: Icons.auto_awesome_outlined,
                    tooltip: path == null ? 'Generate item image with AI' : 'Regenerate item image with AI',
                    busy: _painting,
                    onPressed: _painting ? null : _paint,
                  ),
                ),
            ],
          ),
        ),
        Wrap(alignment: WrapAlignment.center, children: [
          TextButton.icon(
            onPressed: () async {
              final picked = await chooseImages(context, title: 'A picture for ${item.name}');
              if (picked.isEmpty) return;
              host.world.itemImages[item.key] = picked.first.path;
              host.world.addMedia(MediaItem(path: picked.first.path, kind: 'item', caption: item.name, turn: host.turns));
              host.save();
              host.refresh();
              if (mounted) setState(() {});
            },
            icon: const Icon(Icons.photo_library_outlined, size: 16),
            label: Text('Use my picture', style: T.small(color: AppColors.text)),
          ),
        ]),
        const SizedBox(height: 4),
        Text(item.name, textAlign: TextAlign.center, style: T.h2()),
        if (note.isNotEmpty || (d?.description ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(note.isNotEmpty ? note : d!.description, textAlign: TextAlign.center, style: T.body(color: AppColors.textMuted)),
        ],
        const SizedBox(height: 14),
        if (readable)
          AppButton(
            label: writing == null ? 'Read it' : 'Read "${writing.title}"',
            icon: Icons.chrome_reader_mode_outlined,
            onPressed: () => openReader(context, host, item.name),
          ),
        if (readable) const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
          if (equipable && dnd != null)
            OutlinedButton.icon(
              onPressed: () {
                final i = item.dnd!;
                if (!i.equipped) {
                  for (final o in item.owner!.inventory) {
                    if (o.def?.type == i.def!.type) o.equipped = false;
                  }
                }
                i.equipped = !i.equipped;
                host.note('${item.owner!.name} ${i.equipped ? 'equipped' : 'put away'} ${i.name}.');
                host.save();
                host.refresh();
                setState(() {});
              },
              icon: Icon(item.dnd!.equipped ? Icons.remove_circle_outline : Icons.back_hand_outlined, size: 18),
              label: Text(item.dnd!.equipped ? 'Unequip' : 'Equip'),
            ),
          if (d?.type == ItemType.potion && dnd != null && !dnd.inCombat)
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                dnd.usePotionOutOfCombat(item.dnd!, item.owner ?? dnd.hero);
              },
              icon: const Icon(Icons.local_drink_outlined, size: 18),
              label: const Text('Drink'),
            ),
          if (d?.type == ItemType.food && dnd != null)
            OutlinedButton.icon(
              onPressed: () {
                host.world.vitals.apply({'fullness': 35, 'hydration': 10});
                _remove(note: '${item.owner?.name ?? 'The hero'} ate ${item.name}.');
                context.read<AudioService>().play('heal');
                Navigator.pop(context);
                showToast(widget.outer, 'You eat. Fullness ${host.world.vitals.fullness}/100');
              },
              icon: const Icon(Icons.restaurant_outlined, size: 18),
              label: const Text('Eat'),
            ),
          if (host.isAi && !host.busy)
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                Navigator.of(widget.outer).maybePop();
                host.act('I use the ${item.name}.');
              },
              icon: const Icon(Icons.touch_app_outlined, size: 18),
              label: const Text('Use in the story'),
            ),
          if (dnd != null && dnd.adventure.companions.isNotEmpty)
            OutlinedButton.icon(
              onPressed: () => _give(dnd),
              icon: const Icon(Icons.card_giftcard_outlined, size: 18),
              label: const Text('Give'),
            ),
          OutlinedButton.icon(
            onPressed: () async {
              if (!await confirm(context, title: 'Drop ${item.name}?', message: item.qty > 1 ? 'One is dropped; ${item.qty - 1} stay with you.' : 'It is left behind.', action: 'Drop')) return;
              _remove(note: 'The hero dropped ${item.name}.');
              if (context.mounted) Navigator.pop(context);
            },
            icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.danger),
            label: Text('Drop', style: T.small(color: AppColors.danger)),
          ),
        ]),
        const SectionLabel('Details'),
        RowGroup(children: [for (final (k, v) in lines) ListRow(title: k, trailing: SizedBox(width: 150, child: Text(v, textAlign: TextAlign.right, style: T.small(color: AppColors.text))))]),
        const SectionLabel('Your note'),
        AppCard(
          onTap: () async {
            final t = await _editNote(context, note);
            if (t == null) return;
            if (t.trim().isEmpty) {
              w.itemNotes.remove(item.key);
            } else {
              w.itemNotes[item.key] = t.trim();
            }
            host.save();
            host.refresh();
            setState(() {});
          },
          child: Text(note.isEmpty ? 'Tap to describe it in your own words.' : note, style: T.small(color: note.isEmpty ? AppColors.textFaint : AppColors.text)),
        ),
      ]),
    );
  }

  Future<void> _give(AdventureController dnd) async {
    final to = await showAppSheet<Character>(context, builder: (ctx) => ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
          SheetTitle('Give ${item.name} to…'),
          RowGroup(children: [
            for (final c in dnd.adventure.party.where((c) => c != item.owner))
              ListRow(leading: CharacterPortrait(character: c, size: 36), title: c.name, subtitle: 'Level ${c.level} ${c.classSummary}', onTap: () => Navigator.pop(ctx, c)),
          ]),
        ]));
    if (to == null || !mounted) return;
    final i = item.dnd!;
    final from = item.owner!;
    i.qty--;
    if (i.qty <= 0) from.inventory.remove(i);
    final existing = to.inventory.where((x) => x.name == i.name).firstOrNull;
    if (existing != null) {
      existing.qty++;
    } else {
      to.inventory.add(InventoryItem(name: i.name, itemId: i.itemId, qty: 1, description: i.description));
    }
    host.note('${from.name} gave ${i.name} to ${to.name}.');
    host.save();
    host.refresh();
    Navigator.pop(context);
    if (widget.outer.mounted) showToast(widget.outer, '${to.name.split(' ').first} now has the ${i.name}');
  }
}

Future<String?> _editNote(BuildContext context, String initial) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('About this item'),
      content: SizedBox(width: 420, child: TextField(controller: c, autofocus: true, minLines: 2, maxLines: 6, style: T.body())),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Save')),
      ],
    ),
  );
}

// ------------------------------------------------------------- create tool

/// Paints an item in the story's art style and keeps the picture.
Future<String?> paintItem(ImageService images, StoryHost host, String name, String description) async {
  images.resume();
  final key = 'item_${host.storyId}_${name.toLowerCase().hashCode & 0x7fffffff}';
  final path = await images.generate(key, 'A single item, shown alone and centered on a simple dark backdrop, like a game inventory icon painted in detail: $name. $description ${host.worldStyle}', usageTarget: host.usageTotals, style: host.artStyle, category: 'items');
  if (path == null) return null;
  host.world.itemImages[name.toLowerCase()] = path;
  host.world.addMedia(MediaItem(path: path, kind: 'item', caption: name, turn: host.turns, cost: images.costs[path] ?? 0));
  host.save();
  host.refresh();
  return path;
}

const _kinds = ['trinket', 'weapon', 'armor', 'tool', 'food', 'potion', 'clothing', 'jewelry', 'document', 'key', 'tech', 'other'];

/// The item tool: describe something for the AI to make, or fill it in
/// yourself (with your own picture or an AI one). It lands in your inventory.
Future<StoryItem?> showCreateItemSheet(BuildContext context, StoryHost host, {Character? owner}) => showAppSheet<StoryItem>(context, builder: (_) => _CreateItem(host: host, owner: owner));

class _CreateItem extends StatefulWidget {
  const _CreateItem({required this.host, this.owner});
  final StoryHost host;
  final Character? owner;

  @override
  State<_CreateItem> createState() => _CreateItemState();
}

class _CreateItemState extends State<_CreateItem> {
  final _idea = TextEditingController();
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _text = TextEditingController();
  late bool _ai = context.read<SettingsController>().useAiText;
  bool _busy = false;
  late bool _paint = context.read<SettingsController>().useAiImages;
  String _kind = 'trinket';
  int _qty = 1;
  String? _picture;
  bool _painting = false;

  /// Paints the item now, so the picture can be checked before creating it.
  Future<void> _paintNow() async {
    final host = widget.host;
    final what = _ai ? _idea.text.trim() : [_name.text.trim(), _desc.text.trim()].where((s) => s.isNotEmpty).join('. ');
    if (what.isEmpty) {
      showToast(context, _ai ? 'Describe it first' : 'Give it a name first', icon: Icons.edit_outlined);
      return;
    }
    final images = context.read<ImageService>()..resume();
    setState(() => _painting = true);
    final path = await images.generate('item_${host.storyId}_${DateTime.now().millisecondsSinceEpoch}', 'A single item, shown alone and centered on a simple dark backdrop, like a game inventory icon painted in detail: $what. ${host.worldStyle}', usageTarget: host.usageTotals, style: host.artStyle, category: 'items');
    if (!mounted) return;
    setState(() {
      _painting = false;
      if (path != null) _picture = path;
    });
    if (path == null) showToast(context, images.errors.values.lastOrNull ?? 'The picture could not be painted', icon: Icons.error_outline);
  }

  @override
  void dispose() {
    _idea.dispose();
    _name.dispose();
    _desc.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final picked = await chooseImages(context, title: 'A picture for this item');
    if (picked.isNotEmpty && mounted) setState(() => _picture = picked.first.path);
  }

  Future<void> _make() async {
    if (_busy) return;
    final host = widget.host;
    final settings = context.read<SettingsController>();
    var name = '', description = '', text = '';
    if (_ai) {
      final idea = _idea.text.trim();
      if (idea.isEmpty) return;
      setState(() => _busy = true);
      name = idea[0].toUpperCase() + idea.substring(1);
      try {
        final r = await StoryAi(settings).createItem(host, idea);
        if ((r.value['name'] ?? '').isNotEmpty) name = r.value['name']!;
        description = r.value['description'] ?? '';
        text = r.value['text'] ?? '';
      } catch (e) {
        if (mounted) showToast(context, 'The AI couldn\'t describe it, so it was added as written.', icon: Icons.info_outline);
      }
    } else {
      name = _name.text.trim();
      if (name.isEmpty) {
        showToast(context, 'Give it a name', icon: Icons.edit_outlined);
        return;
      }
      description = _desc.text.trim();
      text = _text.text.trim();
    }
    if (!mounted) return;
    final key = name.toLowerCase();
    final w = host.world;
    if (description.isNotEmpty) w.itemNotes[key] = description;
    if (text.isNotEmpty) w.writings[key] = ItemWriting(title: name, kind: writingKind(name), text: text);
    if (_picture != null) {
      w.itemImages[key] = _picture!;
      w.addMedia(MediaItem(path: _picture!, kind: 'item', caption: name, turn: host.turns));
    }
    final qty = _ai ? 1 : _qty;
    StoryItem made;
    if (host is AdventureController) {
      final c = widget.owner ?? host.hero;
      final existing = c.inventory.where((i) => i.name.toLowerCase() == key).firstOrNull;
      final InventoryItem it;
      if (existing != null) {
        existing.qty += qty;
        it = existing;
      } else {
        it = InventoryItem(name: name, qty: qty, description: description);
        c.inventory.add(it);
      }
      made = StoryItem(name: name, qty: it.qty, dnd: it, owner: c);
    } else {
      final t = (host as TaleController).tale;
      for (var i = 0; i < qty; i++) {
        t.inventory.add(name);
      }
      made = StoryItem(name: name, qty: qty);
    }
    host.note('The player now has ${qty > 1 ? '$qty × ' : 'a new item: '}$name.${description.isEmpty ? '' : ' $description'}${_ai ? '' : ' (${_kind == 'other' ? 'an item' : 'a $_kind'})'} Treat it as something they carry from now on.');
    context.read<Achievements>().add(Stat.crafted);
    context.read<AudioService>().play('coin');
    host.save();
    host.refresh();
    // Painted in the background; the picture appears when it's ready.
    if (_picture == null && _paint && settings.canPaint) unawaited(paintItem(context.read<ImageService>(), host, name, description));
    Navigator.pop(context, made);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsController>();
    final images = context.read<ImageService>();
    final preview = _picture == null
        ? Container(color: AppColors.surface2, alignment: Alignment.center, child: Icon(Icons.add_photo_alternate_outlined, color: AppColors.textMuted, size: 28))
        : GeneratedImage(path: _picture, fallback: const SizedBox(), service: images);
    final picture = Row(children: [
      GestureDetector(onTap: _pick, child: ClipRRect(borderRadius: BorderRadius.circular(14), child: SizedBox(width: 72, height: 72, child: _painting ? const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))) : preview))),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (s.canPaint)
            TextButton.icon(onPressed: _painting ? null : _paintNow, icon: const Icon(Icons.auto_awesome, size: 16), label: Text(_painting ? 'Painting…' : (_picture == null ? 'Paint with AI' : 'Paint again'), style: T.small(color: AppColors.text))),
          TextButton.icon(onPressed: _pick, icon: const Icon(Icons.photo_library_outlined, size: 16), label: Text(_picture == null ? 'Use my picture' : 'Choose another', style: T.small(color: AppColors.text))),
          if (_picture != null)
            TextButton.icon(onPressed: () => setState(() => _picture = null), icon: const Icon(Icons.close, size: 16), label: Text('Remove picture', style: T.small(color: AppColors.textMuted)))
          else if (s.canPaint && !_painting)
            Row(children: [
              Switch(value: _paint, onChanged: (v) => setState(() => _paint = v)),
              Flexible(child: Text('Or paint it when created', style: T.small(color: AppColors.text))),
            ]),
        ]),
      ),
    ]);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SheetTitle('Create an item', subtitle: 'It goes straight into your inventory, and the storyteller knows you have it.'),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: true, label: const Text('Describe it'), icon: const Icon(Icons.auto_awesome, size: 16), enabled: s.useAiText),
              const ButtonSegment(value: false, label: Text('Write it myself'), icon: Icon(Icons.edit_outlined, size: 16)),
            ],
            selected: {_ai},
            onSelectionChanged: (v) => setState(() => _ai = v.first),
          ),
          const SizedBox(height: 14),
          if (_ai) ...[
            TextField(
              controller: _idea,
              autofocus: true,
              style: T.body(),
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(hintText: 'A phone, a red flower, a silver locket…'),
              onSubmitted: (_) => _make(),
            ),
            const SizedBox(height: 8),
            CompactChips(child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (final idea in const ['A lucky coin', 'A worn map', 'A bottle of wine', 'A letter from home', 'A compass'])
                ActionChip(label: Text(idea), onPressed: () => setState(() => _idea.text = idea)),
            ])),
            const SizedBox(height: 6),
            Text('The AI fits it to this world and describes it${s.canPaint ? ', and can paint it' : ''}.', style: T.caption()),
            const SizedBox(height: 10),
            picture,
          ] else ...[
            picture,
            const SizedBox(height: 12),
            TextField(controller: _name, autofocus: true, style: T.body(), decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 10),
            TextField(controller: _desc, style: T.body(), minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Description (optional)')),
            const SizedBox(height: 10),
            CompactChips(child: Wrap(spacing: 6, runSpacing: 6, children: [for (final k in _kinds) ChoiceChip(label: Text(k), selected: _kind == k, onSelected: (_) => setState(() => _kind = k))])),
            if (_kind == 'document') ...[
              const SizedBox(height: 10),
              TextField(controller: _text, style: T.body(), minLines: 3, maxLines: 8, decoration: const InputDecoration(labelText: 'What is written on it')),
            ],
            const SizedBox(height: 8),
            Row(children: [
              Text('Quantity', style: T.body()),
              const Spacer(),
              IconButton(onPressed: _qty > 1 ? () => setState(() => _qty--) : null, icon: const Icon(Icons.remove_circle_outline)),
              Text('$_qty', style: T.h3()),
              IconButton(onPressed: () => setState(() => _qty++), icon: const Icon(Icons.add_circle_outline)),
            ]),
          ],
          const SizedBox(height: 14),
          AppButton(label: _busy ? 'Making it…' : 'Create', icon: _ai ? Icons.auto_awesome : Icons.add, busy: _busy, onPressed: _make),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------ reader

/// Opens a readable item. Its text is written by the AI the first time (when
/// the story didn't already say what it says), then kept.
Future<void> openReader(BuildContext context, StoryHost host, String itemName) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _Reader(host: host, item: itemName)));

class _Reader extends StatefulWidget {
  const _Reader({required this.host, required this.item});
  final StoryHost host;
  final String item;

  @override
  State<_Reader> createState() => _ReaderState();
}

class _ReaderState extends State<_Reader> {
  bool _busy = false;
  String? _error;

  ItemWriting? get writing => widget.host.world.writings[widget.item.toLowerCase()];

  @override
  void initState() {
    super.initState();
    if (writing == null) WidgetsBinding.instance.addPostFrameCallback((_) => _write());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<Achievements>().add(Stat.readings);
    });
  }

  Future<void> _write() async {
    final settings = context.read<SettingsController>();
    if (!settings.useAiText) {
      setState(() => _error = 'The writing is too faded to make out. (Turn on the AI storyteller to read found items.)');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final host = widget.host;
      final r = await StoryAi(settings).readItem(host, widget.item, description: host.world.itemNotes[widget.item.toLowerCase()] ?? '');
      host.world.writings[widget.item.toLowerCase()] = r.value;
      host.note('The player read ${widget.item}. It says: "${r.value.text.length > 600 ? '${r.value.text.substring(0, 600)}…' : r.value.text}"');
      host.save();
      host.refresh();
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = writing;
    const paper = Color(0xFFEFE6D2);
    const ink = Color(0xFF2B2216);
    return Scaffold(
      bottomNavigationBar: const NowReadingBar(),
      backgroundColor: const Color(0xFF14110C),
      appBar: AppBar(
        title: Text(widget.item),
        actions: [
          if (w != null) IconButton(tooltip: 'Listen', icon: const Icon(Icons.volume_up_outlined), onPressed: () => context.read<Narrator>().speakNow('${w.title}. ${w.text}')),
          if (w != null)
            IconButton(
              tooltip: 'Copy',
              icon: const Icon(Icons.copy),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: '${w.title}\n\n${w.text}'));
                showToast(context, 'Copied');
              },
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
            child: Container(
              padding: const EdgeInsets.fromLTRB(26, 30, 26, 34),
              decoration: BoxDecoration(
                color: paper,
                borderRadius: BorderRadius.circular(6),
                boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 30, offset: Offset(0, 12))],
                gradient: const RadialGradient(center: Alignment(0, -0.3), radius: 1.3, colors: [Color(0xFFF5EEDC), Color(0xFFDCCDAB)]),
              ),
              child: _busy
                  ? Column(children: [
                      const SizedBox(height: 40),
                      const CircularProgressIndicator(color: ink, strokeWidth: 2),
                      const SizedBox(height: 16),
                      Text('Unfolding it…', style: TextStyle(fontFamily: 'serif', color: ink.withValues(alpha: 0.7), fontSize: 16)),
                      const SizedBox(height: 40),
                    ])
                  : w == null
                      ? Column(children: [
                          Text(_error ?? '', textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'serif', color: ink, fontSize: 16, height: 1.5)),
                          const SizedBox(height: 16),
                          if (context.read<SettingsController>().useAiText) TextButton(onPressed: _write, child: const Text('Try again', style: TextStyle(color: ink))),
                        ])
                      : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(w.kind.toUpperCase(), style: TextStyle(color: ink.withValues(alpha: 0.5), fontSize: 11, letterSpacing: 3)),
                          const SizedBox(height: 10),
                          Text(w.title, style: const TextStyle(fontFamily: 'serif', color: ink, fontSize: 24, fontWeight: FontWeight.w700, height: 1.2)),
                          Container(margin: const EdgeInsets.symmetric(vertical: 16), height: 1, color: ink.withValues(alpha: 0.25)),
                          SelectableText(w.text, style: TextStyle(fontFamily: 'serif', color: ink, fontSize: 17 * T.readingScale, height: 1.65)),
                          if (w.author.isNotEmpty) ...[
                            const SizedBox(height: 22),
                            Align(alignment: Alignment.centerRight, child: Text('— ${w.author}', style: const TextStyle(fontFamily: 'serif', color: ink, fontSize: 16, fontStyle: FontStyle.italic))),
                          ],
                        ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Rolls a die (kept for parity with the character sheet's quick use).
int rollHeal(String expr) => DiceExpression.parse(expr).roll().total;
