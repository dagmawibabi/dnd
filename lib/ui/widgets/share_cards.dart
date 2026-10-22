import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../../art/scene_painter.dart';
import '../../game/story_host.dart';
import '../../models/adventure.dart';
import '../../models/tale.dart';
import '../../models/world.dart';
import '../../services/achievements.dart';
import '../../services/export.dart' show deliverFile;
import '../../services/game_store.dart';
import '../../services/image_service.dart';
import '../../services/settings.dart';
import '../../services/tale_store.dart';
import '../../services/usage.dart';
import '../../theme/ui.dart';
import '../screens/story/story_extras.dart' show fmtDuration, storyStats;
import 'error_card.dart';
import 'media_view.dart';
import 'portrait.dart';

const cardWidth = 360.0;
const cardHeight = 450.0;

/// A preview of a share card with its options and a Share button. [build]
/// draws the card for the current options.
class ShareCardSheet extends StatefulWidget {
  const ShareCardSheet({super.key, required this.title, required this.subtitle, required this.filename, required this.build, this.text, this.options = const [], this.extra});
  final String title;
  final String subtitle;
  final String filename;
  final String? text;

  /// Switches shown above the card: (label, default value).
  final List<(String, bool)> options;
  final Widget Function(Map<String, bool> options) build;

  /// More controls under the card (e.g. choose people).
  final Widget Function(VoidCallback rebuild)? extra;

  @override
  State<ShareCardSheet> createState() => _ShareCardSheetState();
}

class _ShareCardSheetState extends State<ShareCardSheet> {
  final _key = GlobalKey();
  late final Map<String, bool> _opts = {for (final (k, v) in widget.options) k: v};
  bool _busy = false;

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final boundary = _key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final img = await boundary.toImage(pixelRatio: 1080 / cardWidth);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      if (data == null || !mounted) return;
      final ok = await deliverFile(context, name: '${widget.filename}.png', bytes: data.buffer.asUint8List(), mime: 'image/png', text: widget.text);
      if (ok && mounted) {
        context.read<Achievements>().add(Stat.shares);
        showToast(context, 'Card ready');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(children: [
        Text(widget.title, style: T.h2()),
        const SizedBox(height: 4),
        Text(widget.subtitle, style: T.small(), textAlign: TextAlign.center),
        const SizedBox(height: 8),
        for (final (k, _) in widget.options)
          SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(k, style: T.body()), value: _opts[k]!, onChanged: (v) => setState(() => _opts[k] = v)),
        const SizedBox(height: 8),
        FittedBox(child: RepaintBoundary(key: _key, child: MediaQuery(data: (MediaQuery.maybeOf(context) ?? const MediaQueryData()).copyWith(textScaler: TextScaler.noScaling, devicePixelRatio: 3), child: SizedBox(width: cardWidth, height: cardHeight, child: widget.build(_opts))))),
        if (widget.extra != null) ...[const SizedBox(height: 12), widget.extra!(() => setState(() {}))],
        const SizedBox(height: 16),
        AppButton(label: 'Share image', icon: Icons.ios_share, busy: _busy, onPressed: _share),
      ]),
    );
  }
}

Widget _brand({Color fg = Colors.white, Color sub = Colors.white54, String right = ''}) => Row(children: [
      ClipRRect(borderRadius: BorderRadius.circular(5), child: Image.asset('assets/icon/icon.png', width: 16, height: 16, errorBuilder: (_, _, _) => const SizedBox(width: 16))),
      const SizedBox(width: 6),
      Text('DnD', style: T.h3(color: fg).copyWith(fontSize: 12)),
      const Spacer(),
      Text(right, style: T.caption(color: sub).copyWith(fontSize: 10)),
    ]);

Widget _stat(String value, String label, {Color fg = Colors.white, Color sub = Colors.white54}) => Column(children: [
      FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: T.number(16, color: fg))),
      Text(label.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: T.caption(color: sub).copyWith(fontSize: 8.5, letterSpacing: 0.8)),
    ]);

