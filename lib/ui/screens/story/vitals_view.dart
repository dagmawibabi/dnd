import 'package:flutter/material.dart';

import '../../../models/world.dart';
import '../../../theme/ui.dart';

const _icons = {
  'energy': Icons.bedtime_outlined,
  'fullness': Icons.restaurant_outlined,
  'hydration': Icons.water_drop_outlined,
  'wellness': Icons.health_and_safety_outlined,
  'stamina': Icons.directions_run,
  'morale': Icons.wb_sunny_outlined,
  'calm': Icons.self_improvement,
};

const _help = {
  'energy': 'How rested you are. Long days, fights and sleepless nights wear it down; a night\'s sleep restores it.',
  'fullness': 'Hunger. It drops a little every turn. Eat a meal or rations to recover.',
  'hydration': 'Thirst. It drops faster than hunger, especially in heat and on the move.',
  'wellness': 'Sickness, poison and infection. Low wellness makes everything harder until treated.',
  'stamina': 'Breath for exertion: sprinting, climbing, fighting. It recovers quickly with a moment\'s rest.',
  'morale': 'Your spirits. Losses and grim news lower it; victories, kindness and hope raise it.',
  'calm': 'Composure. Terror and stress shake it; safety and rest restore it.',
};

Color vitalColor(int v) => v < 25 ? AppColors.danger : (v < 50 ? AppColors.warning : AppColors.success);

/// The protagonist's condition beyond health: one bar each, with plain words.
class VitalsPanel extends StatelessWidget {
  const VitalsPanel({super.key, required this.vitals});
  final Vitals vitals;

  @override
  Widget build(BuildContext context) {
    final worst = [...Vitals.keys]..sort((a, b) => vitals.get(a).compareTo(vitals.get(b)));
    final low = worst.where((k) => vitals.get(k) < 45).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(
        low.isEmpty ? 'You feel ready for anything.' : 'You feel ${low.take(3).map((k) => Vitals.describe(k, vitals.get(k)).toLowerCase()).join(', ')}.',
        style: T.small(color: low.isEmpty ? AppColors.success : AppColors.warning),
      ),
      const SizedBox(height: 10),
      LayoutBuilder(builder: (context, box) {
        final cols = box.maxWidth > 520 ? 2 : 1;
        final w = (box.maxWidth - (cols - 1) * 10) / cols;
        return Wrap(spacing: 10, runSpacing: 8, children: [
          for (final k in Vitals.keys)
            SizedBox(
              width: w,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => showToast(context, _help[k]!, icon: _icons[k]!),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Icon(_icons[k], size: 16, color: vitalColor(vitals.get(k))),
                      const SizedBox(width: 8),
                      Text(Vitals.labelOf(k), style: T.small(color: AppColors.text)),
                      const Spacer(),
                      Text(Vitals.describe(k, vitals.get(k)), style: T.caption(color: vitalColor(vitals.get(k)))),
                      const SizedBox(width: 6),
                      Text('${vitals.get(k)}', style: T.caption()),
                    ]),
                    const SizedBox(height: 7),
                    Bar(value: vitals.get(k), max: 100, color: vitalColor(vitals.get(k))),
                  ]),
                ),
              ),
            ),
        ]);
      }),
      const SizedBox(height: 6),
      Text('The storyteller sees these and lets them shape the story. Tap any for what affects it.', style: T.caption()),
    ]);
  }
}
