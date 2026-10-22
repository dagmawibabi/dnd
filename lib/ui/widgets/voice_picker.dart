import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/narrator.dart';
import '../../services/settings.dart';
import '../../theme/ui.dart';

/// Picks an AI voice: search, filter by gender, read what each sounds like and
/// hear it before choosing. Returns the chosen voice id (null if dismissed).
Future<String?> showVoicePicker(
  BuildContext context, {
  required String title,
  String? current,
  String? speaker,
  String gender = '',
  String sample = 'The torches gutter as the iron door groans open. Something stirs in the dark.',
  bool allowAutomatic = false,
}) {
  return showAppSheet<String>(context, builder: (_) => _VoicePicker(title: title, current: current, speaker: speaker, gender: gender, sample: sample, allowAutomatic: allowAutomatic));
}

class _VoicePicker extends StatefulWidget {
  const _VoicePicker({required this.title, this.current, this.speaker, required this.gender, required this.sample, required this.allowAutomatic});
  final String title;
  final String? current;
  final String? speaker;
  final String gender;
  final String sample;
  final bool allowAutomatic;

  @override
  State<_VoicePicker> createState() => _VoicePickerState();
}

class _VoicePickerState extends State<_VoicePicker> {
  String _q = '';
  late String _filter = widget.gender == 'female' || widget.gender == 'male' ? widget.gender : 'all';
  String? _playing;

  @override
  void initState() {
    super.initState();
    final n = context.read<Narrator>();
    if (context.read<SettingsController>().useElevenLabs && n.elevenVoices.isEmpty) n.loadElevenVoices();
  }

  void _preview(Narrator n, String id, String? url) {
    setState(() => _playing = id);
    if (url != null) {
      n.playSample(url);
    } else {
      n.previewVoice(id, widget.sample);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.watch<Narrator>();
    final options = n.voiceOptions;
    final list = options.where((o) {
      final g = n.voiceGender(o.$1);
      if (_filter != 'all' && g != _filter && !(_filter == 'other' && g.isEmpty)) return false;
      if (_q.isEmpty) return true;
      return '${o.$2} ${n.describeVoice(o.$1)}'.toLowerCase().contains(_q);
    }).toList();
    final counts = {
      'female': options.where((o) => n.voiceGender(o.$1) == 'female').length,
      'male': options.where((o) => n.voiceGender(o.$1) == 'male').length,
      'other': options.where((o) => n.voiceGender(o.$1).isEmpty).length,
    };
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: Column(children: [
        SheetTitle(widget.title, subtitle: widget.speaker == null ? 'Tap a voice to choose it · ▶ to hear it first' : 'For ${widget.speaker} · tap to choose, ▶ to hear it'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(style: T.body(), decoration: const InputDecoration(hintText: 'Search names, accents, styles', prefixIcon: Icon(Icons.search, size: 18)), onChanged: (v) => setState(() => _q = v.toLowerCase())),
        ),
        SizedBox(
          height: 40,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
            for (final (id, label) in [('all', 'All ${options.length}'), ('female', 'Female ${counts['female']}'), ('male', 'Male ${counts['male']}'), if (counts['other']! > 0) ('other', 'Other ${counts['other']}')])
              Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: Text(label), selected: _filter == id, onSelected: (_) => setState(() => _filter = id))),
          ]),
        ),
        if (n.elevenLoading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
            if (widget.allowAutomatic)
              RowGroup(children: [
                ListRow(
                  leading: const Icon(Icons.auto_awesome_outlined, size: 20),
                  title: 'Automatic',
                  subtitle: 'A voice matched to them, kept for the whole story',
                  trailing: widget.current == null ? const Icon(Icons.check_circle, size: 20, color: AppColors.accent) : null,
                  onTap: () => Navigator.pop(context, ''),
                ),
              ]),
            if (widget.allowAutomatic) const SizedBox(height: 10),
            if (options.isEmpty && !n.elevenLoading) EmptyState(icon: Icons.voice_over_off_outlined, title: 'No voices', message: context.read<SettingsController>().useElevenLabs ? 'Check your ElevenLabs key in Settings → Voice.' : 'This voice model has no named voices; its default is used.'),
            if (list.isNotEmpty)
              RowGroup(children: [
                for (final (id, label, sample) in list)
                  ListRow(
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: id == widget.current ? AppColors.accentSoft : AppColors.surface2),
                      child: Icon(switch (n.voiceGender(id)) { 'female' => Icons.face_3_outlined, 'male' => Icons.face_6_outlined, _ => Icons.record_voice_over_outlined }, size: 18, color: id == widget.current ? AppColors.accent : AppColors.textMuted),
                    ),
                    title: label,
                    subtitle: n.describeVoice(id).isEmpty ? null : n.describeVoice(id),
                    onTap: () => Navigator.pop(context, id),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: 'Hear it',
                        icon: Icon(_playing == id && n.speaking ? Icons.graphic_eq : Icons.play_circle_outline, color: _playing == id ? AppColors.accent : null),
                        onPressed: () => _preview(n, id, sample),
                      ),
                      Icon(id == widget.current ? Icons.check_circle : Icons.circle_outlined, size: 20, color: id == widget.current ? AppColors.accent : AppColors.textFaint),
                    ]),
                  ),
              ]),
            const SizedBox(height: 10),
            Text('Previews are cached, so hearing a voice again is free.', textAlign: TextAlign.center, style: T.caption()),
          ]),
        ),
      ]),
    );
  }
}
