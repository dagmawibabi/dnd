import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'story_extras.dart';
import '../../../art/scene_painter.dart';
import '../../../data/tale_genres.dart';
import '../../../game/archive_host.dart';
import '../../../models/adventure.dart';
import '../../../models/tale.dart';
import '../../../models/world.dart';
import '../../../services/ai/story_ai.dart';
import '../../../services/export.dart' show showStoryExport;
import '../../../services/game_store.dart';
import '../../../services/image_service.dart';
import '../../../services/narrator.dart';
import '../../../services/settings.dart';
import '../../../services/tale_store.dart';
import '../../../theme/ui.dart';
import '../../widgets/media_view.dart';
import '../../widgets/narrator_tone.dart';
import '../../widgets/portrait.dart';
import '../../widgets/share_cards.dart';
import '../adventure/adventure_screen.dart';
import '../adventure/text_adventure_screen.dart';
import '../tales/tales_hub.dart' show taleRoute;
import 'quest_sheet.dart';
import 'replay_screen.dart';
import 'story_tools.dart' show showPersonSheet;

/// Opens a D&D adventure's cover page.
Future<void> openAdventureCover(BuildContext context, String id) async {
  final adv = await context.read<GameStore>().loadAdventure(id);
  if (!context.mounted) return;
  if (adv == null) {
    showToast(context, 'This save could not be loaded.', icon: Icons.error_outline);
    return;
  }
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => StoryCoverScreen(record: adv)));
}

/// Opens a text adventure's cover page.
Future<void> openTaleCover(BuildContext context, String id) async {
  final t = await context.read<TaleStore>().load(id);
  if (t == null || !context.mounted) return;
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => StoryCoverScreen(record: t)));
}

/// Goes straight into a story (the cover's Continue button).
Future<void> playStory(BuildContext context, StoryRecord r) {
  if (r is Adventure) return Navigator.of(context).push(MaterialPageRoute(builder: (_) => r.textMode ? TextAdventureScreen(adventure: r) : AdventureScreen(adventure: r)));
  return Navigator.of(context).push(taleRoute(r as Tale));
}

/// A story's landing page: its art and premise, where you left off, who is in
/// it, what is still open, and the way back in.
class StoryCoverScreen extends StatefulWidget {
  const StoryCoverScreen({super.key, required this.record});
  final StoryRecord record;

  @override
  State<StoryCoverScreen> createState() => _StoryCoverScreenState();
}

class _StoryCoverScreenState extends State<StoryCoverScreen> {
  late final ArchiveHost host = ArchiveHost(
    widget.record,
    settings: context.read<SettingsController>(),
    images: context.read<ImageService>(),
    narrator: context.read<Narrator>(),
    onSave: _persist,
  );
  bool _recapping = false;
  bool _painting = false;
  String? _recap;

  /// Paints a fresh cover from the story so far; older covers stay in the gallery.
  Future<void> _paintCover() async {
    final images = context.read<ImageService>()..resume();
    final premise = adv?.premise ?? tale!.premise;
    setState(() => _painting = true);
    final path = await images.generate(
      'cover_${r.id}_${DateTime.now().millisecondsSinceEpoch}',
      'A striking cover illustration for the story "${host.storyTitle}". ${premise.isEmpty ? '' : '$premise '}${host.summary.isEmpty ? '' : 'So far: ${host.summary.length > 500 ? host.summary.substring(0, 500) : host.summary} '}Setting: ${host.scene.title}. ${host.worldStyle} Cinematic, atmospheric, no text or lettering.',
      size: '1024x1536',
      usageTarget: host.usageTotals,
      style: host.artStyle,
      category: 'images',
    );
    if (!mounted) return;
    setState(() => _painting = false);
    if (path == null) {
      showToast(context, images.errors.values.lastOrNull ?? 'The cover could not be painted', icon: Icons.error_outline);
      return;
    }
    host.world.addMedia(MediaItem(path: path, kind: 'scene', caption: 'Cover: ${host.storyTitle}', turn: host.turns, cost: images.costs[path] ?? 0));
    await _persist();
    if (mounted) setState(() {});
  }

  StoryRecord get r => widget.record;
  Adventure? get adv => r is Adventure ? r as Adventure : null;
  Tale? get tale => r is Tale ? r as Tale : null;

