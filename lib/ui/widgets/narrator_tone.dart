import 'package:flutter/material.dart';

import '../../theme/ui.dart';

/// Ways the storyteller can narrate: (label, instruction for the AI, icon).
const narratorTones = <(String, String, IconData)>[
  ('Classic', 'Classic and heroic, like a well-told fantasy novel: vivid, warm, with real stakes', Icons.auto_stories_outlined),
  ('Grim', 'Grim and gritty: harsh, visceral and morally grey; victories cost something', Icons.bloodtype_outlined),
  ('Cinematic', 'Cinematic and fast-paced like an action film: punchy beats, big set pieces, cliffhangers', Icons.movie_filter_outlined),
  ('Poetic', 'Lyrical and poetic: rich imagery, rhythm and metaphor, but always clear', Icons.spa_outlined),
  ('Witty', 'Witty and wry, with dry humor and playful asides from the narrator', Icons.theater_comedy_outlined),
  ('Terse', 'Terse and punchy: short sentences, only what matters, no purple prose', Icons.short_text),
  ('Eerie', 'Eerie and dread-filled slow-burn horror: small wrong details, never explain too much', Icons.dark_mode_outlined),
  ('Cozy', 'Warm and cozy: gentle stakes, kind characters, comfort and small wonders', Icons.local_cafe_outlined),
  ('Comedic', 'Wildly comedic and absurd: escalating mishaps, everyone a little ridiculous', Icons.sentiment_very_satisfied_outlined),
  ('Noir', 'Hard-boiled noir: clipped, cynical, atmospheric, rain and neon and lies', Icons.nightlife_outlined),
  ('Old-school GM', 'An old-school tabletop game master: fair, descriptive, plays the world straight and asks what you do', Icons.casino_outlined),
  ('Epic', 'Grand and epic, like a myth being told: destiny, legends and sweeping scale', Icons.landscape_outlined),
];

/// The short label for a tone (a preset's name, or "Custom").
String toneLabel(String tone) {
  if (tone.isEmpty) return 'Default';
  return narratorTones.where((t) => t.$2 == tone).firstOrNull?.$1 ?? 'Custom';
}

/// Chips for each tone plus your own words. [value] empty means the default voice.
class NarratorTonePicker extends StatefulWidget {
  const NarratorTonePicker({super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<NarratorTonePicker> createState() => _NarratorTonePickerState();
}

class _NarratorTonePickerState extends State<NarratorTonePicker> {
  late final _custom = TextEditingController(text: narratorTones.any((t) => t.$2 == widget.value) ? '' : widget.value);

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.value;
    final preset = narratorTones.where((t) => t.$2 == v).firstOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CompactChips(
        child: CompactChips(child: Wrap(spacing: 5, runSpacing: 5, children: [
          ChoiceChip(label: const Text('Default'), selected: v.isEmpty, visualDensity: const VisualDensity(horizontal: -2, vertical: -2), onSelected: (_) {
            _custom.clear();
            widget.onChanged('');
          }),
          for (final (label, tone, icon) in narratorTones)
            ChoiceChip(
              avatar: Icon(icon, size: 14),
              label: Text(label),
              visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
              selected: v == tone,
              onSelected: (_) {
                _custom.clear();
                widget.onChanged(tone);
              },
            ),
        ])),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _custom,
        style: T.body(),
        minLines: 1,
        maxLines: 3,
        decoration: const InputDecoration(labelText: 'Or describe it yourself', hintText: 'Like a bard telling it in a tavern, full of exaggeration'),
        onChanged: (t) => widget.onChanged(t.trim()),
      ),
      if (preset != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(preset.$2, style: T.caption())),
    ]);
  }
}