Widget _statGrid(List<(String, String)> stats) => Column(children: [
      for (var r = 0; r < (stats.length / 4).ceil(); r++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            for (var c = 0; c < 4; c++)
              Expanded(
                child: r * 4 + c < stats.length
                    ? Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
                        child: _stat(stats[r * 4 + c].$1, stats[r * 4 + c].$2),
                      )
                    : const SizedBox(),
              ),
          ]),
        ),
    ]);

// ------------------------------------------------------------------- story

/// A card for one story: its art, title, premise, people and numbers.
Future<void> showStoryShareCard(BuildContext context, StoryHost host) {
  final r = host.record;
  final world = host.world;
  return showAppSheet(context, builder: (_) => ShareCardSheet(
        title: 'Story card',
        subtitle: 'A 1080 × 1350 image of ${host.storyTitle}.',
        filename: host.storyTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-'),
        text: '${host.storyTitle}, my ${r is Adventure ? 'D&D adventure' : 'story'} in DnD',
        options: [('Show tokens & cost', false), ('Show the cast', true)],
        build: (o) => StoryCard(host: host, showCost: o['Show tokens & cost']!, showCast: o['Show the cast']!, cover: latestScenePicture(world.gallery) ?? r.sceneImagePath),
      ));
}

class StoryCard extends StatelessWidget {
  const StoryCard({super.key, required this.host, this.showCost = false, this.showCast = true, this.cover});
  final StoryHost host;
  final bool showCost;
  final bool showCast;
  final String? cover;

  @override
  Widget build(BuildContext context) {
    final r = host.record;
    final premise = r is Adventure ? r.premise : (r as Tale).premise;
    final finished = r is Adventure ? r.finished : (r as Tale).finished;
    final s = host.scene;
    final quests = r is Adventure ? r.quests : (r as Tale).goals;
    final done = quests.where((q) => q.status == QuestStatus.completed).length;
    final u = host.usageTotals;
    final tokens = (u['in'] ?? 0) + (u['out'] ?? 0);
    final stats = <(String, String)>[
      ('${host.turns}', 'Turns'),
      (fmtDuration(host.world.playSeconds), 'Played'),
      ('${host.log.where((e) => e.meta['scene'] != null).length}', 'Places'),
      ('${host.people.length}', 'People'),
      ('$done/${quests.length}', r is Adventure ? 'Quests' : 'Goals'),
      ('${host.world.gallery.length}', 'Pictures'),
      if (r is Adventure) ('${r.hero.level}', 'Level'),
      if (host.world.storyAwards.isNotEmpty) ('${host.world.storyAwards.length}', 'Awards'),
      if (showCost && tokens > 0) (fmtTokens(tokens), 'Tokens'),
      if (showCost && (u['cost'] ?? 0) > 0) (fmtCost((u['cost'] ?? 0).toDouble()), 'AI cost'),
    ].take(8).toList();
    final cast = host.people.where((p) => p.alive).take(6).toList();
    final painted = SceneView(location: s.location, time: s.time, mood: s.mood, seed: s.seed);
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(fit: StackFit.expand, children: [
        Container(color: const Color(0xFF0B0A09)),
        Positioned(left: 0, right: 0, top: 0, height: 250, child: MediaView(path: cover, fallback: painted)),
        const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: [0, 0.35, 0.58, 1], colors: [Color(0x33000000), Colors.transparent, Color(0xF20B0A09), Color(0xFF0B0A09)]))),
        Positioned(
          top: 16,
          left: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(999), border: Border.all(color: Colors.white24)),
            child: Text(finished ? 'COMPLETED' : 'IN PROGRESS', style: T.overline(color: finished ? const Color(0xFFE0B354) : Colors.white)),
          ),
        ),
        if (r is Adventure) Positioned(top: 12, right: 14, child: CharacterPortrait(character: r.hero, size: 48)),
        Positioned(
          left: 20,
          right: 20,
          bottom: 16,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(host.storySubtitle.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: T.overline(color: Colors.white60)),
            const SizedBox(height: 4),
            Text(host.storyTitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: T.h1(color: Colors.white).copyWith(fontSize: 28, height: 1.05, fontFamily: 'serif')),
            if (premise.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(premise, maxLines: 3, overflow: TextOverflow.ellipsis, style: T.small(color: Colors.white70).copyWith(fontSize: 11.5, height: 1.35)),
            ],
            if (showCast && cast.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(children: [
                for (final p in cast) Padding(padding: const EdgeInsets.only(right: 6), child: NpcPortrait(npc: p, size: 30)),
                if (host.people.length > cast.length) Text('+${host.people.length - cast.length}', style: T.caption(color: Colors.white60)),
              ]),
            ],
            const SizedBox(height: 12),
            _statGrid(stats),
            const SizedBox(height: 4),
            _brand(right: r is Adventure ? '${r.hero.name} · ${r.hero.raceLabel} ${r.hero.classSummary}' : (r as Tale).protagonist == 'You' ? '' : r.protagonist),
          ]),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- lifetime

