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

/// The game's sounds by where you hear them.
const sfxGroups = <(String, IconData, List<String>)>[
  ('Dice', Icons.casino_outlined, ['dice', 'dice_land', 'crit', 'fumble']),
  ('Combat', Icons.sports_martial_arts, ['sword', 'hit', 'miss', 'roar', 'death', 'flee']),
  ('Magic', Icons.auto_awesome, ['spell', 'heal', 'magic', 'buff', 'chime']),
  ('World', Icons.public, ['door', 'creak', 'splash', 'footsteps', 'thunder', 'coin', 'page']),
  ('Moments', Icons.emoji_events_outlined, ['levelup', 'quest', 'success', 'fail', 'click']),
];

String sfxLabel(String name) => switch (name) {
      'dice' => 'Dice rolling',
      'dice_land' => 'Dice landing',
      'crit' => 'Critical hit',
      'fumble' => 'Fumble',
      'sword' => 'Sword swing',
      'hit' => 'Hit',
      'miss' => 'Miss',
      'roar' => 'Monster roar',
      'death' => 'Defeat',
      'flee' => 'Flee',
      'spell' => 'Spell cast',
      'heal' => 'Healing',
      'magic' => 'Magic',
      'buff' => 'Blessing',
      'chime' => 'Chime (someone wants to talk)',
      'door' => 'Door',
      'creak' => 'Creak',
      'splash' => 'Splash',
      'footsteps' => 'Footsteps',
      'thunder' => 'Thunder',
      'coin' => 'Coins',
      'page' => 'Page turn',
      'levelup' => 'Level up',
      'quest' => 'New quest',
      'success' => 'Success',
      'fail' => 'Failure',
      'click' => 'Tap',
      _ => name,
    };

/// Listen to, adjust and replace every sound in the game, or design new ones.
class SfxStudioScreen extends StatefulWidget {
  const SfxStudioScreen({super.key});

  @override
  State<SfxStudioScreen> createState() => _SfxStudioScreenState();
}

