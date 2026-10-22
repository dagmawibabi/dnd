import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../models/companion.dart';
import '../../../services/companion_store.dart';
import '../companions/companion_editor.dart';
import '../companions/companions_screen.dart';
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
import '../adventure/sheets.dart' show showOracleSheet, showVitalsSheet;
import '../tales/tale_tools.dart' show showTaleVitals;
import '../../../game/tale_controller.dart';
import '../../widgets/narrator_tone.dart';
import '../../widgets/portrait.dart';
import '../../widgets/share_cards.dart';
import 'finance_screen.dart';
import 'inventory_screen.dart';
import 'character_history_screen.dart';
import 'timeline_screen.dart';
import 'notes_screen.dart';
import '../../widgets/ai_trace_sheet.dart';
import 'story_tools.dart';
import 'world_memory_screen.dart';
import '../adventure/camp_screen.dart';

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
  final words = log
      .where(
        (e) =>
            e.kind == LogKind.narration ||
            e.kind == LogKind.dialogue ||
            e.kind == LogKind.companion,
      )
      .fold<int>(0, (n, e) => n + e.text.split(RegExp(r'\s+')).length);
  final rolls = log.where((e) => e.kind == LogKind.roll).toList();
  final passed = rolls.where((e) => e.meta['ok'] == true).length;
  final said = host.world.chats.values.fold<int>(
    0,
    (n, c) => n + c.where((l) => l.fromPlayer).length,
  );
  final romances = host.people
      .where((p) => host.world.bonds[p.id]?.isRomantic ?? false)
      .length;
  final friends = host.people
      .where((p) => (host.world.bonds[p.id]?.friendship ?? p.disposition) >= 20)
      .length;
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
    if (rolls.isNotEmpty)
      (Icons.casino_outlined, 'Rolls won', '$passed/${rolls.length}'),
    (
      Icons.flag_outlined,
      record is Adventure ? 'Quests done' : 'Goals done',
      '$done/${quests.length}',
    ),
    (Icons.photo_library_outlined, 'Pictures', '${host.world.gallery.length}'),
    (
      Icons.sticky_note_2_outlined,
      'Notes',
      '${host.world.notes.where((n) => !n.isEmpty).length}',
    ),
    if (cost > 0) (Icons.toll_outlined, 'AI spend', fmtCost(cost)),
  ];
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.stats});
  final List<(IconData, String, String)> stats;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final cols = box.maxWidth > 520 ? 4 : 3;
      final w = (box.maxWidth - (cols - 1) * 8) / cols;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (icon, label, value) in stats)
            Container(
              width: w,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 15, color: AppColors.textFaint),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(value, style: T.number(17)),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.caption(),
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );
}

