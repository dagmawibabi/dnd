import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../art/class_icon.dart';
import '../../data/presets.dart';
import '../../game/module_engine.dart';
import '../../models/adventure.dart';
import '../../models/character.dart';
import '../../services/achievements.dart';
import '../../services/audio/audio_service.dart';
import '../../services/game_store.dart';
import '../../services/settings.dart';
import '../../theme/ui.dart';
import '../widgets/portrait.dart';
import 'adventure/adventure_screen.dart';
import 'adventure/new_adventure_screen.dart';
import 'achievements_screen.dart';
import 'adventure/text_adventure_screen.dart';
import 'campaign_screen.dart';
import 'character/character_creator.dart';
import 'character/character_sheet.dart';
import 'compendium_screen.dart';
import '../../data/tales/tales.dart';
import 'tales/tales_hub.dart';
import 'dice_tray_screen.dart';
import 'settings/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  /// Set by onboarding: 'tutorial' or 'create'.
  static String? pendingAction;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AudioService>().stopMusic();
      final action = HomeScreen.pendingAction;
      HomeScreen.pendingAction = null;
      if (action == 'tutorial') startTutorial(context);
      if (action == 'create') Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CharacterCreator(thenStartAdventure: true)));
      if (action != null && action.startsWith('tale:')) {
        final p = taleById(action.substring(5));
        if (p != null) startPreset(context, p);
      }
      if (action == 'tale_ai') showNewTaleSheet(context);
    });
  }

  static const _dests = [
    (Icons.home_outlined, Icons.home, 'Home'),
    (Icons.people_outline, Icons.people, 'Characters'),
    (Icons.menu_book_outlined, Icons.menu_book, 'Compendium'),
    (Icons.casino_outlined, Icons.casino, 'Dice'),
    (Icons.settings_outlined, Icons.settings, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    // Text adventure mode hides the D&D-only tabs (characters, compendium).
    final tales = context.select<SettingsController, bool>((s) => s.homeMode == 'tales');
    final visible = tales ? const [0, 3, 4] : const [0, 1, 2, 3, 4];
    final allPages = [const _HomeTab(), const CharactersTab(), const CompendiumScreen(embedded: true), const DiceTrayScreen(embedded: true), const SettingsScreen(embedded: true)];
    final pages = [for (final i in visible) allPages[i]];
    final dests = [for (final i in visible) _dests[i]];
    if (_tab >= pages.length) _tab = 0;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final body = IndexedStack(index: _tab, children: pages);
    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              labelType: NavigationRailLabelType.all,
              groupAlignment: -0.9,
              destinations: [for (final d in dests) NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3))],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(),
          NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: [for (final d in dests) NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3)],
          ),
        ],
      ),
    );
  }
}

Future<void> openAdventure(BuildContext context, String id) async {
  final adv = await context.read<GameStore>().loadAdventure(id);
  if (!context.mounted) return;
  if (adv == null) {
    showToast(context, 'This save could not be loaded.', icon: Icons.error_outline);
    return;
  }
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => adv.textMode ? TextAdventureScreen(adventure: adv) : AdventureScreen(adventure: adv),
    ),
  );
}

void startNewAdventure(BuildContext context) {
  final store = context.read<GameStore>();
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => store.characters.isEmpty ? const CharacterCreator(thenStartAdventure: true) : const NewAdventureScreen()));
}

/// Starts the guided tutorial with the first hero (or a preset).
Future<void> startTutorial(BuildContext context) async {
  final store = context.read<GameStore>();
  var hero = store.characters.isNotEmpty ? store.characters.first : null;
  if (hero == null) {
    hero = presets[1].create();
    await store.saveCharacter(hero);
  }
  final mod = moduleById('tutorial')!;
  final seed = DateTime.now().millisecondsSinceEpoch & 0xffffff;
  final adv = Adventure(
    id: newId(),
    title: mod.title,
    premise: mod.tagline,
    hero: hero.clone()..inventory.add(InventoryItem.of('rations', qty: 3)),
    engine: StoryEngine.module,
    setting: mod.setting,
    tone: mod.tone,
    coverSeed: seed,
    scene: SceneInfo(title: 'The Beginning', location: mod.coverLoc, time: mod.coverTime, mood: 'mystery', seed: seed),
    offline: ModuleEngine.createState(mod.id),
  );
  await store.saveAdventure(adv, syncHero: false);
  if (!context.mounted) return;
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdventureScreen(adventure: adv)));
}

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'Just now';
  if (d.inHours < 1) return '${d.inMinutes}m ago';
  if (d.inDays < 1) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  return '${t.day}/${t.month}/${t.year}';
}

