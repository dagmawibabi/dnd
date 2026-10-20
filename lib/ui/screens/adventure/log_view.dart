import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../art/scene_painter.dart';
import '../../../models/adventure.dart';
import '../../../game/story.dart';
import '../../../models/world.dart';
import '../../../services/image_service.dart';
import '../../../services/narrator.dart';
import '../../../art/render_png.dart';
import '../../widgets/media_view.dart';
import '../../../theme/ui.dart';
import '../../widgets/details_sheet.dart';
import '../../widgets/image_viewer.dart';
import '../../widgets/portrait.dart';
import '../../widgets/typewriter.dart';

/// One item in the story feed.
class LogEntryView extends StatelessWidget {
  const LogEntryView({super.key, required this.entry, required this.adventure, this.animate = false, this.speed = 1, this.onAnimated, this.latestScene = false, this.onTalk, this.onJournal, this.onPassage});

  /// Long-press actions for a passage (listen, illustrate, regenerate…).
  final void Function(LogEntry)? onPassage;
  final void Function(Npc)? onTalk;

  /// Opens the journal on its quests or goals.
  final VoidCallback? onJournal;
  final LogEntry entry;
  final StoryRecord adventure;
  final bool animate;
  final double speed;
  final VoidCallback? onAnimated;
  final bool latestScene;

  @override
  Widget build(BuildContext context) {
    var child = _content(context);
    final tokens = entry.meta['tok'] ?? 0, usd = entry.meta['usd'] ?? 0;
    if ((tokens > 0 || usd > 0) && entry.meta['media'] == null && showItemCost(context, message: true)) {
      child = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [child, Padding(padding: const EdgeInsets.only(bottom: 6), child: CostBadge(tokens: tokens as num, cost: usd as num))]);
    }
    if (entry.kind == LogKind.narration || entry.kind == LogKind.dialogue || entry.kind == LogKind.companion) {
      // Long-press any passage for its actions (or just to hear it).
      final passage = onPassage;
      child = GestureDetector(onLongPress: passage != null ? () => passage(entry) : () => context.read<Narrator>().speakNow(entry.text, speaker: entry.speaker), child: child);
    }
    final person = adventure.personNamed(entry.speaker);
    if (person != null && onTalk != null && (entry.kind == LogKind.dialogue || entry.kind == LogKind.companion)) {
      return GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => onTalk!(person), child: child);
    }
    if (!hasDetails(entry) || questOf(entry) != null) return child;
    return _Tappable(onTap: () => showLogDetails(context, entry), child: child);
  }

  Widget _content(BuildContext context) {
    switch (entry.kind) {
      case LogKind.narration:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: TypewriterText(text: _prose(entry.text), animate: animate, speed: speed, onDone: onAnimated, style: T.reading()),
        );
      case LogKind.dialogue:
        final npc = adventure.personNamed(entry.speaker);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (npc != null)
              NpcPortrait(npc: npc, size: 34)
            else
              Container(width: 34, height: 34, decoration: const BoxDecoration(color: AppColors.surface2, shape: BoxShape.circle), child: const Icon(Icons.person_outline, size: 16)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(entry.speaker ?? '', style: T.h3()),
                const SizedBox(height: 4),
                TypewriterText(text: _prose(entry.text), animate: animate, speed: speed, onDone: onAnimated, style: T.reading(), onTap: npc == null || onTalk == null ? null : () => onTalk!(npc)),
              ]),
            ),
          ]),
        );
      case LogKind.companion:
        final c = adventure.companionNamed(entry.speaker);
        final npc = adventure.personNamed(entry.speaker);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (c != null) CharacterPortrait(character: c, size: 28)
            else if (npc != null) NpcPortrait(npc: npc, size: 28)
            else const CircleAvatar(radius: 14, child: Icon(Icons.person_outline, size: 16)),
            const SizedBox(width: 10),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: const BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.only(topRight: Radius.circular(16), bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16), topLeft: Radius.circular(4)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(entry.speaker ?? '', style: T.caption(color: AppColors.textMuted)),
                  const SizedBox(height: 2),
                  Text(entry.text, style: T.chat()),
                ]),
              ),
            ),
            const SizedBox(width: 40),
          ]),
        );
      case LogKind.player:
        return Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6, left: 56),
          child: Align(
            alignment: Alignment.centerRight,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(
                color: AppColors.text,
                borderRadius: BorderRadius.only(topLeft: Radius.circular(16), bottomLeft: Radius.circular(16), topRight: Radius.circular(16), bottomRight: Radius.circular(4)),
              ),
              child: Text(entry.text, style: T.chat(color: AppColors.bg)),
            ),
          ),
        );
      case LogKind.roll:
        final ok = entry.meta['ok'] == true;
        final nat = entry.meta['nat'];
        final color = ok ? AppColors.success : AppColors.danger;
        final label = entry.meta['label'] != null
            ? '${entry.meta['label']} · ${entry.meta['total']} vs DC ${entry.meta['dc']} · ${ok ? 'Success' : 'Failure'}${nat == 20 ? ' (natural 20)' : nat == 1 ? ' (natural 1)' : ''}'
            : entry.text;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Center(child: Tag(label, icon: Icons.casino_outlined, color: color, filled: true)),
        );
      case LogKind.combat:
        final color = switch (entry.meta['fx']) {
          'crit' => AppColors.warning,
          'hit' => AppColors.danger,
          'heal' => AppColors.success,
          'spell' => AppColors.accent,
          'death' => AppColors.danger,
          'roar' => AppColors.warning,
          'buff' => AppColors.info,
          _ => AppColors.textFaint,
        };
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 6), child: Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle))),
            const SizedBox(width: 10),
            Expanded(child: Text(entry.text, style: T.small())),
          ]),
        );
      case LogKind.loot:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            const Icon(Icons.add_circle_outline, size: 14, color: AppColors.success),
            const SizedBox(width: 8),
            Expanded(child: Text(entry.text, style: T.small(color: AppColors.text))),
          ]),
        );
      case LogKind.levelup when questOf(entry) != null:
        return QuestCard(entry: entry, onJournal: onJournal);
      case LogKind.levelup:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Icon(Icons.auto_awesome_outlined, color: AppColors.accent, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text(entry.text, style: T.body())),
            ]),
          ),
        );
      case LogKind.oracle:
        return OracleCard(entry: entry);
      case LogKind.system:
        if (entry.meta['scene'] is Map) return SceneCard(entry: entry, adventure: adventure, latest: latestScene);
        if (entry.meta['media'] is String) return MomentCard(entry: entry);
        if (entry.meta['bond'] != null) {
          final romance = entry.text.contains('romance');
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Icon(romance ? Icons.favorite : Icons.handshake_outlined, size: 14, color: romance ? const Color(0xFFF472B6) : AppColors.info),
              const SizedBox(width: 8),
              Expanded(child: Text(entry.text, style: T.small(color: AppColors.textMuted))),
            ]),
          );
        }
        return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(entry.text, style: T.small()));
    }
  }

  String _prose(String text) {
    try {
      return readableNarration(text);
    } on FormatException {
      return 'This saved response was incomplete. Continue the story to try again.';
    }
  }
}

