import 'package:flutter/material.dart';

import '../data/srd.dart';
import '../theme/app_theme.dart';

IconData classIconData(String classId) => switch (classId) {
      'barbarian' => Icons.local_fire_department_outlined,
      'bard' => Icons.music_note_outlined,
      'cleric' => Icons.wb_sunny_outlined,
      'druid' => Icons.eco_outlined,
      'fighter' => Icons.shield_outlined,
      'monk' => Icons.self_improvement,
      'paladin' => Icons.verified_user_outlined,
      'ranger' => Icons.my_location,
      'rogue' => Icons.visibility_off_outlined,
      'sorcerer' => Icons.bolt_outlined,
      'warlock' => Icons.remove_red_eye_outlined,
      'wizard' => Icons.auto_fix_high_outlined,
      _ => Icons.person_outline,
    };

/// Minimal class badge: tinted rounded square with an outline icon.
class ClassIcon extends StatelessWidget {
  const ClassIcon({super.key, required this.classId, this.size = 40});
  final String classId;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = classById(classId).color;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(size * 0.3)),
      child: Icon(classIconData(classId), size: size * 0.52, color: Color.lerp(color, Colors.white, 0.35)),
    );
  }
}

IconData abilityIconData(Ability a) => switch (a) {
      Ability.str => Icons.fitness_center,
      Ability.dex => Icons.air,
      Ability.con => Icons.favorite_border,
      Ability.int_ => Icons.menu_book_outlined,
      Ability.wis => Icons.visibility_outlined,
      Ability.cha => Icons.chat_bubble_outline,
    };

class AbilityIcon extends StatelessWidget {
  const AbilityIcon(this.ability, {super.key, this.size = 32});
  final Ability ability;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(size * 0.3), border: Border.all(color: AppColors.border)),
      child: Icon(abilityIconData(ability), size: size * 0.5, color: AppColors.textMuted),
    );
  }
}
