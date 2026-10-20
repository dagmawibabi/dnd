import 'dart:async';

import 'package:flutter/material.dart';

import '../../../game/story_host.dart';
import '../../../models/world.dart';
import '../../../theme/ui.dart';

String _when(DateTime d) {
  final now = DateTime.now();
  final diff = now.difference(d);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes} min ago';
  if (diff.inDays < 1 && now.day == d.day) return 'today ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  if (diff.inDays < 7) return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

List<StoryNote> sortedNotes(StoryHost host) => host.world.notes.where((n) => !n.isEmpty).toList()
  ..sort((a, b) => a.pinned != b.pinned ? (a.pinned ? -1 : 1) : b.updated.compareTo(a.updated));

/// Opens the full notes page for a story.
Future<void> openNotes(BuildContext context, StoryHost host) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NotesScreen(host: host)));

/// Opens one note for editing (a new one when [note] is null).
Future<void> openNote(BuildContext context, StoryHost host, [StoryNote? note]) async {
  final n = note ?? (StoryNote()..title = '');
  if (note == null) host.world.notes.add(n);
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => NoteEditor(host: host, note: n)));
  if (n.isEmpty) host.world.notes.remove(n);
  host.save();
  host.refresh();
}

/// The player's own notes for a story: clues, plans, names, theories.
class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key, required this.host});
  final StoryHost host;

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final host = widget.host;
    return Scaffold(
      appBar: AppBar(title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Notes'), Text(host.storyTitle, style: T.caption(), overflow: TextOverflow.ellipsis)])),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await openNote(context, host);
          if (mounted) setState(() {});
        },
        icon: const Icon(Icons.edit_note),
        label: const Text('New note'),
      ),
      body: ContentWidth(
        child: ListenableBuilder(
          listenable: host,
          builder: (context, _) {
            final all = sortedNotes(host);
            final q = _q.toLowerCase();
            final list = all.where((n) => q.isEmpty || '${n.title} ${n.body}'.toLowerCase().contains(q)).toList();
            return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 100), children: [
              if (all.length > 3)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(style: T.body(), decoration: const InputDecoration(hintText: 'Search notes', prefixIcon: Icon(Icons.search, size: 18)), onChanged: (v) => setState(() => _q = v)),
                ),
              if (all.isEmpty)
                const EmptyState(icon: Icons.sticky_note_2_outlined, title: 'No notes yet', message: 'Jot down clues, names, plans and theories. Notes are yours alone; the storyteller doesn\'t read them.'),
              for (final n in list) NoteCard(host: host, note: n, onChanged: () => setState(() {})),
            ]);
          },
        ),
      ),
    );
  }
}

class NoteCard extends StatelessWidget {
  const NoteCard({super.key, required this.host, required this.note, this.onChanged});
  final StoryHost host;
  final StoryNote note;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final preview = note.title.trim().isEmpty ? note.body.trim().split('\n').skip(1).join(' ') : note.body.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        onTap: () async {
          await openNote(context, host, note);
          onChanged?.call();
        },
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if (note.pinned) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.push_pin, size: 14, color: AppColors.accent)),
                Expanded(child: Text(note.heading, style: T.h3(), maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
              if (preview.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(preview, style: T.small(), maxLines: 3, overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: 6),
              Text(_when(note.updated), style: T.caption()),
            ]),
          ),
          IconButton(
            tooltip: note.pinned ? 'Unpin' : 'Pin',
            visualDensity: VisualDensity.compact,
            icon: Icon(note.pinned ? Icons.push_pin : Icons.push_pin_outlined, size: 18, color: note.pinned ? AppColors.accent : AppColors.textFaint),
            onPressed: () {
              note.pinned = !note.pinned;
              host.save();
              host.refresh();
              onChanged?.call();
            },
          ),
        ]),
      ),
    );
  }
}

/// Writing one note. Saves as you type.
class NoteEditor extends StatefulWidget {
  const NoteEditor({super.key, required this.host, required this.note});
  final StoryHost host;
  final StoryNote note;

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late final _title = TextEditingController(text: widget.note.title);
  late final _body = TextEditingController(text: widget.note.body);
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _write();
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _write() {
    final n = widget.note;
    if (n.title == _title.text && n.body == _body.text) return;
    n
      ..title = _title.text
      ..body = _body.text
      ..updated = DateTime.now();
    widget.host.save();
  }

  void _changed(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _write);
  }

  void _stamp() {
    final h = widget.host;
    final stamp = '[Turn ${h.turns}${h.scene.title.isEmpty ? '' : ' · ${h.scene.title}'}] ';
    final sel = _body.selection;
    final at = sel.isValid ? sel.start : _body.text.length;
    _body.text = _body.text.replaceRange(at, sel.isValid ? sel.end : at, stamp);
    _body.selection = TextSelection.collapsed(offset: at + stamp.length);
    _changed('');
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.note;
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(tooltip: 'Insert turn and scene', icon: const Icon(Icons.bookmark_add_outlined), onPressed: _stamp),
          IconButton(
            tooltip: n.pinned ? 'Unpin' : 'Pin',
            icon: Icon(n.pinned ? Icons.push_pin : Icons.push_pin_outlined, color: n.pinned ? AppColors.accent : null),
            onPressed: () => setState(() => n.pinned = !n.pinned),
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (n.isEmpty || await confirm(context, title: 'Delete this note?', message: 'This can\'t be undone.', action: 'Delete')) {
                _title.clear();
                _body.clear();
                widget.host.world.notes.remove(n);
                widget.host.save();
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
        ],
      ),
      body: ContentWidth(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: Column(children: [
            TextField(
              controller: _title,
              onChanged: _changed,
              style: T.h2(),
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Title', border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false),
            ),
            Expanded(
              child: TextField(
                controller: _body,
                onChanged: _changed,
                autofocus: n.isEmpty,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                textCapitalization: TextCapitalization.sentences,
                style: T.reading(),
                decoration: const InputDecoration(hintText: 'Clues, names, plans, theories…', border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false),
              ),
            ),
            Align(alignment: Alignment.centerRight, child: Text('Saved automatically · ${_body.text.trim().isEmpty ? 0 : _body.text.trim().split(RegExp(r'\s+')).length} words', style: T.caption())),
          ]),
        ),
      ),
    );
  }
}

/// Notes inside the journal.
class NotesTab extends StatelessWidget {
  const NotesTab({super.key, required this.host});
  final StoryHost host;

  @override
  Widget build(BuildContext context) {
    final notes = sortedNotes(host);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        Expanded(child: AppButton(label: 'New note', icon: Icons.edit_note, onPressed: () => openNote(context, host))),
        const SizedBox(width: 8),
        Expanded(child: AppButton(label: 'All notes', icon: Icons.open_in_full, kind: ButtonKind.secondary, onPressed: () => openNotes(context, host))),
      ]),
      const SizedBox(height: 12),
      if (notes.isEmpty) const EmptyState(icon: Icons.sticky_note_2_outlined, title: 'No notes yet', message: 'Your own notebook for this story: clues, names, plans.'),
      for (final n in notes) NoteCard(host: host, note: n),
    ]);
  }
}
