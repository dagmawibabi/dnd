import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../game/adventure_controller.dart';
import '../../../data/tale_genres.dart';
import '../../../services/game_store.dart';
import '../../../services/tale_store.dart';
import '../../../services/settings.dart';
import '../../../services/usage.dart';
import '../../../services/ai/gateway_client.dart';
import '../../../game/story_host.dart';
import '../../../theme/ui.dart';
import '../story/story_tools.dart';

/// Choice controls stay left while the story's usage stays right.
class ChoiceToolbar extends StatelessWidget {
  const ChoiceToolbar({super.key, required this.host, required this.collapsed, required this.onToggle, required this.hasChoices, this.trailing = const []});
  final StoryHost host;

  /// Extra right-aligned buttons beside the cost chip.
  final List<Widget> trailing;
  final bool collapsed;
  final VoidCallback onToggle;
  final bool hasChoices;

  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: Align(alignment: Alignment.centerLeft, child: hasChoices
      ? TextButton.icon(
          onPressed: onToggle,
          icon: Icon(collapsed ? Icons.expand_more : Icons.expand_less, size: 18),
          label: Text(collapsed ? 'Show choices' : 'Hide choices'),
        )
      : const SizedBox.shrink())),
    Expanded(child: Align(alignment: Alignment.centerRight, child: FittedBox(fit: BoxFit.scaleDown,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        UsageChip(usage: host.usageTotals, title: host.storyTitle, turns: host.turns, storyId: host.storyId),
        ...trailing,
      ])))),
  ]);
}

/// Story spend, shown only when enabled.
class UsageChip extends StatelessWidget {
  const UsageChip({super.key, required this.usage, this.title, this.turns = 0, this.storyId});
  final Map<String, num> usage;
  final String? title;
  final int turns;
  final String? storyId;

  @override
  Widget build(BuildContext context) {
    final show = context.select<SettingsController, bool>((s) => s.showUsage);
    if (!show) return const SizedBox.shrink();
    context.watch<UsageTracker>();
    final u = usage;
    final tokens = (u['in'] ?? 0) + (u['out'] ?? 0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Semantics(
        button: true,
        label: 'Usage: ${fmtTokens(tokens)} tokens, ${fmtCost((u['cost'] ?? 0).toDouble())}',
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => showUsageSheet(context, story: usage, title: title, turns: turns, highlight: storyId),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(999), border: Border.all(color: AppColors.border)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.toll_outlined, size: 13, color: AppColors.textMuted),
              const SizedBox(width: 5),
              Text('${fmtTokens(tokens)} · ${fmtCost((u['cost'] ?? 0).toDouble())}', style: T.caption(color: AppColors.textMuted)),
            ]),
          ),
        ),
      ),
    );
  }
}

void showUsageSheet(BuildContext context, {Map<String, num>? story, String? title, int turns = 0, String? highlight}) {
  showAppSheet(context, builder: (ctx) => _UsageSheet(story: story, title: title, turns: turns, highlight: highlight));
}

void showStoryUsage(BuildContext context, StoryHost host) => showUsageSheet(context, story: host.usageTotals, title: host.storyTitle, turns: host.turns, highlight: host.storyId);

class _UsageSheet extends StatefulWidget {
  const _UsageSheet({this.story, this.title, this.turns = 0, this.highlight});
  final Map<String, num>? story;
  final String? title;
  final int turns;
  final String? highlight;

  @override
  State<_UsageSheet> createState() => _UsageSheetState();
}

class _UsageSheetState extends State<_UsageSheet> {
  late bool _allTime = widget.story == null;

