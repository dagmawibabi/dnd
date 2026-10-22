import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/achievements.dart';
import '../../theme/ui.dart';
import '../widgets/share_cards.dart';

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
      appBar: AppBar(title: const Text('Achievements'), actions: [
        IconButton(tooltip: 'Share your totals', icon: const Icon(Icons.ios_share), onPressed: () => showLifetimeShareCard(context)),
      ]),
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
          if (ach.storyAwards.isNotEmpty) ...[
            SectionLabel('Awarded by the storyteller · ${ach.storyAwards.length}'),
            RowGroup(children: [
              for (final a in ach.storyAwards.reversed)
                ListRow(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: const Color(0x22E0B354), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE0B354))),
                    child: Icon(a.iconData, size: 20, color: const Color(0xFFE0B354)),
                  ),
                  title: a.title,
                  subtitle: '${a.description}${a.story.isEmpty ? '' : '\n${a.story}'}',
                  onTap: () => showStoryAwardSheet(context, a),
                ),
            ]),
          ],
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
      button: true,
      child: InkWell(
        onTap: () => showAchievementSheet(context, def),
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
      ),
    );
  }
}

String _date(DateTime d) => '${d.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]} ${d.year}';

/// An achievement up close: what it takes, how far along you are, when you
/// earned it, how rare it is among your unlocks, and a card to share.
Future<void> showAchievementSheet(BuildContext context, AchievementDef def) => showAppSheet(context, builder: (ctx) {
      final ach = ctx.watch<Achievements>();
      final unlocked = ach.isUnlocked(def.id);
      final hidden = def.secret && !unlocked;
      final value = ach.stat(def.stat);
      final at = ach.unlockedAt(def.id);
      final same = achievementDefs.where((a) => a.stat == def.stat).toList()..sort((a, b) => a.goal.compareTo(b.goal));
      final color = unlocked ? const Color(0xFFE0B354) : AppColors.textFaint;
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [color.withValues(alpha: 0.35), color.withValues(alpha: 0.05)]),
                border: Border.all(color: color, width: 3),
                boxShadow: unlocked ? [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 36, spreadRadius: 2)] : null,
              ),
              child: Icon(hidden ? Icons.lock_outline : def.icon, size: 52, color: color),
            ),
          ),
          const SizedBox(height: 14),
          Text(unlocked ? 'UNLOCKED' : (hidden ? 'SECRET' : 'IN PROGRESS'), textAlign: TextAlign.center, style: T.overline(color: color).copyWith(letterSpacing: 3)),
          const SizedBox(height: 6),
          Text(hidden ? 'Secret achievement' : def.name, textAlign: TextAlign.center, style: T.h1()),
          const SizedBox(height: 6),
          Text(hidden ? 'Keep playing to discover this one.' : def.description, textAlign: TextAlign.center, style: T.body(color: AppColors.textMuted)),
          const SizedBox(height: 18),
          if (!hidden) ...[
            Row(children: [
              Expanded(child: StatTile(label: statLabels[def.stat] ?? 'Progress', value: '$value')),
              const SizedBox(width: 8),
              Expanded(child: StatTile(label: 'Goal', value: '${def.goal}')),
              const SizedBox(width: 8),
              Expanded(child: StatTile(label: unlocked ? 'Earned' : 'To go', value: unlocked ? (at == null ? '✓' : _date(at)) : '${(def.goal - value).clamp(0, def.goal)}')),
            ]),
            const SizedBox(height: 12),
            Bar(value: value.clamp(0, def.goal), max: def.goal, color: unlocked ? AppColors.success : AppColors.accent),
            const SizedBox(height: 6),
            Text('${((value / def.goal).clamp(0.0, 1.0) * 100).round()}% · you have unlocked ${ach.unlockedCount} of ${ach.total}', textAlign: TextAlign.center, style: T.caption()),
          ],
          if (same.length > 1 && !hidden) ...[
            const SectionLabel('In this series'),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final a in same) Tag('${a.name} · ${a.goal}', icon: ach.isUnlocked(a.id) ? Icons.check_circle : Icons.radio_button_unchecked, color: ach.isUnlocked(a.id) ? AppColors.success : AppColors.textMuted),
            ]),
          ],
          const SizedBox(height: 18),
          if (unlocked)
            AppButton(label: 'Share as a card', icon: Icons.ios_share, onPressed: () {
              Navigator.pop(ctx);
              showAchievementShareCard(context, title: def.name, description: def.description, icon: def.icon, detail: '${statLabels[def.stat] ?? ''}: $value', when: at == null ? '' : _date(at));
            }),
        ]),
      );
    });

/// An award the storyteller gave, with its story and a card to share.
Future<void> showStoryAwardSheet(BuildContext context, StoryAchievement a) => showAppSheet(context, builder: (ctx) {
      const color = Color(0xFFE0B354);
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [color.withValues(alpha: 0.35), color.withValues(alpha: 0.05)]), border: Border.all(color: color, width: 3), boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 36, spreadRadius: 2)]),
              child: Icon(a.iconData, size: 52, color: color),
            ),
          ),
          const SizedBox(height: 14),
          Text('AWARDED BY THE STORYTELLER', textAlign: TextAlign.center, style: T.overline(color: color).copyWith(letterSpacing: 2)),
          const SizedBox(height: 6),
          Text(a.title, textAlign: TextAlign.center, style: T.h1()),
          const SizedBox(height: 6),
          Text(a.description, textAlign: TextAlign.center, style: T.body(color: AppColors.textMuted)),
          const SizedBox(height: 12),
          Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
            if (a.story.isNotEmpty) Tag(a.story, icon: Icons.auto_stories_outlined),
            Tag(_date(a.at), icon: Icons.event_outlined),
          ]),
          const SizedBox(height: 18),
          AppButton(label: 'Share as a card', icon: Icons.ios_share, onPressed: () {
            Navigator.pop(ctx);
            showAchievementShareCard(context, title: a.title, description: a.description, icon: a.iconData, detail: a.story, when: _date(a.at));
          }),
        ]),
      );
    });

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