/// Wraps a feed item so it highlights on hover and shows a chevron.
class _Tappable extends StatefulWidget {
  const _Tappable({required this.onTap, required this.child});
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_Tappable> createState() => _TappableState();
}

class _TappableState extends State<_Tappable> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(color: _hover ? AppColors.surface : Colors.transparent, borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            Expanded(child: widget.child),
            Icon(Icons.chevron_right, size: 16, color: _hover ? AppColors.textMuted : AppColors.border),
          ]),
        ),
      ),
    );
  }
}

class SceneCard extends StatelessWidget {
  const SceneCard({super.key, required this.entry, required this.adventure, required this.latest});
  final LogEntry entry;
  final StoryRecord adventure;
  final bool latest;

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  @override
  Widget build(BuildContext context) {
    final s = SceneInfo.fromJson(Map<String, dynamic>.from(entry.meta['scene']));
    final images = context.watch<ImageService>();
    final path = latest ? adventure.sceneImagePath : adventure.sceneImages[s.title];
    final video = isVideoPath(path);
    final cost = path == null ? 0.0 : adventure.mediaCosts[path] ?? images.costs[path] ?? 0;
    final showCost = cost > 0 && showItemCost(context, video: video);
    final busyKey = images.busy.where((key) => key.startsWith('scene_${adventure.id}_')).firstOrNull;
    Widget art({bool animate = false}) {
      final painted = SceneView(location: s.location, time: s.time, mood: s.mood, seed: s.seed, animate: animate);
      return MediaView(path: path, fallback: painted, fit: animate ? BoxFit.contain : BoxFit.cover, controls: animate);
    }

    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: MouseRegion(
        cursor: SystemMouseCursors.zoomIn,
        child: GestureDetector(
          onTap: () => openImageViewer(context, title: s.title, subtitle: '${_cap(s.location)} · ${_cap(s.time)}', aspectRatio: 16 / 9, actions: mediaActions(context, path, name: s.title, render: () => scenePng(s)), builder: (_) => art(animate: true)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 150,
              child: Stack(fit: StackFit.expand, children: [
                art(),
                const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xCC000000)]))),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 12,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.title, style: T.h3(color: Colors.white)),
                    Text('${_cap(s.location)} · ${_cap(s.time)}', style: T.caption(color: Colors.white70)),
                  ]),
                ),
                const Positioned(top: 10, right: 10, child: Icon(Icons.open_in_full, size: 16, color: Colors.white70)),
                if (video) const Positioned(top: 10, left: 34, child: Icon(Icons.videocam_outlined, size: 16, color: Colors.white70)),
                if (showCost) Positioned(top: 8, right: 34, child: CostBadge(cost: cost, onImage: true)),
                if (latest && busyKey != null)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Row(children: [
                      const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                      if (images.status[busyKey] != null) ...[const SizedBox(width: 8), Text('${images.status[busyKey]} video…', style: T.caption(color: Colors.white))],
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

IconData choiceIcon(ChoiceType t) => switch (t) {
      ChoiceType.action => Icons.bolt_outlined,
      ChoiceType.dialogue => Icons.chat_bubble_outline,
      ChoiceType.explore => Icons.explore_outlined,
      ChoiceType.combat => Icons.sports_kabaddi_outlined,
      ChoiceType.stealth => Icons.visibility_off_outlined,
      ChoiceType.magic => Icons.auto_fix_high_outlined,
      ChoiceType.rest => Icons.bedtime_outlined,
      ChoiceType.leave => Icons.directions_walk,
    };

/// A fate-chart answer from the oracle.
class OracleCard extends StatelessWidget {
  const OracleCard({super.key, required this.entry});
  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final m = entry.meta;
    final answer = entry.text;
    final yes = answer.toLowerCase().contains('yes');
    final strong = answer.toLowerCase().contains('exceptional');
    final color = yes ? AppColors.success : AppColors.danger;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.help_outline, size: 15, color: AppColors.info),
            const SizedBox(width: 6),
            Text('ORACLE', style: T.overline(color: AppColors.info)),
            const Spacer(),
            if (m['roll'] != null) Text('d100 ${m['roll']} · ${m['likelihood'] ?? ''}', style: T.caption()),
          ]),
          if ((m['q'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('"${m['q']}"', style: T.body(color: AppColors.textMuted)),
          ],
          const SizedBox(height: 8),
          Text(answer, style: T.h2(color: color).copyWith(fontSize: strong ? 22 : 19)),
          if (m['event'] != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(10)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.bolt, size: 16, color: AppColors.warning),
                const SizedBox(width: 8),
                Expanded(child: Text('Random event: ${m['event']}', style: T.small(color: AppColors.text))),
              ]),
            ),
          ],
          if (m['meaning'] != null) ...[
            const SizedBox(height: 8),
            Text('Meaning: ${m['meaning']}', style: T.small()),
          ],
        ]),
      ),
    );
  }
}

