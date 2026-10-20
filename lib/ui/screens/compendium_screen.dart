import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/ai/model_catalog.dart';
import '../../services/codex_art.dart';
import '../../services/image_service.dart';
import '../../services/settings.dart';
import '../../services/usage.dart' show fmtCost;
import '../widgets/media_view.dart' show openMedia;

import '../../art/render_png.dart';

import '../../art/class_icon.dart';
import '../../art/monster_painter.dart';
import '../../data/srd.dart';
import '../../models/character.dart';
import '../../theme/ui.dart';
import '../widgets/portrait.dart';

const _rules = [
  ('Ability checks', 'Roll a d20 and add the ability modifier (plus proficiency if you are proficient in the skill). Meet or beat the Difficulty Class (DC). Typical DCs: easy 10, medium 13, hard 16, very hard 19.'),
  ('Advantage & disadvantage', 'Roll two d20s and keep the higher (advantage) or lower (disadvantage). If you have both, they cancel out.'),
  ('Attack rolls', 'd20 + attack bonus against the target\'s Armor Class. A natural 20 is a critical hit: roll the damage dice twice. A natural 1 always misses.'),
  ('Saving throws', 'When a spell or hazard targets you, roll a d20 + the relevant ability modifier (plus proficiency if your class grants it) against the DC.'),
  ('Initiative', 'At the start of combat everyone rolls d20 + Dexterity modifier. Turns go from highest to lowest each round.'),
  ('Hit points & dying', 'At 0 HP you fall unconscious and make death saving throws each turn: 10+ succeeds, 9 or lower fails, a natural 20 restores 1 HP. Three failures and you fall.'),
  ('Resting', 'A short rest lets you spend Hit Dice to heal. A long rest restores all HP, spell slots and most daily features.'),
  ('Spellcasting', 'Spell attack = spellcasting modifier + proficiency. Spell save DC = 8 + spellcasting modifier + proficiency. Leveled spells consume a slot; cantrips are free.'),
  ('Proficiency bonus', '+2 at levels 1–4, +3 at 5–8, +4 at 9–12, +5 at 13–16, +6 at 17–20.'),
  ('Multiclassing', 'When you level up you may take a level in a different class. Your features stack; spell slots use the best single progression in this app.'),
];

class CompendiumScreen extends StatefulWidget {
  const CompendiumScreen({super.key, this.embedded = false});
  final bool embedded;

  @override
  State<CompendiumScreen> createState() => _CompendiumScreenState();
}