/// A card with every adventure's totals: stories, turns, hours, achievements.
Future<void> showLifetimeShareCard(BuildContext context) => showAppSheet(context, builder: (ctx) => ShareCardSheet(
      title: 'All your adventures',
      subtitle: 'Your totals across every story, as an image.',
      filename: 'dnd-adventures',
      text: 'My adventures in DnD',
      options: [('Show tokens & cost', false)],
      build: (o) => LifetimeCard(showCost: o['Show tokens & cost']!),
    ));

class LifetimeCard extends StatelessWidget {
  const LifetimeCard({super.key, this.showCost = false});
  final bool showCost;

  @override
  Widget build(BuildContext context) {
    final ach = context.watch<Achievements>();
    final games = context.watch<GameStore>();
    final tales = context.watch<TaleStore>();
    final usage = context.watch<UsageTracker>();
    final settings = context.read<SettingsController>();
    final stories = games.adventures.length + tales.tales.length;
    final finished = games.adventures.where((a) => a.finished).length + tales.tales.where((t) => t.finished).length;
    final seconds = games.adventures.fold<int>(0, (n, a) => n + a.playSeconds) + tales.tales.fold<int>(0, (n, t) => n + t.playSeconds);
    final stats = <(String, String)>[
      ('$stories', 'Stories'),
      ('$finished', 'Finished'),
      (fmtDuration(seconds), 'Played'),
      ('${ach.stat(Stat.turns)}', 'Turns'),
      ('${ach.stat(Stat.npcs)}', 'People met'),
      ('${ach.stat(Stat.kills)}', 'Foes beaten'),
      ('${ach.stat(Stat.maxLevel)}', 'Top level'),
      ('${ach.unlockedCount}/${ach.total}', 'Achievements'),
      ('${ach.stat(Stat.places)}', 'Places'),
      ('${ach.stat(Stat.romances)}', 'Romances'),
      ('${ach.stat(Stat.crits)}', 'Crits'),
      if (showCost) (fmtCost(usage.total.cost), 'AI cost') else ('${ach.storyAwards.length}', 'Awards'),
    ];
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(fit: StackFit.expand, children: [
        const SceneView(location: 'castle', time: 'dusk', mood: 'triumph', seed: 77),
        const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: [0, 0.42, 1], colors: [Color(0x55000000), Color(0xE6000000), Color(0xFF000000)]))),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('MY ADVENTURES', style: T.overline(color: const Color(0xFFE0B354)).copyWith(letterSpacing: 3)),
            const SizedBox(height: 6),
            Text(settings.playerName.isEmpty ? 'A Life of Stories' : settings.playerName, style: T.h1(color: Colors.white).copyWith(fontSize: 30, fontFamily: 'serif')),
            const SizedBox(height: 4),
            Text('${ach.unlockedCount} achievements · ${ach.stat(Stat.completed) + ach.stat(Stat.talesFinished)} endings reached', style: T.small(color: Colors.white70)),
            const Spacer(),
            _statGrid(stats),
            const SizedBox(height: 4),
            _brand(right: 'D&D and text adventures'),
          ]),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------- relationships