/// Tap the story title: an overview with stats and how the story is set up.
Future<void> showStoryOverview(BuildContext context, StoryHost host) {
  final record = host.record;
  final s = host.settings;
  String cap(String v) => v.isEmpty ? v : v[0].toUpperCase() + v.substring(1);
  final config = <(String, String)>[
    ('Mode', record is Adventure ? 'D&D adventure' : 'Text adventure'),
    if (record is Adventure) ...[
      (
        'Storyteller',
        switch (record.engine) {
          StoryEngine.ai => 'AI Dungeon Master',
          StoryEngine.module => 'Handcrafted story',
          StoryEngine.offline => 'Endless offline quests',
        },
      ),
      ('Setting', '${record.setting} · ${record.tone}'),
      (
        'Difficulty',
        '${record.difficulty}${record.hardcore ? ' · hardcore' : ''} · DCs ${record.showDcs ? 'shown' : 'hidden'}',
      ),
      (
        'Hero',
        '${record.hero.name}, level ${record.hero.level} ${record.hero.raceLabel} ${record.hero.classSummary}',
      ),
      (
        'Party',
        record.companions.isEmpty
            ? 'Solo'
            : record.companions.map((c) => c.name).join(', '),
      ),
      ('Layout', record.textMode ? 'Text' : 'Standard'),
      ('Started', record.createdAt.toLocal().toString().substring(0, 16)),
    ],
    if (record is Tale) ...[
      (
        'Storyteller',
        record.engine == TaleEngine.ai ? 'AI narrator' : 'Handcrafted story',
      ),
      ('Genre', cap(record.genre)),
      ('Protagonist', record.protagonist),
      ('Layout', record.terminal ? 'Terminal' : 'Book'),
      ('Started', record.createdAt.toLocal().toString().substring(0, 16)),
    ],
    if (host.isAi) ('Story model', s.textModel.replaceFirst('or:', '')),
    (
      'Images',
      s.useAiImages
          ? 'AI · ${s.imageModel.replaceFirst('or:', '')}'
          : 'Drawn on device',
    ),
    (
      'Voice',
      !s.ttsEnabled
          ? 'Off'
          : s.useElevenLabs
          ? 'ElevenLabs'
          : s.useAiVoice
          ? 'AI voices'
          : 'Device voice',
    ),
  ];
  final premise = record is Adventure
      ? record.premise
      : (record as Tale).premise;
  final finished = record is Adventure
      ? record.finished
      : (record as Tale).finished;
  void go(BuildContext ctx, VoidCallback f) {
    Navigator.pop(ctx);
    f();
  }

  Widget link(
    BuildContext ctx,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) => Expanded(
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => go(ctx, onTap),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: AppColors.accent),
            const SizedBox(height: 6),
            Text(
              label,
              style: T.caption(color: AppColors.text),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    ),
  );
  return showAppSheet(
    context,
    builder: (ctx) => ListenableBuilder(
      listenable: host,
      builder: (ctx, _) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 140,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    SceneBackdrop(host: host),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0xD9000000)],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 14,
                      right: 14,
                      bottom: 12,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            host.storySubtitle.toUpperCase(),
                            style: T.overline(color: Colors.white70),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            host.storyTitle,
                            style: T.h2(color: Colors.white),
                          ),
                          if (host.scene.title.isNotEmpty)
                            Text(
                              'Now: ${host.scene.title}',
                              style: T.caption(color: Colors.white70),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (premise.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(premise, style: T.body(color: AppColors.textMuted)),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                link(
                  ctx,
                  Icons.backpack_outlined,
                  'Inventory',
                  () => openInventory(context, host),
                ),
                const SizedBox(width: 8),
                link(
                  ctx,
                  Icons.account_balance_wallet_outlined,
                  'Money',
                  () => openFinance(context, host),
                ),
                const SizedBox(width: 8),
                link(
                  ctx,
                  Icons.timeline,
                  'Timeline',
                  () => openTimeline(context, host),
                ),
                const SizedBox(width: 8),
                link(
                  ctx,
                  Icons.monitor_heart_outlined,
                  'Condition',
                  () => host is AdventureController
                      ? showVitalsSheet(context, host)
                      : showTaleVitals(context, host as TaleController),
                ),
                const SizedBox(width: 8),
                link(
                  ctx,
                  Icons.ios_share,
                  'Share',
                  () => showStoryShareCard(context, host),
                ),
              ],
            ),
            if (host.isAi && !finished && s.useAiText) ...[
              const SectionLabel('Storyteller'),
              RowGroup(
                children: [
                  ListRow(
                    leading: const Icon(
                      Icons.record_voice_over_outlined,
                      size: 20,
                    ),
                    title: 'Narrator tone',
                    subtitle: host.world.narratorTone.isEmpty
                        ? 'Default · tap to change how the story is told'
                        : '${toneLabel(host.world.narratorTone)} · ${host.world.narratorTone}',
                    trailing: const Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: AppColors.textFaint,
                    ),
                    onTap: () => showNarratorToneSheet(ctx, host),
                  ),
                  ListRow(
                    leading: Icon(
                      Icons.flag_circle_outlined,
                      size: 20,
                      color: host.world.wrapUpTurn >= 0
                          ? AppColors.warning
                          : null,
                    ),
                    title: 'Wrap up the story',
                    subtitle: host.world.wrapUpTurn >= 0
                        ? 'The storyteller is steering toward an ending within a few turns'
                        : 'Tired? Ask the storyteller to bring it to a satisfying end soon',
                    trailing: Switch(
                      value: host.world.wrapUpTurn >= 0,
                      onChanged: (v) {
                        host.world.wrapUpTurn = v ? host.turns : -1;
                        host.note(
                          v
                              ? 'The player wants to wrap the story up soon: head for the climax and ending.'
                              : 'The player wants the story to continue at its own pace again.',
                        );
                        host.save();
                        host.refresh();
                        if (v)
                          showToast(
                            ctx,
                            'The story will head for its ending',
                            icon: Icons.flag_circle_outlined,
                          );
                      },
                    ),
                  ),
                ],
              ),
            ],
            if (host.people.isNotEmpty) ...[
              SectionLabel(
                'Characters · ${host.people.length}',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () => go(ctx, () => openCharacterHistory(context)),
                      child: Text(
                        'All stories',
                        style: T.caption(color: AppColors.textMuted),
                      ),
                    ),
                    const SizedBox(width: 14),
                    GestureDetector(
                      onTap: () =>
                          go(ctx, () => showRelationshipsCard(context, host)),
                      child: Text(
                        'Share',
                        style: T.caption(color: AppColors.textMuted),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 86,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final p in host.people)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: GestureDetector(
                          onTap: () =>
                              go(ctx, () => showPersonSheet(context, host, p)),
                          child: SizedBox(
                            width: 60,
                            child: Column(
                              children: [
                                Opacity(
                                  opacity: p.alive ? 1 : 0.4,
                                  child: NpcPortrait(npc: p, size: 50),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  p.name.split(' ').first,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: T.caption(color: AppColors.text),
                                ),
                                Text(
                                  host.world.bondFor(p).label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: T
                                      .caption(
                                        color: host.world.bondFor(p).isHostile
                                            ? AppColors.danger
                                            : AppColors.textFaint,
                                      )
                                      .copyWith(fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (host.summary.isNotEmpty) ...[
              const SectionLabel('So far'),
              Text(host.summary, style: T.small(color: AppColors.text)),
            ],
            const SectionLabel('Stats'),
            _StatGrid(stats: storyStats(host)),
            const SectionLabel('Setup'),
            RowGroup(
              children: [
                for (final (k, v) in config) ListRow(title: k, subtitle: v),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Journal',
                    icon: Icons.book_outlined,
                    kind: ButtonKind.secondary,
                    onPressed: () {
                      Navigator.pop(ctx);
                      showStoryJournal(context, host);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AppButton(
                    label: 'Export',
                    icon: Icons.ios_share,
                    kind: ButtonKind.secondary,
                    onPressed: () {
                      Navigator.pop(ctx);
                      showStoryExport(context, host);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// Choose how the storyteller narrates, mid-story.
Future<void> showNarratorToneSheet(
  BuildContext context,
  StoryHost host,
) => showAppSheet(
  context,
  builder: (ctx) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      0,
      20,
      MediaQuery.viewInsetsOf(ctx).bottom + 24,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetTitle(
            'Narrator tone',
            subtitle:
                'How the storyteller tells your story from the next turn on.',
          ),
          NarratorTonePicker(
            value: host.world.narratorTone,
            onChanged: (v) {
              host.world.narratorTone = v;
              host.save();
              host.refresh();
            },
          ),
          const SizedBox(height: 16),
          AppButton(label: 'Done', onPressed: () => Navigator.pop(ctx)),
        ],
      ),
    ),
  ),
);

/// Long-press a passage: listen, illustrate, film, rewrite or keep it.
Future<void> showPassageSheet(
  BuildContext context,
  StoryHost host,
  LogEntry entry,
) {
  final latest =
      host.log.lastIndexWhere((e) => e.kind == LogKind.player) <
      host.log.indexOf(entry);
  return showAppSheet(
    context,
    builder: (ctx) {
      final s = context.read<SettingsController>();
      final narrator = ctx.watch<Narrator>();
      void go(VoidCallback f) {
        Navigator.pop(ctx);
        f();
      }

      // Everything spoken from this passage on, for "play from here".
      final from = host.log.indexOf(entry);
      final rest = [
        for (final e in host.log.skip(from < 0 ? host.log.length : from))
          if (e.kind == LogKind.narration ||
              e.kind == LogKind.dialogue ||
              e.kind == LogKind.companion)
            (e.text, e.kind == LogKind.narration ? null : e.speaker),
      ];
      return ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (entry.speaker != null && entry.kind == LogKind.companion)
                  Text(entry.speaker!, style: T.h3()),
                Text(
                  entry.text,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: T.reading(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          RowGroup(
            children: [
              if (narrator.speaking)
                ListRow(
                  leading: const Icon(
                    Icons.stop_circle_outlined,
                    size: 20,
                    color: AppColors.danger,
                  ),
                  title: 'Stop reading',
                  onTap: () => go(narrator.stop),
                )
              else
                ListRow(
                  leading: const Icon(Icons.volume_up_outlined, size: 20),
                  title: 'Read aloud',
                  subtitle: s.useElevenLabs
                      ? 'ElevenLabs · replays are free'
                      : s.useAiVoice
                      ? 'AI voice · replays are free'
                      : 'Device voice',
                  onTap: () => go(
                    () => narrator.speakNow(
                      entry.text,
                      speaker: entry.kind == LogKind.narration
                          ? null
                          : entry.speaker,
                    ),
                  ),
                ),
              if (!narrator.speaking && rest.length > 1)
                ListRow(
                  leading: const Icon(Icons.playlist_play, size: 20),
                  title: 'Play from here',
                  subtitle: '${rest.length} passages to the latest',
                  onTap: () => go(() => narrator.playAll(rest)),
                ),
              if (s.useAiImages)
                ListRow(
                  leading: const Icon(Icons.brush_outlined, size: 20),
                  title: 'Illustrate this',
                  subtitle: 'An AI picture of this moment, added to the story',
                  onTap: () => go(() {
                    host.illustrate(entry.text);
                    showToast(
                      context,
                      'Painting this moment…',
                      icon: Icons.brush_outlined,
                    );
                  }),
                ),
              if (s.useAiVideo)
                ListRow(
                  leading: const Icon(Icons.movie_outlined, size: 20),
                  title: 'Film this',
                  subtitle: '${s.videoDuration}s clip · takes a minute or two',
                  onTap: () => go(() {
                    host.illustrate(entry.text, video: true);
                    showToast(
                      context,
                      'Filming this moment…',
                      icon: Icons.movie_outlined,
                    );
                  }),
                ),
              if (latest && host.aiTrace != null)
                ListRow(
                  leading: const Icon(Icons.manage_search, size: 20),
                  title: 'Behind the story',
                  subtitle: 'How this was written: steps, thinking, context',
                  onTap: () => go(() => showAiTrace(context, host)),
                ),
              if (latest && host.canRegenerate)
                ListRow(
                  leading: const Icon(Icons.refresh, size: 20),
                  title: 'Regenerate',
                  subtitle: 'Undo this turn and ask the storyteller again',
                  onTap: () => go(host.regenerate),
                ),
              ListRow(
                leading: const Icon(Icons.psychology_alt_outlined, size: 20),
                title: 'Remember this',
                subtitle: 'Add to the story\'s memory',
                onTap: () => go(() {
                  host.canon.add(
                    CanonEntry(
                      id: newId(),
                      kind: 'fact',
                      name: entry.text
                          .split(RegExp(r'[.!?]'))
                          .first
                          .trim()
                          .characters
                          .take(48)
                          .toString(),
                      text: entry.text.characters.take(300).toString(),
                      turn: host.turns,
                      pinned: true,
                    ),
                  );
                  host.save();
                  showToast(context, 'Pinned to memory');
                }),
              ),
              ListRow(
                leading: const Icon(Icons.note_add_outlined, size: 20),
                title: 'Add to notes',
                onTap: () => go(() {
                  host.world.notes.add(
                    StoryNote(
                      title: entry.speaker ?? 'Turn ${host.turns}',
                      body: entry.text,
                    ),
                  );
                  host.save();
                  showToast(context, 'Added to your notes');
                }),
              ),
              ListRow(
                leading: const Icon(Icons.copy, size: 20),
                title: 'Copy',
                onTap: () => go(() {
                  Clipboard.setData(ClipboardData(text: entry.text));
                  showToast(context, 'Copied');
                }),
              ),
            ],
          ),
        ],
      );
    },
  );
}

/// The narration player as a screen's bottom bar (shown only while reading).
class NowReadingBar extends StatelessWidget {
  const NowReadingBar({super.key});

  @override
  Widget build(BuildContext context) => const SafeArea(
        top: false,
        child: Padding(padding: EdgeInsets.fromLTRB(12, 0, 12, 6), child: NowReading()),
      );
}

/// The narration player, shown while the story is read aloud: pause, skip
/// back or ahead, restart the passage, change speed, or stop. Tap the text to
/// open the full controls.
class NowReading extends StatelessWidget {
  const NowReading({super.key});

  @override
  Widget build(BuildContext context) {
    final n = context.watch<Narrator>();
    if (!n.speaking) return const SizedBox.shrink();
    Widget btn(
      IconData icon,
      String tip,
      VoidCallback onTap, {
      double size = 20,
    }) => IconButton(
      tooltip: tip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 34, height: 34),
      icon: Icon(icon, size: size),
      onPressed: onTap,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 2, 4, 2),
        decoration: BoxDecoration(
          color: AppColors.accentSoft,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            if (n.loadingVoice)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.accent,
                ),
              )
            else if (n.errorCount > 0 && n.lastError != null)
              Tooltip(
                message: n.lastError!,
                child: const Icon(
                  Icons.error_outline,
                  size: 16,
                  color: AppColors.warning,
                ),
              )
            else if (n.paused)
              const Icon(Icons.pause, size: 14, color: AppColors.accent)
            else
              const _Bars(),
            const SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => showNarrationPlayer(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      n.loadingVoice
                          ? 'Generating narration…'
                          : (n.currentSpeaker ?? 'Narrator'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: T.caption(color: AppColors.accent),
                    ),
                    Text(
                      n.current ?? 'Reading aloud',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: T.small(color: AppColors.text),
                    ),
                  ],
                ),
              ),
            ),
            btn(Icons.replay_10, 'Back 10 seconds', () => n.seekBy(-10)),
            btn(
              n.paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              n.paused ? 'Resume' : 'Pause',
              n.togglePause,
              size: 24,
            ),
            btn(Icons.forward_10, 'Forward 10 seconds', () => n.seekBy(10)),
            GestureDetector(
              onTap: n.cycleSpeed,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.5),
                  ),
                ),
                child: Text(
                  '${_speedLabel(n.speed)}×',
                  style: T.caption(color: AppColors.accent),
                ),
              ),
            ),
            btn(Icons.stop_rounded, 'Stop', n.stop),
          ],
        ),
      ),
    );
  }
}

