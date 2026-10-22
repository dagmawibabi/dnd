import 'package:flutter/material.dart';

import '../../../models/chronicle.dart';
import '../../../theme/ui.dart';
import '../adventure/sheets.dart' show editTextDialog;

class WorldMemoryScreen extends StatefulWidget {
  const WorldMemoryScreen({super.key, required this.world, this.listenable, this.onChanged, this.chapterId = '', this.chapterTitle = '', this.turn = 0});
  final Chronicle Function() world;
  final Listenable? listenable;
  final VoidCallback? onChanged;
  final String chapterId, chapterTitle;
  final int turn;
  @override
  State<WorldMemoryScreen> createState() => _WorldMemoryScreenState();
}

class _WorldMemoryScreenState extends State<WorldMemoryScreen> {
  String _query = '', _kind = 'All';
  bool _timeline = false;
  @override
  void initState() {
    super.initState();
    widget.listenable?.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.listenable?.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  bool _matches(String kind, String text) => (_kind == 'All' || kind == _kind) && text.toLowerCase().contains(_query.toLowerCase());

  @override
  Widget build(BuildContext context) {
    final world = widget.world();
    final kinds = {'All', ...world.facts.map((f) => f.kind), ...world.history.map((h) => h.kind)};
    final facts = world.facts.where((f) => _matches(f.kind, '${f.name} ${f.state}')).toList()
      ..sort(
        (a, b) => a.pinned == b.pinned
            ? a.name.compareTo(b.name)
            : a.pinned
            ? -1
            : 1,
      );
    final changes = world.history.reversed.where((h) => _matches(h.kind, '${h.name} ${h.before} ${h.after} ${h.reason} ${h.chapterTitle}')).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('World memory'),
        actions: [if (widget.onChanged != null) IconButton(tooltip: 'Record a world fact', icon: const Icon(Icons.add), onPressed: _add)],
      ),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Day ${world.day} · ${world.facts.length} current facts · ${world.history.length} changes', style: T.h3()),
            const SizedBox(height: 8),
            Text(
              'The storyteller and character conversations receive the current world state. The history preserves what changed and why. Pin important facts to put them first.',
              style: T.small(),
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search people, places, actions or chapters'),
              onChanged: (s) => setState(() => _query = s),
            ),
            const SizedBox(height: 12),
            CompactChips(child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [for (final kind in kinds) ChoiceChip(label: Text(kind), selected: _kind == kind, onSelected: (_) => setState(() => _kind = kind))],
            )),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Current world')),
                ButtonSegment(value: true, label: Text('Consequences')),
              ],
              selected: {_timeline},
              onSelectionChanged: (s) => setState(() => _timeline = s.first),
            ),
            const SizedBox(height: 16),
            if (!_timeline && facts.isEmpty || _timeline && changes.isEmpty)
              const EmptyState(
                icon: Icons.public,
                title: 'No matching memories',
                message: 'World changes, quests and camp activities will appear here as you play.',
              ),
            if (!_timeline)
              for (final f in facts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(f.name, style: T.h3())),
                            if (widget.onChanged != null)
                              IconButton(
                                tooltip: f.pinned ? 'Unpin memory' : 'Pin memory',
                                icon: Icon(f.pinned ? Icons.push_pin : Icons.push_pin_outlined, size: 18),
                                onPressed: () {
                                  f.pinned = !f.pinned;
                                  widget.onChanged!();
                                  _refresh();
                                },
                              ),
                            if (widget.onChanged != null)
                              IconButton(tooltip: 'Correct current state', icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _edit(f)),
                          ],
                        ),
                        Text(f.kind == 'faction' ? 'faction · reputation ${f.reputation}/100' : f.kind, style: T.caption()),
                        const SizedBox(height: 8),
                        Text(f.state, style: T.body()),
                        TextButton(
                          onPressed: () => setState(() {
                            _query = f.name;
                            _kind = f.kind;
                            _timeline = true;
                          }),
                          child: const Text('See what changed'),
                        ),
                      ],
                    ),
                  ),
                ),
            if (_timeline)
              for (final h in changes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(h.name, style: T.h3()),
                        Text('${h.chapterTitle} · turn ${h.turn} · day ${h.day}', style: T.caption()),
                        if (h.before.isNotEmpty) ...[const SizedBox(height: 8), Text('Before: ${h.before}', style: T.small())],
                        const SizedBox(height: 8),
                        Text('After: ${h.after}', style: T.body()),
                        if (h.reason.isNotEmpty) ...[const SizedBox(height: 8), Text('Because: ${h.reason}', style: T.small())],
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(WorldFact fact) async {
    final value = await editTextDialog(context, title: 'Correct ${fact.name}', initial: fact.state, lines: 5);
    if (value == null || value.trim().isEmpty || !mounted) return;
    widget.world().record(
      kind: fact.kind,
      name: fact.name,
      state: value.trim(),
      reason: 'Corrected by the player.',
      chapter: widget.chapterId,
      chapterTitle: widget.chapterTitle,
      turn: widget.turn,
    );
    widget.onChanged!();
    _refresh();
  }

  Future<void> _add() async {
    final name = await editTextDialog(context, title: 'Name this world fact', hint: 'A place, faction, promise or person');
    if (name == null || name.trim().isEmpty || !mounted) return;
    final state = await editTextDialog(context, title: 'What should be remembered?', lines: 5);
    if (state == null || state.trim().isEmpty || !mounted) return;
    widget.world().record(
      kind: 'fact',
      name: name,
      state: state,
      reason: 'Recorded by the player.',
      chapter: widget.chapterId,
      chapterTitle: widget.chapterTitle,
      turn: widget.turn,
    );
    widget.onChanged!();
    _refresh();
  }
}
