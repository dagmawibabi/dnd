import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../game/chapter_recap.dart';
import '../../../game/story_host.dart';
import '../../../models/adventure.dart';
import '../../../models/chronicle.dart';
import '../../../services/export.dart' show showStoryExport;
import '../../../theme/ui.dart';
import '../../widgets/portrait.dart';
import 'story_tools.dart' show romanceColor;
import 'world_memory_screen.dart';

/// Opens "What changed" for the current chapter of [host].
Future<void> openChapterRecap(BuildContext context, StoryHost host, {bool ended = false, String? continueLabel, VoidCallback? onContinue}) =>
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChapterRecapScreen(host: host, ended: ended, continueLabel: continueLabel, onContinue: onContinue),
    ));

/// The end-of-chapter screen: how the world, your relationships, companions
/// and quests moved because of what you did.
class ChapterRecapScreen extends StatelessWidget {
  const ChapterRecapScreen({super.key, required this.host, this.ended = false, this.continueLabel, this.onContinue});
  final StoryHost host;

  /// The chapter is over (rather than a look at the chapter so far).
  final bool ended;
  final String? continueLabel;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final c = summarizeChapter(host.record, host.people);
    var step = 0;
    Widget reveal(Widget child) => FadeIn(delay: Duration(milliseconds: 60 * (step++).clamp(0, 14)), child: child);
    final groups = c.byKind;
    return Scaffold(
      appBar: AppBar(
        title: Text(ended ? 'Chapter complete' : 'What changed so far'),
        actions: [
          IconButton(
            tooltip: 'Copy summary',
            icon: const Icon(Icons.copy_outlined),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: c.toText()));
              showToast(context, 'Summary copied');
            },
          ),
          IconButton(tooltip: 'Export journal', icon: const Icon(Icons.ios_share), onPressed: () => showStoryExport(context, host)),
        ],
      ),
      body: ContentWidth(
        maxWidth: 720,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
          reveal(_Hero(c: c, ended: ended)),
          const SizedBox(height: 12),
          reveal(Wrap(spacing: 8, runSpacing: 8, children: [
            _Stat(Icons.timelapse, '${c.turns}', 'turns'),
            _Stat(Icons.public, '${c.changes.where((x) => x.kind != 'camp').length}', 'world changes'),
            _Stat(Icons.local_fire_department_outlined, '${c.campDays}', c.campDays == 1 ? 'day at camp' : 'days at camp'),
            _Stat(Icons.forum_outlined, '${c.conversations}', 'lines spoken in private'),
            if (c.approaches > 0) _Stat(Icons.waving_hand_outlined, '${c.approaches}', c.approaches == 1 ? 'time someone came to you' : 'times someone came to you'),
            _Stat(Icons.people_outline, '${c.peopleKnown}', 'people known'),
          ])),
          if (c.isEmpty)
            reveal(const Padding(
              padding: EdgeInsets.only(top: 24),
              child: EmptyState(icon: Icons.hourglass_empty, title: 'Nothing has shifted yet', message: 'Your choices will leave marks on the world, your companions and the people you meet.'),
            )),
          if (groups.isNotEmpty) ...[
            const SectionLabel('The world remembers'),
            for (final e in groups.entries) ...[
              reveal(Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
                child: Text(kindTitle(e.key).toUpperCase(), style: T.overline()),
              )),
              for (final ch in e.value) reveal(_ChangeCard(change: ch)),
            ],
          ],
          if (c.reputation.isNotEmpty) ...[
            const SectionLabel('Reputation'),
            reveal(Wrap(spacing: 8, runSpacing: 8, children: [
              for (final r in c.reputation.entries)
                Tag('${r.key} ${r.value > 0 ? '+' : ''}${r.value}', icon: r.value >= 0 ? Icons.trending_up : Icons.trending_down, color: r.value >= 0 ? AppColors.success : AppColors.danger),
            ])),
          ],
          if (c.bonds.isNotEmpty) ...[
            const SectionLabel('Relationships'),
            for (final b in c.bonds) reveal(_BondCard(shift: b)),
          ],
          if (c.arcs.isNotEmpty) ...[
            const SectionLabel('Companion stories'),
            for (final a in c.arcs) reveal(_ArcCard(arc: a)),
          ],
          if (c.completed.isNotEmpty || c.failed.isNotEmpty || c.open.isNotEmpty) ...[
            const SectionLabel('Quests'),
            reveal(AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Column(children: [
                for (final q in c.completed) _QuestRow(q, Icons.check_circle, AppColors.success, 'Completed'),
                for (final q in c.failed) _QuestRow(q, Icons.cancel, AppColors.danger, 'Failed'),
                for (final q in c.open) _QuestRow(q, Icons.radio_button_unchecked, AppColors.textMuted, ended ? 'Carries on' : 'Open'),
              ]),
            )),
          ],
          const SizedBox(height: 20),
          reveal(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppButton(
              label: 'Browse world memory',
              icon: Icons.public,
              kind: ButtonKind.secondary,
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WorldMemoryScreen(
                    world: () => host.world.chronicle,
                    listenable: host,
                    onChanged: () {
                      host.refresh();
                      host.save();
                    },
                    chapterId: host.storyId,
                    chapterTitle: host.storyTitle,
                    turn: host.turns,
                  ))),
            ),
            if (onContinue != null) ...[
              const SizedBox(height: 10),
              AppButton(
                label: continueLabel ?? 'Continue',
                icon: Icons.auto_stories_outlined,
                kind: ButtonKind.accent,
                onPressed: () {
                  Navigator.pop(context);
                  onContinue!();
                },
              ),
            ],
          ])),
        ]),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.c, required this.ended});
  final ChapterChanges c;
  final bool ended;

  @override
  Widget build(BuildContext context) {
    final headline = c.changes.isEmpty
        ? 'A quiet chapter.'
        : c.byKind.length == 1
            ? 'You changed ${c.byKind.values.first.length} ${kindTitle(c.byKind.keys.first).toLowerCase()}.'
            : 'You left your mark on ${c.byKind.length} kinds of things.';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.accent.withValues(alpha: 0.28), AppColors.surface]),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(ended ? 'END OF CHAPTER' : 'CHAPTER SO FAR', style: T.overline(color: AppColors.accent)),
        const SizedBox(height: 6),
        Text(c.title, style: T.h1()),
        const SizedBox(height: 6),
        Text(headline, style: T.body(color: AppColors.textMuted)),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.icon, this.value, this.label);
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Text(value, style: T.h3()),
          const SizedBox(width: 6),
          Flexible(child: Text(label, style: T.caption(), overflow: TextOverflow.ellipsis)),
        ]),
      );
}

