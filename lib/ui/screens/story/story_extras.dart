import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../game/adventure_controller.dart';
import '../../../game/story_host.dart';
import '../../../models/adventure.dart';
import '../../../models/character.dart' show newId;
import '../../../models/tale.dart';
import '../../../models/world.dart';
import '../../../services/export.dart';
import '../../../services/narrator.dart';
import '../../../services/settings.dart';
import '../../../services/usage.dart';
import '../../../theme/ui.dart';
import '../../widgets/dice.dart';
import '../adventure/sheets.dart' show showOracleSheet;
import 'notes_screen.dart';
import 'story_tools.dart';

String fmtDuration(int seconds) {
  if (seconds < 60) return '${seconds}s';
  final m = seconds ~/ 60;
  if (m < 60) return '${m}m';
  return '${m ~/ 60}h ${m % 60}m';
}

/// Numbers that describe a story so far.
List<(IconData, String, String)> storyStats(StoryHost host) {
  final log = host.log;
  final actions = log.where((e) => e.kind == LogKind.player).length;
  final words = log.where((e) => e.kind == LogKind.narration || e.kind == LogKind.dialogue || e.kind == LogKind.companion).fold<int>(0, (n, e) => n + e.text.split(RegExp(r'\s+')).length);
  final rolls = log.where((e) => e.kind == LogKind.roll).toList();
  final passed = rolls.where((e) => e.meta['ok'] == true).length;
  final said = host.world.chats.values.fold<int>(0, (n, c) => n + c.where((l) => l.fromPlayer).length);
  final romances = host.people.where((p) => host.world.bonds[p.id]?.isRomantic ?? false).length;
  final friends = host.people.where((p) => (host.world.bonds[p.id]?.friendship ?? p.disposition) >= 20).length;
  final record = host.record;
  final quests = record is Adventure ? record.quests : (record as Tale).goals;
  final done = quests.where((q) => q.status == QuestStatus.completed).length;
  final scenes = log.where((e) => e.meta['scene'] != null).length;
  final cost = (host.usageTotals['cost'] ?? 0).toDouble();
  return [
    (Icons.timer_outlined, 'Time played', fmtDuration(host.world.playSeconds)),
    (Icons.repeat, 'Turns', '${host.turns}'),
    (Icons.touch_app_outlined, 'Actions', '$actions'),
    (Icons.menu_book_outlined, 'Words read', fmtTokens(words)),
    (Icons.place_outlined, 'Places', '$scenes'),
    (Icons.people_outline, 'People met', '${host.people.length}'),
    (Icons.handshake_outlined, 'Friends', '$friends'),
    if (romances > 0) (Icons.favorite_border, 'Romances', '$romances'),
    (Icons.forum_outlined, 'Things said', '$said'),
    if (rolls.isNotEmpty) (Icons.casino_outlined, 'Rolls won', '$passed/${rolls.length}'),
    (Icons.flag_outlined, record is Adventure ? 'Quests done' : 'Goals done', '$done/${quests.length}'),
    (Icons.photo_library_outlined, 'Pictures', '${host.world.gallery.length}'),
    (Icons.sticky_note_2_outlined, 'Notes', '${host.world.notes.where((n) => !n.isEmpty).length}'),
    if (cost > 0) (Icons.toll_outlined, 'AI spend', fmtCost(cost)),
  ];
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.stats});
  final List<(IconData, String, String)> stats;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final cols = box.maxWidth > 520 ? 4 : 3;
        final w = (box.maxWidth - (cols - 1) * 8) / cols;
        return Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (icon, label, value) in stats)
            Container(
              width: w,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon, size: 15, color: AppColors.textFaint),
                const SizedBox(height: 6),
                FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: T.number(17))),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.caption()),
              ]),
            ),
        ]);
      });
}