/// A special-effect image or video for a dramatic moment.
class MomentCard extends StatelessWidget {
  const MomentCard({super.key, required this.entry});
  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final path = entry.meta['media'] as String;
    final video = entry.meta['video'] == true || isVideoPath(path);
    final cost = (entry.meta['usd'] ?? 0) as num;
    final fallback = Container(color: AppColors.surface2, child: const Center(child: Icon(Icons.auto_awesome_outlined, color: AppColors.textFaint)));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: GestureDetector(
        onTap: () => openMedia(context, path: path, fallback: fallback, title: 'Moment', subtitle: entry.text),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(fit: StackFit.expand, children: [
              MediaView(path: path, fallback: fallback),
              const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.center, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xB3000000)]))),
              Positioned(
                left: 12,
                right: 12,
                bottom: 10,
                child: Text(entry.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: T.small(color: Colors.white)),
              ),
              Positioned(top: 8, left: 10, child: Icon(video ? Icons.videocam_outlined : Icons.auto_awesome, size: 16, color: Colors.white70)),
              if (cost > 0 && showItemCost(context, video: video)) Positioned(top: 8, right: 8, child: CostBadge(cost: cost, onImage: true)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Quest or goal info for a log entry: its metadata, or parsed from the text
/// of older saves ("New goal: Find the ledger").
Map<String, dynamic>? questOf(LogEntry e) {
  if (e.kind != LogKind.levelup) return null;
  final m = e.meta['quest'];
  if (m is Map) return Map<String, dynamic>.from(m);
  final hit = RegExp(r'^(New quest|Quest complete|Quest failed|Quest updated|New goal|Goal complete|Goal failed): (.+)$').firstMatch(e.text.trim());
  if (hit == null) return null;
  final kind = hit.group(1)!;
  return {
    'title': hit.group(2)!,
    'goal': kind.contains('oal'),
    'state': kind.contains('complete') ? 'done' : kind.contains('failed') ? 'failed' : kind.contains('updated') ? 'update' : 'new',
  };
}

(String, Color, IconData) _questLook(Map<String, dynamic> q) {
  final goal = q['goal'] == true;
  final noun = goal ? 'GOAL' : 'QUEST';
  return switch (q['state']) {
    'done' => ('$noun COMPLETE', AppColors.success, Icons.verified_outlined),
    'failed' => ('$noun FAILED', AppColors.danger, Icons.do_not_disturb_on_outlined),
    'update' => ('$noun UPDATED', AppColors.info, Icons.edit_note),
    _ => ('NEW $noun', const Color(0xFFE0B354), Icons.flag_outlined),
  };
}

/// A quest or goal starting, advancing, succeeding or failing.
class QuestCard extends StatelessWidget {
  const QuestCard({super.key, required this.entry, this.onJournal});
  final LogEntry entry;
  final VoidCallback? onJournal;

  @override
  Widget build(BuildContext context) {
    final q = questOf(entry)!;
    final (label, color, icon) = _questLook(q);
    final desc = (q['desc'] ?? '').toString();
    final failed = q['state'] == 'failed';
    Widget rule() => Expanded(child: Container(height: 1, decoration: BoxDecoration(gradient: LinearGradient(colors: [color.withValues(alpha: 0), color.withValues(alpha: 0.55), color.withValues(alpha: 0)]))));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => showQuestSheet(context, entry, onJournal: onJournal),
          child: Ink(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: AppColors.surface,
              border: Border.all(color: color.withValues(alpha: 0.28)),
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.10), blurRadius: 24, spreadRadius: -6)],
            ),
            child: Column(children: [
              Row(children: [
                rule(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon, size: 14, color: color),
                    const SizedBox(width: 6),
                    Text(label, style: T.overline(color: color).copyWith(letterSpacing: 2)),
                  ]),
                ),
                rule(),
              ]),
              const SizedBox(height: 10),
              Text(
                (q['title'] ?? '').toString(),
                textAlign: TextAlign.center,
                style: T.reading().copyWith(fontSize: 19 * T.readingScale, fontWeight: FontWeight.w600, height: 1.25, color: failed ? AppColors.textMuted : AppColors.text, decoration: failed ? TextDecoration.lineThrough : null),
              ),
              if (desc.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(desc, textAlign: TextAlign.center, style: T.small(), maxLines: 3, overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: 10),
              Text('Tap for details', style: T.caption(color: color.withValues(alpha: 0.8))),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Details of a quest or goal, with a way into the journal.
Future<void> showQuestSheet(BuildContext context, LogEntry entry, {VoidCallback? onJournal}) {
  final q = questOf(entry)!;
  final (label, color, icon) = _questLook(q);
  final goal = q['goal'] == true;
  final details = entry.meta['details'] is Map ? Map<String, dynamic>.from(entry.meta['details']) : const <String, dynamic>{};
  final lines = [for (final l in (details['lines'] as List? ?? const [])) if (l is List && l.length >= 2) (l[0].toString(), l[1].toString())];
  final desc = (q['desc'] ?? '').toString();
  return showAppSheet(context, builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.12), border: Border.all(color: color.withValues(alpha: 0.5))),
              child: Icon(icon, color: color, size: 26),
            ),
          ),
          const SizedBox(height: 10),
          Text(label, textAlign: TextAlign.center, style: T.overline(color: color).copyWith(letterSpacing: 2)),
          const SizedBox(height: 6),
          Text((q['title'] ?? '').toString(), textAlign: TextAlign.center, style: T.h2()),
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(desc, textAlign: TextAlign.center, style: T.body(color: AppColors.textMuted)),
          ],
          if (lines.isNotEmpty) ...[
            const SizedBox(height: 14),
            RowGroup(children: [for (final (k, v) in lines) ListRow(title: k, subtitle: v)]),
          ],
          const SizedBox(height: 8),
          Text('Recorded ${entry.at.hour.toString().padLeft(2, '0')}:${entry.at.minute.toString().padLeft(2, '0')}', textAlign: TextAlign.center, style: T.caption()),
          if (onJournal != null) ...[
            const SizedBox(height: 16),
            AppButton(
              label: goal ? 'View all goals' : 'View all quests',
              icon: Icons.book_outlined,
              onPressed: () {
                Navigator.pop(ctx);
                onJournal();
              },
            ),
          ],
        ]),
      ));
}
