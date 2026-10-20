import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../game/dice.dart';
import '../../services/audio/audio_service.dart';
import '../../services/settings.dart';
import '../../theme/ui.dart';

/// Flat, outlined polyhedral die face.
class DieFacePainter extends CustomPainter {
  DieFacePainter({required this.sides, required this.value, this.rotation = 0, this.tint, this.fill = AppColors.surface2});
  final int sides;
  final int value;
  final double rotation;
  final Color? tint;
  final Color fill;

  Path _shape(Offset c, double r) {
    final n = switch (sides) { 4 => 3, 6 || 8 || 10 => 4, 12 => 5, _ => 6 };
    final p = Path();
    final start = sides == 6 ? -math.pi / 4 : -math.pi / 2;
    for (var i = 0; i < n; i++) {
      final a = start + i / n * math.pi * 2;
      var rad = sides == 6 ? r * 0.9 : r;
      if (sides == 10 && (i == 1 || i == 3)) rad = r * 0.72;
      final pt = c + Offset(math.cos(a), math.sin(a)) * rad;
      i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
    }
    return p..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 * 0.92;
    final stroke = tint ?? AppColors.borderStrong;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(rotation);
    canvas.translate(-c.dx, -c.dy);
    final shape = _shape(c, r);
    canvas.drawPath(shape, Paint()..color = tint == null ? fill : Color.alphaBlend(tint!.withValues(alpha: 0.12), fill));
    final inner = _shape(c, r * 0.56);
    final facet = Paint()
      ..color = AppColors.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawPath(inner, facet);
    final m1 = shape.computeMetrics().first;
    final m2 = inner.computeMetrics().first;
    final verts = switch (sides) { 4 => 3, 6 || 8 || 10 => 4, 12 => 5, _ => 6 };
    for (var i = 0; i < verts; i++) {
      canvas.drawLine(m1.getTangentForOffset(m1.length * i / verts)!.position, m2.getTangentForOffset(m2.length * i / verts)!.position, facet);
    }
    canvas.drawPath(shape, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeJoin = StrokeJoin.round
      ..color = stroke);
    canvas.restore();
    final tp = TextPainter(
      text: TextSpan(text: '$value', style: T.number(r * (value >= 10 ? 0.5 : 0.6), color: tint ?? AppColors.text)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant DieFacePainter old) => true;
}

/// A die you tap or flick to roll.
class RollableDie extends StatefulWidget {
  const RollableDie({super.key, this.sides = 20, this.size = 140, required this.onRolled, this.enabled = true, this.autoRoll = false, this.forced});
  final int sides;
  final double size;
  final void Function(int value) onRolled;
  final bool enabled;
  final bool autoRoll;
  final int? forced;

  @override
  State<RollableDie> createState() => RollableDieState();
}

class RollableDieState extends State<RollableDie> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  late int _shown = widget.sides;
  int? _result;
  double _spin = 0;
  bool _rolling = false;
  final _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _c.addListener(() {
      if (_rng.nextDouble() < (1 - _c.value) * 0.8 + 0.05) _shown = _rng.nextInt(widget.sides) + 1;
      setState(() {});
    });
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) _land();
    });
    if (widget.autoRoll) WidgetsBinding.instance.addPostFrameCallback((_) => roll());
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void roll({double power = 1}) {
    if (_rolling || !widget.enabled) return;
    _rolling = true;
    _result = widget.forced ?? rollDie(widget.sides);
    _spin = (_rng.nextBool() ? 1 : -1) * (3 + power * 3) * math.pi;
    context.read<AudioService>().play('dice');
    if (context.read<SettingsController>().haptics) HapticFeedback.mediumImpact();
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _c.duration = reduced ? const Duration(milliseconds: 120) : Duration(milliseconds: (800 + power * 400).round().clamp(700, 1500));
    _c.forward(from: 0);
  }

  void _land() {
    setState(() {
      _shown = _result!;
      _rolling = false;
    });
    context.read<AudioService>().play('dice_land');
    if (context.read<SettingsController>().haptics) HapticFeedback.heavyImpact();
    widget.onRolled(_result!);
  }

  @override
  Widget build(BuildContext context) {
    final t = Curves.easeOutCubic.transform(_c.value);
    final animating = _c.isAnimating;
    final landed = _result != null && !_rolling;
    Color? tint;
    if (landed && widget.sides == 20 && _result == 20) tint = AppColors.success;
    if (landed && widget.sides == 20 && _result == 1) tint = AppColors.danger;
    return Semantics(
      button: true,
      label: landed ? 'd${widget.sides}, rolled $_shown' : 'd${widget.sides}. Tap to roll',
      child: GestureDetector(
      onTap: () => roll(),
      onPanEnd: (d) => roll(power: (d.velocity.pixelsPerSecond.distance / 1500).clamp(0.3, 1.5)),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Transform.translate(
          offset: Offset(0, animating ? -(math.sin(t * math.pi * 3) * (1 - t)).abs() * 24 : 0),
          child: Transform.scale(
            scale: animating ? 1 + math.sin(t * math.pi) * 0.08 : 1,
            child: CustomPaint(painter: DieFacePainter(sides: widget.sides, value: _shown, rotation: animating ? _spin * (1 - t) : 0, tint: tint)),
          ),
        ),
      ),
    ),
    );
  }
}