  Future<void> _persist() async {
    if (adv != null) {
      await context.read<GameStore>().saveAdventure(adv!, syncHero: false);
    } else {
      await context.read<TaleStore>().save(tale!);
    }
  }

  @override
  void initState() {
    super.initState();
    final last = host.world.aiNotes.reversed.where((n) => n.kind == 'recap').firstOrNull;
    if (last != null && last.turn == host.turns) _recap = last.text;
  }

  Future<void> _previously() async {
    final s = context.read<SettingsController>();
    if (!s.useAiText) {
      setState(() => _recap = host.summary.isNotEmpty ? host.summary : (host.log.lastWhere((e) => e.kind == LogKind.narration, orElse: () => LogEntry(kind: LogKind.narration, text: 'Nothing has happened yet.')).text));
      return;
    }
    setState(() => _recapping = true);
    try {
      final res = await StoryAi(s).recapOf(r);
      host.world.addAiNote(AiNote(kind: 'recap', title: 'Previously on…', text: res.value, turn: host.turns, tokens: res.tokens, cost: res.cost));
      await _persist();
      if (mounted) setState(() => _recap = res.value);
    } catch (e) {
      if (mounted) showToast(context, 'Couldn\'t write a recap: $e', icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _recapping = false);
    }
  }

  Future<void> _play() async {
    await playStory(context, r);
    if (mounted) setState(() {});
  }

