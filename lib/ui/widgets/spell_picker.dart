import 'package:flutter/material.dart';

import '../../data/spellcasting.dart';
import '../../data/srd.dart';
import '../../models/character.dart';
import '../../theme/ui.dart';

/// Lets the player choose cantrips, known spells, a wizard's spellbook, and
/// prepared spells, enforcing the 5e limits for the character's class.
class SpellPicker extends StatefulWidget {
  const SpellPicker({super.key, required this.character, this.onChanged});
  final Character character;
  final VoidCallback? onChanged;

  @override
  State<SpellPicker> createState() => _SpellPickerState();
}

class _SpellPickerState extends State<SpellPicker> {
  int _level = -1; // filter: -1 = all

  Character get c => widget.character;

  void _toggle(List<String> list, String id, bool on, int max, int count) {
    setState(() {
      if (on) {
        if (count >= max) return;
        list.add(id);
      } else {
        list.remove(id);
        if (identical(list, c.spellbook)) c.spells.remove(id);
      }
    });
    widget.onChanged?.call();
  }

  Widget _row(SpellDef s, bool selected, bool canAdd, ValueChanged<bool> onToggle) {
    final enabled = selected || canAdd;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: ListRow(
        title: s.name,
        subtitle: [
          s.level == 0 ? 'Cantrip' : 'Level ${s.level}',
          if (s.concentration) 'concentration',
          if (s.reaction) 'reaction',
          if (s.dice != null) '${s.dice}${s.damageType != null ? ' ${s.damageType}' : ''}',
          s.description,
        ].join(' · '),
        onTap: enabled ? () => onToggle(!selected) : null,
        trailing: Checkbox(value: selected, onChanged: enabled ? (v) => onToggle(v ?? false) : null),
      ),
    );
  }

  Widget _counter(String label, int n, int max) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Row(children: [
          Text(label.toUpperCase(), style: T.overline()),
          const Spacer(),
          Text('$n / $max', style: T.caption(color: n >= max ? AppColors.success : AppColors.warning)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final cls = c.casterClass;
    if (cls == null) return const EmptyState(icon: Icons.auto_fix_off_outlined, title: 'No spellcasting');
    final cantrips = c.cantripPool;
    final cantripMax = c.cantripMax.clamp(0, cantrips.length);
    final wizard = cls == 'wizard';
    final bookMax = spellbookSize(c.casterLevel);
    final bookPool = wizard ? spellsFor('wizard', maxLevel: c.maxSpellLevel).where((s) => s.level > 0).toList() : <SpellDef>[];
    final pool = c.leveledPool;
    final leveledMax = c.leveledMax.clamp(0, pool.isEmpty ? 0 : pool.length);
    final levels = {for (final s in [...pool, ...bookPool]) s.level}.toList()..sort();
    bool show(SpellDef s) => _level < 0 || s.level == _level;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(
        c.prepares
            ? 'As a ${classById(cls).name.toLowerCase()} you prepare spells each day: ${c.mod(c.spellAbility!)} (${c.spellAbility!.short}) + ${cls == 'paladin' ? 'half your level' : 'your level'}. You can change them after a rest.'
            : 'As a ${classById(cls).name.toLowerCase()} you know a fixed list of spells. You learn more as you level up.',
        style: T.small(),
      ),
      if (levels.length > 1) ...[
        const SizedBox(height: 12),
        CompactChips(child: Wrap(spacing: 6, runSpacing: 6, children: [
          ChoiceChip(label: const Text('All'), selected: _level < 0, onSelected: (_) => setState(() => _level = -1)),
          for (final l in levels) ChoiceChip(label: Text('Level $l'), selected: _level == l, onSelected: (_) => setState(() => _level = l)),
        ])),
      ],
      if (cantripMax > 0 && _level <= 0) ...[
        _counter('Cantrips', c.cantripsChosen, cantripMax),
        RowGroup(children: [
          for (final s in cantrips) _row(s, c.spells.contains(s.id), c.cantripsChosen < cantripMax, (on) => _toggle(c.spells, s.id, on, cantripMax, c.cantripsChosen)),
        ]),
      ],
      if (wizard && _level != 0) ...[
        _counter('Spellbook', c.spellbook.length, bookMax),
        RowGroup(children: [
          for (final s in bookPool.where(show)) _row(s, c.spellbook.contains(s.id), c.spellbook.length < bookMax, (on) => _toggle(c.spellbook, s.id, on, bookMax, c.spellbook.length)),
        ]),
      ],
      if (leveledMax > 0 && _level != 0) ...[
        _counter(c.prepares ? 'Prepared' : 'Known spells', c.leveledChosen, leveledMax),
        RowGroup(children: [
          for (final s in pool.where(show)) _row(s, c.spells.contains(s.id), c.leveledChosen < leveledMax, (on) => _toggle(c.spells, s.id, on, leveledMax, c.leveledChosen)),
        ]),
      ] else if (wizard && pool.isEmpty && _level != 0)
        Padding(padding: const EdgeInsets.only(top: 12), child: Text('Add spells to your spellbook, then prepare them here.', style: T.caption())),
    ]);
  }
}

/// Full-screen sheet wrapper around [SpellPicker].
Future<void> showSpellPicker(BuildContext context, Character c, {VoidCallback? onChanged, String? title}) {
  return showAppSheet(context, builder: (ctx) {
    return SizedBox(
      height: MediaQuery.sizeOf(ctx).height * 0.88,
      child: Column(children: [
        SheetTitle(title ?? 'Spells', subtitle: '${c.name} · spells up to level ${c.maxSpellLevel}'),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [SpellPicker(character: c, onChanged: onChanged)]),
        ),
        SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12), child: AppButton(label: 'Done', onPressed: () => Navigator.pop(ctx)))),
      ]),
    );
  });
}
