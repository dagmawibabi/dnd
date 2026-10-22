import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../art/scene_painter.dart';
import '../../../data/tale_genres.dart';
import '../../../data/tales/tales.dart';
import '../../../models/tale.dart';
import '../../../services/ai/tale_narrator.dart';
import '../../../services/settings.dart';
import '../../../services/tale_store.dart';
import '../../../theme/ui.dart';
import '../../widgets/ai_gate.dart';
import '../../widgets/bright_art.dart';
import '../../widgets/import_adventure_button.dart';
import '../../widgets/genre_editor.dart';
import '../../widgets/media_view.dart';
import '../../widgets/narrator_tone.dart';
import '../story/cover_screen.dart';
import 'tale_screen.dart';
import 'tale_terminal_screen.dart';

/// Opens a story in the layout it was last played in.
Route<void> taleRoute(Tale t) => MaterialPageRoute(builder: (_) => t.terminal ? TaleTerminalScreen(tale: t) : TaleScreen(tale: t));

Future<void> openTale(BuildContext context, String id) async {
  final t = await context.read<TaleStore>().load(id);
  if (t == null || !context.mounted) return;
  Navigator.of(context).push(taleRoute(t));
}

Future<void> startPreset(BuildContext context, TalePreset p) async {
  final t = Tale.create(title: p.title, genre: p.genre, engine: TaleEngine.preset, presetId: p.id)..terminal = context.read<SettingsController>().taleTerminal;
  await context.read<TaleStore>().save(t);
  if (!context.mounted) return;
  Navigator.of(context).push(taleRoute(t));
}

/// Home content for text adventures.
class TalesHub extends StatefulWidget {
  const TalesHub({super.key});

  @override
  State<TalesHub> createState() => _TalesHubState();
}