  Future<void> _delete() async {
    if (!await confirm(context, title: 'Delete "${host.storyTitle}"?', message: 'This story and its pictures are permanently deleted.', action: 'Delete')) return;
    if (!mounted) return;
    if (adv != null) {
      await context.read<GameStore>().deleteAdventure(r.id);
    } else {
      await context.read<TaleStore>().delete(r.id);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final finished = adv?.finished ?? tale!.finished;
    final started = host.log.isNotEmpty;
    final premise = adv?.premise ?? tale!.premise;
    final g = tale == null ? null : genreById(tale!.genre);
    final s = host.scene;
    final cover = latestScenePicture(host.world.gallery) ?? r.sceneImagePath;
    final accent = g?.color ?? const Color(0xFFE0B354);
    final quests = questsOf(host);
    final open = quests.where((q) => q.status == QuestStatus.active).toList()..sort((a, b) => (b.tracked ? 1 : 0).compareTo(a.tracked ? 1 : 0));
    final cast = host.people;
    final pictures = host.world.gallery.reversed.where((m) => !m.video && m.kind != 'item').take(10).toList();
    final ending = tale?.ending ?? (adv?.hero.dead ?? false ? 'bad' : 'good');
    final status = finished ? (ending == 'bad' ? 'A sad ending' : 'Completed') : (started ? 'In progress' : 'Not started');
    final tone = host.world.narratorTone;
    final painted = s.title.isEmpty && g != null ? SceneView(location: g.scene, time: g.time, mood: 'mystery', seed: r.id.hashCode & 0xffff) : SceneView(location: s.location, time: s.time, mood: s.mood, seed: s.seed, animate: true);
    final stats = <(String, String)>[
      ('${host.turns}', 'Turns'),
      (fmtDuration(host.world.playSeconds), 'Played'),
      ('${host.log.where((e) => e.meta['scene'] != null).length}', 'Places'),
      ('${cast.length}', 'People'),
      ('${quests.where((q) => q.status == QuestStatus.completed).length}/${quests.length}', adv != null ? 'Quests' : 'Goals'),
      ('${host.world.gallery.length}', 'Pictures'),
    ];
    return Scaffold(
      bottomNavigationBar: const NowReadingBar(),
      body: CustomScrollView(slivers: [
        SliverAppBar(
          pinned: true,
          stretch: true,
          expandedHeight: size.height * 0.56,
          backgroundColor: AppColors.bg,
          actions: [
            if (context.watch<SettingsController>().canPaint)
              IconButton(
                tooltip: 'Paint a new cover with AI',
                icon: _painting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome),
                onPressed: _painting ? null : _paintCover,
              ),
            IconButton(tooltip: 'Share', icon: const Icon(Icons.ios_share), onPressed: () => showStoryShareCard(context, host)),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'export') showStoryExport(context, host);
                if (v == 'people') showRelationshipsCard(context, host);
                if (v == 'replay') openReplay(context, host);
                if (v == 'delete') _delete();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'export', child: ListTile(leading: Icon(Icons.save_alt), title: Text('Export or back up'))),
                if (cast.isNotEmpty) const PopupMenuItem(value: 'people', child: ListTile(leading: Icon(Icons.groups_outlined), title: Text('Relationships card'))),
                if (started) const PopupMenuItem(value: 'replay', child: ListTile(leading: Icon(Icons.slideshow_outlined), title: Text('Replay the story'))),
                const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline, color: AppColors.danger), title: Text('Delete'))),
              ],
            ),
          ],
          flexibleSpace: FlexibleSpaceBar(
            stretchModes: const [StretchMode.zoomBackground],
            background: Stack(fit: StackFit.expand, children: [
              MediaView(path: cover, fallback: painted),
              DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: const [0, 0.3, 0.72, 1], colors: [Colors.black.withValues(alpha: 0.45), Colors.transparent, AppColors.bg.withValues(alpha: 0.85), AppColors.bg]))),
              Positioned(
                left: 20,
                right: 20,
                bottom: 18,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    if (g != null) ...[Icon(g.icon, size: 14, color: accent), const SizedBox(width: 6)],
                    Flexible(child: Text(host.storySubtitle.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: T.overline(color: accent).copyWith(letterSpacing: 2))),
                  ]),
                  const SizedBox(height: 8),
                  Text(host.storyTitle, style: T.h1(color: Colors.white).copyWith(fontSize: 34, height: 1.05, fontFamily: 'serif', shadows: const [Shadow(blurRadius: 20, color: Colors.black)])),
                  const SizedBox(height: 10),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    Tag(status, icon: finished ? Icons.emoji_events_outlined : (started ? Icons.play_circle_outline : Icons.auto_awesome_outlined), color: finished ? accent : AppColors.info, filled: true),
                    if (host.isAi) const Tag('AI storyteller', icon: Icons.auto_awesome),
                    if (tone.isNotEmpty) Tag(toneLabel(tone), icon: Icons.record_voice_over_outlined),
                    if (adv?.hardcore ?? false) const Tag('Hardcore', icon: Icons.local_fire_department_outlined, color: AppColors.danger),
                  ]),
                ]),
              ),
            ]),
          ),
        ),
        SliverToBoxAdapter(
          child: ContentWidth(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (premise.isNotEmpty) Text(premise, style: T.reading(color: AppColors.textMuted)),
                const SizedBox(height: 18),
                Row(children: [
                  Expanded(
                    flex: 3,
                    child: AppButton(
                      label: finished ? 'Read it again' : (started ? 'Continue' : 'Begin'),
                      icon: finished ? Icons.menu_book_outlined : Icons.play_arrow_rounded,
                      kind: ButtonKind.accent,
                      onPressed: _play,
                    ),
                  ),
                  if (started) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: AppButton(label: _recapping ? 'Recapping…' : 'Recap', icon: Icons.history_edu_outlined, kind: ButtonKind.secondary, busy: _recapping, onPressed: _recapping ? null : _previously),
                    ),
                  ],
                ]),
                if (finished && started) ...[
                  const SizedBox(height: 8),
                  AppButton(label: 'Replay with pictures and narration', icon: Icons.slideshow_outlined, kind: ButtonKind.secondary, onPressed: () => openReplay(context, host)),
                ],
                if (_recap != null) ...[
                  const SizedBox(height: 14),
                  FadeIn(
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                      decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.accent.withValues(alpha: 0.35))),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('RECAP', style: T.overline(color: AppColors.accent)),
                            const SizedBox(height: 4),
                            Text(_recap!, style: T.small(color: AppColors.text)),
                          ]),
                        ),
                        IconButton(tooltip: 'Listen', icon: const Icon(Icons.volume_up_outlined, size: 18), onPressed: () => context.read<Narrator>().speakNow(_recap!)),
                      ]),
                    ),
                  ),
                ],
                const SectionLabel('Overview'),
                LayoutBuilder(builder: (context, box) {
                  final cols = box.maxWidth > 520 ? 6 : 3;
                  final w = (box.maxWidth - (cols - 1) * 8) / cols;
                  return Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final (v, l) in stats)
                      Container(
                        width: w,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                        child: Column(children: [
                          FittedBox(fit: BoxFit.scaleDown, child: Text(v, style: T.number(18))),
                          Text(l, style: T.caption()),
                        ]),
                      ),
                  ]);
                }),
                if (adv != null) ...[
                  const SectionLabel('Your hero'),
                  AppCard(
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      CharacterPortrait(character: adv!.hero, size: 56, viewable: true),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(adv!.hero.name, style: T.h3()),
                          Text('Level ${adv!.hero.level} ${adv!.hero.raceLabel} ${adv!.hero.classSummary}', style: T.small()),
                          const SizedBox(height: 8),
                          Bar(value: adv!.hero.hp, max: adv!.hero.maxHp, color: AppColors.hp),
                        ]),
                      ),
                    ]),
                  ),
                ],
                if (cast.isNotEmpty || (host.isAi && !finished)) ...[
                  SectionLabel('Characters · ${cast.length}'),
                  SizedBox(
                    height: 104,
                    child: ListView(scrollDirection: Axis.horizontal, children: [
                      for (final p in cast)
                        Padding(
                          padding: const EdgeInsets.only(right: 14),
                          child: GestureDetector(
                            onTap: () => showPersonSheet(context, host, p),
                            child: SizedBox(
                              width: 70,
                              child: Column(children: [
                                Opacity(opacity: p.alive ? 1 : 0.4, child: NpcPortrait(npc: p, size: 60)),
                                const SizedBox(height: 6),
                                Text(p.name.split(' ').first, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.caption(color: AppColors.text)),
                                Text(host.world.bondFor(p).label, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.caption(color: host.world.bondFor(p).isHostile ? AppColors.danger : AppColors.textFaint).copyWith(fontSize: 10)),
                              ]),
                            ),
                          ),
                        ),
                      if (host.isAi && !finished)
                        GestureDetector(
                          onTap: () async {
                            await pickCompanionFor(context, host);
                            if (mounted) setState(() {});
                          },
                          child: SizedBox(
                            width: 70,
                            child: Column(children: [
                              Container(width: 60, height: 60, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.accent.withValues(alpha: 0.6))), child: const Icon(Icons.diversity_1_outlined, color: AppColors.accent)),
                              const SizedBox(height: 6),
                              Text('Companion', maxLines: 1, overflow: TextOverflow.ellipsis, style: T.caption(color: AppColors.accent)),
                              Text('bring along', maxLines: 1, style: T.caption(color: AppColors.textFaint).copyWith(fontSize: 10)),
                            ]),
                          ),
                        ),
                    ]),
                  ),
                ],
                if (open.isNotEmpty) ...[
                  SectionLabel(adv != null ? 'Open quests' : 'Open goals'),
                  RowGroup(children: [
                    for (final q in open.take(5))
                      ListRow(
                        leading: Icon(q.tracked ? Icons.push_pin : Icons.flag_outlined, size: 18, color: const Color(0xFFE0B354)),
                        title: q.title,
                        subtitle: q.description.isEmpty ? null : q.description,
                        onTap: () => showQuestDetails(context, host, q),
                      ),
                  ]),
                ],
                if (host.summary.isNotEmpty) ...[
                  const SectionLabel('The story so far'),
                  Text(host.summary, style: T.small(color: AppColors.text)),
                ],
                if (pictures.isNotEmpty) ...[
                  SectionLabel('Pictures · ${host.world.gallery.length}'),
                  SizedBox(
                    height: 96,
                    child: ListView(scrollDirection: Axis.horizontal, children: [
                      for (final m in pictures)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () => openMedia(context, path: m.path, fallback: const SizedBox(), title: m.caption.isEmpty ? m.kind : m.caption),
                            child: ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(width: m.kind == 'portrait' ? 96 : 150, child: MediaView(path: m.path, fallback: Container(color: AppColors.surface2), cacheWidth: 320))),
                          ),
                        ),
                    ]),
                  ),
                ],
                const SizedBox(height: 22),
                Text('Started ${r is Adventure ? (r as Adventure).createdAt.toLocal().toString().substring(0, 10) : (r as Tale).createdAt.toLocal().toString().substring(0, 10)}', textAlign: TextAlign.center, style: T.caption()),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
