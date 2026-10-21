import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/audio/audio_service.dart';
import '../../../services/audio/synth.dart';
import '../../../services/export.dart' show deliverFile;
import '../../../services/settings.dart';
import '../../../services/studio.dart';
import '../../../services/user_media.dart' show deleteImported;
import '../../../theme/ui.dart';
import '../../widgets/media_import.dart';
import 'studio_common.dart';

const soundscapeLabels = {
  'rain': ('Rain', Icons.water_drop_outlined),
  'storm': ('Storm', Icons.thunderstorm_outlined),
  'wind': ('Wind', Icons.air),
  'snow': ('Snowfall', Icons.ac_unit),
  'forest': ('Forest', Icons.forest_outlined),
  'cave': ('Cave', Icons.landscape_outlined),
  'crowd': ('Crowd', Icons.groups_outlined),
  'fire': ('Campfire', Icons.local_fire_department_outlined),
  'surf': ('Surf', Icons.waves),
};

/// Explore the game's music, compose your own loops, add your own songs and
/// soundscapes, and choose what plays where.
class MusicStudioScreen extends StatefulWidget {
  const MusicStudioScreen({super.key});

  @override
  State<MusicStudioScreen> createState() => _MusicStudioScreenState();
}

class _MusicStudioScreenState extends State<MusicStudioScreen> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 4, vsync: this);
  late final AudioService _audio;

  /// What is looping right now: a theme, a track id, 'draft' or an ambience.
  String? _playing;
  String? _loading;
  Uint8List? _wav;

  // The composer's draft.
  MusicSpec _spec = MusicSpec.forTheme('town');
  String? _editing;
  String _name = 'My theme';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _audio = context.read<AudioService>();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tabs.dispose();
    _audio.stopPreview();
    super.dispose();
  }

  /// Starts or stops a looping preview. [start] begins playback.
  Future<void> _loop(String id, Future<void> Function() start) async {
    if (_playing == id) {
      await _audio.stopPreview(resume: false);
      setState(() => _playing = null);
      return;
    }
    setState(() => _loading = id);
    try {
      await start();
      if (mounted && _loading == id) setState(() => _playing = id);
    } finally {
      if (mounted && _loading == id) setState(() => _loading = null);
    }
  }

  Future<void> Function() _wavLoop(Future<Uint8List> Function() render, {bool show = false, double volume = 0.8}) => () async {
        final wav = await render();
        if (!mounted) return;
        if (show) setState(() => _wav = wav);
        await _audio.previewLoop(wav, volume: volume);
      };

  Future<void> Function() _trackLoop(StudioTrack t) => t.isFile ? () => _audio.previewFile(t.file!, loop: true) : _wavLoop(() => _audio.renderTrack(t.spec ?? const MusicSpec()));

  void _setSpec(MusicSpec s) {
    setState(() => _spec = s);
    if (_playing == 'draft') {
      // Re-render shortly after the last change, so it follows the sliders.
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 700), () async {
        if (!mounted || _playing != 'draft') return;
        setState(() => _loading = 'draft');
        final wav = await _audio.renderTrack(_spec);
        if (!mounted || _playing != 'draft') return;
        await _audio.previewLoop(wav);
        setState(() {
          _wav = wav;
          _loading = null;
        });
      });
    }
  }

  void _openInComposer(MusicSpec spec, {String? id, String? name}) {
    setState(() {
      _spec = spec;
      _editing = id;
      _name = name ?? 'My theme';
      _wav = null;
    });
    _tabs.animateTo(1);
  }

  Widget _playButton(String id, Future<void> Function() start, {double size = 40}) {
    if (_loading == id) return SizedBox(width: size, height: size, child: const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2)));
    final on = _playing == id;
    return CircleIconButton(icon: on ? Icons.stop : Icons.play_arrow, size: size, tooltip: on ? 'Stop' : 'Play', color: on ? AppColors.accent : null, onPressed: () => _loop(id, start));
  }

  /// Copies audio files in as tracks; returns the new tracks.
  Future<List<StudioTrack>> _importTracks() async {
    final files = await chooseAudio(context);
    if (files.isEmpty || !mounted) return const [];
    final added = [for (final f in files) StudioTrack(name: f.name, file: f.path)];
    context.read<StudioStore>().update((s) => s.tracks.addAll(added));
    showToast(context, 'Added ${added.length} ${added.length == 1 ? 'file' : 'files'}');
    return added;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Music'),
        bottom: TabBar(controller: _tabs, isScrollable: true, tabAlignment: TabAlignment.start, tabs: const [
          Tab(text: 'Themes'),
          Tab(text: 'Compose'),
          Tab(text: 'My tracks'),
          Tab(text: 'Soundscapes'),
        ]),
      ),
      body: TabBarView(controller: _tabs, children: [_themes(), _composer(), _tracks(), _soundscapes()]),
    );
  }

  // --------------------------------------------------------------- themes

  Widget _themes() {
    final s = context.watch<SettingsController>();
    final studio = context.watch<StudioStore>();
    return ContentWidth(
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
        Text('Every piece of music is generated on your device. Listen to each theme, remix it, or have your own tracks and songs play in its place. Give a theme several tracks and they take turns.', style: T.small()),
        const SizedBox(height: 12),
        RowGroup(children: [
          ListRow(
            leading: const Icon(Icons.music_note_outlined, size: 20),
            title: 'Music in stories',
            trailing: Switch(value: s.musicEnabled, onChanged: (v) => s.update((s) => s.musicEnabled = v)),
          ),
          ParamSlider(label: 'Volume', value: s.musicVolume, min: 0, max: 1, format: (v) => '${(v * 100).round()}%', onChanged: (v) => s.update((s) => s.musicVolume = v)),
        ]),
        const SectionLabel('Game themes'),
        RowGroup(children: [
          for (final t in musicThemes)
            Builder(builder: (context) {
              final mine = studio.tracksFor(t);
              final spec = MusicSpec.forTheme(t);
              return ListRow(
                leading: Icon(themeIcon(t), size: 20, color: mine.isNotEmpty ? AppColors.accent : null),
                title: themeLabel(t),
                subtitle: mine.isNotEmpty
                    ? 'Your ${mine.length == 1 ? 'track' : 'playlist'}: ${mine.map((x) => x.name).join(', ')}'
                    : '${spec.minor ? 'Minor' : 'Major'} in ${noteNames[spec.root % 12]} · ${spec.bpm.round()} bpm · ${spec.style}',
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  _playButton('theme:$t', mine.isNotEmpty ? _trackLoop(mine.first) : _wavLoop(() => _audio.renderTrack(spec))),
                  PopupMenuButton<String>(
                    tooltip: 'Options',
                    onSelected: (v) async {
                      switch (v) {
                        case 'remix':
                          _openInComposer(spec, name: '${themeLabel(t)} remix');
                        case 'choose':
                          await _chooseFor(themeLabel(t), studio.musicSlots, t);
                        case 'import':
                          final added = await _importTracks();
                          if (added.isNotEmpty) studio.update((s) => s.musicSlots.putIfAbsent(t, () => []).addAll([for (final a in added) a.id]));
                        case 'reset':
                          studio.update((s) => s.musicSlots.remove(t));
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'import', child: ListTile(leading: Icon(Icons.audio_file_outlined), title: Text('Add songs from my device'))),
                      PopupMenuItem(value: 'choose', enabled: studio.tracks.isNotEmpty, child: const ListTile(leading: Icon(Icons.playlist_add_check), title: Text('Choose my tracks'))),
                      const PopupMenuItem(value: 'remix', child: ListTile(leading: Icon(Icons.tune), title: Text('Remix in the composer'))),
                      if (mine.isNotEmpty) const PopupMenuItem(value: 'reset', child: ListTile(leading: Icon(Icons.restore), title: Text('Restore the original'))),
                    ],
                  ),
                ]),
              );
            }),
        ]),
      ]),
    );
  }

  /// Ticks tracks into the playlist for one theme or soundscape.
  Future<void> _chooseFor(String label, Map<String, List<String>> slots, String key) => showAppSheet(context, builder: (sheet) => StatefulBuilder(builder: (sheet, set) {
        final studio = context.read<StudioStore>();
        return SizedBox(
          height: MediaQuery.sizeOf(sheet).height * 0.7,
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
            SheetTitle('Play for $label', subtitle: 'Tick one or more. With several, they take turns.'),
            RowGroup(children: [
              for (final t in studio.tracks)
                CheckboxListTile(
                  secondary: Icon(t.isFile ? Icons.audio_file_outlined : Icons.library_music_outlined, size: 20),
                  title: Text(t.name, style: T.body()),
                  subtitle: Text(t.isFile ? 'From your device' : 'Composed', style: T.caption()),
                  value: slots[key]?.contains(t.id) ?? false,
                  onChanged: (v) {
                    studio.update((_) => StudioStore.toggle(slots, key, t.id, v == true));
                    set(() {});
                  },
                ),
            ]),
          ]),
        );
      }));

  // ------------------------------------------------------------- composer

  Widget _composer() {
    final s = _spec;
    final studio = context.watch<StudioStore>();
    return ContentWidth(
      child: ListView(padding: const EdgeInsets.fromLTRB(0, 12, 0, 40), children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_name, style: T.h2(), overflow: TextOverflow.ellipsis),
                Text('${s.minor ? 'Minor' : 'Major'} in ${noteName(s.root)} · ${s.bpm.round()} bpm · ${s.beats} beats · ${(60 / s.bpm * s.beats).toStringAsFixed(0)}s loop', style: T.caption()),
              ]),
            ),
            _playButton('draft', _wavLoop(() => _audio.renderTrack(_spec), show: true), size: 52),
          ]),
        ),
        const SizedBox(height: 12),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: WaveformView(wav: _wav)),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(icon: const Icon(Icons.casino_outlined, size: 18), label: const Text('Surprise me'), onPressed: () => _setSpec(_randomSpec(math.Random()))),
            OutlinedButton.icon(icon: const Icon(Icons.shuffle, size: 18), label: const Text('New melody'), onPressed: () => _setSpec(s.copy({'seed': math.Random().nextInt(1 << 30)}))),
            PopupMenuButton<String>(
              tooltip: 'Start from a theme',
              onSelected: (t) => _openInComposer(MusicSpec.forTheme(t), name: '${themeLabel(t)} remix'),
              itemBuilder: (_) => [for (final t in musicThemes) PopupMenuItem(value: t, child: Text(themeLabel(t)))],
              child: const Chip(avatar: Icon(Icons.library_music_outlined, size: 16), label: Text('Start from a theme')),
            ),
          ]),
        ),
        const SectionLabel('Key & tempo', padding: EdgeInsets.fromLTRB(20, 20, 20, 0)),
        ChipPicker<bool>(label: 'Mode', options: const [false, true], value: s.minor, labelOf: (m) => m ? 'Minor (dark)' : 'Major (bright)', onChanged: (v) => _setSpec(s.copy({'minor': v}))),
        ParamSlider(label: 'Key', value: s.root.toDouble(), min: 43, max: 67, divisions: 24, format: (v) => noteName(v.round()), onChanged: (v) => _setSpec(s.copy({'root': v.round()}))),
        ParamSlider(label: 'Tempo', value: s.bpm, min: 40, max: 180, divisions: 140, format: (v) => '${v.round()} bpm', onChanged: (v) => _setSpec(s.copy({'bpm': v.roundToDouble()}))),
        ChipPicker<int>(label: 'Length', options: const [16, 24, 32], value: s.beats, labelOf: (b) => '$b beats', onChanged: (v) => _setSpec(s.copy({'beats': v}))),
        ChipPicker<bool>(label: 'Chords', options: const [false, true], value: s.altChords, labelOf: (a) => a ? 'Searching' : 'Settled', onChanged: (v) => _setSpec(s.copy({'alt': v}))),
        const SectionLabel('Arrangement', padding: EdgeInsets.fromLTRB(20, 20, 20, 0)),
        ChipPicker<String>(
          label: 'Style',
          options: MusicSpec.styles,
          value: s.style,
          labelOf: (v) => switch (v) { 'lilt' => 'Lute & dance', 'ambient' => 'Ambient', 'drone' => 'Drone', 'driving' => 'Driving', _ => v },
          onChanged: (v) => _setSpec(s.copy({'style': v})),
        ),
        ChipPicker<String>(
          label: 'Lead instrument',
          options: MusicSpec.leads,
          value: s.lead,
          labelOf: (v) => switch (v) { 'pluck' => 'Plucked string', 'sine' => 'Flute', 'tri' => 'Ocarina', 'square' => 'Chiptune', 'saw' => 'Brass', _ => v },
          onChanged: (v) => _setSpec(s.copy({'lead': v})),
        ),
        ParamSlider(label: 'Melody', value: s.density, min: 0, max: 1, help: 'How many notes the lead plays', format: (v) => '${(v * 100).round()}%', onChanged: (v) => _setSpec(s.copy({'density': v}))),
        ParamSlider(label: 'Reverb', value: s.reverb, min: 0, max: 0.9, help: 'From a dry room to a great hall', format: (v) => '${(v * 100).round()}%', onChanged: (v) => _setSpec(s.copy({'reverb': v}))),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final (k, label, on) in [('pad', 'Pad', s.pad), ('bass', 'Bass', s.bass), ('drums', 'Drums', s.drums), ('birds', 'Birdsong', s.birds), ('drips', 'Water drips', s.drips)])
              FilterChip(label: Text(label), selected: on, onSelected: (v) => _setSpec(s.copy({k: v}))),
          ]),
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppButton(
              label: _editing == null ? 'Save to my tracks' : 'Save changes',
              icon: Icons.save_outlined,
              kind: ButtonKind.accent,
              onPressed: () async {
                final name = await askName(context, title: 'Name your track', initial: _name);
                if (name == null || name.isEmpty || !mounted) return;
                studio.update((st) {
                  final existing = st.track(_editing ?? '');
                  if (existing != null && !existing.isFile) {
                    existing
                      ..name = name
                      ..spec = _spec;
                  } else {
                    final t = StudioTrack(name: name, spec: _spec);
                    st.tracks.add(t);
                    _editing = t.id;
                  }
                });
                setState(() => _name = name);
                if (mounted) showToast(context, 'Saved "$name" to your tracks');
              },
            ),
            const SizedBox(height: 8),
            AppButton(
              label: 'Save as a WAV file',
              icon: Icons.download_outlined,
              kind: ButtonKind.secondary,
              onPressed: () async {
                final wav = await _audio.renderTrack(_spec);
                if (!mounted) return;
                await deliverFile(context, name: '${_name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-').toLowerCase()}.wav', bytes: wav, mime: 'audio/wav');
              },
            ),
          ]),
        ),
      ]),
    );
  }

  MusicSpec _randomSpec(math.Random r) => MusicSpec(
        bpm: (50 + r.nextInt(110)).toDouble(),
        beats: [16, 24, 32][r.nextInt(3)],
        root: 48 + r.nextInt(14),
        minor: r.nextBool(),
        style: MusicSpec.styles[r.nextInt(4)],
        lead: MusicSpec.leads[r.nextInt(5)],
        pad: r.nextDouble() < 0.8,
        bass: r.nextDouble() < 0.85,
        drums: r.nextBool(),
        density: 0.3 + r.nextDouble() * 0.6,
        reverb: 0.15 + r.nextDouble() * 0.5,
        seed: r.nextInt(1 << 30),
        altChords: r.nextBool(),
        birds: r.nextDouble() < 0.2,
        drips: r.nextDouble() < 0.15,
      );

  // ---------------------------------------------------------------- tracks

  Widget _tracks() {
    final studio = context.watch<StudioStore>();
    final add = Row(children: [
      Expanded(child: AppButton(label: 'Add from device', icon: Icons.audio_file_outlined, kind: ButtonKind.secondary, height: 42, onPressed: _importTracks)),
      const SizedBox(width: 8),
      Expanded(child: AppButton(label: 'Compose', icon: Icons.tune, kind: ButtonKind.secondary, height: 42, onPressed: () => _tabs.animateTo(1))),
    ]);
    if (studio.tracks.isEmpty) {
      return ContentWidth(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const EmptyState(icon: Icons.library_music_outlined, title: 'No tracks yet', message: 'Add songs from your device or compose a loop. Then choose which themes and soundscapes they play for.'),
          add,
        ]),
      );
    }
    String uses(StudioTrack t) => [
          for (final e in studio.musicSlots.entries) if (e.value.contains(t.id)) themeLabel(e.key),
          for (final e in studio.ambienceSlots.entries) if (e.value.contains(t.id)) soundscapeLabels[e.key]?.$1 ?? e.key,
        ].join(', ');
    return ContentWidth(
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
        add,
        const SizedBox(height: 12),
        RowGroup(children: [
          for (final t in studio.tracks)
            ListRow(
              leading: Icon(t.isFile ? Icons.audio_file_outlined : Icons.library_music_outlined, size: 20),
              title: t.name,
              subtitle: [
                t.isFile ? 'From your device' : '${t.spec!.minor ? 'Minor' : 'Major'} · ${t.spec!.bpm.round()} bpm',
                if (uses(t).isNotEmpty) 'plays for ${uses(t)}',
              ].join(' · '),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                _playButton('track:${t.id}', _trackLoop(t)),
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    switch (v) {
                      case 'edit':
                        _openInComposer(t.spec!, id: t.id, name: t.name);
                      case 'assign':
                        await _assign(t);
                      case 'rename':
                        final n = await askName(context, title: 'Rename track', initial: t.name);
                        if (n != null && n.isNotEmpty) studio.update((_) => t.name = n);
                      case 'delete':
                        if (await confirm(context, title: 'Delete "${t.name}"?', message: 'Anything using it goes back to the game\'s own music.')) {
                          studio.update((s) => s.tracks.remove(t));
                          if (t.file != null) unawaited(deleteImported(t.file!));
                        }
                    }
                  },
                  itemBuilder: (_) => [
                    if (!t.isFile) const PopupMenuItem(value: 'edit', child: Text('Edit in the composer')),
                    const PopupMenuItem(value: 'assign', child: Text('Choose where it plays')),
                    const PopupMenuItem(value: 'rename', child: Text('Rename')),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ]),
            ),
        ]),
      ]),
    );
  }

  Future<void> _assign(StudioTrack t) => showAppSheet(context, builder: (sheet) => StatefulBuilder(builder: (sheet, set) {
        final studio = context.read<StudioStore>();
        Widget tick(Icon icon, String label, Map<String, List<String>> slots, String key) => CheckboxListTile(
              secondary: icon,
              title: Text(label, style: T.body()),
              value: slots[key]?.contains(t.id) ?? false,
              onChanged: (v) {
                studio.update((_) => StudioStore.toggle(slots, key, t.id, v == true));
                set(() {});
              },
            );
        return SizedBox(
          height: MediaQuery.sizeOf(sheet).height * 0.75,
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
            SheetTitle('Where "${t.name}" plays', subtitle: 'It joins the playlist for everything you tick.'),
            const SectionLabel('Music'),
            RowGroup(children: [for (final theme in musicThemes) tick(Icon(themeIcon(theme), size: 20), themeLabel(theme), studio.musicSlots, theme)]),
            const SectionLabel('Soundscapes'),
            RowGroup(children: [
              for (final k in ambienceNames) tick(Icon(soundscapeLabels[k]?.$2 ?? Icons.graphic_eq, size: 20), soundscapeLabels[k]?.$1 ?? k, studio.ambienceSlots, k),
            ]),
          ]),
        );
      }));

  // ----------------------------------------------------------- soundscapes

  Widget _soundscapes() {
    final s = context.watch<SettingsController>();
    final studio = context.watch<StudioStore>();
    final vol = s.ambienceVolume.clamp(0.3, 1).toDouble();
    return ContentWidth(
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
        Text('Soundscapes play under the music and follow the weather and the place you are in. Long-press one to use your own recordings instead.', style: T.small()),
        const SizedBox(height: 12),
        RowGroup(children: [
          ListRow(leading: const Icon(Icons.surround_sound_outlined, size: 20), title: 'Ambient sound in stories', trailing: Switch(value: s.ambienceEnabled, onChanged: (v) => s.update((s) => s.ambienceEnabled = v))),
          ParamSlider(label: 'Volume', value: s.ambienceVolume, min: 0, max: 1, format: (v) => '${(v * 100).round()}%', onChanged: (v) => s.update((s) => s.ambienceVolume = v)),
        ]),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: MediaQuery.sizeOf(context).width > 600 ? 3 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.5,
          children: [
            for (final k in ambienceNames)
              Builder(builder: (context) {
                final id = 'amb:$k';
                final on = _playing == id;
                final (label, icon) = soundscapeLabels[k] ?? (k, Icons.graphic_eq);
                final mine = studio.ambienceFor(k);
                return GestureDetector(
                  onLongPress: () => _ownSoundscape(k, label),
                  child: AppCard(
                    onTap: () => _loop(id, mine != null ? _trackLoop(mine) : _wavLoop(() => _audio.renderSoundscape(k), volume: vol)),
                    color: on ? AppColors.accentSoft : null,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Row(children: [
                        Icon(icon, color: on ? AppColors.accent : AppColors.text),
                        const Spacer(),
                        if (_loading == id) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) else Icon(on ? Icons.stop : Icons.play_arrow, size: 18, color: on ? AppColors.accent : AppColors.textMuted),
                      ]),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(label, style: T.h3()),
                        Text(mine != null ? 'Your audio' : 'Generated', style: T.caption(color: mine != null ? AppColors.accent : AppColors.textFaint)),
                      ]),
                    ]),
                  ),
                );
              }),
          ],
        ),
        const SizedBox(height: 16),
        AppButton(label: 'Add ambient audio from device', icon: Icons.audio_file_outlined, kind: ButtonKind.secondary, onPressed: () async {
          final added = await _importTracks();
          if (added.length == 1 && mounted) await _assign(added.first);
        }),
      ]),
    );
  }

  Future<void> _ownSoundscape(String kind, String label) async {
    final studio = context.read<StudioStore>();
    final choice = await showAppSheet<String>(context, builder: (sheet) => ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
          SheetTitle(label),
          RowGroup(children: [
            ListRow(leading: const Icon(Icons.audio_file_outlined, size: 20), title: 'Add audio from my device', onTap: () => Navigator.pop(sheet, 'import')),
            if (studio.tracks.isNotEmpty) ListRow(leading: const Icon(Icons.playlist_add_check, size: 20), title: 'Choose from my tracks', onTap: () => Navigator.pop(sheet, 'choose')),
            if (studio.ambienceSlots[kind]?.isNotEmpty ?? false) ListRow(leading: const Icon(Icons.restore, size: 20), title: 'Use the generated sound again', onTap: () => Navigator.pop(sheet, 'reset')),
          ]),
        ]));
    if (!mounted) return;
    switch (choice) {
      case 'import':
        final added = await _importTracks();
        if (added.isNotEmpty) studio.update((s) => s.ambienceSlots.putIfAbsent(kind, () => []).addAll([for (final a in added) a.id]));
      case 'choose':
        await _chooseFor(label, studio.ambienceSlots, kind);
      case 'reset':
        studio.update((s) => s.ambienceSlots.remove(kind));
    }
  }
}
