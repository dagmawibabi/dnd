import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'story_extras.dart';
import '../../../art/scene_painter.dart';
import '../../../game/story_host.dart';
import '../../../models/adventure.dart';
import '../../../services/narrator.dart';
import '../../../theme/ui.dart';
import '../../widgets/details_sheet.dart';
import '../../widgets/media_view.dart';
import '../adventure/log_view.dart' show questOf;
import 'quest_sheet.dart';
import 'story_tools.dart' show showPersonSheet;

/// What kind of moment a timeline entry is.
enum Beat { place, quest, person, world, battle, moment, growth, award }

class _Event {
  _Event(this.beat, this.text, this.entry, {this.icon, this.color});
  final Beat beat;
  final String text;
  final LogEntry entry;
  final IconData? icon;
  final Color? color;
}

class _Chapter {
  _Chapter(this.title, this.scene, this.turn);
  final String title;
  final SceneInfo? scene;
  final int turn;
  int endTurn = 0;
  DateTime? at;
  String opening = '';
  final events = <_Event>[];
  final passages = <(String, String?)>[];
}

Future<void> openTimeline(BuildContext context, StoryHost host) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TimelineScreen(host: host)));

/// The story so far as a timeline: each place you went, and what happened there.
class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key, required this.host});
  final StoryHost host;

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

const _beatLabels = {Beat.place: 'Places', Beat.quest: 'Quests', Beat.person: 'People', Beat.world: 'World', Beat.battle: 'Battles', Beat.moment: 'Moments', Beat.growth: 'Growth', Beat.award: 'Awards'};

class _TimelineScreenState extends State<TimelineScreen> {
  final Set<Beat> _show = {...Beat.values};
  bool _newestFirst = false;

  List<_Chapter> _build() {
    final host = widget.host;
    final out = <_Chapter>[];
    var turn = 0;
    _Chapter current = _Chapter(host.storyTitle, null, 0)..opening = '';
    out.add(current);
    for (final e in host.log) {
      if (e.kind == LogKind.player) turn++;
      final scene = e.meta['scene'];
      if (scene is Map) {
        current.endTurn = turn;
        current = _Chapter(e.text, SceneInfo.fromJson(Map<String, dynamic>.from(scene)), turn)..at = e.at;
        out.add(current);
        continue;
      }
      current.at ??= e.at;
      if (e.kind == LogKind.narration || e.kind == LogKind.dialogue) {
        if (current.opening.isEmpty) current.opening = e.text;
        current.passages.add((e.text, e.kind == LogKind.narration ? null : e.speaker));
      }
      final q = questOf(e);
      if (q != null) {
        final state = q['state'];
        current.events.add(_Event(Beat.quest, e.text, e, icon: state == 'done' ? Icons.check_circle : (state == 'failed' ? Icons.cancel_outlined : Icons.flag_outlined), color: state == 'done' ? AppColors.success : (state == 'failed' ? AppColors.danger : const Color(0xFFE0B354))));
      } else if (e.meta['award'] != null) {
        current.events.add(_Event(Beat.award, e.text, e, icon: Icons.workspace_premium, color: AppColors.warning));
      } else if (e.kind == LogKind.levelup) {
        current.events.add(_Event(Beat.award, e.text, e, icon: Icons.auto_awesome, color: AppColors.accent));
      } else if (e.meta['npc'] != null) {
        current.events.add(_Event(Beat.person, e.text, e, icon: Icons.person_add_alt, color: AppColors.info));
      } else if (e.meta['bond'] != null) {
        current.events.add(_Event(Beat.person, e.text, e, icon: e.text.contains('romance') ? Icons.favorite : Icons.handshake_outlined, color: e.text.contains('romance') ? const Color(0xFFF472B6) : AppColors.info));
      } else if (e.meta['growth'] != null) {
        current.events.add(_Event(Beat.growth, e.text, e, icon: Icons.psychology_outlined, color: AppColors.accent));
      } else if (e.meta['world'] != null) {
        current.events.add(_Event(Beat.world, e.text, e, icon: Icons.public, color: AppColors.warning));
      } else if (e.meta['media'] is String) {
        current.events.add(_Event(Beat.moment, e.text, e, icon: Icons.auto_awesome_outlined, color: AppColors.accent));
      } else if (e.kind == LogKind.combat && (e.meta['fx'] == 'roar' && current.events.where((x) => x.beat == Beat.battle).isEmpty)) {
        current.events.add(_Event(Beat.battle, e.text, e, icon: Icons.sports_kabaddi_outlined, color: AppColors.danger));
      } else if (e.kind == LogKind.levelup || (e.kind == LogKind.combat && (e.text.startsWith('VICTORY') || e.text.startsWith('DEFEAT')))) {
        current.events.add(_Event(Beat.battle, e.text, e, icon: e.text.startsWith('VICTORY') ? Icons.emoji_events_outlined : Icons.sentiment_very_dissatisfied_outlined, color: e.text.startsWith('VICTORY') ? AppColors.success : AppColors.danger));
      }
    }
    current.endTurn = turn;
    return out.where((c) => c.scene != null || c.events.isNotEmpty || c.opening.isNotEmpty).toList();
  }

