import 'package:flutter/material.dart';

import '../../../game/adventure_controller.dart';
import '../../../theme/ui.dart';
import '../story/story_tools.dart' show ApproachBanner;
import '../story/world_memory_screen.dart';

class CampScreen extends StatelessWidget {
  const CampScreen({super.key, required this.controller});
  final AdventureController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final ctl = controller;
      final a = ctl.adventure;
      final town = const {'town', 'tavern', 'temple', 'castle'}.contains(a.scene.location);
      void result(String text) => showToast(context, text);
      return Scaffold(
        appBar: AppBar(title: const Text('Camp & companions')),
        bottomNavigationBar: SafeArea(top: false, child: ContentWidth(child: ApproachBanner(host: ctl))),
        body: ContentWidth(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Day ${a.chronicle.day} · ${a.scene.title.isEmpty ? 'On the road' : a.scene.title}', style: T.h2()),
              const SizedBox(height: 8),
              Text(
                ctl.canDowntime
                    ? 'Choose one activity. It spends a day; continue the story to unlock another. Resting is separate.'
                    : 'Activities are unavailable during combat, pending rolls, or after using this turn’s downtime. Continue the story to return to camp.',
                style: T.small(),
              ),
              const SectionLabel('Downtime'),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: !ctl.busy && !ctl.inCombat && ctl.pendingRoll == null && !a.finished && !a.hero.dead
                        ? () => result(
                            ctl.restFromMenu(long: false) ?? (ctl.inCombat ? 'Your rest was interrupted. Return to the adventure.' : 'Short rest completed.'),
                          )
                        : null,
                    child: const Text('Short rest'),
                  ),
                  OutlinedButton(
                    onPressed: !ctl.busy && !ctl.inCombat && ctl.pendingRoll == null && !a.finished && !a.hero.dead
                        ? () => result(
                            ctl.restFromMenu(long: true) ?? (ctl.inCombat ? 'Your camp was ambushed. Return to the adventure.' : 'Long rest completed.'),
                          )
                        : null,
                    child: const Text('Long rest'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('Long rests use rations and have an 8-turn cooldown. Resting in the wilderness risks an ambush.', style: T.caption()),
              const SizedBox(height: 12),
              RowGroup(
                children: [
                  for (final (id, title, detail, needsTown) in const [
                    ('train', 'Train', 'Gain Inspiration for your next check', false),
                    ('craft', 'Brew a healing potion', '25 gp · Medicine or Arcana DC 13 · ingredients lost on failure', false),
                    ('work', 'Work in town', 'Earn gold with a skill check', true),
                    ('carouse', 'Gather rumors', '5 gp · learn a rumor from the locals', true),
                    ('research', 'Research', 'History or Investigation DC 12 · uncover a clue', true),
                  ])
                    ListRow(
                      title: title,
                      subtitle: '$detail${needsTown && !town ? ' · requires a settlement' : ''}',
                      onTap: ctl.canDowntime && (!needsTown || town) ? () => result(ctl.downtime(id)) : null,
                    ),
                ],
              ),
              const SectionLabel('Companion stories'),
              if (a.companions.isEmpty) const Text('Recruit companions during your adventures to share camp and discover their stories.'),
              for (final c in a.companions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AppCard(
                    child: Builder(
                      builder: (context) {
                        final arc = a.chronicle.arcs[c.id];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.name, style: T.h3()),
                            Text('Loyalty ${c.loyalty}/100 · ${c.loyaltyLabel}', style: T.caption()),
                            const SizedBox(height: 8),
                            Text(arc == null ? 'At 60 loyalty, they will share a personal quest.' : '${arc.title} · ${arc.stage}', style: T.body()),
                            if (arc != null) ...[
                              const SizedBox(height: 6),
                              Text(arc.description, style: T.small()),
                              if (arc.outcome.isNotEmpty) Text(arc.outcome, style: T.small()),
                              if (!arc.ended && arc.stage != 'choice')
                                Text('Leads secured: ${arc.progress}/2. Follow two leads, or complete the quest through the story.', style: T.small()),
                            ],
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton(
                                  onPressed: ctl.canDowntime && !c.dead ? () => result(ctl.spendTimeWith(c)) : null,
                                  child: const Text('Spend time · +5 loyalty'),
                                ),
                                if (arc != null && !arc.ended && arc.stage != 'choice')
                                  OutlinedButton(
                                    onPressed: ctl.canDowntime && !c.dead ? () => result(ctl.pursueCompanionLead(c)) : null,
                                    child: const Text('Follow a lead · DC 12'),
                                  ),
                              ],
                            ),
                            if (arc?.stage == 'choice') ...[
                              const SizedBox(height: 8),
                              Text('Choose how this story ends. The decision and its rewards will be remembered.', style: T.small()),
                              TextButton(
                                onPressed: !ctl.busy && !ctl.inCombat && ctl.pendingRoll == null && !c.dead
                                    ? () => result(ctl.resolveCompanionArc(c, fulfill: true))
                                    : null,
                                child: const Text('Fulfill their goal · +10 loyalty, companion Inspiration'),
                              ),
                              TextButton(
                                onPressed: !ctl.busy && !ctl.inCombat && ctl.pendingRoll == null && !c.dead
                                    ? () => result(ctl.resolveCompanionArc(c, fulfill: false))
                                    : null,
                                child: const Text('Choose a new path · +5 loyalty, Inspiration for both'),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                ),
              for (final arc in a.chronicle.arcs.values.where((arc) => !a.companions.any((c) => c.id == arc.companionId)))
                ListTile(title: Text('${arc.name} · ${arc.stage}'), subtitle: Text('${arc.title}\n${arc.outcome}')),
              const SizedBox(height: 12),
              AppButton(
                label: 'Browse world consequences',
                icon: Icons.public,
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => WorldMemoryScreen(
                      world: () => ctl.adventure.chronicle,
                      listenable: ctl,
                      onChanged: () {
                        ctl.refresh();
                        ctl.save();
                      },
                      chapterId: a.id,
                      chapterTitle: a.title,
                      turn: a.turns,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
