import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/tale_genres.dart';
import '../../../game/tale_controller.dart';
import '../../../models/adventure.dart';
import '../../../models/tale.dart';
import '../../../services/achievements.dart';
import '../../../services/audio/audio_service.dart';
import '../../../services/image_service.dart';
import '../../../services/narrator.dart';
import '../../../services/settings.dart';
import '../../../services/tale_store.dart';
import '../../../services/usage.dart';
import '../../../theme/ui.dart';
import '../../widgets/portrait.dart';
import '../story/story_tools.dart';

TaleController createTaleController(BuildContext context, Tale tale) => TaleController(
      tale: tale,
      settings: context.read<SettingsController>(),
      store: context.read<TaleStore>(),
      audio: context.read<AudioService>(),
      narrator: context.read<Narrator>(),
      usage: context.read<UsageTracker>(),
      achievements: context.read<Achievements>(),
      images: context.read<ImageService>(),
    );

/// Text adventure journal: Goals and Items, then People, Memory and Gallery.
Future<void> showTaleJournal(BuildContext context, TaleController ctl, {String? initial}) => showStoryJournal(
      context,
      ctl,
      initial: initial,
      leading: [
        ('Goals', (_) => _GoalsTab(ctl: ctl)),
        ('Items', (_) => _ItemsTab(ctl: ctl)),
      ],
    );

class _GoalsTab extends StatelessWidget {
  const _GoalsTab({required this.ctl});
  final TaleController ctl;

  @override
  Widget build(BuildContext context) {
    final goals = ctl.tale.goals;
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (ctl.tale.premise.isNotEmpty) ...[
        Text(ctl.tale.premise, style: T.small(color: AppColors.textMuted)),
        const SizedBox(height: 12),
      ],
      if (goals.isEmpty) EmptyState(icon: Icons.flag_outlined, title: 'No goals yet', message: ctl.isAi ? 'The story sets goals as it unfolds.' : 'Handcrafted stories keep their goals secret.'),
      if (goals.isNotEmpty)
        RowGroup(children: [
          for (final q in goals.reversed)
            ListRow(
              leading: Icon(
                q.status == QuestStatus.completed ? Icons.check_circle : (q.status == QuestStatus.failed ? Icons.cancel_outlined : Icons.radio_button_unchecked),
                size: 20,
                color: q.status == QuestStatus.completed ? AppColors.success : (q.status == QuestStatus.failed ? AppColors.danger : AppColors.textMuted),
              ),
              title: q.title,
              subtitle: q.description.isEmpty ? null : q.description,
            ),
        ]),
    ]);
  }
}

class _ItemsTab extends StatelessWidget {
  const _ItemsTab({required this.ctl});
  final TaleController ctl;

  @override
  Widget build(BuildContext context) {
    final t = ctl.tale;
    final g = ctl.genre;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        Expanded(child: StatTile(label: g.healthLabel, value: '${t.health}/100')),
        const SizedBox(width: 8),
        Expanded(child: StatTile(label: 'Turns', value: '${t.turns}')),
        const SizedBox(width: 8),
        Expanded(child: StatTile(label: 'Items', value: '${t.inventory.length}')),
      ]),
      if (t.status.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Tag(t.status, icon: Icons.warning_amber_outlined, color: AppColors.warning)),
      const SectionLabel('Carrying'),
      if (t.inventory.isEmpty) const EmptyState(icon: Icons.backpack_outlined, title: 'Empty pockets'),
      if (t.inventory.isNotEmpty)
        RowGroup(children: [
          for (final i in t.inventory)
            ListRow(
              leading: const Icon(Icons.inventory_2_outlined, size: 18),
              title: i,
              trailing: t.finished || !ctl.isAi
                  ? null
                  : TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        ctl.freeText('I use the $i.');
                      },
                      child: const Text('Use'),
                    ),
            ),
        ]),
    ]);
  }
}