class _TalesHubState extends State<TalesHub> {
  String? _genre;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<TaleStore>();
    final settings = context.watch<SettingsController>();
    final active = store.tales.where((t) => !t.finished).toList();
    final latest = active.isEmpty ? null : active.first;
    final presets = talePresets.where((p) => _genre == null || p.genre == _genre).toList();
    // Your own AI stories lead the featured list; replays of handcrafted ones stay below.
    final mine = store.tales.where((t) => t.isAi && (_genre == null || t.genre == _genre)).toList();
    final played = store.tales.where((t) => !t.isAi).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (latest != null) ...[
        _ContinueTale(summary: latest),
        const SizedBox(height: 12),
      ],
      AppCard(
        onTap: () => showNewTaleSheet(context, genre: _genre),
        borderColor: settings.useAiText ? AppColors.accent : null,
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: settings.useAiText ? AppColors.accentSoft : AppColors.surface2, borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.auto_awesome, color: settings.useAiText ? AppColors.accent : AppColors.textFaint),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('New story', style: T.h3()),
              const SizedBox(height: 2),
              Text(settings.useAiText ? 'An original adventure in any genre' : 'Set up your AI narrator', style: T.small()),
            ]),
          ),
          const Icon(Icons.chevron_right, color: AppColors.textFaint),
        ]),
      ),
      const SectionLabel('Genres'),
      SizedBox(
        height: 36,
        child: CompactChips(child: ListView(scrollDirection: Axis.horizontal, children: [
          Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: const Text('All'), selected: _genre == null, onSelected: (_) => setState(() => _genre = null))),
          for (final g in allTaleGenres)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onLongPress: isCustomGenre(g.id) ? () => showGenreEditor(context, existing: settings.customGenres.where((x) => x['id'] == g.id).firstOrNull) : null,
                child: ChoiceChip(
                  avatar: Icon(g.icon, size: 16, color: _genre == g.id ? AppColors.text : g.color),
                  label: Text(g.name, style: T.small(color: AppColors.text)),
                  selected: _genre == g.id,
                  onSelected: (_) => setState(() => _genre = _genre == g.id ? null : g.id),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ActionChip(avatar: const Icon(Icons.add, size: 16), label: const Text('Your own'), onPressed: () async {
              final id = await showGenreEditor(context);
              if (id != null && mounted) setState(() => _genre = id);
            }),
          ),
        ])),
      ),
      SectionLabel(_genre == null ? 'Featured stories' : '${genreById(_genre!).name} stories'),
      if (presets.isEmpty && mine.isEmpty)
        AppCard(
          onTap: () => showNewTaleSheet(context, genre: _genre),
          child: Text('No handcrafted ${genreById(_genre!).name.toLowerCase()} story yet. Tap to let the AI write one.', style: T.small()),
        ),
      LayoutBuilder(builder: (context, constraints) {
        final columns = constraints.maxWidth >= 650 ? 2 : 1;
        final width = (constraints.maxWidth - (columns - 1) * 16) / columns;
        return Wrap(spacing: 16, runSpacing: 16, children: [
          for (final t in mine) SizedBox(width: width, child: _MyTaleCard(summary: t)),
          for (final p in presets) SizedBox(width: width, child: _PresetCard(preset: p)),
        ]);
      }),
      if (played.isNotEmpty) ...[
        const SectionLabel('Your playthroughs'),
        RowGroup(children: [
          for (final t in played)
            Dismissible(
              key: ValueKey(t.id),
              direction: DismissDirection.endToStart,
              background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), color: AppColors.danger.withValues(alpha: 0.15), child: const Icon(Icons.delete_outline, color: AppColors.danger)),
              confirmDismiss: (_) => confirm(context, title: 'Delete story?', message: '"${t.title}" will be permanently deleted.'),
              onDismissed: (_) => store.delete(t.id),
              child: ListRow(
                leading: Icon(genreById(t.genre).icon, size: 20, color: genreById(t.genre).color),
                title: t.title,
                subtitle: '${genreById(t.genre).name}${t.isAi ? ' · AI' : ''} · ${t.finished ? switch (t.ending) { 'good' => 'Good ending', 'bad' => 'Bad ending', _ => 'Finished' } : '${t.turns} turns'}',
                onTap: () => openTaleCover(context, t.id),
              ),
            ),
        ]),
      ],
    ]);
  }
}

class _ContinueTale extends StatelessWidget {
  const _ContinueTale({required this.summary});
  final TaleSummary summary;

  @override
  Widget build(BuildContext context) {
    final g = genreById(summary.genre);
    return AppCard(
      onTap: () => openTaleCover(context, summary.id),
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(color: g.color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(14)),
          child: Icon(g.icon, color: g.color),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('CONTINUE', style: T.overline(color: g.color)),
            const SizedBox(height: 4),
            Text(summary.title, style: T.h3(), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('${g.name} · ${summary.turns} turns · ${g.healthLabel} ${summary.health}', style: T.small(), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        GestureDetector(
          onTap: () => openTale(context, summary.id),
          child: Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(color: AppColors.text, shape: BoxShape.circle),
            child: const Icon(Icons.play_arrow_rounded, color: AppColors.bg),
          ),
        ),
      ]),
    );
  }
}

/// One of your AI-written stories, as a featured card.
class _MyTaleCard extends StatelessWidget {
  const _MyTaleCard({required this.summary});
  final TaleSummary summary;

