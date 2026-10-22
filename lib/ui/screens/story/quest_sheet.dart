import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../game/story_host.dart';
import '../../../models/adventure.dart';
import '../../../models/tale.dart';
import '../../../models/world.dart';
import '../../../services/ai/story_ai.dart';
import '../../../services/settings.dart';
import '../../../theme/ui.dart';
import '../../widgets/error_card.dart';
import 'story_tools.dart' show editTextDialog, canonIcon;

/// The story's quests (D&D) or goals (text adventures).
List<Quest> questsOf(StoryHost host) {
  final r = host.record;
  return r is Adventure ? r.quests : (r as Tale).goals;
}

(Color, IconData, String) questLook(QuestStatus s) => switch (s) {
      QuestStatus.completed => (AppColors.success, Icons.check_circle, 'Completed'),
      QuestStatus.failed => (AppColors.danger, Icons.cancel_outlined, 'Failed'),
      QuestStatus.active => (const Color(0xFFE0B354), Icons.flag_outlined, 'In progress'),
    };

/// A list of quests or goals, tracked ones first; tap any for its details.
class QuestList extends StatelessWidget {
  const QuestList({super.key, required this.host, this.goals = false});
  final StoryHost host;
  final bool goals;

  @override
  Widget build(BuildContext context) {
    final all = questsOf(host);
    final active = all.where((q) => q.status == QuestStatus.active).toList()..sort((a, b) => (b.tracked ? 1 : 0).compareTo(a.tracked ? 1 : 0));
    final done = all.where((q) => q.status != QuestStatus.active).toList().reversed.toList();
    Widget row(Quest q) {
      final (color, icon, _) = questLook(q.status);
      return ListRow(
        leading: Icon(q.tracked && q.status == QuestStatus.active ? Icons.push_pin : icon, size: 20, color: q.status == QuestStatus.active && !q.tracked ? AppColors.textMuted : color),
        title: q.title,
        subtitle: [if (q.description.isNotEmpty) q.description, if (q.updates.length > 1) '${q.updates.length} steps'].join(' · '),
        trailing: const Icon(Icons.chevron_right, size: 18, color: AppColors.textFaint),
        onTap: () => showQuestDetails(context, host, q),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (all.isEmpty) EmptyState(icon: Icons.flag_outlined, title: goals ? 'No goals yet' : 'No quests yet', message: goals ? (host.isAi ? 'The story sets goals as it unfolds.' : 'Handcrafted stories keep their goals secret.') : 'Quests appear as the story offers them.'),
      if (active.isNotEmpty) ...[
        SectionLabel('${goals ? 'Goals' : 'Quests'} in progress · ${active.length}', padding: const EdgeInsets.fromLTRB(4, 0, 4, 8)),
        RowGroup(children: [for (final q in active) row(q)]),
      ],
      if (done.isNotEmpty) ...[
        SectionLabel('Finished · ${done.length}'),
        RowGroup(children: [for (final q in done) row(q)]),
      ],
    ]);
  }
}

/// Everything about a quest or goal: status, how it unfolded, who's involved,
/// what the story remembers about it, a hint and your own note.
Future<void> showQuestDetails(BuildContext context, StoryHost host, Quest q) => showAppSheet(context, builder: (_) => _QuestSheet(host: host, quest: q));

/// Opens the details for a quest or goal by title (from a story card).
void showQuestByTitle(BuildContext context, StoryHost host, String title) {
  final q = questsOf(host).where((q) => q.title.toLowerCase() == title.toLowerCase()).firstOrNull;
  if (q != null) showQuestDetails(context, host, q);
}

class _QuestSheet extends StatefulWidget {
  const _QuestSheet({required this.host, required this.quest});
  final StoryHost host;
  final Quest quest;

  @override
  State<_QuestSheet> createState() => _QuestSheetState();
}

class _QuestSheetState extends State<_QuestSheet> {
  bool _thinking = false;
  String? _hint;