String _speedLabel(double s) => s == s.roundToDouble()
    ? s.toStringAsFixed(0)
    : s.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');

/// Full narration controls: the line being read, progress through the
/// passage, skip, restart and a speed slider.
Future<void> showNarrationPlayer(BuildContext context) => showAppSheet(
  context,
  builder: (ctx) {
    final n = ctx.watch<Narrator>();
    final s = ctx.read<SettingsController>();
    Widget big(
      IconData icon,
      String tip,
      VoidCallback? onTap, {
      double size = 28,
      bool primary = false,
    }) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: primary
          ? CircleIconButton(
              icon: icon,
              size: 60,
              tooltip: tip,
              onPressed: onTap,
            )
          : IconButton(
              tooltip: tip,
              iconSize: size,
              icon: Icon(icon),
              onPressed: onTap,
            ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetTitle(
            n.speaking ? (n.currentSpeaker ?? 'Narrator') : 'Nothing playing',
            subtitle: n.speaking
                ? 'Part ${n.index + 1} of ${n.length} · ${s.useElevenLabs
                      ? 'ElevenLabs'
                      : s.useAiVoice
                      ? 'AI voice'
                      : 'Device voice'}'
                : 'Long-press any passage to hear it',
          ),
          if (n.lastError != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 18,
                    color: AppColors.warning,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'The ${s.useCloudVoice ? 'AI' : 'device'} voice had a problem${s.useCloudVoice ? ', so the device voice read instead' : ''}: ${n.lastError}',
                      style: T.small(color: AppColors.text),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (n.speaking) ...[
            Container(
              constraints: const BoxConstraints(maxHeight: 160),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: SingleChildScrollView(
                child: Text(n.current ?? '', style: T.reading()),
              ),
            ),
            const SizedBox(height: 10),
            if (n.length > 1)
              Bar(value: n.index + 1, max: n.length, color: AppColors.accent),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                big(
                  Icons.skip_previous_rounded,
                  'Previous part',
                  n.index > 0 ? n.previous : null,
                ),
                big(Icons.replay_10, 'Back 10 seconds', () => n.seekBy(-10)),
                big(
                  n.paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  n.paused ? 'Resume' : 'Pause',
                  n.togglePause,
                  primary: true,
                ),
                big(Icons.forward_10, 'Forward 10 seconds', () => n.seekBy(10)),
                big(Icons.skip_next_rounded, 'Next part', n.next),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: n.restart,
                  icon: const Icon(Icons.restart_alt, size: 18),
                  label: const Text('Restart passage'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: n.stop,
                  icon: const Icon(
                    Icons.stop_rounded,
                    size: 18,
                    color: AppColors.danger,
                  ),
                  label: Text('Stop', style: T.small(color: AppColors.danger)),
                ),
              ],
            ),
            if (!n.playingAudio)
              Text(
                'The device voice skips by sentence; AI voices skip by seconds.',
                textAlign: TextAlign.center,
                style: T.caption(),
              ),
          ],
          const SectionLabel('Speed'),
          Row(
            children: [
              const Icon(
                Icons.slow_motion_video,
                size: 18,
                color: AppColors.textMuted,
              ),
              Expanded(
                child: Slider(
                  value: n.speed.clamp(0.5, 2.5),
                  min: 0.5,
                  max: 2.5,
                  divisions: 20,
                  label: '${_speedLabel(n.speed)}×',
                  onChanged: (v) => n.setSpeed((v * 20).round() / 20),
                ),
              ),
              SizedBox(
                width: 44,
                child: Text(
                  '${_speedLabel(n.speed)}×',
                  textAlign: TextAlign.right,
                  style: T.small(color: AppColors.text),
                ),
              ),
            ],
          ),
          CompactChips(child: Wrap(
            spacing: 6,
            alignment: WrapAlignment.center,
            children: [
              for (final v in const [0.75, 1.0, 1.15, 1.25, 1.5, 2.0])
                ChoiceChip(
                  label: Text('${_speedLabel(v)}×'),
                  selected: (n.speed - v).abs() < 0.01,
                  onSelected: (_) => n.setSpeed(v),
                ),
            ],
          )),
        ],
      ),
    );
  },
);

