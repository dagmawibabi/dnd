import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/tables.dart';
import '../../game/oracle.dart';
import '../../theme/ui.dart';

IconData _tableIcon(String name) => switch (name) {
      'local_bar' => Icons.local_bar_outlined,
      'hearing' => Icons.hearing_outlined,
      'cloud' => Icons.cloud_outlined,
      'face' => Icons.face_outlined,
      'badge' => Icons.badge_outlined,
      'diamond' => Icons.diamond_outlined,
      'alt_route' => Icons.alt_route,
      'flag' => Icons.flag_outlined,
      'castle' => Icons.castle_outlined,
      'location_city' => Icons.location_city_outlined,
      'inventory_2' => Icons.inventory_2_outlined,
      'psychology' => Icons.psychology_outlined,
      _ => Icons.casino_outlined,
    };

/// Random tables for improvising: names, rumors, weather, loot…
class RandomTablesView extends StatefulWidget {
  const RandomTablesView({super.key});

  @override
  State<RandomTablesView> createState() => _RandomTablesViewState();
}

class _RandomTablesViewState extends State<RandomTablesView> {
  final Map<String, String> _results = {};

  void _roll(RandomTable t) {
    HapticFeedback.selectionClick();
    setState(() => _results[t.id] = t.roll());
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
      Text('Tap a table to roll on it. Long-press a result to copy it.', style: T.small()),
      const SizedBox(height: 12),
      for (final t in randomTables)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AppCard(
            onTap: () => _roll(t),
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(_tableIcon(t.icon), size: 18, color: AppColors.textMuted),
                const SizedBox(width: 10),
                Expanded(child: Text(t.name, style: T.h3())),
                Text('d${t.entries.length}', style: T.caption()),
                const SizedBox(width: 8),
                const Icon(Icons.casino_outlined, size: 16, color: AppColors.textFaint),
              ]),
              if (_results[t.id] == null) Padding(padding: const EdgeInsets.only(top: 4, left: 28), child: Text(t.description, style: T.small())),
              if (_results[t.id] != null)
                FadeIn(
                  key: ValueKey(_results[t.id]),
                  child: GestureDetector(
                    onLongPress: () {
                      Clipboard.setData(ClipboardData(text: _results[t.id]!));
                      showToast(context, 'Copied');
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8, left: 28),
                      child: Text(_results[t.id]!, style: T.body()),
                    ),
                  ),
                ),
            ]),
          ),
        ),
    ]);
  }
}

/// A standalone oracle for pen-and-paper solo play outside the app's stories.
class OracleView extends StatefulWidget {
  const OracleView({super.key});

  @override
  State<OracleView> createState() => _OracleViewState();
}

class _OracleViewState extends State<OracleView> {
  final _oracle = Oracle();
  final _q = TextEditingController();
  Likelihood _l = Likelihood.even;
  int _chaos = 5;
  final List<(String, OracleResult)> _history = [];

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  void _ask() {
    final r = _oracle.ask(_l, _chaos);
    HapticFeedback.mediumImpact();
    setState(() => _history.insert(0, (_q.text.trim(), r)));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
      Text('Ask yes/no questions when you play solo. Likelihood and chaos shape the answer; doubles can trigger random events.', style: T.small()),
      const SizedBox(height: 14),
      TextField(controller: _q, style: T.body(), decoration: const InputDecoration(hintText: 'Does the bridge hold?')),
      const SizedBox(height: 12),
      CompactChips(child: Wrap(spacing: 6, runSpacing: 6, children: [
        for (final l in Likelihood.values) ChoiceChip(label: Text(l.label), selected: _l == l, onSelected: (_) => setState(() => _l = l)),
      ])),
      const SizedBox(height: 12),
      Row(children: [
        Text('CHAOS $_chaos', style: T.overline()),
        Expanded(child: Slider(value: _chaos.toDouble(), min: 1, max: 9, divisions: 8, onChanged: (v) => setState(() => _chaos = v.round()))),
        Text('${Oracle.chanceFor(_l, _chaos)}% yes', style: T.caption(color: AppColors.textMuted)),
      ]),
      const SizedBox(height: 4),
      Row(children: [
        Expanded(child: AppButton(label: 'Ask the oracle', icon: Icons.help_outline, onPressed: _ask)),
        const SizedBox(width: 8),
        AppButton(
          label: 'Meaning',
          kind: ButtonKind.secondary,
          expand: false,
          onPressed: () {
            final m = _oracle.meaning();
            showToast(context, 'Meaning: $m', icon: Icons.auto_awesome);
          },
        ),
      ]),
      const SizedBox(height: 16),
      for (final (q, r) in _history.take(30))
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AppCard(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(q.isEmpty ? 'A question to fate' : q, style: T.small())),
                Text('d100 ${r.roll}', style: T.caption()),
              ]),
              const SizedBox(height: 4),
              Text(r.answer, style: T.h2(color: r.yes ? AppColors.success : AppColors.danger)),
              if (r.event != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Random event: ${r.event} · ${r.meaning}', style: T.small(color: AppColors.warning))),
            ]),
          ),
        ),
    ]);
  }
}