class _HomeTab extends StatelessWidget {
  const _HomeTab();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<GameStore>();
    final settings = context.watch<SettingsController>();
    final ach = context.watch<Achievements>();
    final active = store.adventures.where((a) => !a.finished).toList();
    final latest = active.isEmpty ? null : active.first;
    final others = store.adventures.where((a) => a != latest).toList();
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good morning' : (hour < 18 ? 'Good afternoon' : 'Good evening');
    return SafeArea(
      child: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            PageHeader(
              title: settings.playerName.isEmpty ? greeting : '$greeting, ${settings.playerName}',
              subtitle: switch (settings.aiMode) {
                AiMode.both => 'AI story and images on',
                AiMode.text => 'AI story on',
                AiMode.images => 'AI images on',
                AiMode.none => 'Offline mode',
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 4),
                  const _ModeSwitch(),
                  const SizedBox(height: 16),
                  if (settings.homeMode == 'tales')
                    const TalesHub()
                  else ...[
                    if (latest != null) ...[_ContinueCard(summary: latest), const SizedBox(height: 12)],
                    Row(
                      children: [
                        Expanded(
                          child: _ActionTile(icon: Icons.add, title: 'New adventure', onTap: () => startNewAdventure(context), primary: latest == null),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _ActionTile(
                            icon: Icons.person_add_alt,
                            title: 'New character',
                            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CharacterCreator())),
                          ),
                        ),
                      ],
                    ),
                    if (store.characters.isNotEmpty) ...[
                      SectionLabel('Characters', trailing: Text('${store.characters.length}', style: T.caption())),
                      SizedBox(
                        height: 92,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: store.characters.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 14),
                          itemBuilder: (ctx, i) {
                            final c = store.characters[i];
                            return InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CharacterSheetScreen(characterId: c.id))),
                              child: SizedBox(
                                width: 64,
                                child: Column(
                                  children: [
                                    CharacterPortrait(character: c, size: 60),
                                    const SizedBox(height: 6),
                                    Text(
                                      c.name.split(' ').first,
                                      style: T.caption(color: AppColors.textMuted),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    if (store.campaigns.isNotEmpty) ...[
                      SectionLabel('Campaigns', trailing: Text('${store.campaigns.length}', style: T.caption())),
                      RowGroup(
                        children: [
                          for (final c in store.campaigns)
                            ListRow(
                              leading: const Icon(Icons.auto_stories_outlined, size: 20),
                              title: c.name,
                              subtitle: '${store.character(c.heroId)?.name ?? ''} · ${c.chapters.length} ${c.chapters.length == 1 ? 'chapter' : 'chapters'}',
                              trailing: const Icon(Icons.chevron_right, size: 18, color: AppColors.textFaint),
                              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CampaignScreen(campaignId: c.id))),
                            ),
                        ],
                      ),
                    ],
                    if (store.adventures.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      AppCard(
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AchievementsScreen())),
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            const Icon(Icons.emoji_events_outlined, size: 20, color: AppColors.warning),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Achievements', style: T.h3()),
                                  const SizedBox(height: 6),
                                  Bar(value: ach.unlockedCount, max: achievementDefs.length, color: AppColors.warning),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text('${ach.unlockedCount}/${achievementDefs.length}', style: T.caption(color: AppColors.textMuted)),
                            const SizedBox(width: 4),
                            const Icon(Icons.chevron_right, size: 18, color: AppColors.textFaint),
                          ],
                        ),
                      ),
                    ],
                    if (others.isNotEmpty) ...[
                      const SectionLabel('Adventures'),
                      RowGroup(children: [for (final a in others) _AdventureRow(summary: a)]),
                    ],
                    if (store.adventures.isEmpty) ...[
                      const SizedBox(height: 12),
                      AppCard(
                        onTap: () => startTutorial(context),
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            const Icon(Icons.school_outlined, size: 20, color: AppColors.accent),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('New to DnD?', style: T.h3()),
                                  Text('Play the 3-minute guided tutorial.', style: T.small()),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right, size: 18, color: AppColors.textFaint),
                          ],
                        ),
                      ),
                    ],
                    if (store.adventures.isEmpty && store.characters.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 40),
                        child: EmptyState(icon: Icons.auto_stories_outlined, title: 'No adventures yet', message: 'Create a character or pick a preset, then start your first adventure.'),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Switches the home screen between D&D and text adventures.