  @override
  Widget build(BuildContext context) {
    final usage = context.watch<UsageTracker>();
    final settings = context.read<SettingsController>();
    final a = widget.story;
    final storyVoice = a == null ? null : usageBreakdown(a, 'category')['voice'];
    final allVoice = usage.byCategory['voice'];
    final days = usage.recentDays(14);
    final maxDay = days.fold<double>(0, (m, d) => d.$2.cost > m ? d.$2.cost : m);
    final models = usage.byModel.entries.toList()..sort((x, y) => y.value.cost.compareTo(x.value.cost));
    final insights = usage.insights(turns: widget.turns, textModel: settings.textModel, fastModel: settings.fastModel);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.85,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text('Usage & cost', style: T.h2())),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
          child: Text('Estimated from token counts and published prices (OpenRouter reports exact costs). Your provider dashboard has the exact bill.', style: T.small()),
        ),
        if (a != null) ...[
          DefaultTabController(length: 2, initialIndex: _allTime ? 1 : 0, child: TabBar(
            tabAlignment: TabAlignment.fill,
            tabs: const [Tab(text: 'Current story'), Tab(text: 'All time')],
            onTap: (index) => setState(() => _allTime = index == 1),
          )),
          const SizedBox(height: 16),
        ],
        if (a != null && !_allTime) ...[
          SectionLabel(widget.title ?? 'Current story', padding: const EdgeInsets.fromLTRB(4, 0, 4, 8)),
          Row(children: [
            Expanded(child: StatTile(label: 'Spend', value: fmtCost((a['cost'] ?? 0).toDouble()))),
            const SizedBox(width: 8),
            Expanded(child: StatTile(label: 'Tokens', value: fmtTokens((a['in'] ?? 0) + (a['out'] ?? 0)))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: StatTile(label: 'Images', value: '${(a['images'] ?? 0).toInt()}')),
            const SizedBox(width: 8),
            Expanded(child: StatTile(label: 'Videos', value: '${(a['videos'] ?? 0).toInt()}', sub: (a['seconds'] ?? 0) > 0 ? '${(a['seconds'] ?? 0).toInt()} sec' : null)),
          ]),
          const SizedBox(height: 8),
          StatTile(
            label: 'Voice',
            value: '${fmtTokens(storyVoice?.characters ?? (a['chars'] ?? 0))} characters',
            sub: '${storyVoice?.calls ?? 0} calls · ${fmtCost(storyVoice?.cost ?? 0)}',
          ),
        ],
        if (a != null && !_allTime) ...[
          UsageBreakdown(values: a),
          if (widget.turns > 0)
            Padding(padding: const EdgeInsets.all(4), child: Text('${widget.turns} turns · ${fmtCost((a['cost'] ?? 0) / widget.turns)} per turn', style: T.small())),
        ],
        if (_allTime) ...[
        const SectionLabel('All time'),
        Row(children: [
          Expanded(child: StatTile(label: 'Spend', value: fmtCost(usage.total.cost))),
          const SizedBox(width: 8),
          Expanded(child: StatTile(label: 'Today', value: fmtCost(usage.today.cost))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: StatTile(label: 'Input tokens', value: fmtTokens(usage.total.inputTokens))),
          const SizedBox(width: 8),
          Expanded(child: StatTile(label: 'Output tokens', value: fmtTokens(usage.total.outputTokens))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: StatTile(label: 'Images', value: '${usage.total.images}')),
          const SizedBox(width: 8),
          Expanded(child: StatTile(label: 'Videos', value: '${usage.total.videos}', sub: usage.total.seconds > 0 ? '${usage.total.seconds} sec' : null)),
        ]),
        const SizedBox(height: 8),
        StatTile(
          label: 'Voice',
          value: '${fmtTokens(usage.total.characters)} characters',
          sub: '${allVoice?.calls ?? 0} calls · ${fmtCost(allVoice?.cost ?? 0)}',
        ),
        const SectionLabel('All-time usage by feature'),
        for (final item in usage.byCategory.entries)
          ListRow(leading: Icon(usageCategoryIcon(item.key), size: 18), title: usageCategoryLabel(item.key), subtitle: item.value.detail, trailing: Text(fmtCost(item.value.cost), style: T.small())),
        const SectionLabel('Last 14 days'),
        AppCard(
          child: SizedBox(
            height: 96,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (final (day, t) in days)
                Expanded(
                  child: Tooltip(
                    message: '$day · ${fmtCost(t.cost)} · ${fmtTokens(t.tokens)} tokens',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          height: maxDay == 0 ? 2 : (2 + 70 * t.cost / maxDay),
                          decoration: BoxDecoration(color: t.cost > 0 ? AppColors.accent : AppColors.surface3, borderRadius: BorderRadius.circular(3)),
                        ),
                        const SizedBox(height: 6),
                        Text(day.substring(8), style: T.caption().copyWith(fontSize: 9)),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
        ),
        const SectionLabel('Insights'),
        for (final i in insights)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              padding: const EdgeInsets.all(14),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(i.tip ? Icons.lightbulb_outline : Icons.insights_outlined, size: 18, color: i.tip ? AppColors.warning : AppColors.textMuted),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(i.title, style: T.h3()),
                    const SizedBox(height: 2),
                    Text(i.text, style: T.small()),
                  ]),
                ),
              ]),
            ),
          ),
        const SectionLabel('By adventure'),
        AdventureUsageList(highlight: widget.highlight),
        if (models.isNotEmpty) ...[
          const SectionLabel('By model'),
          RowGroup(children: [
            for (final m in models)
              ListRow(
                title: AiRoute.bare(m.key),
                subtitle: '${AiRoute.routerName(m.key)} · ${m.value.detail}',
                trailing: Text(fmtCost(m.value.cost), style: T.small(color: AppColors.text)),
              ),
          ]),
        ],
        const SizedBox(height: 16),
        AppButton(
          label: 'Reset statistics',
          kind: ButtonKind.ghost,
          onPressed: () async {
            if (await confirm(context, title: 'Reset usage?', message: 'Clears all-time totals and history. Adventure totals are kept.', action: 'Reset')) {
              usage.reset();
            }
          },
        ),
        ],
      ]),
    );
  }
}

