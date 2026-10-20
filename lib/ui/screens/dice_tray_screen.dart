import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../game/dice.dart';
import '../../services/settings.dart';
import '../../theme/ui.dart';
import '../widgets/dice.dart';
import 'tables_view.dart';

const _sides = [4, 6, 8, 10, 12, 20];

class DiceTrayScreen extends StatefulWidget {
  const DiceTrayScreen({super.key, this.embedded = false});
  final bool embedded;

  @override
  State<DiceTrayScreen> createState() => _DiceTrayScreenState();
}

class _TrayDie {
  _TrayDie(this.sides);
  final int sides;
  final key = GlobalKey<RollableDieState>();
  int? value;
}

class _DiceTrayScreenState extends State<DiceTrayScreen> {
  final List<_TrayDie> _dice = [_TrayDie(20)];
  int _tab = 0;
  int _mod = 0;
  final List<(String, int)> _history = [];
  final _exprCtrl = TextEditingController();

  @override
  void dispose() {
    _exprCtrl.dispose();
    super.dispose();
  }

  void _rollAll() {
    for (final d in _dice) {
      d.value = null;
    }
    setState(() {});
    for (final (i, d) in _dice.indexed) {
      Future.delayed(Duration(milliseconds: i * 60), () => d.key.currentState?.roll());
    }
  }

  void _onRolled(_TrayDie d, int v) {
    setState(() => d.value = v);
    if (_dice.every((x) => x.value != null)) {
      final total = _dice.fold<int>(0, (a, x) => a + x.value!) + _mod;
      final counts = <int, int>{};
      for (final x in _dice) {
        counts[x.sides] = (counts[x.sides] ?? 0) + 1;
      }
      final expr = counts.entries.map((e) => '${e.value}d${e.key}').join(' + ') + (_mod != 0 ? ' ${_mod > 0 ? '+' : '−'} ${_mod.abs()}' : '');
      setState(() => _history.insert(0, (expr, total)));
    }
  }

  /// Keep only the highest N dice (e.g. 2d20kh1 for advantage).
  int? _keep;

  void _rollExpression() {
    final e = DiceExpression.parse(_exprCtrl.text);
    _keep = e.keepHighest;
    setState(() {
      _dice
        ..clear()
        ..addAll([
          for (final t in e.terms)
            for (var i = 0; i < t.count.clamp(1, 12); i++) _TrayDie(_sides.contains(t.sides) ? t.sides : 20),
        ]);
      _mod = e.modifier;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _rollAll());
  }

  Widget _formulas() {
    final settings = context.watch<SettingsController>();
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        children: [
          for (final (name, expr) in settings.diceFormulas)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onLongPress: () async {
                  if (await confirm(context, title: 'Delete "$name"?', message: expr, action: 'Delete')) {
                    settings.update((s) => s.diceFormulas = s.diceFormulas.where((f) => f.$1 != name).toList());
                  }
                },
                child: ActionChip(
                  label: Text('$name · $expr'),
                  onPressed: () {
                    _exprCtrl.text = expr;
                    _rollExpression();
                  },
                ),
              ),
            ),
          ActionChip(
            avatar: const Icon(Icons.bookmark_add_outlined, size: 16),
            label: const Text('Save formula'),
            onPressed: () async {
              final expr = _exprCtrl.text.trim();
              if (expr.isEmpty || DiceExpression.parse(expr).terms.isEmpty) {
                showToast(context, 'Type a formula like 2d6+3 first.', icon: Icons.info_outline);
                return;
              }
              final ctrl = TextEditingController();
              final name = await showDialog<String>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Name this formula'),
                  content: TextField(controller: ctrl, autofocus: true, style: T.body(), decoration: InputDecoration(hintText: 'e.g. Greatsword', helperText: expr)),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: T.h3(color: AppColors.textMuted))),
                    TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Save')),
                  ],
                ),
              );
              if (name == null || name.isEmpty) return;
              settings.update((s) => s.diceFormulas = [...s.diceFormulas.where((f) => f.$1 != name), (name, expr)]);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final done = _dice.isNotEmpty && _dice.every((d) => d.value != null);
    final values = done ? (_dice.map((d) => d.value!).toList()..sort((a, b) => b.compareTo(a))) : <int>[];
    final total = done ? values.take(_keep ?? values.length).fold<int>(0, (a, v) => a + v) + _mod : null;
    final dieSize = _dice.length <= 2 ? 120.0 : (_dice.length <= 6 ? 84.0 : 64.0);
    final body = ContentWidth(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.embedded) const PageHeader(title: 'Dice'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 0, label: Text('Dice'), icon: Icon(Icons.casino_outlined, size: 16)),
                ButtonSegment(value: 1, label: Text('Tables'), icon: Icon(Icons.table_rows_outlined, size: 16)),
                ButtonSegment(value: 2, label: Text('Oracle'), icon: Icon(Icons.help_outline, size: 16)),
              ],
              selected: {_tab},
              onSelectionChanged: (v) => setState(() => _tab = v.first),
            ),
          ),
          if (_tab == 1) const Expanded(child: RandomTablesView()),
          if (_tab == 2) const Expanded(child: OracleView()),
          if (_tab == 0) ...[
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: AppCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 56,
                        child: Center(
                          child: total == null ? Text(_dice.isEmpty ? 'Add dice below' : 'Tap a die or press Roll', style: T.small()) : Text('$total', style: T.number(44)),
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: SingleChildScrollView(
                            child: Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final d in _dice)
                                  GestureDetector(
                                    onLongPress: () => setState(() => _dice.remove(d)),
                                    child: RollableDie(key: d.key, sides: d.sides, size: dieSize, onRolled: (v) => _onRolled(d, v)),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (_dice.isNotEmpty) Text('Long-press a die to remove it', style: T.caption()),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  for (final s in _sides)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: AppCard(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          radius: 12,
                          onTap: () => setState(() {
                      _keep = null;
                      _dice.add(_TrayDie(s));
                    }),
                          child: Column(
                            children: [
                              SizedBox(
                                width: 26,
                                height: 26,
                                child: CustomPaint(
                                  painter: DieFacePainter(sides: s, value: s),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text('d$s', style: T.caption(color: AppColors.textMuted)),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  CircleIconButton(icon: Icons.remove, size: 36, onPressed: () => setState(() => _mod--)),
                  SizedBox(
                    width: 56,
                    child: Center(child: Text(signed(_mod), style: T.number(16))),
                  ),
                  CircleIconButton(icon: Icons.add, size: 36, onPressed: () => setState(() => _mod++)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _exprCtrl,
                      style: T.body(),
                      decoration: InputDecoration(
                        hintText: '2d6+3',
                        suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward, size: 18), onPressed: _rollExpression),
                      ),
                      onSubmitted: (_) => _rollExpression(),
                    ),
                  ),
                ],
              ),
            ),
            _formulas(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: AppButton(label: 'Clear', kind: ButtonKind.secondary, onPressed: _dice.isEmpty ? null : () => setState(_dice.clear)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: AppButton(label: 'Roll', icon: Icons.casino_outlined, onPressed: _dice.isEmpty ? null : _rollAll),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 84,
              child: _history.isEmpty
                  ? null
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                      children: [
                        for (final (expr, total) in _history.take(20))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                Expanded(child: Text(expr, style: T.small())),
                                Text('$total', style: T.number(14, color: AppColors.textMuted)),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ],
      ),
    );
    if (widget.embedded) return SafeArea(child: body);
    return Scaffold(
      appBar: AppBar(title: const Text('Dice')),
      body: body,
    );
  }
}