/// Health, status and the cast you can talk to — the text adventure's status bar.
class TaleStatusBar extends StatelessWidget {
  const TaleStatusBar({super.key, required this.ctl, this.mono = false});
  final TaleController ctl;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final t = ctl.tale;
    final g = ctl.genre;
    // The most recent speakers first.
    final recent = <Npc>[];
    for (final e in t.log.reversed) {
      final p = t.personNamed(e.speaker);
      if (p != null && !recent.contains(p)) recent.add(p);
      if (recent.length >= 4) break;
    }
    for (final p in t.npcs.reversed) {
      if (recent.length >= 4) break;
      if (!recent.contains(p)) recent.add(p);
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
      child: Row(children: [
        InkWell(
          onTap: () => showTaleJournal(context, ctl, initial: 'Items'),
          customBorder: const CircleBorder(),
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(shape: BoxShape.circle, color: g.color.withValues(alpha: 0.14), border: Border.all(color: g.color.withValues(alpha: 0.5))),
            child: Icon(g.icon, size: 15, color: g.color),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(g.healthLabel, style: mono ? T.mono(11, color: AppColors.textMuted) : T.caption()),
              const SizedBox(width: 6),
              Text('${t.health}/100', style: mono ? T.mono(11) : T.caption(color: AppColors.text)),
              const Spacer(),
              if (t.status.isNotEmpty) Flexible(child: Text(t.status, style: T.caption(color: AppColors.warning), overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 5),
            Bar(value: t.health, max: 100, color: t.health < 30 ? AppColors.danger : g.color),
          ]),
        ),
        for (final p in recent)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Tooltip(
              message: 'Talk to ${p.name}',
              child: InkWell(customBorder: const CircleBorder(), onTap: () => showCharacterChat(context, ctl, p), child: NpcPortrait(npc: p, size: 28)),
            ),
          ),
      ]),
    );
  }
}

/// The text adventure menu: shared story tools plus layout, font and sound.
void showTaleMenu(BuildContext context, TaleController ctl, {required bool terminal, required VoidCallback switchLayout, required VoidCallback restart}) {
  final s = context.read<SettingsController>();
  showAppSheet(context, builder: (ctx) => ListenableBuilder(
        listenable: s,
        builder: (ctx, _) => ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
          SheetTitle(ctl.tale.title, subtitle: '${ctl.genre.name} · ${ctl.isAi ? 'AI narrator' : 'Handcrafted'} · ${ctl.tale.turns} turns'),
          ...storyMenuRows(context, ctx, ctl),
          const SizedBox(height: 12),
          RowGroup(children: [
            ListRow(
              leading: Icon(terminal ? Icons.chrome_reader_mode_outlined : Icons.terminal, size: 20),
              title: terminal ? 'Switch to book layout' : 'Switch to terminal layout',
              subtitle: terminal ? 'Illustrated pages with tappable choices' : 'Classic monospace text with a > prompt',
              onTap: () {
                Navigator.pop(ctx);
                switchLayout();
              },
            ),
            ListRow(leading: const Icon(Icons.music_note_outlined, size: 20), title: 'Music', trailing: Switch(value: s.musicEnabled, onChanged: (v) => s.update((s) => s.musicEnabled = v))),
            ListRow(leading: const Icon(Icons.water_drop_outlined, size: 20), title: 'Ambient sound', trailing: Switch(value: s.ambienceEnabled, onChanged: (v) => s.update((s) => s.ambienceEnabled = v))),
            ListRow(
              leading: const Icon(Icons.replay, size: 20),
              title: 'Start over',
              subtitle: 'A fresh copy of this story; this one is kept',
              onTap: () {
                Navigator.pop(ctx);
                restart();
              },
            ),
          ]),
        ]),
      ));
}

/// A fresh copy of a story for "Play again" and "Start over".
Future<Tale> restartTale(BuildContext context, Tale old) async {
  final fresh = Tale.create(title: old.title, genre: old.genre, engine: old.engine, presetId: old.presetId, protagonist: old.protagonist, premise: old.premise)..terminal = old.terminal;
  await context.read<TaleStore>().save(fresh);
  return fresh;
}

TaleGenre genreOf(Tale t) => genreById(t.genre);