/// D&D-only menu rows: oracle and rewind, plus the shared story rows.
List<Widget> adventureMenuRows(BuildContext context, BuildContext sheetContext, AdventureController ctl) {
  final a = ctl.adventure;
  return [
    ...storyMenuRows(context, sheetContext, ctl),
    const SizedBox(height: 12),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Wrap(spacing: 6, runSpacing: 6, children: [
        Tag(a.difficulty, icon: Icons.tune),
        if (a.hardcore) const Tag('Hardcore', icon: Icons.local_fire_department_outlined, color: AppColors.danger),
        Tag(a.showDcs ? 'DCs shown' : 'DCs hidden', icon: a.showDcs ? Icons.visibility_outlined : Icons.visibility_off_outlined),
      ]),
    ),
  ];
}

/// Tokens and estimated spend for every adventure, most expensive first.
class AdventureUsageList extends StatelessWidget {
  const AdventureUsageList({super.key, this.highlight, this.limit});
  final String? highlight;
  final int? limit;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<GameStore>();
    final tales = context.watch<TaleStore>();
    // D&D adventures and text adventures, side by side.
    final list = <_UsageRow>[
      for (final s in store.adventures) _UsageRow(s.id, s.title, s.heroName, s.usage),
      for (final t in tales.tales) _UsageRow(t.id, t.title, 'Text adventure · ${genreById(t.genre).name}', t.usage),
    ].where((s) => s.tokens > 0 || s.cost > 0).toList()
      ..sort((x, y) => y.cost.compareTo(x.cost));
    if (list.isEmpty) {
      return Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text('No AI usage recorded for any adventure yet.', style: T.small()));
    }
    final total = list.fold<double>(0, (t, s) => t + s.cost);
    final shown = limit == null ? list : list.take(limit!).toList();
    return RowGroup(children: [
      for (final s in shown)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(s.title, style: T.body(color: s.id == highlight ? AppColors.accent : AppColors.text), maxLines: 1, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              Text(fmtCost(s.cost), style: T.small(color: AppColors.text)),
            ]),
            const SizedBox(height: 4),
            Text(
              '${s.who} · ${fmtTokens(s.usage['in'] ?? 0)} in · ${fmtTokens(s.usage['out'] ?? 0)} out · ${(s.usage['calls'] ?? 0).toInt()} calls${(s.usage['images'] ?? 0) > 0 ? ' · ${(s.usage['images'] ?? 0).toInt()} images' : ''}${(s.usage['videos'] ?? 0) > 0 ? ' · ${(s.usage['videos'] ?? 0).toInt()} videos' : ''}${(s.usage['chars'] ?? 0) > 0 ? ' · ${fmtTokens(s.usage['chars'] ?? 0)} voiced chars' : ''}',
              style: T.caption(),
            ),
            TextButton(
              onPressed: () => showAppSheet(context, builder: (_) => SingleChildScrollView(child: Padding(
                padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min,
                  children: [Text(s.title, style: T.h2()), UsageBreakdown(values: s.usage)]),
              ))),
              child: const Text('View feature & model breakdown'),
            ),
            const SizedBox(height: 6),
            Bar(value: total == 0 ? 0 : s.cost, max: total == 0 ? 1 : total, color: AppColors.accent),
          ]),
        ),
      if (limit != null && list.length > limit!)
        ListRow(title: 'All ${list.length} adventures', trailing: const Icon(Icons.chevron_right, size: 18), onTap: () => showUsageSheet(context)),
    ]);
  }
}

class _UsageRow {
  _UsageRow(this.id, this.title, this.who, this.usage);
  final String id;
  final String title;
  final String who;
  final Map<String, num> usage;
  int get tokens => ((usage['in'] ?? 0) + (usage['out'] ?? 0)).toInt();
  double get cost => (usage['cost'] ?? 0).toDouble();
}


class UsageBreakdown extends StatelessWidget {
  const UsageBreakdown({super.key, required this.values});
  final Map<String, num> values;

  @override
  Widget build(BuildContext context) {
    final categories = usageBreakdown(values, 'category');
    final models = usageBreakdown(values, 'model');
    final classified = categories.values.fold<int>(0, (n, t) => n + t.calls);
    Widget row(String label, UsageTotals t, {IconData? icon}) => ListRow(
      leading: icon == null ? null : Icon(icon, size: 18),
      title: label,
      subtitle: t.detail,
      trailing: Text(fmtCost(t.cost), style: T.small()),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionLabel('By feature'),
      for (final category in categories.entries) row(usageCategoryLabel(category.key), category.value, icon: usageCategoryIcon(category.key)),
      if ((values['calls'] ?? 0) > classified)
        Text('Earlier usage is included in totals but has no feature or model breakdown.', style: T.caption()),
      if (models.isNotEmpty) const SectionLabel('By model'),
      for (final model in models.entries)
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(AiRoute.bare(model.key), style: T.small()),
          subtitle: Text('${AiRoute.routerName(model.key)} · ${model.value.detail} · ${fmtCost(model.value.cost)}', style: T.caption()),
          children: [
            for (final category in categories.keys)
              ...usageBreakdown(values, 'categoryModel:$category').entries.where((e) => e.key == model.key).map((e) => row(usageCategoryLabel(category), e.value)),
          ],
        ),
    ]);
  }
}