/// A card of the bonds you formed: choose who appears, and optionally paint
/// an AI group photo of them together.
Future<void> showRelationshipsCard(BuildContext context, StoryHost host) {
  final people = [...host.people]..sort((a, b) => host.world.bondFor(b).friendship.abs().compareTo(host.world.bondFor(a).friendship.abs()));
  final picked = <String>{for (final p in people.take(6)) p.id};
  String? photo = host.world.gallery.reversed.where((m) => m.kind == 'group').firstOrNull?.path;
  var painting = false;
  return showAppSheet(context, builder: (ctx) => ShareCardSheet(
        title: 'Relationships',
        subtitle: 'The people of ${host.storyTitle} and where you stand with each.',
        filename: '${host.storyTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}-relationships',
        text: 'The people of ${host.storyTitle}',
        options: [('Use the group photo', true)],
        build: (o) => RelationshipsCard(host: host, people: [for (final p in people) if (picked.contains(p.id)) p], photo: o['Use the group photo']! ? photo : null),
        extra: (rebuild) => StatefulBuilder(builder: (ctx, setState) {
          final settings = ctx.watch<SettingsController>();
          Future<void> paint() async {
            final images = ctx.read<ImageService>();
            final chosen = [for (final p in people) if (picked.contains(p.id)) p];
            if (chosen.isEmpty) return;
            setState(() => painting = true);
            images.resume();
            final key = 'group_${host.storyId}_${DateTime.now().millisecondsSinceEpoch}';
            final hero = host.record is Adventure ? (host.record as Adventure).hero : null;
            final refs = <(String, String)>[
              if (hero?.portrait.aiImagePath != null) (hero!.name, hero.portrait.aiImagePath!),
              for (final p in chosen)
                if (p.portrait.aiImagePath != null) (p.name, p.portrait.aiImagePath!),
            ];
            final who = [if (hero != null) '${hero.name} (the hero, ${hero.raceLabel} ${hero.classSummary}${hero.appearance.isEmpty ? '' : ': ${hero.appearance}'})', for (final p in chosen) '${p.name}${p.description.isEmpty ? '' : ' (${p.description})'}'];
            final path = await images.generate(
              key,
              'A warm group portrait, like a photograph or painting of friends posing together after an adventure: ${who.join('; ')}. Everyone is clearly visible, standing or sitting close together, expressions that fit how they feel about the hero. Set in ${host.scene.title.isEmpty ? 'the world of the story' : host.scene.title}.',
              size: '1536x1024',
              usageTarget: host.usageTotals,
              style: host.artStyle,
              references: refs,
            );
            if (!ctx.mounted) return;
            setState(() => painting = false);
            if (path == null) {
              final err = images.errors[key];
              if (err != null) showIssueSheet(ctx, err, label: 'Group photo');
              return;
            }
            photo = path;
            host.world.addMedia(MediaItem(path: path, kind: 'group', caption: 'Group photo: ${chosen.map((p) => p.name.split(' ').first).join(', ')}', turn: host.turns, cost: images.costs[path] ?? 0));
            host.save();
            rebuild();
          }

          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('WHO TO INCLUDE · ${picked.length}', style: T.overline()),
            const SizedBox(height: 8),
            CompactChips(child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (final p in people)
                FilterChip(
                  avatar: NpcPortrait(npc: p, size: 22),
                  label: Text(p.name.split(' ').first),
                  selected: picked.contains(p.id),
                  onSelected: (v) {
                    setState(() => v ? picked.add(p.id) : picked.remove(p.id));
                    rebuild();
                  },
                ),
            ])),
            if (settings.useAiImages) ...[
              const SizedBox(height: 10),
              AppButton(label: painting ? 'Painting the group photo…' : (photo == null ? 'Paint a group photo' : 'Paint a new group photo'), icon: Icons.groups_outlined, kind: ButtonKind.secondary, busy: painting, onPressed: painting || picked.isEmpty ? null : paint),
              const SizedBox(height: 4),
              Text('Uses everyone\'s portraits so faces match. Saved to the story\'s gallery.', style: T.caption(), textAlign: TextAlign.center),
            ],
          ]);
        }),
      ));
}

class RelationshipsCard extends StatelessWidget {
  const RelationshipsCard({super.key, required this.host, required this.people, this.photo});
  final StoryHost host;
  final List<Npc> people;
  final String? photo;