class _SfxStudioScreenState extends State<SfxStudioScreen> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 3, vsync: this);
  late final AudioService _audio;
  final _rng = math.Random();

  String? _open;
  SfxSpec _spec = const SfxSpec(wave: 'square', hz: 880, duration: 0.08, repeats: 2, gap: 0.08, step: 7, decay: 0.8);
  String? _editing;
  String _name = 'My sound';
  Uint8List? _wav;
  bool _rendering = false;

  @override
  void initState() {
    super.initState();
    _audio = context.read<AudioService>();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _hear({String? name, SfxSpec? spec, double pitch = 1, double volume = 1, bool show = false}) async {
    final wav = await _audio.renderSound(name: name, spec: spec, pitch: pitch);
    if (show && mounted) setState(() => _wav = wav);
    await _audio.previewSound(wav, volume: volume);
  }

  Future<void> _hearDraft() async {
    setState(() => _rendering = true);
    try {
      await _hear(spec: _spec, show: true);
    } finally {
      if (mounted) setState(() => _rendering = false);
    }
  }

  void _set(SfxSpec s, {bool play = false}) {
    setState(() => _spec = s);
    if (play) _hearDraft();
  }

  void _openInDesigner(SfxSpec spec, {String? id, String? name}) {
    setState(() {
      _spec = spec;
      _editing = id;
      _name = name ?? 'My sound';
      _wav = null;
    });
    _tabs.animateTo(1);
    _hearDraft();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sound effects'),
        bottom: TabBar(controller: _tabs, isScrollable: true, tabAlignment: TabAlignment.start, tabs: const [Tab(text: 'Game sounds'), Tab(text: 'Designer'), Tab(text: 'My sounds')]),
      ),
      body: TabBarView(controller: _tabs, children: [_gameSounds(), _designer(), _mySounds()]),
    );
  }

  // ----------------------------------------------------------- game sounds

  Widget _gameSounds() {
    final s = context.watch<SettingsController>();
    final studio = context.watch<StudioStore>();
    return ContentWidth(
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
        Text('Tap a sound to hear it. Open one to change its pitch and loudness, or swap in a sound you designed.', style: T.small()),
        const SizedBox(height: 12),
        RowGroup(children: [
          ListRow(leading: const Icon(Icons.volume_up_outlined, size: 20), title: 'Sound effects in stories', trailing: Switch(value: s.sfxEnabled, onChanged: (v) => s.update((s) => s.sfxEnabled = v))),
          ParamSlider(label: 'Volume', value: s.sfxVolume, min: 0, max: 1, format: (v) => '${(v * 100).round()}%', onChanged: (v) => s.update((s) => s.sfxVolume = v)),
        ]),
        for (final (group, icon, names) in sfxGroups) ...[
          SectionLabel(group),
          RowGroup(children: [
            for (final n in names) _soundRow(studio, n, icon),
          ]),
        ],
        const SizedBox(height: 16),
        if (studio.tweaks.isNotEmpty || studio.sfxSlots.isNotEmpty)
          AppButton(
            label: 'Restore every original sound',
            icon: Icons.restore,
            kind: ButtonKind.secondary,
            onPressed: () async {
              if (await confirm(context, title: 'Restore all sounds?', message: 'Your pitch and volume changes and replacements are removed. Your designed sounds are kept.', action: 'Restore', danger: false)) {
                studio.update((s) {
                  s.tweaks.clear();
                  s.sfxSlots.clear();
                });
              }
            },
          ),
      ]),
    );
  }

  /// Plays a game sound as it will sound in stories (or one of its variations).
  void _hearGame(StudioStore studio, String name, {double? pitch, double? volume}) {
    final tweak = studio.tweakFor(name);
    final x = studio.soundFor(name);
    final p = pitch ?? tweak.pitch, v = volume ?? tweak.volume;
    if (x != null && x.isFile) {
      _audio.previewFile(x.file!, volume: v.clamp(0, 1).toDouble());
    } else {
      _hear(name: x == null ? name : null, spec: x?.spec, pitch: p, volume: v);
    }
  }

  void _hearMine(StudioSound x) => x.isFile ? _audio.previewFile(x.file!) : _hear(spec: x.spec);

  Widget _soundRow(StudioStore studio, String name, IconData icon) {
    final tweak = studio.tweakFor(name);
    final mine = [for (final id in studio.sfxSlots[name] ?? const <String>[]) ?studio.sound(id)];
    final open = _open == name;
    final changed = mine.isNotEmpty || !tweak.isDefault;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ListRow(
        leading: Icon(icon, size: 20, color: changed ? AppColors.accent : null),
        title: sfxLabel(name),
        subtitle: [
          if (mine.length == 1) 'Your sound: ${mine.single.name}',
          if (mine.length > 1) '${mine.length} of your sounds, picked at random',
          if ((tweak.pitch - 1).abs() >= 0.01) 'pitch ×${tweak.pitch.toStringAsFixed(2)}',
          if ((tweak.volume - 1).abs() >= 0.01) 'volume ${(tweak.volume * 100).round()}%',
        ].join(' · ').ifEmpty(null),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(tooltip: 'Play', icon: const Icon(Icons.play_arrow), onPressed: () => _hearGame(studio, name)),
          Icon(open ? Icons.expand_less : Icons.expand_more, size: 18, color: AppColors.textFaint),
        ]),
        onTap: () => setState(() => _open = open ? null : name),
      ),
      if (open)
        Container(
          color: AppColors.surface2,
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ParamSlider(
              label: 'Pitch',
              value: tweak.pitch,
              min: 0.5,
              max: 2,
              help: 'Lower is deeper and slower, higher is brighter and quicker',
              format: (v) => '×${v.toStringAsFixed(2)}',
              onChanged: (v) => studio.update((s) => s.tweaks[name] = SfxTweak(volume: tweak.volume, pitch: v)),
              onChangeEnd: (v) => _hearGame(studio, name, pitch: v),
            ),
            ParamSlider(
              label: 'Loudness',
              value: tweak.volume,
              min: 0,
              max: 1.5,
              format: (v) => '${(v * 100).round()}%',
              onChanged: (v) => studio.update((s) => s.tweaks[name] = SfxTweak(volume: v, pitch: tweak.pitch)),
              onChangeEnd: (v) => _hearGame(studio, name, volume: v),
            ),
            for (final x in mine)
              ListRow(
                leading: Icon(x.isFile ? Icons.audio_file_outlined : Icons.graphic_eq, size: 18),
                title: x.name,
                subtitle: x.isFile ? 'From your device' : 'Designed',
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(tooltip: 'Play', icon: const Icon(Icons.play_arrow, size: 20), onPressed: () => _hearMine(x)),
                  IconButton(tooltip: 'Stop using it here', icon: const Icon(Icons.close, size: 18), onPressed: () => studio.update((s) => StudioStore.toggle(s.sfxSlots, name, x.id, false))),
                ]),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.audio_file_outlined, size: 18),
                  label: const Text('Add a file'),
                  onPressed: () async {
                    final added = await _importSounds();
                    if (added.isNotEmpty) studio.update((s) => s.sfxSlots.putIfAbsent(name, () => []).addAll([for (final a in added) a.id]));
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.playlist_add_check, size: 18),
                  label: const Text('Choose my sounds'),
                  onPressed: studio.sounds.isEmpty ? () => showToast(context, 'Design a sound or add a file first.', icon: Icons.info_outline) : () => _chooseFor(name),
                ),
                OutlinedButton.icon(icon: const Icon(Icons.tune, size: 18), label: const Text('Design a new one'), onPressed: () => _openInDesigner(_spec, name: '${sfxLabel(name)} (new)')),
                if (changed)
                  TextButton.icon(
                    icon: const Icon(Icons.restore, size: 18),
                    label: const Text('Restore original'),
                    onPressed: () => studio.update((s) {
                      s.tweaks.remove(name);
                      s.sfxSlots.remove(name);
                    }),
                  ),
              ]),
            ),
          ]),
        ),
    ]);
  }

  Future<List<StudioSound>> _importSounds() async {
    final files = await chooseAudio(context);
    if (files.isEmpty || !mounted) return const [];
    final added = [for (final f in files) StudioSound(name: f.name, file: f.path)];
    context.read<StudioStore>().update((s) => s.sounds.addAll(added));
    showToast(context, 'Added ${added.length} ${added.length == 1 ? 'sound' : 'sounds'}');
    return added;
  }

  Future<void> _chooseFor(String name) => showAppSheet(context, builder: (sheet) => StatefulBuilder(builder: (sheet, set) {
        final studio = context.read<StudioStore>();
        return SizedBox(
          height: MediaQuery.sizeOf(sheet).height * 0.7,
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
            SheetTitle('Play for "${sfxLabel(name)}"', subtitle: 'Tick several for variety: one is picked each time.'),
            RowGroup(children: [
              for (final x in studio.sounds)
                CheckboxListTile(
                  secondary: Icon(x.isFile ? Icons.audio_file_outlined : Icons.graphic_eq, size: 20),
                  title: Text(x.name, style: T.body()),
                  value: studio.sfxSlots[name]?.contains(x.id) ?? false,
                  onChanged: (v) {
                    studio.update((s) => StudioStore.toggle(s.sfxSlots, name, x.id, v == true));
                    set(() {});
                  },
                ),
            ]),
          ]),
        );
      }));

  // -------------------------------------------------------------- designer

  Widget _designer() {
    final s = _spec;
    final studio = context.watch<StudioStore>();
    String secs(double v) => v < 1 ? '${(v * 1000).round()} ms' : '${v.toStringAsFixed(2)} s';
    return ContentWidth(
      child: ListView(padding: const EdgeInsets.fromLTRB(0, 12, 0, 40), children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Expanded(child: Text(_name, style: T.h2(), overflow: TextOverflow.ellipsis)),
            CircleIconButton(icon: Icons.play_arrow, size: 52, tooltip: 'Play', busy: _rendering, onPressed: _hearDraft),
          ]),
        ),
        const SizedBox(height: 12),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: WaveformView(wav: _wav)),
        const SectionLabel('Generate', padding: EdgeInsets.fromLTRB(20, 20, 20, 0)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: CompactChips(child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final k in SfxSpec.kinds) ActionChip(label: Text(k[0].toUpperCase() + k.substring(1)), onPressed: () => _set(SfxSpec.random(k, _rng), play: true)),
            ActionChip(avatar: const Icon(Icons.auto_fix_high, size: 16), label: const Text('Mutate'), onPressed: () => _set(_mutate(s), play: true)),
          ])),
        ),
        const SectionLabel('Shape', padding: EdgeInsets.fromLTRB(20, 20, 20, 0)),
        ChipPicker<String>(
          label: 'Sound source',
          options: SfxSpec.waves,
          value: s.wave,
          labelOf: (w) => switch (w) { 'sine' => 'Pure', 'square' => 'Retro', 'saw' => 'Buzzy', 'tri' => 'Soft', 'noise' => 'Noise', 'pluck' => 'String', 'bell' => 'Bell', _ => w },
          onChanged: (v) => _set(s.copy({'wave': v}), play: true),
        ),
        ParamSlider(
          label: 'Pitch',
          value: math.log(s.hz) / math.ln2,
          min: math.log(40) / math.ln2,
          max: math.log(4000) / math.ln2,
          format: (v) => '${math.pow(2, v).round()} Hz',
          onChanged: (v) => _set(s.copy({'hz': math.pow(2, v).toDouble()})),
          onChangeEnd: (_) => _hearDraft(),
        ),
        ParamSlider(label: 'Slide', value: s.sweep, min: -0.95, max: 3, help: 'Pitch falls (left) or rises (right) over the sound', format: (v) => v == 0 ? 'none' : (v < 0 ? 'falls ${(-v * 100).round()}%' : 'rises ${(v * 100).round()}%'), onChanged: (v) => _set(s.copy({'sweep': v})), onChangeEnd: (_) => _hearDraft()),
        ParamSlider(label: 'Length', value: s.duration, min: 0.02, max: 2, format: secs, onChanged: (v) => _set(s.copy({'dur': v})), onChangeEnd: (_) => _hearDraft()),
        ParamSlider(label: 'Attack', value: s.attack, min: 0.001, max: 0.5, help: 'How softly it starts', format: secs, onChanged: (v) => _set(s.copy({'a': v})), onChangeEnd: (_) => _hearDraft()),
        ParamSlider(label: 'Decay', value: s.decay, min: 0.05, max: 1, help: 'How quickly it fades after the peak', format: (v) => '${(v * 100).round()}%', onChanged: (v) => _set(s.copy({'d': v})), onChangeEnd: (_) => _hearDraft()),
        ParamSlider(label: 'Hold', value: s.sustain, min: 0, max: 1, help: 'How much stays until the end', format: (v) => '${(v * 100).round()}%', onChanged: (v) => _set(s.copy({'s': v})), onChangeEnd: (_) => _hearDraft()),
        const SectionLabel('Pattern', padding: EdgeInsets.fromLTRB(20, 20, 20, 0)),
        ParamSlider(label: 'Notes', value: s.repeats.toDouble(), min: 1, max: 8, divisions: 7, format: (v) => '${v.round()}', onChanged: (v) => _set(s.copy({'rep': v.round()})), onChangeEnd: (_) => _hearDraft()),
        ParamSlider(label: 'Gap', value: s.gap, min: 0.02, max: 0.5, format: secs, onChanged: (v) => _set(s.copy({'gap': v})), onChangeEnd: (_) => _hearDraft()),
        ParamSlider(label: 'Step', value: s.step.toDouble(), min: -12, max: 12, divisions: 24, help: 'Semitones between notes', format: (v) => v == 0 ? 'same' : '${v > 0 ? '+' : ''}${v.round()}', onChanged: (v) => _set(s.copy({'step': v.round()})), onChangeEnd: (_) => _hearDraft()),
        const SectionLabel('Texture', padding: EdgeInsets.fromLTRB(20, 20, 20, 0)),
        ParamSlider(label: 'Wobble', value: s.vibrato, min: 0, max: 0.05, format: (v) => '${(v * 2000).round()}%', onChanged: (v) => _set(s.copy({'vib': v})), onChangeEnd: (_) => _hearDraft()),
        ParamSlider(label: 'Grit', value: s.noise, min: 0, max: 1, help: 'A burst of noise under the note', format: (v) => '${(v * 100).round()}%', onChanged: (v) => _set(s.copy({'noise': v})), onChangeEnd: (_) => _hearDraft()),
        ParamSlider(label: 'Echo', value: s.reverb, min: 0, max: 0.8, format: (v) => '${(v * 100).round()}%', onChanged: (v) => _set(s.copy({'rev': v})), onChangeEnd: (_) => _hearDraft()),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppButton(
              label: _editing == null ? 'Save to my sounds' : 'Save changes',
              icon: Icons.save_outlined,
              kind: ButtonKind.accent,
              onPressed: () async {
                final name = await askName(context, title: 'Name your sound', initial: _name);
                if (name == null || name.isEmpty || !mounted) return;
                studio.update((st) {
                  final existing = st.sound(_editing ?? '');
                  if (existing != null && !existing.isFile) {
                    existing
                      ..name = name
                      ..spec = _spec;
                  } else {
                    final x = StudioSound(name: name, spec: _spec);
                    st.sounds.add(x);
                    _editing = x.id;
                  }
                });
                setState(() => _name = name);
                if (mounted) showToast(context, 'Saved "$name"');
              },
            ),
            const SizedBox(height: 8),
            AppButton(
              label: 'Save as a WAV file',
              icon: Icons.download_outlined,
              kind: ButtonKind.secondary,
              onPressed: () async {
                final wav = await _audio.renderSound(spec: _spec);
                if (!mounted) return;
                await deliverFile(context, name: '${_name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-').toLowerCase()}.wav', bytes: wav, mime: 'audio/wav');
              },
            ),
          ]),
        ),
      ]),
    );
  }

  SfxSpec _mutate(SfxSpec s) {
    double nudge(double v, double lo, double hi, double amt) => (v + (_rng.nextDouble() * 2 - 1) * (hi - lo) * amt).clamp(lo, hi).toDouble();
    return s.copy({
      'hz': nudge(s.hz, 40, 4000, 0.08),
      'sweep': nudge(s.sweep, -0.95, 3, 0.1),
      'dur': nudge(s.duration, 0.02, 2, 0.06),
      'd': nudge(s.decay, 0.05, 1, 0.15),
      'vib': nudge(s.vibrato, 0, 0.05, 0.2),
      'noise': nudge(s.noise, 0, 1, 0.1),
    });
  }

  // ------------------------------------------------------------- my sounds

  Widget _mySounds() {
    final studio = context.watch<StudioStore>();
    final add = Row(children: [
      Expanded(child: AppButton(label: 'Add from device', icon: Icons.audio_file_outlined, kind: ButtonKind.secondary, height: 42, onPressed: _importSounds)),
      const SizedBox(width: 8),
      Expanded(child: AppButton(label: 'Design', icon: Icons.tune, kind: ButtonKind.secondary, height: 42, onPressed: () => _tabs.animateTo(1))),
    ]);
    if (studio.sounds.isEmpty) {
      return ContentWidth(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const EmptyState(icon: Icons.graphic_eq, title: 'No sounds yet', message: 'Add audio files from your device or design a sound, then swap them in for any sound in the game.'),
          add,
        ]),
      );
    }
    return ContentWidth(
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
        add,
        const SizedBox(height: 12),
        RowGroup(children: [
          for (final x in studio.sounds)
            ListRow(
              leading: Icon(x.isFile ? Icons.audio_file_outlined : Icons.graphic_eq, size: 20),
              title: x.name,
              subtitle: [
                x.isFile ? 'From your device' : '${x.spec!.wave} · ${x.spec!.hz.round()} Hz',
                for (final e in studio.sfxSlots.entries) if (e.value.contains(x.id)) 'plays for ${sfxLabel(e.key)}',
              ].join(' · '),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(tooltip: 'Play', icon: const Icon(Icons.play_arrow), onPressed: () => _hearMine(x)),
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    switch (v) {
                      case 'edit':
                        _openInDesigner(x.spec!, id: x.id, name: x.name);
                      case 'assign':
                        await _assign(x);
                      case 'rename':
                        final n = await askName(context, title: 'Rename sound', initial: x.name);
                        if (n != null && n.isNotEmpty) studio.update((_) => x.name = n);
                      case 'delete':
                        if (await confirm(context, title: 'Delete "${x.name}"?', message: 'Game sounds using it go back to the original.')) {
                          studio.update((s) => s.sounds.remove(x));
                          if (x.file != null) unawaited(deleteImported(x.file!));
                        }
                    }
                  },
                  itemBuilder: (_) => [
                    if (!x.isFile) const PopupMenuItem(value: 'edit', child: Text('Edit in the designer')),
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

  Future<void> _assign(StudioSound x) => showAppSheet(context, builder: (sheet) => StatefulBuilder(builder: (sheet, set) {
        final studio = context.read<StudioStore>();
        return SizedBox(
          height: MediaQuery.sizeOf(sheet).height * 0.7,
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
            SheetTitle('Where "${x.name}" plays', subtitle: 'It replaces the game sounds you tick. A sound with several picks one at random.'),
            for (final (group, _, names) in sfxGroups) ...[
              SectionLabel(group),
              RowGroup(children: [
                for (final n in names)
                  CheckboxListTile(
                    title: Text(sfxLabel(n), style: T.body()),
                    value: studio.sfxSlots[n]?.contains(x.id) ?? false,
                    onChanged: (v) {
                      studio.update((s) => StudioStore.toggle(s.sfxSlots, n, x.id, v == true));
                      set(() {});
                    },
                  ),
              ]),
            ],
          ]),
        );
      }));
}

extension on String {
  String? ifEmpty(String? other) => isEmpty ? other : this;
}
