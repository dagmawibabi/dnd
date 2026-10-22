import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/narrator.dart';
import '../../../theme/ui.dart';
import '../story/story_extras.dart' show NowReadingBar;

/// Every voice clip saved on the device: what it says, who says it, and the
/// story it belongs to. Play any of them again for free, or delete them.
class SavedAudioScreen extends StatefulWidget {
  const SavedAudioScreen({super.key});

  @override
  State<SavedAudioScreen> createState() => _SavedAudioScreenState();
}

class _SavedAudioScreenState extends State<SavedAudioScreen> {
  List<SavedClip>? _clips;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final clips = await context.read<Narrator>().savedClips();
    if (mounted) setState(() => _clips = clips);
  }

  String _group(SavedClip c) => c.isSample ? 'Voice samples' : (c.story.isNotEmpty ? c.story : (c.text.isEmpty ? 'Earlier clips' : 'Previews and settings'));

  static String _size(int bytes) => bytes >= 1024 * 1024 ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB' : '${(bytes / 1024).ceil()} KB';

  static String _when(DateTime? d) {
    if (d == null) return '';
    final ago = DateTime.now().difference(d);
    if (ago.inMinutes < 1) return 'just now';
    if (ago.inHours < 1) return '${ago.inMinutes} min ago';
    if (ago.inDays < 1) return '${ago.inHours} h ago';
    if (ago.inDays < 7) return '${ago.inDays} d ago';
    return '${d.day}/${d.month}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final narrator = context.watch<Narrator>();
    final all = _clips;
    final q = _search.text.trim().toLowerCase();
    final shown = all?.where((c) => q.isEmpty || '${c.text} ${c.speaker} ${c.story} ${c.voice}'.toLowerCase().contains(q)).toList();
    final groups = <String, List<SavedClip>>{};
    for (final c in shown ?? const <SavedClip>[]) {
      groups.putIfAbsent(_group(c), () => []).add(c);
    }
    final total = (all ?? const <SavedClip>[]).fold<int>(0, (n, c) => n + c.bytes);
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Saved audio', style: T.h3()),
          if (all != null) Text('${all.length} clips · ${_size(total)}', style: T.caption()),
        ]),
        actions: [
          if (all != null && all.isNotEmpty)
            TextButton(
              onPressed: () async {
                if (!await confirm(context, title: 'Clear all saved audio?', message: 'Lines will be generated again (and charged again) the next time they are read.')) return;
                if (!context.mounted) return;
                await context.read<Narrator>().clearCache();
                await _load();
              },
              child: const Text('Clear all'),
            ),
        ],
      ),
      bottomNavigationBar: const NowReadingBar(),
      body: all == null
          ? const Center(child: CircularProgressIndicator())
          : all.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: EmptyState(icon: Icons.library_music_outlined, title: 'No saved audio', message: 'AI narration, character lines and voice samples are kept here after they play, so listening again is free.'),
                )
              : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
                  TextField(
                    controller: _search,
                    style: T.body(),
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search, size: 20), hintText: 'Search what was said, who, or the story'),
                  ),
                  for (final e in groups.entries) ...[
                    SectionLabel(e.key, trailing: Text('${e.value.length}', style: T.caption())),
                    RowGroup(children: [
                      for (final c in e.value)
                        ListRow(
                          leading: IconButton(
                            tooltip: 'Play',
                            icon: Icon(narrator.speaking && narrator.current == (c.text.isEmpty ? 'Saved clip' : c.text) ? Icons.graphic_eq : Icons.play_circle_outline),
                            onPressed: () => narrator.playFiles([c.file.path], label: c.text.isEmpty ? 'Saved clip' : c.text, speaker: c.speaker.isEmpty ? null : c.speaker),
                          ),
                          title: c.text.isEmpty ? (c.isSample ? 'Voice sample' : 'A saved clip') : c.text,
                          subtitle: [
                            c.speaker.isEmpty ? (c.isSample ? '' : 'Narrator') : c.speaker,
                            if (c.voice.isNotEmpty) narrator.labelOfVoice(c.voice),
                            _size(c.bytes),
                            _when(c.at),
                          ].where((s) => s.isNotEmpty).join(' · '),
                          trailing: IconButton(
                            tooltip: 'Delete',
                            icon: const Icon(Icons.delete_outline, size: 20),
                            onPressed: () async {
                              await narrator.deleteClip(c);
                              await _load();
                            },
                          ),
                        ),
                    ]),
                  ],
                  if (groups.isEmpty) Padding(padding: const EdgeInsets.only(top: 24), child: Text('Nothing matches.', style: T.small(), textAlign: TextAlign.center)),
                ]),
    );
  }
}
