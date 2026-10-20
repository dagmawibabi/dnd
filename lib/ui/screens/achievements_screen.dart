import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/achievements.dart';
import '../../theme/ui.dart';

class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ach = context.watch<Achievements>();
    final total = achievementDefs.length;
    final sorted = [...achievementDefs]..sort((a, b) {
        final ua = ach.isUnlocked(a.id), ub = ach.isUnlocked(b.id);
        if (ua != ub) return ua ? -1 : 1;
        return (ach.stat(b.stat) / b.goal).compareTo(ach.stat(a.stat) / a.goal);
      });
    final keyStats = [Stat.turns, Stat.kills, Stat.crits, Stat.checksPassed, Stat.gold, Stat.spells, Stat.completed, Stat.maxLevel, Stat.oracle, Stat.nat1s, Stat.npcs, Stat.deaths];
    return Scaffold(
      appBar: AppBar(title: const Text('Achievements')),
      body: ContentWidth(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
          AppCard(
            child: Row(children: [
              SizedBox(
                width: 56,
                height: 56,
                child: Stack(fit: StackFit.expand, children: [
                  CircularProgressIndicator(value: total == 0 ? 0 : ach.unlockedCount / total, strokeWidth: 5, backgroundColor: AppColors.surface3, color: AppColors.accent),
                  Center(child: Text('${ach.unlockedCount}', style: T.number(18))),
                ]),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${ach.unlockedCount} of $total unlocked', style: T.h3()),
                  const SizedBox(height: 2),
                  Text('Every roll, fight and story counts toward something.', style: T.small()),
                ]),
              ),
            ]),
          ),
          const SectionLabel('Lifetime stats'),
          GridView.count(
            crossAxisCount: MediaQuery.sizeOf(context).width > 700 ? 4 : 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.35,
            children: [
              for (final k in keyStats) StatTile(label: statLabels[k] ?? k, value: _fmt(ach.stat(k))),
            ],
          ),
          const SectionLabel('Achievements'),
          RowGroup(children: [
            for (final a in sorted) _AchievementRow(def: a, ach: ach),
          ]),
          const SizedBox(height: 24),
          AppButton(
            label: 'Reset progress',
            kind: ButtonKind.ghost,
            onPressed: () async {
              if (await confirm(context, title: 'Reset achievements?', message: 'All stats and unlocks will be cleared.', action: 'Reset')) ach.reset();
            },
          ),
        ]),
      ),
    );
  }

  static String _fmt(int v) => v >= 10000 ? '${(v / 1000).toStringAsFixed(1)}K' : '$v';
}

class _AchievementRow extends StatelessWidget {
  const _AchievementRow({required this.def, required this.ach});
  final AchievementDef def;
  final Achievements ach;

  @override
  Widget build(BuildContext context) {
    final unlocked = ach.isUnlocked(def.id);
    final hidden = def.secret && !unlocked;
    final progress = (ach.stat(def.stat) / def.goal).clamp(0.0, 1.0);
    return Semantics(
      label: '${hidden ? 'Secret achievement' : def.name}, ${unlocked ? 'unlocked' : '${(progress * 100).round()} percent'}',
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: unlocked ? AppColors.accentSoft : AppColors.surface2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: unlocked ? AppColors.accent : AppColors.border),
            ),
            child: Icon(hidden ? Icons.lock_outline : def.icon, size: 20, color: unlocked ? AppColors.accent : AppColors.textFaint),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(hidden ? 'Secret' : def.name, style: T.h3(color: unlocked ? AppColors.text : AppColors.textMuted)),
              const SizedBox(height: 2),
              Text(hidden ? 'Keep playing to discover this one.' : def.description, style: T.small()),
              if (!unlocked && !hidden) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: Bar(value: ach.stat(def.stat).clamp(0, def.goal), max: def.goal, color: AppColors.accent)),
                  const SizedBox(width: 8),
                  Text('${ach.stat(def.stat).clamp(0, def.goal)}/${def.goal}', style: T.caption()),
                ]),
              ],
            ]),
          ),
          if (unlocked) const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.check_circle, size: 18, color: AppColors.success)),
        ]),
      ),
    );
  }
}

/// Shows an unlock toast through the app-wide messenger.
void showAchievementToast(ScaffoldMessengerState? messenger, AchievementDef a) {
  if (messenger == null) return;
  messenger.showSnackBar(SnackBar(
    duration: const Duration(seconds: 4),
    content: Row(children: [
      Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.accent)),
        child: Icon(a.icon, size: 18, color: AppColors.accent),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('ACHIEVEMENT UNLOCKED', style: T.overline(color: AppColors.accent)),
          Text(a.name, style: T.h3()),
        ]),
      ),
    ]),
  ));
}