class _Bars extends StatefulWidget {
  const _Bars();

  @override
  State<_Bars> createState() => _BarsState();
}

class _BarsState extends State<_Bars> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, _) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            width: 3,
            height:
                6 +
                8 *
                    (0.5 +
                        0.5 *
                            (((_c.value + i * 0.3) % 1) < 0.5
                                ? ((_c.value + i * 0.3) % 1) * 2
                                : 2 - ((_c.value + i * 0.3) % 1) * 2)),
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
      ],
    ),
  );
}

/// The storyteller is working: animated, with what it's doing and how long.
class ThinkingIndicator extends StatefulWidget {
  const ThinkingIndicator({
    super.key,
    this.mono = false,
    this.first = false,
    this.onTap,
  });
  final bool mono;

  /// Opens what the storyteller is doing right now.
  final VoidCallback? onTap;

  /// The opening scene (usually the slowest call).
  final bool first;

  @override
  State<ThinkingIndicator> createState() => _ThinkingIndicatorState();
}

class _ThinkingIndicatorState extends State<ThinkingIndicator>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();
  final _sw = Stopwatch()..start();
  Timer? _tick;

  static const _first = [
    'Setting the stage',
    'Lighting the lanterns',
    'Inventing the cast',
    'Drawing the first map',
    'Writing the opening scene',
  ];
  static const _turn = [
    'The storyteller is thinking',
    'Weighing your choice',
    'Rolling behind the screen',
    'Writing what happens next',
  ];

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
    final style = widget.mono
        ? T.monoStory(14, color: AppColors.textMuted)
        : T.bodyMuted();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            AnimatedBuilder(
              animation: _c,
              builder: (context, _) => Row(
                children: [
                  for (var i = 0; i < 3; i++)
                    Container(
                      margin: const EdgeInsets.only(right: 5),
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.accent.withValues(
                          alpha:
                              0.25 +
                              0.75 *
                                  (((_c.value * 3 - i) % 3) < 1
                                      ? 1 - ((_c.value * 3 - i) % 3)
                                      : 0),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Expanded, not Flexible beside a Spacer: that gave the text only
            // half the row and cut it off.
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.centerLeft,
                  children: [...previous, ?current],
                ),
                child: Text(
                  '$line…${secs >= 6 ? '  ${secs}s' : ''}',
                  key: ValueKey(line),
                  style: style,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (widget.onTap != null) ...[
              const SizedBox(width: 8),
              const Icon(
                Icons.visibility_outlined,
                size: 18,
                color: AppColors.textFaint,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Quick controls and play tools behind the lightbulb button.
Future<void> showStoryActions(
  BuildContext context,
  StoryHost host,
) => showAppSheet(
  context,
  builder: (sheet) {
    final s = context.read<SettingsController>();
    void go(VoidCallback f) {
      Navigator.pop(sheet);
      f();
    }

    return ListenableBuilder(
      listenable: Listenable.merge([s, host]),
      builder: (sheet, _) {
        final dnd = host is AdventureController ? host : null;
        Widget toggle(
          IconData icon,
          String label,
          bool value,
          ValueChanged<bool> onChanged,
        ) => Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => onChanged(!value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: value ? AppColors.accentSoft : AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: value
                      ? AppColors.accent.withValues(alpha: 0.5)
                      : AppColors.border,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 22,
                    color: value ? AppColors.accent : AppColors.textMuted,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: T.small(color: AppColors.text),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          value ? 'On' : 'Off',
                          style: T.caption(
                            color: value
                                ? AppColors.accent
                                : AppColors.textFaint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            const SheetTitle('Story tools'),
            Row(
              children: [
                toggle(
                  Icons.graphic_eq,
                  'Sound effects',
                  s.sfxEnabled,
                  (v) => s.update((s) => s.sfxEnabled = v),
                ),
                const SizedBox(width: 10),
                toggle(
                  Icons.keyboard_outlined,
                  'Typewriter',
                  s.typewriter,
                  (v) => s.update((s) => s.typewriter = v),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                toggle(
                  Icons.music_note_outlined,
                  'Music',
                  s.musicEnabled,
                  (v) => s.update((s) => s.musicEnabled = v),
                ),
                const SizedBox(width: 10),
                toggle(
                  Icons.water_drop_outlined,
                  'Ambient sound',
                  s.ambienceEnabled,
                  (v) => s.update((s) => s.ambienceEnabled = v),
                ),
              ],
            ),
            const SizedBox(height: 12),
            RowGroup(
              children: [
                if (host.isAi)
                  ListRow(
                    leading: const Icon(Icons.diversity_1_outlined, size: 20),
                    title: 'Bring a companion',
                    subtitle: 'A friend joins this story, with their memories',
                    onTap: () => go(() => pickCompanionFor(context, host)),
                  ),
                ListRow(
                  leading: const Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 20,
                  ),
                  title: 'Wallet',
                  subtitle: 'Money, transfers, debts and prices',
                  onTap: () => go(() => openFinance(context, host)),
                ),
                ListRow(
                  leading: const Icon(Icons.psychology_outlined, size: 20),
                  title: 'AI tools',
                  subtitle: 'Ideas, recap, lore, diary and AI switches',
                  onTap: () => go(() => showAiTools(context, host)),
                ),
                ListRow(
                  leading: const Icon(Icons.sticky_note_2_outlined, size: 20),
                  title: 'Notes',
                  subtitle: 'Your story notebook',
                  onTap: () => go(() => openNotes(context, host)),
                ),
                ListRow(
                  leading: const Icon(Icons.casino_outlined, size: 20),
                  title: 'Roll a die',
                  subtitle: 'Any die, no strings attached',
                  onTap: () => go(() => showQuickRoll(context)),
                ),
                if (dnd != null) ...[
                  ListRow(
                    leading: const Icon(
                      Icons.local_fire_department_outlined,
                      size: 20,
                    ),
                    title: 'Camp & companions',
                    subtitle: 'Downtime and personal quests',
                    onTap: () => go(
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CampScreen(controller: dnd),
                        ),
                      ),
                    ),
                  ),
                  ListRow(
                    leading: const Icon(Icons.public, size: 20),
                    title: 'World memory',
                    subtitle: 'Browse the consequences of your actions',
                    onTap: () => go(
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => WorldMemoryScreen(
                            world: () => dnd.adventure.chronicle,
                            listenable: dnd,
                            onChanged: () {
                              dnd.refresh();
                              dnd.save();
                            },
                            chapterId: dnd.storyId,
                            chapterTitle: dnd.storyTitle,
                            turn: dnd.turns,
                          ),
                        ),
                      ),
                    ),
                  ),
                  ListRow(
                    leading: const Icon(Icons.help_outline, size: 20),
                    title: 'Ask the oracle',
                    subtitle:
                        'Yes/no questions to fate · chaos ${dnd.adventure.chaos}',
                    onTap: () => go(() => showOracleFor(context, dnd)),
                  ),
                  ListRow(
                    leading: const Icon(Icons.undo, size: 20),
                    title: 'Rewind last turn',
                    subtitle: dnd.adventure.hardcore
                        ? 'Not available in hardcore mode'
                        : (dnd.canRewind
                              ? 'Undo your last choice'
                              : 'Nothing to rewind'),
                    onTap: dnd.canRewind
                        ? () => go(() {
                            dnd.rewind();
                            showToast(
                              context,
                              'Rewound to before your last action',
                              icon: Icons.undo,
                            );
                          })
                        : null,
                  ),
                ],
                if (host.canRegenerate)
                  ListRow(
                    leading: const Icon(Icons.refresh, size: 20),
                    title: 'Regenerate last turn',
                    subtitle: 'Ask the storyteller to write it again',
                    onTap: () => go(host.regenerate),
                  ),
                ListRow(
                  leading: const Icon(Icons.insights_outlined, size: 20),
                  title: 'Story overview',
                  subtitle: 'Stats and setup',
                  onTap: () => go(() => showStoryOverview(context, host)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...storyLayoutRows(context, sheet, host),
          ],
        );
      },
    );
  },
);

/// A quick die roll outside any check.
Future<void> showQuickRoll(BuildContext context) =>
    DiceCheckSheet.show(context, label: 'Roll', modifier: 0);

void showOracleFor(BuildContext context, AdventureController ctl) =>
    showOracleSheet(context, ctl);

/// Lets the player bring one of their companions into [host].
Future<void> pickCompanionFor(BuildContext context, StoryHost host) async {
  final store = CompanionStore.instance;
  final here = {for (final (c, _) in store.inStory(host.storyId)) c.id};
  final options = [for (final c in store.companions) if (!here.contains(c.id)) c];
  final picked = await showAppSheet<Companion>(
    context,
    builder: (ctx) => ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        const SheetTitle('Bring a companion', subtitle: 'They join this story and remember it afterwards'),
        if (options.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(store.companions.isEmpty ? 'You have no companions yet. Make one from the home screen, or tap "Make a companion" on anyone\'s profile.' : 'All your companions are already here.', style: T.small()),
          ),
        if (options.isNotEmpty)
          RowGroup(children: [
            for (final c in options)
              ListRow(
                leading: CompanionAvatar(companion: c, size: 40),
                title: c.name,
                subtitle: [c.subtitle, c.bond.label].where((s) => s.isNotEmpty).join(' · '),
                onTap: () => Navigator.pop(ctx, c),
              ),
          ]),
        const SizedBox(height: 12),
        AppButton(
          label: 'New companion',
          icon: Icons.add,
          kind: ButtonKind.secondary,
          onPressed: () async {
            final c = await Navigator.of(ctx).push<Companion>(MaterialPageRoute(builder: (_) => const CompanionEditor()));
            if (c != null && ctx.mounted) Navigator.pop(ctx, c);
          },
        ),
      ],
    ),
  );
  if (picked == null || !context.mounted) return;
  final why = host.bringCompanion(picked);
  showToast(context, why ?? '${picked.name} joins you', icon: why == null ? Icons.diversity_1_outlined : Icons.info_outline);
}