/// Dialog that asks the player to roll for a check.
class DiceCheckSheet extends StatefulWidget {
  const DiceCheckSheet({super.key, required this.label, required this.modifier, this.dc, this.mode = RollMode.normal, this.subtitle = '', this.sides = 20, this.attack = false});
  final bool attack;
  final String label;
  final String subtitle;
  final int modifier;
  final int? dc;
  final RollMode mode;
  final int sides;

  static Future<int?> show(BuildContext context, {required String label, required int modifier, int? dc, RollMode mode = RollMode.normal, String subtitle = '', int sides = 20, bool attack = false}) {
    return showGeneralDialog<int>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, a, b) => DiceCheckSheet(label: label, modifier: modifier, dc: dc, mode: mode, subtitle: subtitle, sides: sides, attack: attack),
      transitionBuilder: (ctx, a, b, child) => FadeTransition(
        opacity: a,
        child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOut)), child: child),
      ),
    );
  }

  @override
  State<DiceCheckSheet> createState() => _DiceCheckSheetState();
}

class _DiceCheckSheetState extends State<DiceCheckSheet> {
  final List<int> _rolls = [];
  int? _final;
  bool get _double => widget.mode != RollMode.normal;

  void _onRoll(int v) {
    _rolls.add(v);
    if (_double && _rolls.length < 2) {
      setState(() {});
      return;
    }
    final nat = !_double ? v : (widget.mode == RollMode.advantage ? math.max(_rolls[0], _rolls[1]) : math.min(_rolls[0], _rolls[1]));
    setState(() => _final = nat);
    final ok = widget.dc == null || nat == 20 || (nat != 1 && nat + widget.modifier >= widget.dc!);
    final audio = context.read<AudioService>();
    Future.delayed(const Duration(milliseconds: 200), () => audio.play(nat == 20 ? 'crit' : nat == 1 ? 'fumble' : ok ? 'success' : 'fail'));
  }

  @override
  Widget build(BuildContext context) {
    final total = _final == null ? null : _final! + widget.modifier;
    final ok = _final == null ? null : (widget.dc == null || _final == 20 || (_final != 1 && total! >= widget.dc!));
    final outcome = _final == 20 ? 'Natural 20' : (_final == 1 ? 'Natural 1' : (ok == true ? (widget.attack ? 'Hit' : 'Success') : (widget.attack ? 'Miss' : 'Failure')));
    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(24), border: Border.all(color: AppColors.border)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(widget.label, style: T.h2(), textAlign: TextAlign.center),
                if (widget.subtitle.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(widget.subtitle, style: T.small(), textAlign: TextAlign.center)),
                const SizedBox(height: 14),
                Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
                  Tag('Modifier ${signed(widget.modifier)}'),
                  if (widget.dc != null) Tag('${widget.attack ? 'AC' : 'DC'} ${widget.dc}'),
                  if (_double) Tag(widget.mode == RollMode.advantage ? 'Advantage' : 'Disadvantage', color: widget.mode == RollMode.advantage ? AppColors.success : AppColors.danger, filled: true),
                ]),
                const SizedBox(height: 18),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  RollableDie(sides: widget.sides, size: _double ? 110 : 140, onRolled: _onRoll, enabled: _rolls.isEmpty),
                  if (_double) ...[const SizedBox(width: 12), RollableDie(sides: widget.sides, size: 110, onRolled: _onRoll, enabled: _rolls.length == 1)],
                ]),
                const SizedBox(height: 16),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _final == null
                      ? Padding(
                          key: const ValueKey('hint'),
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(_double && _rolls.length == 1 ? 'Roll the second die' : 'Tap or flick the die', style: T.small()),
                        )
                      : Column(key: const ValueKey('r'), children: [
                          Text('$_final ${widget.modifier >= 0 ? '+' : '−'} ${widget.modifier.abs()} = $total', style: T.number(26)),
                          const SizedBox(height: 4),
                          Text(outcome, style: T.h3(color: ok == true ? AppColors.success : AppColors.danger)),
                          const SizedBox(height: 18),
                          AppButton(label: 'Continue', onPressed: () => Navigator.of(context).pop(_final)),
                        ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
