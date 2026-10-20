import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/tale_genres.dart';
import '../../../services/achievements.dart';
import '../../../services/game_store.dart';
import '../../../services/settings.dart';
import '../../../services/tale_store.dart';
import '../../../theme/ui.dart';
import '../achievements_screen.dart';
import 'profile_editor.dart';
import '../home_screen.dart' show openAdventure;
import '../story/story_extras.dart' show fmtDuration;
import '../tales/tales_hub.dart' show openTale;

/// You, at a glance: name, lifetime stats and your latest stories.
class ProfileCard extends StatelessWidget {
  const ProfileCard({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsController>();
    final store = context.watch<GameStore>();
    final tales = context.watch<TaleStore>();
    final ach = context.watch<Achievements>();
    final name = s.playerName.trim().isEmpty ? 'Adventurer' : s.playerName.trim();
    final stories = <(String id, String title, String sub, DateTime at, int secs, bool tale)>[
      for (final a in store.adventures) (a.id, a.title, '${a.heroName} · ${a.turns} turns', a.updatedAt, a.playSeconds, false),
      for (final t in tales.tales) (t.id, t.title, '${genreById(t.genre).name} · ${t.turns} turns', t.updatedAt, t.playSeconds, true),
    ]..sort((x, y) => y.$4.compareTo(x.$4));
    final played = ach.stat(Stat.playSeconds);
    final finished = ach.stat(Stat.completed) + ach.stat(Stat.talesFinished);
    Widget stat(String value, String label) => Expanded(
          child: Column(children: [
            FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: T.number(18))),
            const SizedBox(height: 2),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.caption()),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppCard(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Row(children: [
            const ProfileAvatar(size: 60, viewable: true),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: T.h2(), overflow: TextOverflow.ellipsis),
                Text('${ach.unlockedCount} achievements · ${fmtDuration(played)} played', style: T.small()),
              ]),
            ),
            IconButton(
              tooltip: 'Edit profile',
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileEditorScreen())),
            ),
          ]),
          if (s.playerBio.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerLeft, child: Text(s.playerBio.trim(), style: T.small(color: AppColors.text), maxLines: 4, overflow: TextOverflow.ellipsis)),
          ] else ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileEditorScreen())),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add a picture and a bio'),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(children: [
            stat('${stories.length}', 'Stories'),
            stat(fmtDuration(played), 'Played'),
            stat('${ach.stat(Stat.turns) + tales.tales.fold<int>(0, (n, t) => n + t.turns)}', 'Turns'),
            stat('$finished', 'Finished'),
          ]),
          const SizedBox(height: 12),
          AppButton(
            label: 'Achievements & stats',
            icon: Icons.emoji_events_outlined,
            kind: ButtonKind.secondary,
            height: 40,
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AchievementsScreen())),
          ),
        ]),
      ),
      if (stories.isNotEmpty) ...[
        const SectionLabel('Your stories'),
        RowGroup(children: [
          for (final x in stories.take(5))
            ListRow(
              leading: Icon(x.$6 ? Icons.menu_book_outlined : Icons.shield_outlined, size: 20),
              title: x.$2,
              subtitle: '${x.$3}${x.$5 > 0 ? ' · ${fmtDuration(x.$5)}' : ''}',
              trailing: const Icon(Icons.play_arrow_rounded, size: 20, color: AppColors.textFaint),
              onTap: () => x.$6 ? openTale(context, x.$1) : openAdventure(context, x.$1),
            ),
        ]),
      ],
    ]);
  }
}