class _ChangeCard extends StatelessWidget {
  const _ChangeCard({required this.change});
  final WorldChange change;

  @override
  Widget build(BuildContext context) {
    final ch = change;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(ch.name, style: T.h3())),
            const SizedBox(width: 8),
            Text('turn ${ch.turn} · day ${ch.day}', style: T.caption()),
          ]),
          const SizedBox(height: 8),
          if (ch.before.isNotEmpty) ...[
            Text(ch.before, style: T.small().copyWith(decoration: TextDecoration.lineThrough, decorationColor: AppColors.textFaint)),
            const Padding(padding: EdgeInsets.symmetric(vertical: 2), child: Icon(Icons.arrow_downward, size: 14, color: AppColors.textFaint)),
          ],
          Text(ch.after, style: T.body()),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.subdirectory_arrow_right, size: 14, color: AppColors.accent)),
            const SizedBox(width: 6),
            Expanded(child: Text('Because ${ch.reason[0].toLowerCase()}${ch.reason.substring(1)}', style: T.small(color: AppColors.accent))),
          ]),
        ]),
      ),
    );
  }
}

class _BondCard extends StatelessWidget {
  const _BondCard({required this.shift});
  final BondShift shift;

  @override
  Widget build(BuildContext context) {
    final s = shift;
    Widget delta(String label, int v, Color c) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Tag('$label ${v > 0 ? '+' : ''}$v', color: v == 0 ? AppColors.textMuted : (v > 0 ? c : AppColors.danger)),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.all(12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          NpcPortrait(npc: s.person, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(s.person.name, style: T.h3(), overflow: TextOverflow.ellipsis)),
                Flexible(child: Text(s.bond.label, style: T.small(color: s.bond.isRomantic ? romanceColor : AppColors.text), overflow: TextOverflow.ellipsis)),
              ]),
              const SizedBox(height: 6),
              Wrap(runSpacing: 6, children: [
                delta('Friendship', s.friendship, AppColors.success),
                if (s.romance != 0) delta('Romance', s.romance, romanceColor),
              ]),
              const SizedBox(height: 6),
              for (final m in s.moments.reversed.take(2)) Text('• ${m.text}', style: T.caption(), maxLines: 2, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _ArcCard extends StatelessWidget {
  const _ArcCard({required this.arc});
  final CompanionArc arc;

  @override
  Widget build(BuildContext context) {
    final a = arc;
    final color = switch (a.stage) {
      'resolved' => AppColors.success,
      'failed' || 'departed' => AppColors.danger,
      'choice' => AppColors.warning,
      _ => AppColors.info,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${a.name}: ${a.title}', style: T.h3())),
            Tag(stageLabel(a.stage), color: color),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: a.ended || a.stage == 'choice' ? 1 : a.progress / 2, minHeight: 6, color: color, backgroundColor: AppColors.surface3),
          ),
          const SizedBox(height: 6),
          Text(a.outcome.isNotEmpty ? a.outcome : 'Leads ${a.progress}/2 · ${a.description}', style: T.small()),
          if (a.rewarded) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Rewards granted', style: T.caption(color: AppColors.success))),
        ]),
      ),
    );
  }
}

class _QuestRow extends StatelessWidget {
  const _QuestRow(this.q, this.icon, this.color, this.label);
  final Quest q;
  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(q.title, style: T.body())),
          Text(label, style: T.caption(color: color)),
        ]),
      );
}
