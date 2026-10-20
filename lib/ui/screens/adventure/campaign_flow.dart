import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/modules.dart';
import '../../../game/adventure_controller.dart';
import '../../../game/module_engine.dart';
import '../../../models/adventure.dart';
import '../../../models/campaign.dart';
import '../../../models/character.dart';
import '../../../services/ai/dungeon_master.dart';
import '../../../services/export.dart';
import '../../../services/game_store.dart';
import '../../../services/settings.dart';
import '../../../theme/ui.dart';
import 'adventure_screen.dart';
import 'text_adventure_screen.dart';

/// Next module in a handcrafted series, if any.
AdventureModule? nextSeriesModule(Adventure a) {
  if (a.engine != StoryEngine.module) return null;
  final id = a.offline['module'];
  final cur = id is String ? moduleById(id) : null;
  if (cur?.seriesId == null) return null;
  return adventureModules.where((m) => m.seriesId == cur!.seriesId && m.part == cur.part + 1).firstOrNull;
}

/// Buttons shown when an adventure ends.
class FinishedActions extends StatelessWidget {
  const FinishedActions({super.key, required this.controller});
  final AdventureController controller;

  @override
  Widget build(BuildContext context) {
    final a = controller.adventure;
    final store = context.watch<GameStore>();
    final camp = store.campaign(a.campaignId);
    final next = nextSeriesModule(a);
    final dead = a.hero.dead;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (camp != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('${camp.name} · chapter ${camp.chapters.indexOf(a.id) + 1} of ${camp.chapters.length}', style: T.caption()),
        ),
      if (!dead)
        AppButton(
          label: next != null ? 'Continue: ${next.title}' : (camp != null ? 'Next chapter' : 'Continue as a campaign'),
          icon: Icons.auto_stories_outlined,
          kind: ButtonKind.accent,
          onPressed: () => startNextChapter(context, controller.adventure),
        ),
      const SizedBox(height: 8),
      AppButton(label: 'Export journal', icon: Icons.ios_share, kind: ButtonKind.secondary, onPressed: () => showExportSheet(context, a)),
    ]);
  }
}

/// Carries the hero, party, people and memory into a new chapter.
Future<void> startNextChapter(BuildContext context, Adventure prev) async {
  final store = context.read<GameStore>();
  final settings = context.read<SettingsController>();
  var camp = store.campaign(prev.campaignId);
  if (camp == null) {
    final name = await _askName(context, '${prev.hero.name.split(' ').first}\'s Saga');
    if (name == null || !context.mounted) return;
    camp = Campaign(id: newId(), name: name, heroId: prev.hero.id, chapters: [prev.id]);
    final next0 = nextSeriesModule(prev);
    if (next0 != null) camp.seriesId = next0.seriesId;
    prev.campaignId = camp.id;
  }
  // Merge this chapter's canon and summary into the campaign.
  for (final c in prev.canon) {
    camp.canon.removeWhere((x) => x.name.toLowerCase() == c.name.toLowerCase());
    camp.canon.add(CanonEntry(id: c.id, kind: c.kind, name: c.name, text: c.text, pinned: c.pinned));
  }
  final chapterNo = camp.chapters.length;
  final recap = prev.memory.isNotEmpty ? prev.memory : prev.log.where((e) => e.kind == LogKind.narration).map((e) => e.text).toList().reversed.take(2).toList().reversed.join(' ');
  camp.summary = [if (camp.summary.isNotEmpty) camp.summary, 'Chapter $chapterNo, "${prev.title}": ${recap.length > 600 ? '${recap.substring(0, 600)}…' : recap}'].join('\n');
  await store.saveAdventure(prev, syncHero: false);

  final hero = (store.character(prev.hero.id) ?? prev.hero).clone();
  hero.hp = hero.maxHp;
  hero.conditions.clear();
  final companions = [for (final c in prev.companions) c.clone()..hp = c.maxHp];
  final next = nextSeriesModule(prev);
  final engine = next != null ? StoryEngine.module : (prev.engine == StoryEngine.ai && settings.useAiText ? StoryEngine.ai : StoryEngine.offline);
  var title = next?.title ?? '${camp.name}: Chapter ${chapterNo + 1}';
  var premise = next?.tagline ?? 'The story continues. Previously: ${camp.summary.split('\n').last}';
  if (engine == StoryEngine.ai) {
    try {
      final p = await AiDungeonMaster(settings).premise(setting: prev.setting, tone: prev.tone, hero: hero, seedIdea: 'A new chapter of an ongoing campaign. Story so far:\n${camp.summary}\nOpen threads: ${prev.quests.where((q) => q.status == QuestStatus.active).map((q) => q.title).join(', ')}');
      title = p['title'] ?? title;
      premise = p['premise'] ?? premise;
    } catch (_) {}
  }
  final seed = DateTime.now().millisecondsSinceEpoch & 0xffffff;
  final adv = Adventure(
    id: newId(),
    title: title,
    premise: premise,
    hero: hero,
    engine: engine,
    setting: next != null ? next.setting[0].toUpperCase() + next.setting.substring(1) : prev.setting,
    tone: next?.tone ?? prev.tone,
    difficulty: prev.difficulty,
    textMode: prev.textMode,
    companions: companions,
    coverSeed: seed,
    npcs: [for (final n in prev.npcs) n],
    quests: [for (final q in prev.quests.where((q) => q.status == QuestStatus.active)) q],
    canon: [for (final c in camp.canon) CanonEntry(id: newId(), kind: c.kind, name: c.name, text: c.text, pinned: c.pinned)],
    memory: camp.summary,
    scene: SceneInfo(title: 'The Beginning', location: next?.coverLoc ?? prev.scene.location, time: next?.coverTime ?? 'dawn', mood: 'mystery', seed: seed),
    offline: next == null ? null : ModuleEngine.createState(next.id),
    campaignId: camp.id,
    hardcore: prev.hardcore,
    showDcs: prev.showDcs,
    chaos: prev.chaos,
  );
  camp.chapters.add(adv.id);
  await store.saveCampaign(camp);
  await store.saveAdventure(adv, syncHero: false);
  if (!context.mounted) return;
  Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => adv.textMode ? TextAdventureScreen(adventure: adv) : AdventureScreen(adventure: adv)));
}

Future<String?> _askName(BuildContext context, String initial) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Name your campaign'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Your hero, companions, the people you met and everything remembered carry into the next chapter.', style: T.small()),
        const SizedBox(height: 14),
        TextField(controller: c, autofocus: true, style: T.body()),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: T.h3(color: AppColors.textMuted))),
        TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim().isEmpty ? initial : c.text.trim()), child: const Text('Begin')),
      ],
    ),
  );
}