/// Tap the story title: an overview with stats and how the story is set up.
Future<void> showStoryOverview(BuildContext context, StoryHost host) {
  final record = host.record;
  final s = host.settings;
  String cap(String v) => v.isEmpty ? v : v[0].toUpperCase() + v.substring(1);
  final config = <(String, String)>[
    ('Mode', record is Adventure ? 'D&D adventure' : 'Text adventure'),
    if (record is Adventure) ...[
      ('Storyteller', switch (record.engine) { StoryEngine.ai => 'AI Dungeon Master', StoryEngine.module => 'Handcrafted story', StoryEngine.offline => 'Endless offline quests' }),
      ('Setting', '${record.setting} · ${record.tone}'),
      ('Difficulty', '${record.difficulty}${record.hardcore ? ' · hardcore' : ''} · DCs ${record.showDcs ? 'shown' : 'hidden'}'),
      ('Hero', '${record.hero.name}, level ${record.hero.level} ${record.hero.raceLabel} ${record.hero.classSummary}'),
      ('Party', record.companions.isEmpty ? 'Solo' : record.companions.map((c) => c.name).join(', ')),
      ('Layout', record.textMode ? 'Text' : 'Standard'),
      ('Started', record.createdAt.toLocal().toString().substring(0, 16)),
    ],
    if (record is Tale) ...[
      ('Storyteller', record.engine == TaleEngine.ai ? 'AI narrator' : 'Handcrafted story'),
      ('Genre', cap(record.genre)),
      ('Protagonist', record.protagonist),
      ('Layout', record.terminal ? 'Terminal' : 'Book'),
      ('Started', record.createdAt.toLocal().toString().substring(0, 16)),
    ],
    if (host.isAi) ('Story model', s.textModel.replaceFirst('or:', '')),
    ('Images', s.useAiImages ? 'AI · ${s.imageModel.replaceFirst('or:', '')}' : 'Drawn on device'),
    ('Voice', !s.ttsEnabled ? 'Off' : s.useElevenLabs ? 'ElevenLabs' : s.useAiVoice ? 'AI voices' : 'Device voice'),
  ];
  final premise = record is Adventure ? record.premise : (record as Tale).premise;
  return showAppSheet(context, builder: (ctx) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 140,
              child: Stack(fit: StackFit.expand, children: [
                SceneBackdrop(host: host),
                const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xD9000000)]))),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 12,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(host.storySubtitle.toUpperCase(), style: T.overline(color: Colors.white70)),
                    const SizedBox(height: 2),
                    Text(host.storyTitle, style: T.h2(color: Colors.white)),
                    if (host.scene.title.isNotEmpty) Text('Now: ${host.scene.title}', style: T.caption(color: Colors.white70)),
                  ]),
                ),
              ]),
            ),
          ),
          if (premise.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(premise, style: T.body(color: AppColors.textMuted)),
          ],
          if (host.summary.isNotEmpty) ...[
            const SectionLabel('So far'),
            Text(host.summary, style: T.small(color: AppColors.text)),
          ],
          const SectionLabel('Stats'),
          _StatGrid(stats: storyStats(host)),
          const SectionLabel('Setup'),
          RowGroup(children: [for (final (k, v) in config) ListRow(title: k, subtitle: v)]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: AppButton(label: 'Journal', icon: Icons.book_outlined, kind: ButtonKind.secondary, onPressed: () {
              Navigator.pop(ctx);
              showStoryJournal(context, host);
            })),
            const SizedBox(width: 8),
            Expanded(child: AppButton(label: 'Export', icon: Icons.ios_share, kind: ButtonKind.secondary, onPressed: () {
              Navigator.pop(ctx);
              showStoryExport(context, host);
            })),
          ]),
        ]),
      ));
}