  Future<void> _ask() async {
    setState(() => _thinking = true);
    try {
      final r = await StoryAi(widget.host.settings).questHint(widget.host, widget.quest);
      if (!mounted) return;
      setState(() => _hint = r.value);
      widget.host.world.addAiNote(AiNote(kind: 'insight', title: 'Hint: ${widget.quest.title}', text: r.value, turn: widget.host.turns, tokens: r.tokens, cost: r.cost));
      widget.host.save();
    } catch (e) {
      if (mounted) showIssueSheet(context, '$e', label: 'Hint');
    } finally {
      if (mounted) setState(() => _thinking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final host = widget.host;
    final q = widget.quest;
    final (color, icon, label) = questLook(q.status);
    final settings = context.watch<SettingsController>();
    final words = q.title.toLowerCase().split(RegExp(r'\W+')).where((w) => w.length > 3).toSet();
    bool related(String text) {
      final t = text.toLowerCase();
      return t.contains(q.title.toLowerCase()) || words.where(t.contains).length >= 2;
    }

    final facts = host.canon.where((c) => c.name.toLowerCase() != q.title.toLowerCase() && (related(c.name) || related(c.text))).take(6).toList();
    final people = host.people.where((p) => (q.giver.isNotEmpty && q.giver.toLowerCase().contains(p.name.split(' ').first.toLowerCase())) || q.description.toLowerCase().contains(p.name.split(' ').first.toLowerCase()) || q.updates.any((u) => u.text.toLowerCase().contains(p.name.split(' ').first.toLowerCase()))).take(5).toList();
    final span = q.endTurn != null ? 'Turns ${q.startTurn}–${q.endTurn}' : (q.startTurn > 0 ? 'Since turn ${q.startTurn} · ${host.turns - q.startTurn} turns' : '');
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.86,
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 28), children: [
        Center(
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.12), border: Border.all(color: color.withValues(alpha: 0.5))),
            child: Icon(icon, color: color, size: 28),
          ),
        ),
        const SizedBox(height: 10),
        Text(label.toUpperCase(), textAlign: TextAlign.center, style: T.overline(color: color).copyWith(letterSpacing: 2)),
        const SizedBox(height: 6),
        Text(q.title, textAlign: TextAlign.center, style: T.h2()),
        if (q.description.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(q.description, textAlign: TextAlign.center, style: T.body(color: AppColors.textMuted)),
        ],
        const SizedBox(height: 14),
        Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
          if (span.isNotEmpty) Tag(span, icon: Icons.schedule),
          if (q.giver.isNotEmpty) Tag('From ${q.giver}', icon: Icons.person_outline),
          if (q.reward.isNotEmpty) Tag(q.reward, icon: Icons.redeem_outlined, color: AppColors.warning),
          if (q.updates.isNotEmpty) Tag('${q.updates.length} steps', icon: Icons.timeline),
        ]),
        const SizedBox(height: 14),
        if (q.status == QuestStatus.active)
          Row(children: [
            Expanded(
              child: AppButton(
                label: q.tracked ? 'Pinned' : 'Pin to top',
                icon: q.tracked ? Icons.push_pin : Icons.push_pin_outlined,
                kind: ButtonKind.secondary,
                onPressed: () => setState(() {
                  q.tracked = !q.tracked;
                  host.save();
                  host.refresh();
                }),
              ),
            ),
            if (host.isAi && settings.useAiText) ...[
              const SizedBox(width: 8),
              Expanded(child: AppButton(label: _thinking ? 'Thinking…' : 'Get a hint', icon: Icons.lightbulb_outline, busy: _thinking, onPressed: _thinking ? null : _ask)),
            ],
          ]),
        if (_hint != null) ...[
          const SizedBox(height: 12),
          AppCard(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.lightbulb, size: 18, color: AppColors.warning),
            const SizedBox(width: 10),
            Expanded(child: Text(_hint!, style: T.small(color: AppColors.text))),
          ])),
        ],
        if (q.status == QuestStatus.active && host.isAi && !host.busy) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () {
              Navigator.pop(context);
              host.act('I focus on "${q.title}" and work toward it.');
            },
            icon: const Icon(Icons.directions_run, size: 18),
            label: const Text('Pursue it now'),
          ),
        ],
        const SectionLabel('How it unfolded'),
        if (q.updates.isEmpty) Text('No steps recorded yet.', style: T.small()),
        for (final (i, u) in q.updates.indexed)
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                width: 22,
                child: Column(children: [
                  Container(width: 10, height: 10, margin: const EdgeInsets.only(top: 4), decoration: BoxDecoration(shape: BoxShape.circle, color: i == q.updates.length - 1 ? color : AppColors.surface3)),
                  if (i < q.updates.length - 1) Expanded(child: Container(width: 2, color: AppColors.border)),
                ]),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(u.text, style: T.small(color: AppColors.text)),
                    Text('Turn ${u.turn}', style: T.caption()),
                  ]),
                ),
              ),
            ]),
          ),
        if (people.isNotEmpty) ...[
          const SectionLabel('People involved'),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final p in people) Tag(p.name, icon: Icons.person_outline)]),
        ],
        if (facts.isNotEmpty) ...[
          const SectionLabel('What the story remembers'),
          RowGroup(children: [for (final f in facts) ListRow(leading: Icon(canonIcon(f.kind), size: 18), title: f.name, subtitle: f.text)]),
        ],
        const SectionLabel('Your note'),
        AppCard(
          onTap: () async {
            final t = await editTextDialog(context, title: 'Note on ${q.title}', initial: q.note, hint: 'Suspects, leads, plans…', lines: 4);
            if (t == null) return;
            setState(() => q.note = t.trim());
            host.save();
          },
          child: Text(q.note.isEmpty ? 'Tap to jot down leads, suspects or plans.' : q.note, style: T.small(color: q.note.isEmpty ? AppColors.textFaint : AppColors.text)),
        ),
      ]),
    );
  }
}
