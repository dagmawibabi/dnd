import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../services/audio/synth.dart';
import '../../../theme/ui.dart';

/// A labelled slider with its value on the right.
class ParamSlider extends StatelessWidget {
  const ParamSlider({super.key, required this.label, required this.value, required this.min, required this.max, required this.onChanged, this.onChangeEnd, this.format, this.divisions, this.help});
  final String label;
  final double value, min, max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final String Function(double v)? format;
  final int? divisions;
  final String? help;

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(min, max).toDouble();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(label, style: T.body())),
          Text(format?.call(v) ?? v.toStringAsFixed(2), style: T.small(color: AppColors.text)),
          const SizedBox(width: 8),
        ]),
        if (help != null) Text(help!, style: T.caption()),
        Slider(value: v, min: min, max: max, divisions: divisions, onChanged: onChanged, onChangeEnd: onChangeEnd),
      ]),
    );
  }
}

/// A row of choice chips for picking one of a few options.
class ChipPicker<V> extends StatelessWidget {
  const ChipPicker({super.key, required this.label, required this.options, required this.value, required this.onChanged, this.labelOf, this.iconOf});
  final String label;
  final List<V> options;
  final V value;
  final ValueChanged<V> onChanged;
  final String Function(V)? labelOf;
  final IconData? Function(V)? iconOf;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: T.body()),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final o in options)
              ChoiceChip(
                avatar: iconOf?.call(o) == null ? null : Icon(iconOf!(o), size: 16),
                label: Text(labelOf?.call(o) ?? '$o'),
                selected: o == value,
                onSelected: (_) => onChanged(o),
              ),
          ]),
        ]),
      );
}

/// Draws a WAV's shape: peaks per column, like an audio editor.
class WaveformView extends StatelessWidget {
  const WaveformView({super.key, required this.wav, this.height = 72, this.color = AppColors.accent, this.progress});
  final Uint8List? wav;
  final double height;
  final Color color;
  final double? progress;

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: wav == null
              ? Center(child: Text('Press play to hear it', style: T.caption()))
              : CustomPaint(painter: _WavePainter(decodeWav(wav!), color), size: Size.infinite),
        ),
      );
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.samples, this.color);
  final Float32List samples;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;
    final mid = size.height / 2;
    final cols = size.width.floor().clamp(1, 2000);
    final per = math.max(1, samples.length ~/ cols);
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid), Paint()..color = AppColors.border);
    for (var x = 0; x < cols; x++) {
      var lo = 0.0, hi = 0.0;
      final start = x * per;
      for (var i = start; i < math.min(start + per, samples.length); i += math.max(1, per ~/ 64)) {
        final s = samples[i];
        if (s < lo) lo = s;
        if (s > hi) hi = s;
      }
      canvas.drawLine(Offset(x.toDouble(), mid - hi * mid * 0.95), Offset(x.toDouble(), mid - lo * mid * 0.95), p);
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => old.samples != samples || old.color != color;
}

/// A text field dialog for naming a creation.
Future<String?> askName(BuildContext context, {required String title, String initial = ''}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(controller: c, autofocus: true, style: T.body(), onSubmitted: (v) => Navigator.pop(ctx, v.trim())),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: T.h3(color: AppColors.textMuted))),
        TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Save')),
      ],
    ),
  );
}

/// Friendly names for the game's music themes.
String themeLabel(String theme) => switch (theme) {
      'menu' => 'Title & menus',
      'tavern' => 'Tavern',
      'town' => 'Town',
      'forest' => 'Wilds & roads',
      'dungeon' => 'Dungeons & caves',
      'combat' => 'Combat',
      'mystery' => 'Mystery',
      'triumph' => 'Triumph',
      'calm' => 'Camp & calm',
      'boss' => 'Boss fight',
      _ => theme,
    };

IconData themeIcon(String theme) => switch (theme) {
      'menu' => Icons.home_outlined,
      'tavern' => Icons.sports_bar_outlined,
      'town' => Icons.location_city_outlined,
      'forest' => Icons.forest_outlined,
      'dungeon' => Icons.castle_outlined,
      'combat' => Icons.sports_martial_arts,
      'mystery' => Icons.search,
      'triumph' => Icons.emoji_events_outlined,
      'calm' => Icons.local_fire_department_outlined,
      'boss' => Icons.whatshot_outlined,
      _ => Icons.music_note,
    };

const noteNames = ['C', 'C♯', 'D', 'E♭', 'E', 'F', 'F♯', 'G', 'A♭', 'A', 'B♭', 'B'];
String noteName(int midi) => '${noteNames[midi % 12]}${midi ~/ 12 - 1}';