/// Long-press a passage: listen, illustrate, film, rewrite or keep it.
Future<void> showPassageSheet(BuildContext context, StoryHost host, LogEntry entry) {
  final latest = host.log.lastIndexWhere((e) => e.kind == LogKind.player) < host.log.indexOf(entry);
  return showAppSheet(context, builder: (ctx) {
    final s = context.read<SettingsController>();
    final narrator = ctx.watch<Narrator>();
    void go(VoidCallback f) {
      Navigator.pop(ctx);
      f();
    }

    return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (entry.speaker != null) Text(entry.speaker!, style: T.h3()),
          Text(entry.text, maxLines: 4, overflow: TextOverflow.ellipsis, style: T.reading()),
        ]),
      ),
      const SizedBox(height: 12),
      RowGroup(children: [
        if (narrator.speaking)
          ListRow(leading: const Icon(Icons.stop_circle_outlined, size: 20, color: AppColors.danger), title: 'Stop reading', onTap: () => go(narrator.stop))
        else
          ListRow(leading: const Icon(Icons.volume_up_outlined, size: 20), title: 'Read aloud', subtitle: s.useElevenLabs ? 'ElevenLabs' : s.useAiVoice ? 'AI voice' : 'Device voice', onTap: () => go(() => narrator.speakNow(entry.text, speaker: entry.speaker))),
        if (s.useAiImages) ListRow(leading: const Icon(Icons.brush_outlined, size: 20), title: 'Illustrate this', subtitle: 'An AI picture of this moment, added to the story', onTap: () => go(() {
          host.illustrate(entry.text);
          showToast(context, 'Painting this moment…', icon: Icons.brush_outlined);
        })),
        if (s.useAiVideo) ListRow(leading: const Icon(Icons.movie_outlined, size: 20), title: 'Film this', subtitle: '${s.videoDuration}s clip · takes a minute or two', onTap: () => go(() {
          host.illustrate(entry.text, video: true);
          showToast(context, 'Filming this moment…', icon: Icons.movie_outlined);
        })),
        if (latest && host.canRegenerate)
          ListRow(leading: const Icon(Icons.refresh, size: 20), title: 'Regenerate', subtitle: 'Undo this turn and ask the storyteller again', onTap: () => go(host.regenerate)),
        ListRow(leading: const Icon(Icons.psychology_alt_outlined, size: 20), title: 'Remember this', subtitle: 'Add to the story\'s memory', onTap: () => go(() {
          host.canon.add(CanonEntry(id: newId(), kind: 'fact', name: entry.text.split(RegExp(r'[.!?]')).first.trim().characters.take(48).toString(), text: entry.text.characters.take(300).toString(), turn: host.turns, pinned: true));
          host.save();
          showToast(context, 'Pinned to memory');
        })),
        ListRow(leading: const Icon(Icons.note_add_outlined, size: 20), title: 'Add to notes', onTap: () => go(() {
          host.world.notes.add(StoryNote(title: entry.speaker ?? 'Turn ${host.turns}', body: entry.text));
          host.save();
          showToast(context, 'Added to your notes');
        })),
        ListRow(leading: const Icon(Icons.copy, size: 20), title: 'Copy', onTap: () => go(() {
          Clipboard.setData(ClipboardData(text: entry.text));
          showToast(context, 'Copied');
        })),
      ]),
    ]);
  });
}

/// Shown while the story is being read aloud, with a stop button.
class NowReading extends StatelessWidget {
  const NowReading({super.key});

  @override
  Widget build(BuildContext context) {
    final n = context.watch<Narrator>();
    if (!n.speaking) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(999), border: Border.all(color: AppColors.accent.withValues(alpha: 0.35))),
        child: Row(children: [
          const _Bars(),
          const SizedBox(width: 10),
          Expanded(child: Text(n.current == null ? 'Reading aloud' : n.current!, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.small(color: AppColors.text))),
          TextButton.icon(onPressed: n.stop, icon: const Icon(Icons.stop_rounded, size: 18), label: const Text('Stop')),
        ]),
      ),
    );
  }
}

class _Bars extends StatefulWidget {
  const _Bars();

  @override
  State<_Bars> createState() => _BarsState();
}

class _BarsState extends State<_Bars> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < 3; i++)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              width: 3,
              height: 6 + 8 * (0.5 + 0.5 * (((_c.value + i * 0.3) % 1) < 0.5 ? ((_c.value + i * 0.3) % 1) * 2 : 2 - ((_c.value + i * 0.3) % 1) * 2)),
              decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(2)),
            ),
        ]),
      );
}

/// The storyteller is working: animated, with what it's doing and how long.
class ThinkingIndicator extends StatefulWidget {
  const ThinkingIndicator({super.key, this.mono = false, this.first = false});
  final bool mono;

  /// The opening scene (usually the slowest call).
  final bool first;

  @override
  State<ThinkingIndicator> createState() => _ThinkingIndicatorState();
}

class _ThinkingIndicatorState extends State<ThinkingIndicator> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  final _sw = Stopwatch()..start();
  Timer? _tick;

  static const _first = ['Setting the stage', 'Lighting the lanterns', 'Inventing the cast', 'Drawing the first map', 'Writing the opening scene'];
  static const _turn = ['The storyteller is thinking', 'Weighing your choice', 'Rolling behind the screen', 'Writing what happens next'];

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final secs = _sw.elapsed.inSeconds;
    final lines = widget.first ? _first : _turn;
    final line = lines[(secs ~/ 3) % lines.length];
    final style = widget.mono ? T.monoStory(13, color: AppColors.textMuted) : T.small();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(children: [
        AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Row(children: [
            for (var i = 0; i < 3; i++)
              Container(
                margin: const EdgeInsets.only(right: 5),
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accent.withValues(alpha: 0.25 + 0.75 * (((_c.value * 3 - i) % 3) < 1 ? 1 - ((_c.value * 3 - i) % 3) : 0)),
                ),
              ),
          ]),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text('$line…${secs >= 6 ? '  ${secs}s' : ''}', key: ValueKey(line), style: style),
          ),
        ),
      ]),
    );
  }
}