  @override
  Widget build(BuildContext context) {
    final host = widget.host;
    return ListenableBuilder(
      listenable: host,
      builder: (context, _) {
        var chapters = _build();
        if (_newestFirst) chapters = chapters.reversed.toList();
        final counts = {for (final b in Beat.values) b: chapters.fold<int>(0, (n, c) => n + c.events.where((e) => e.beat == b).length)};
        counts[Beat.place] = chapters.where((c) => c.scene != null).length;
        final history = host.world.chronicle.history.where((h) => h.chapter == host.storyId && h.reason != 'Established in the story.').toList();
        return Scaffold(
          bottomNavigationBar: const NowReadingBar(),
          appBar: AppBar(
            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Timeline', style: T.h3()),
              Text('${host.storyTitle} · ${host.turns} turns · ${counts[Beat.place]} places', style: T.caption(), overflow: TextOverflow.ellipsis),
            ]),
            actions: [
              IconButton(tooltip: _newestFirst ? 'Oldest first' : 'Newest first', icon: Icon(_newestFirst ? Icons.vertical_align_top : Icons.vertical_align_bottom), onPressed: () => setState(() => _newestFirst = !_newestFirst)),
            ],
          ),
          body: ContentWidth(
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
              SizedBox(
                height: 38,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  for (final b in Beat.values)
                    if ((counts[b] ?? 0) > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text('${_beatLabels[b]} ${counts[b]}'),
                          selected: _show.contains(b),
                          onSelected: (v) => setState(() => v ? _show.add(b) : _show.remove(b)),
                        ),
                      ),
                ]),
              ),
              const SizedBox(height: 12),
              if (chapters.isEmpty) const EmptyState(icon: Icons.timeline, title: 'Nothing yet', message: 'Your story\'s places and turning points appear here as you play.'),
              for (final (i, c) in chapters.indexed) _chapter(context, c, i == chapters.length - 1),
              if (history.isNotEmpty && _show.contains(Beat.world)) ...[
                const SectionLabel('How the world changed'),
                RowGroup(children: [
                  for (final h in (_newestFirst ? history.reversed : history))
                    ListRow(leading: const Icon(Icons.public, size: 18, color: AppColors.warning), title: h.name, subtitle: '${h.before.isEmpty ? '' : '${h.before} → '}${h.after}\n${h.reason} · turn ${h.turn}'),
                ]),
              ],
            ]),
          ),
        );
      },
    );
  }

  Widget _chapter(BuildContext context, _Chapter c, bool last) {
    final host = widget.host;
    final path = c.scene == null ? null : host.record.sceneImages[c.title];
    final events = c.events.where((e) => _show.contains(e.beat)).toList();
    if (!_show.contains(Beat.place) && events.isEmpty) return const SizedBox.shrink();
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 26,
          child: Column(children: [
            Container(
              width: 14,
              height: 14,
              margin: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.bg, border: Border.all(color: AppColors.accent, width: 3)),
            ),
            if (!last) Expanded(child: Container(width: 2, color: AppColors.border)),
          ]),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 22),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(c.title, style: T.h3())),
                Text(c.endTurn > c.turn ? 'Turns ${c.turn}–${c.endTurn}' : 'Turn ${c.turn}', style: T.caption()),
              ]),
              if (c.scene != null && _show.contains(Beat.place)) ...[
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => openMedia(context, path: path, fallback: SceneView(location: c.scene!.location, time: c.scene!.time, mood: c.scene!.mood, seed: c.scene!.seed, animate: true), title: c.title),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 110,
                      width: double.infinity,
                      child: MediaView(path: path, fallback: SceneView(location: c.scene!.location, time: c.scene!.time, mood: c.scene!.mood, seed: c.scene!.seed), cacheWidth: 700),
                    ),
                  ),
                ),
              ],
              if (c.opening.isNotEmpty && _show.contains(Beat.place)) ...[
                const SizedBox(height: 8),
                Text(c.opening, maxLines: 3, overflow: TextOverflow.ellipsis, style: T.small()),
              ],
              if (c.passages.isNotEmpty && _show.contains(Beat.place))
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                    onPressed: () => context.read<Narrator>().playAll(c.passages),
                    icon: const Icon(Icons.headphones_outlined, size: 16),
                    label: Text('Listen to this part (${c.passages.length})', style: T.caption(color: AppColors.textMuted)),
                  ),
                ),
              for (final e in events)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _open(context, e),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (e.beat == Beat.moment)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(width: 54, height: 40, child: MediaView(path: e.entry.meta['media'] as String, fallback: Container(color: AppColors.surface2), cacheWidth: 160)),
                        )
                      else
                        Padding(padding: const EdgeInsets.only(top: 1), child: Icon(e.icon, size: 17, color: e.color)),
                      const SizedBox(width: 10),
                      Expanded(child: Text(e.text, maxLines: 3, overflow: TextOverflow.ellipsis, style: T.small(color: AppColors.text))),
                    ]),
                  ),
                ),
            ]),
          ),
        ),
      ]),
    );
  }

  void _open(BuildContext context, _Event e) {
    final host = widget.host;
    final q = questOf(e.entry);
    if (q != null) return showQuestByTitle(context, host, (q['title'] ?? '').toString());
    if (e.beat == Beat.moment) {
      openMedia(context, path: e.entry.meta['media'] as String, fallback: const SizedBox(), title: 'Moment', subtitle: e.entry.text);
      return;
    }
    final who = e.entry.meta['npc'] ?? e.entry.meta['bond'] ?? e.entry.meta['growth'];
    if (who != null) {
      final p = host.people.where((n) => n.id == who || n.name == who).firstOrNull;
      if (p != null) {
        showPersonSheet(context, host, p);
        return;
      }
    }
    if (hasDetails(e.entry)) showLogDetails(context, e.entry);
  }
}