class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsController>();
    Widget option(String id, IconData icon, String title, String sub) {
      final on = s.homeMode == id;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          child: GestureDetector(
            onTap: () {
              if (!on) {
                context.read<AudioService>().play('page');
                s.update((s) => s.homeMode = id);
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              decoration: BoxDecoration(color: on ? AppColors.surface3 : Colors.transparent, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: on ? AppColors.text : AppColors.textFaint),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(title, style: T.h3(color: on ? AppColors.text : AppColors.textMuted), maxLines: 1),
                        ),
                        Text(sub, style: T.caption(), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [option('dnd', Icons.shield_outlined, 'D&D', 'Heroes & dice'), const SizedBox(width: 4), option('tales', Icons.menu_book_outlined, 'Text adventures', 'Any genre')],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.title, required this.onTap, this.primary = false});
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      color: primary ? AppColors.text : AppColors.surface,
      borderColor: primary ? AppColors.text : null,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: primary ? AppColors.bg : AppColors.text),
          const SizedBox(height: 18),
          Text(title, style: T.h3(color: primary ? AppColors.bg : AppColors.text)),
        ],
      ),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.summary});
  final AdventureSummary summary;

  @override
  Widget build(BuildContext context) {
    final store = context.read<GameStore>();
    final hero = store.characters.where((c) => c.name == summary.heroName).firstOrNull;
    final portrait = summary.heroPortrait == null ? null : PortraitSpec.fromJson(summary.heroPortrait!);
    return AppCard(
      onTap: () => openAdventure(context, summary.id),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('CONTINUE', style: T.overline(color: AppColors.accent)),
              const Spacer(),
              Text(_ago(summary.updatedAt), style: T.caption()),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (portrait != null) PortraitView(spec: portrait, raceId: hero?.raceId ?? 'human', classId: hero?.classLevels.keys.first, size: 48),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(summary.title, style: T.h2(), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text('${summary.heroName} · Level ${summary.level} · ${summary.turns} turns', style: T.small(), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(color: AppColors.text, shape: BoxShape.circle),
                child: const Icon(Icons.play_arrow_rounded, color: AppColors.bg),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Bar(value: summary.hp, max: summary.maxHp, color: AppColors.hp),
              ),
              const SizedBox(width: 10),
              Text('${summary.hp}/${summary.maxHp} HP', style: T.caption()),
            ],
          ),
        ],
      ),
    );
  }
}

class _AdventureRow extends StatelessWidget {
  const _AdventureRow({required this.summary});
  final AdventureSummary summary;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(summary.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: AppColors.danger.withValues(alpha: 0.15),
        child: const Icon(Icons.delete_outline, color: AppColors.danger),
      ),
      confirmDismiss: (_) => confirm(context, title: 'Delete adventure?', message: '"${summary.title}" will be permanently deleted.'),
      onDismissed: (_) => context.read<GameStore>().deleteAdventure(summary.id),
      child: ListRow(
        title: summary.title,
        subtitle: '${summary.heroName} · ${summary.finished ? 'Completed' : _ago(summary.updatedAt)}${summary.textMode ? ' · Text mode' : ''}',
        leading: Icon(
          summary.finished
              ? Icons.emoji_events_outlined
              : (summary.engine == StoryEngine.ai ? Icons.auto_awesome_outlined : (summary.engine == StoryEngine.module ? Icons.menu_book_outlined : Icons.all_inclusive)),
          size: 20,
        ),
        onTap: () => openAdventure(context, summary.id),
      ),
    );
  }
}

class CharactersTab extends StatelessWidget {
  const CharactersTab({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<GameStore>();
    void create() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CharacterCreator()));
    return SafeArea(
      child: ContentWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Characters',
              trailing: CircleIconButton(icon: Icons.add, tooltip: 'New character', onPressed: create),
            ),
            Expanded(
              child: store.characters.isEmpty
                  ? EmptyState(
                      icon: Icons.person_outline,
                      title: 'No characters yet',
                      message: 'Create one from scratch or choose a preset.',
                      action: AppButton(label: 'New character', icon: Icons.add, expand: false, onPressed: create),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                      children: [
                        RowGroup(children: [for (final c in store.characters) _CharacterRow(character: c)]),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CharacterRow extends StatelessWidget {
  const _CharacterRow({required this.character});
  final Character character;

  @override
  Widget build(BuildContext context) {
    final c = character;
    return ListRow(
      leading: CharacterPortrait(character: c, size: 44),
      title: c.name,
      subtitle: 'Level ${c.level} ${c.raceLabel} · ${c.classSummary}',
      trailing: ClassIcon(classId: c.primaryClass.id, size: 30),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CharacterSheetScreen(characterId: c.id))),
    );
  }
}