/// Quick controls and play tools behind the lightbulb button.
Future<void> showStoryActions(BuildContext context, StoryHost host) => showAppSheet(context, builder: (sheet) {
      final s = context.read<SettingsController>();
      void go(VoidCallback f) {
        Navigator.pop(sheet);
        f();
      }

      return ListenableBuilder(
        listenable: Listenable.merge([s, host]),
        builder: (sheet, _) {
          final dnd = host is AdventureController ? host : null;
          Widget toggle(IconData icon, String label, bool value, ValueChanged<bool> onChanged) => Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => onChanged(!value),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: value ? AppColors.accentSoft : AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: value ? AppColors.accent.withValues(alpha: 0.5) : AppColors.border),
                    ),
                    child: Row(children: [
                      Icon(icon, size: 22, color: value ? AppColors.accent : AppColors.textMuted),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.small(color: AppColors.text)),
                          const SizedBox(height: 2),
                          Text(value ? 'On' : 'Off', style: T.caption(color: value ? AppColors.accent : AppColors.textFaint)),
                        ]),
                      ),
                    ]),
                  ),
                ),
              );
          return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
            const SheetTitle('Story tools'),
            Row(children: [
              toggle(Icons.graphic_eq, 'Sound effects', s.sfxEnabled, (v) => s.update((s) => s.sfxEnabled = v)),
              const SizedBox(width: 10),
              toggle(Icons.keyboard_outlined, 'Typewriter', s.typewriter, (v) => s.update((s) => s.typewriter = v)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              toggle(Icons.music_note_outlined, 'Music', s.musicEnabled, (v) => s.update((s) => s.musicEnabled = v)),
              const SizedBox(width: 10),
              toggle(Icons.water_drop_outlined, 'Ambient sound', s.ambienceEnabled, (v) => s.update((s) => s.ambienceEnabled = v)),
            ]),
            const SizedBox(height: 12),
            RowGroup(children: [
              ListRow(leading: const Icon(Icons.psychology_outlined, size: 20), title: 'AI tools', subtitle: 'Ideas, recap, lore, diary and AI switches', onTap: () => go(() => showAiTools(context, host))),
              ListRow(leading: const Icon(Icons.sticky_note_2_outlined, size: 20), title: 'Notes', subtitle: 'Your story notebook', onTap: () => go(() => openNotes(context, host))),
              ListRow(leading: const Icon(Icons.casino_outlined, size: 20), title: 'Roll a die', subtitle: 'Any die, no strings attached', onTap: () => go(() => showQuickRoll(context))),
              if (dnd != null) ...[
                ListRow(leading: const Icon(Icons.help_outline, size: 20), title: 'Ask the oracle', subtitle: 'Yes/no questions to fate · chaos ${dnd.adventure.chaos}', onTap: () => go(() => showOracleFor(context, dnd))),
                ListRow(
                  leading: const Icon(Icons.undo, size: 20),
                  title: 'Rewind last turn',
                  subtitle: dnd.adventure.hardcore ? 'Not available in hardcore mode' : (dnd.canRewind ? 'Undo your last choice' : 'Nothing to rewind'),
                  onTap: dnd.canRewind
                      ? () => go(() {
                            dnd.rewind();
                            showToast(context, 'Rewound to before your last action', icon: Icons.undo);
                          })
                      : null,
                ),
              ],
              if (host.canRegenerate)
                ListRow(leading: const Icon(Icons.refresh, size: 20), title: 'Regenerate last turn', subtitle: 'Ask the storyteller to write it again', onTap: () => go(host.regenerate)),
              ListRow(leading: const Icon(Icons.text_fields, size: 20), title: 'Text & font', onTap: () => go(() => showTextStyleSheet(context))),
              ListRow(leading: const Icon(Icons.insights_outlined, size: 20), title: 'Story overview', subtitle: 'Stats and setup', onTap: () => go(() => showStoryOverview(context, host))),
            ]),
            const SizedBox(height: 12),
            ...storyLayoutRows(context, sheet, host),
          ]);
        },
      );
    });

/// A quick die roll outside any check.
Future<void> showQuickRoll(BuildContext context) => DiceCheckSheet.show(context, label: 'Roll', modifier: 0);

void showOracleFor(BuildContext context, AdventureController ctl) => showOracleSheet(context, ctl);