class _CompendiumScreenState extends State<CompendiumScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 7, vsync: this);
  String _q = '';

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// A list thumbnail: AI art when painted, otherwise the drawn version.
  Widget _thumb(String kind, String id, Widget drawn) {
    final path = context.watch<CodexArt?>()?.pathOf(kind, id);
    if (path == null) return drawn;
    return ClipRRect(borderRadius: BorderRadius.circular(10), child: SizedBox.square(dimension: 40, child: GeneratedImage(path: path, fallback: drawn, service: context.read<ImageService>(), cacheWidth: 120)));
  }

  /// The art at the top of a detail sheet: tap to view full screen, save or share.
  Widget _hero(String kind, String id, String name, Widget drawn, Future<Uint8List?> Function()? render) {
    final path = context.read<CodexArt?>()?.pathOf(kind, id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GestureDetector(
        onTap: () => openMedia(context, path: path, fallback: Center(child: FittedBox(child: drawn)), title: name, subtitle: path == null ? 'Drawn on device' : 'AI art', aspectRatio: 1, render: render),
        child: Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox.square(
              dimension: 160,
              child: path == null
                  ? Container(color: AppColors.surface2, child: Center(child: drawn))
                  : GeneratedImage(path: path, fallback: Center(child: drawn), service: context.read<ImageService>()),
            ),
          ),
        ),
      ),
    );
  }

  Widget _artButton() {
    final art = context.watch<CodexArt?>();
    if (art == null) return const SizedBox.shrink();
    if (art.running) {
      return IconButton(
        tooltip: 'Stop painting',
        onPressed: art.cancel,
        icon: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, value: art.total == 0 ? null : art.done / art.total)),
      );
    }
    return IconButton(tooltip: 'Remake art with AI', icon: const Icon(Icons.auto_awesome_outlined), onPressed: _confirmArt);
  }

  Widget _progress() {
    final art = context.watch<CodexArt>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Row(children: [
        Expanded(child: LinearProgressIndicator(value: art.total == 0 ? null : art.done / art.total, minHeight: 4, borderRadius: BorderRadius.circular(4))),
        const SizedBox(width: 10),
        Text('Painting ${art.done}/${art.total}', style: T.caption()),
        TextButton(onPressed: art.cancel, child: const Text('Stop')),
      ]),
    );
  }

  Future<void> _confirmArt() async {
    final settings = context.read<SettingsController>();
    final art = context.read<CodexArt>();
    if (!settings.useAiImages) {
      showToast(context, 'Turn on AI images in Settings → Images first.', icon: Icons.image_not_supported_outlined);
      return;
    }
    final total = codexSubjects().length;
    final missing = art.missing();
    final price = context.read<ModelCatalog>().byId(settings.imageModel)?.imagePrice;
    String est(int n) => price == null ? '' : ' (about ${fmtCost(price * n)})';
    final choice = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Paint the codex with AI?'),
        content: Text(
          'This creates AI art for races, classes and monsters with ${settings.imageModel.replaceFirst('or:', '')}.\n\n'
          '${missing == 0 ? 'Everything already has art.' : '$missing of $total still use drawn art.'}\n\n'
          'Pictures are made one at a time; you can stop any time.',
          style: T.body(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: T.h3(color: AppColors.textMuted))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Remake all $total${est(total)}')),
          if (missing > 0) FilledButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Paint $missing${est(missing)}')),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    await art.paint(context.read<ImageService>(), missingOnly: !choice);
    if (!mounted) return;
    showToast(context, art.error != null ? 'Stopped: ${art.error}' : 'Codex art ready', icon: art.error != null ? Icons.error_outline : Icons.auto_awesome);
  }

  bool _match(String s) => _q.isEmpty || s.toLowerCase().contains(_q.toLowerCase());

  @override
  Widget build(BuildContext context) {
    final body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (widget.embedded) ContentWidth(child: PageHeader(title: 'Codex', subtitle: 'Rules, spells, gear and monsters', trailing: _artButton())),
      if (context.watch<CodexArt?>()?.running ?? false) ContentWidth(child: _progress()),
      ContentWidth(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(style: T.body(), decoration: const InputDecoration(hintText: 'Search the compendium', prefixIcon: Icon(Icons.search, size: 20)), onChanged: (v) => setState(() => _q = v)),
        ),
      ),
      ContentWidth(
        child: TabBar(controller: _tabs, isScrollable: true, tabs: const [
          Tab(text: 'Races'),
          Tab(text: 'Classes'),
          Tab(text: 'Spells'),
          Tab(text: 'Equipment'),
          Tab(text: 'Monsters'),
          Tab(text: 'Conditions'),
          Tab(text: 'Rules'),
        ]),
      ),
      Expanded(
        child: TabBarView(controller: _tabs, children: [
          _list([
            for (final r in races.where((r) => _match(r.name)))
              ListRow(
                leading: _thumb('race', r.id, PortraitView(spec: PortraitSpec.random(r.id, seed: 1000 + r.id.length * 13), raceId: r.id, size: 40)),
                title: r.name,
                subtitle: '${r.size} · ${r.speed} ft${r.subraces.isEmpty ? '' : ' · ${r.subraces.length} subraces'}',
                onTap: () => _raceSheet(r),
              ),
          ]),
          _list([
            for (final c in classes.where((c) => _match(c.name)))
              ListRow(leading: _thumb('class', c.id, ClassIcon(classId: c.id, size: 40)), title: c.name, subtitle: 'd${c.hitDie} · ${c.primary.full}${c.caster != CasterType.none ? ' · spellcaster' : ''}', onTap: () => _classSheet(c)),
          ]),
          _list([
            for (final lvl in [0, 1, 2, 3])
              if (spells.any((s) => s.level == lvl && _match(s.name))) ...[
                Padding(padding: const EdgeInsets.fromLTRB(4, 12, 4, 6), child: Text(lvl == 0 ? 'CANTRIPS' : 'LEVEL $lvl', style: T.overline())),
                for (final s in spells.where((s) => s.level == lvl && _match(s.name)))
                  ListRow(
                    title: s.name,
                    subtitle: '${s.description}${s.dice != null ? ' · ${s.dice}${s.damageType != null ? ' ${s.damageType}' : ''}' : ''}',
                    trailing: Text(s.classes.map((c) => classById(c).name.substring(0, 3)).join(' '), style: T.caption()),
                    onTap: () => _spellSheet(s),
                  ),
              ],
          ]),
          _list([
            for (final type in ItemType.values)
              if (items.any((i) => i.type == type && _match(i.name))) ...[
                Padding(padding: const EdgeInsets.fromLTRB(4, 12, 4, 6), child: Text(type.name.toUpperCase(), style: T.overline())),
                for (final i in items.where((i) => i.type == type && _match(i.name)))
                  ListRow(
                    title: i.name,
                    subtitle: switch (i.type) {
                      ItemType.weapon => '${i.damage} ${i.damageType}${i.finesse ? ' · finesse' : ''}${i.ranged ? ' · ranged' : ''}${i.twoHanded ? ' · two-handed' : ''}',
                      ItemType.armor => 'AC ${i.ac}${i.dexCap == null ? ' + Dex' : (i.dexCap! > 0 ? ' + Dex (max ${i.dexCap})' : '')}',
                      ItemType.shield => '+${i.ac} AC',
                      ItemType.potion => 'Heals ${i.heal}',
                      ItemType.scroll => i.damage != null ? '${i.damage} ${i.damageType}' : 'Single use',
                      _ => i.description,
                    },
                    trailing: Text('${i.value} gp', style: T.caption()),
                  ),
              ],
          ]),
          _list([
            for (final m in (monsters.where((m) => _match(m.name)).toList()..sort((a, b) => a.cr.compareTo(b.cr))))
              ListRow(
                leading: _thumb('monster', m.id, SizedBox(width: 40, height: 40, child: CustomPaint(painter: MonsterPainter(type: m.type, color: m.color, seed: m.id.hashCode)))),
                title: m.name,
                subtitle: 'CR ${_cr(m.cr)} · ${m.type} · ${m.hp} HP · AC ${m.ac}',
                onTap: () => _monsterSheet(m),
              ),
          ]),
          _list([
            for (final e in conditionInfo.entries.where((e) => _match(e.key))) ListRow(title: e.key, subtitle: e.value),
          ]),
          _list([
            for (final r in _rules.where((r) => _match(r.$1) || _match(r.$2))) ListRow(title: r.$1, subtitle: r.$2),
          ]),
        ]),
      ),
    ]);
    if (widget.embedded) return SafeArea(child: body);
    return Scaffold(appBar: AppBar(title: const Text('Codex'), actions: [_artButton(), const SizedBox(width: 8)]), body: body);
  }

  Widget _list(List<Widget> children) => ContentWidth(
        child: children.isEmpty
            ? const EmptyState(icon: Icons.search_off, title: 'Nothing found')
            : ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
                AppCard(padding: EdgeInsets.zero, child: Column(children: [for (final (i, c) in children.indexed) ...[if (i > 0 && c is ListRow && children[i - 1] is ListRow) const Divider(indent: 16), c]])),
              ]),
      );

  static String _cr(double cr) => cr == 0.125 ? '1/8' : (cr == 0.25 ? '1/4' : (cr == 0.5 ? '1/2' : cr.toStringAsFixed(0)));

  void _sheet(String title, String? subtitle, List<Widget> children) {
    showAppSheet(context, builder: (_) => SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 28),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SheetTitle(title, subtitle: subtitle),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)),
          ]),
        ));
  }

  void _raceSheet(RaceDef r) => _sheet(r.name, '${r.size} · speed ${r.speed} ft${r.darkvision ? ' · darkvision' : ''}', [
        _hero('race', r.id, r.name, PortraitView(spec: PortraitSpec.random(r.id, seed: 1000 + r.id.length * 13), raceId: r.id, size: 120),
            () => portraitPng(PortraitSpec.random(r.id, seed: 1000 + r.id.length * 13), r.id)),
        Text(r.description, style: T.body()),
        const SectionLabel('Traits'),
        for (final t in r.traits) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('• $t', style: T.small(color: AppColors.text))),
        if (r.subraces.isNotEmpty) ...[
          const SectionLabel('Subraces'),
          RowGroup(children: [
            for (final s in r.subraces) ListRow(title: s.name, subtitle: [if (s.bonuses.isNotEmpty) s.bonuses.entries.map((e) => '+${e.value} ${e.key.short}').join(', '), ...s.traits].join(' · ')),
          ]),
        ],
      ]);

  void _classSheet(ClassDef c) => _sheet(c.name, c.epithet, [
        _hero('class', c.id, c.name, ClassIcon(classId: c.id, size: 96), null),
        Text(c.description, style: T.body()),
        const SizedBox(height: 12),
        Wrap(spacing: 6, runSpacing: 6, children: [
          Tag('Hit die d${c.hitDie}'),
          Tag('Primary ${c.primary.full}'),
          Tag('Saves ${c.saves.map((s) => s.short).join(', ')}'),
          Tag('${c.numSkills} skills'),
          if (c.caster != CasterType.none) Tag('${c.caster.name} caster', color: AppColors.accent, filled: true),
        ]),
        const SectionLabel('Features'),
        RowGroup(children: [for (final f in c.features) ListRow(title: 'Level ${f.level} · ${f.name}', subtitle: f.text)]),
        const SectionLabel('Skill choices'),
        Text(c.skillChoices.map((s) => s.label).join(', '), style: T.small()),
        if (c.spellAbility != null) ...[
          const SectionLabel('Spells'),
          Text(spellsFor(c.id).map((s) => s.name).join(', '), style: T.small()),
        ],
        const SectionLabel('Suggested races'),
        Text(c.optimalRaces.map((r) => raceById(r).name).join(', '), style: T.small()),
      ]);

  void _spellSheet(SpellDef s) => _sheet(s.name, s.level == 0 ? 'Cantrip' : 'Level ${s.level} spell', [
        Text(s.description, style: T.body()),
        const SizedBox(height: 14),
        RowGroup(children: [
          ListRow(title: 'Type', trailing: Text(switch (s.kind) { SpellKind.attack => 'Spell attack', SpellKind.save => '${s.save?.full ?? ''} save', SpellKind.heal => 'Healing', SpellKind.buff => 'Buff', SpellKind.utility => 'Utility' }, style: T.small(color: AppColors.text))),
          if (s.dice != null) ListRow(title: s.kind == SpellKind.heal ? 'Healing' : 'Damage', trailing: Text('${s.dice}${s.damageType != null ? ' ${s.damageType}' : ''}', style: T.small(color: AppColors.text))),
          ListRow(title: 'Area', trailing: Text(s.aoe ? 'Up to 3 targets' : 'Single target', style: T.small(color: AppColors.text))),
          ListRow(title: 'Classes', subtitle: s.classes.map((c) => classById(c).name).join(', ')),
        ]),
        if (s.level == 0 && s.scaling) Padding(padding: const EdgeInsets.only(top: 12), child: Text('Cantrip damage increases at levels 5 and 11.', style: T.caption())),
        if (s.level > 0) Padding(padding: const EdgeInsets.only(top: 12), child: Text('Cast with a higher slot to add one more damage die per level.', style: T.caption())),
      ]);

  void _monsterSheet(MonsterDef m) => _sheet(m.name, 'CR ${_cr(m.cr)} ${m.type} · ${m.xp} XP', [
        _hero('monster', m.id, m.name, SizedBox(width: 120, height: 120, child: CustomPaint(painter: MonsterPainter(type: m.type, color: m.color, seed: m.id.hashCode))),
            () => paintPng(const Size.square(1024), (c, s) => MonsterPainter(type: m.type, color: m.color, seed: m.id.hashCode).paint(c, s))),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: StatTile(label: 'Armor class', value: '${m.ac}')),
          const SizedBox(width: 8),
          Expanded(child: StatTile(label: 'Hit points', value: '${m.hp}')),
          const SizedBox(width: 8),
          Expanded(child: StatTile(label: 'Attacks', value: '${m.multi}×')),
        ]),
        const SizedBox(height: 12),
        RowGroup(children: [
          ListRow(title: m.attackName, subtitle: '+${m.attackBonus} to hit · ${m.damage} damage'),
          ListRow(title: 'Dexterity', trailing: Text(m.dexMod >= 0 ? '+${m.dexMod}' : '${m.dexMod}', style: T.small(color: AppColors.text))),
          ListRow(title: 'Found in', subtitle: m.environments.join(', ')),
        ]),
      ]);
}