  @override
  Widget build(BuildContext context) {
    final cols = people.length <= 4 ? 2 : 3;
    final shown = people.take(cols == 2 ? 4 : 9).toList();
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(fit: StackFit.expand, children: [
        Container(color: const Color(0xFF100C10)),
        if (photo != null) Positioned(left: 0, right: 0, top: 0, height: 210, child: MediaView(path: photo, fallback: const SizedBox())),
        DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: photo == null ? const [0, 1] : const [0.25, 0.48], colors: const [Color(0x00100C10), Color(0xFF100C10)]))),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('MY PEOPLE', style: T.overline(color: const Color(0xFFF472B6)).copyWith(letterSpacing: 3)),
            const SizedBox(height: 4),
            Text(host.storyTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.h2(color: Colors.white).copyWith(fontFamily: 'serif')),
            const Spacer(),
            if (shown.isEmpty) Center(child: Text('Choose who to include below.', style: T.small(color: Colors.white54))),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final p in shown)
                SizedBox(
                  width: (cardWidth - 36 - (cols - 1) * 8) / cols,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white12)),
                    child: Row(children: [
                      NpcPortrait(npc: p, size: cols == 2 ? 38 : 30),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(p.name.split(' ').first, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.small(color: Colors.white).copyWith(fontWeight: FontWeight.w600)),
                          Text(host.world.bondFor(p).label, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.caption(color: host.world.bondFor(p).isRomantic ? const Color(0xFFF472B6) : (host.world.bondFor(p).isHostile ? const Color(0xFFF87171) : Colors.white60)).copyWith(fontSize: 10)),
                        ]),
                      ),
                    ]),
                  ),
                ),
            ]),
            if (people.length > shown.length) Padding(padding: const EdgeInsets.only(top: 6), child: Text('and ${people.length - shown.length} more', style: T.caption(color: Colors.white54))),
            const SizedBox(height: 12),
            _brand(right: '${host.people.length} met · ${host.turns} turns'),
          ]),
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------- achievement

/// Shares one achievement as a card.
Future<void> showAchievementShareCard(BuildContext context, {required String title, required String description, required IconData icon, String detail = '', String when = ''}) => showAppSheet(context, builder: (_) => ShareCardSheet(
      title: 'Achievement card',
      subtitle: 'Show off "$title".',
      filename: 'achievement-${title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}',
      text: 'Achievement unlocked in DnD: $title',
      build: (_) => AchievementCard(title: title, description: description, icon: icon, detail: detail, when: when),
    ));

class AchievementCard extends StatelessWidget {
  const AchievementCard({super.key, required this.title, required this.description, required this.icon, this.detail = '', this.when = ''});
  final String title;
  final String description;
  final IconData icon;
  final String detail;
  final String when;

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFE0B354);
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: const BoxDecoration(gradient: RadialGradient(center: Alignment(0, -0.35), radius: 1.1, colors: [Color(0xFF3A2C12), Color(0xFF0D0A06)])),
        padding: const EdgeInsets.fromLTRB(24, 30, 24, 18),
        child: Column(children: [
          Text('ACHIEVEMENT UNLOCKED', style: T.overline(color: gold).copyWith(letterSpacing: 3)),
          const Spacer(),
          Container(
            width: 132,
            height: 132,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(colors: [Color(0x55E0B354), Color(0x11E0B354)]),
              border: Border.all(color: gold, width: 3),
              boxShadow: [BoxShadow(color: gold.withValues(alpha: 0.35), blurRadius: 40, spreadRadius: 4)],
            ),
            child: Icon(icon, size: 62, color: gold),
          ),
          const SizedBox(height: 22),
          Text(title, textAlign: TextAlign.center, style: T.h1(color: Colors.white).copyWith(fontSize: 28, fontFamily: 'serif')),
          const SizedBox(height: 8),
          Text(description, textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis, style: T.body(color: Colors.white70)),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(detail, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: T.caption(color: gold)),
          ],
          const Spacer(),
          _brand(right: when),
        ]),
      ),
    );
  }
}

/// Stats for the overview (kept in sync with [storyStats]).
List<(IconData, String, String)> shareableStats(StoryHost host) => storyStats(host);