  @override
  Widget build(BuildContext context) {
    final t = summary;
    final g = genreById(t.genre);
    final painted = BrightArt(child: SceneView(location: g.scene, time: g.time, mood: 'mystery', seed: t.id.hashCode & 0xffff));
    final status = t.finished ? switch (t.ending) { 'good' => 'Good ending', 'bad' => 'Bad ending', _ => 'Finished' } : '${t.turns} turns';
    return Dismissible(
      key: ValueKey('mine-${t.id}'),
      direction: DismissDirection.endToStart,
      background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.delete_outline, color: AppColors.danger)),
      confirmDismiss: (_) => confirm(context, title: 'Delete story?', message: '"${t.title}" will be permanently deleted.'),
      onDismissed: (_) => context.read<TaleStore>().delete(t.id),
      child: AppCard(
        padding: EdgeInsets.zero,
        borderColor: g.color.withValues(alpha: 0.45),
        onTap: () => openTaleCover(context, t.id),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
            child: SizedBox(
              height: 136,
              child: Stack(fit: StackFit.expand, children: [
                t.cover == null ? painted : MediaView(path: t.cover, fallback: painted),
                const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: [0.55, 1], colors: [Colors.transparent, Color(0xB3000000)]))),
                Positioned(
                  left: 14,
                  bottom: 10,
                  right: 14,
                  child: Row(children: [
                    Icon(g.icon, size: 14, color: g.color),
                    const SizedBox(width: 6),
                    Text(g.name.toUpperCase(), style: T.overline(color: g.color)),
                    const Spacer(),
                    const Icon(Icons.auto_awesome, size: 14, color: Colors.white70),
                  ]),
                ),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.title, style: T.h3().copyWith(letterSpacing: 0)),
              if (t.premise.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(t.premise, style: T.small(), maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                const Tag('Yours · AI', icon: Icons.auto_awesome_outlined, color: AppColors.accent),
                Tag(status, icon: t.finished ? Icons.flag_outlined : Icons.repeat),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({required this.preset});
  final TalePreset preset;

  @override
  Widget build(BuildContext context) {
    final g = genreById(preset.genre);
    return AppCard(
      padding: EdgeInsets.zero,
      onTap: () => startPreset(context, preset),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
          child: SizedBox(
            height: 136,
            child: Stack(fit: StackFit.expand, children: [
              BrightArt(child: SceneView(location: g.scene, time: g.time, mood: 'mystery', seed: preset.id.hashCode & 0xffff)),
              const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: [0.55, 1], colors: [Colors.transparent, Color(0xB3000000)]))),
              Positioned(
                left: 14,
                bottom: 10,
                right: 14,
                child: Row(children: [
                  Icon(g.icon, size: 14, color: g.color),
                  const SizedBox(width: 6),
                  Text(g.name.toUpperCase(), style: T.overline(color: g.color)),
                ]),
              ),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(preset.title, style: T.h3().copyWith(letterSpacing: 0)),
            const SizedBox(height: 4),
            Text(preset.blurb, style: T.small()),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              Tag('~${preset.minutes} min', icon: Icons.schedule),
              Tag('${preset.endings} endings', icon: Icons.alt_route),
              const Tag('Offline', icon: Icons.wifi_off_outlined),
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// Create an AI-narrated story in any genre.
void showNewTaleSheet(BuildContext context, {String? genre}) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => _NewTale(initialGenre: genre ?? 'scifi')));
}

class _NewTale extends StatefulWidget {
  const _NewTale({required this.initialGenre});
  final String initialGenre;

  @override
  State<_NewTale> createState() => _NewTaleState();
}

class _NewTaleState extends State<_NewTale> {
  late String _genre = widget.initialGenre;
  final _title = TextEditingController();
  final _premise = TextEditingController();
  final _name = TextEditingController();
  bool _busy = false;
  String _tone = '';
  late bool _terminal = context.read<SettingsController>().taleTerminal;

  @override
  void dispose() {
    _title.dispose();
    _premise.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _suggest() async {
    setState(() => _busy = true);
    try {
      final (t, p) = await TaleNarrator(context.read<SettingsController>()).idea(_genre, seed: _premise.text.trim());
      _title.text = t;
      _premise.text = p;
    } catch (e) {
      if (mounted) showToast(context, 'Couldn\'t get an idea: $e', icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// A random genre and narrator, and (with AI) a fresh idea to go with them.
  Future<void> _random() async {
    final r = math.Random();
    final all = allTaleGenres;
    setState(() {
      _genre = all[r.nextInt(all.length)].id;
      _tone = r.nextInt(3) == 0 ? '' : narratorTones[r.nextInt(narratorTones.length)].$2;
      _title.clear();
      _premise.clear();
    });
    if (context.read<SettingsController>().useAiText) await _suggest();
  }

  Future<void> _start() async {
    if (!context.read<SettingsController>().useAiText) {
      showAiUnavailable(context, feature: 'AI-written stories');
      return;
    }
    final g = genreById(_genre);
    final t = Tale.create(
      title: _title.text.trim().isEmpty ? 'A ${g.name} Story' : _title.text.trim(),
      genre: _genre,
      engine: TaleEngine.ai,
      protagonist: _name.text.trim().isEmpty ? 'You' : _name.text.trim(),
      premise: _premise.text.trim(),
    )
      ..terminal = _terminal
      ..narratorTone = _tone;
    final store = context.read<TaleStore>();
    final nav = Navigator.of(context);
    await store.save(t);
    nav.pop();
    nav.push(taleRoute(t));
  }

  @override
  Widget build(BuildContext context) {
    final g = genreById(_genre);
    return Scaffold(
      appBar: AppBar(title: const Text('New adventure'), actions: const [ImportAdventureButton()]),
      body: SafeArea(child: ContentWidth(child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('New text adventure', style: T.h2()),
          const SizedBox(height: 4),
          Text(g.tagline, style: T.small()),
          const SizedBox(height: 16),
          CompactChips(child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final x in allTaleGenres)
              GestureDetector(
                onLongPress: isCustomGenre(x.id) ? () => showGenreEditor(context, existing: context.read<SettingsController>().customGenres.where((g) => g['id'] == x.id).firstOrNull) : null,
                child: ChoiceChip(
                  avatar: Icon(x.icon, size: 16, color: _genre == x.id ? AppColors.text : x.color),
                  label: Text(x.name, style: T.small(color: AppColors.text)),
                  selected: _genre == x.id,
                  onSelected: (_) => setState(() => _genre = x.id),
                ),
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 16),
              label: Text('Your own', style: T.small(color: AppColors.text)),
              onPressed: () async {
                final id = await showGenreEditor(context);
                if (id != null && mounted) setState(() => _genre = id);
              },
            ),
            ActionChip(
              avatar: const Icon(Icons.casino_outlined, size: 16),
              label: Text('Surprise me', style: T.small(color: AppColors.text)),
              onPressed: _random,
            ),
          ])),
          if (isCustomGenre(_genre)) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Long-press your genre to edit it.', style: T.caption())),
          const SizedBox(height: 16),
          TextField(controller: _name, style: T.body(), decoration: const InputDecoration(labelText: 'Your character\'s name (optional)')),
          const SizedBox(height: 10),
          TextField(controller: _title, style: T.body(), decoration: const InputDecoration(labelText: 'Title (optional)')),
          const SizedBox(height: 10),
          TextField(controller: _premise, style: T.body(), minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Premise or idea (optional)', hintText: 'A lighthouse keeper receives letters from the future')),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy || !context.watch<SettingsController>().useAiText ? null : _suggest,
              icon: _busy ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.lightbulb_outline, size: 16),
              label: Text('Suggest an idea', style: T.small(color: AppColors.text)),
            ),
          ),
          const SectionLabel('Narrator tone (optional)'),
          NarratorTonePicker(value: _tone, onChanged: (v) => setState(() => _tone = v)),
          const SectionLabel('Layout'),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('Book'), icon: Icon(Icons.chrome_reader_mode_outlined, size: 16)),
              ButtonSegment(value: true, label: Text('Terminal'), icon: Icon(Icons.terminal, size: 16)),
            ],
            selected: {_terminal},
            onSelectionChanged: (v) => setState(() => _terminal = v.first),
          ),
          const SizedBox(height: 12),
          AppButton(label: 'Begin', icon: Icons.play_arrow_rounded, kind: ButtonKind.accent, onPressed: _busy ? null : _start),
        ]),
      ))),
    );
  }
}
