import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../art/scene_painter.dart';
import '../../data/tale_genres.dart';
import '../../models/character.dart' show newId;
import '../../services/settings.dart';
import '../../theme/ui.dart';

/// Create or edit your own text adventure genre. Returns its id when saved.
Future<String?> showGenreEditor(BuildContext context, {Map<String, dynamic>? existing}) => showAppSheet<String>(context, builder: (_) => _GenreEditor(existing: existing));

class _GenreEditor extends StatefulWidget {
  const _GenreEditor({this.existing});
  final Map<String, dynamic>? existing;

  @override
  State<_GenreEditor> createState() => _GenreEditorState();
}

class _GenreEditorState extends State<_GenreEditor> {
  late final _name = TextEditingController(text: widget.existing?['name'] ?? '');
  late final _tagline = TextEditingController(text: widget.existing?['tagline'] ?? '');
  late final _style = TextEditingController(text: widget.existing?['style'] ?? '');
  late final _health = TextEditingController(text: widget.existing?['health'] ?? '');
  late String _scene = widget.existing?['scene'] ?? 'castle';
  late String _time = widget.existing?['time'] ?? 'dusk';
  late int _icon = ((widget.existing?['icon'] ?? 0) as num).toInt();
  late int _color = ((widget.existing?['color'] ?? 0) as num).toInt();

  @override
  void dispose() {
    _name.dispose();
    _tagline.dispose();
    _style.dispose();
    _health.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showToast(context, 'Give your genre a name', icon: Icons.edit_outlined);
      return;
    }
    final s = context.read<SettingsController>();
    final id = (widget.existing?['id'] as String?) ?? 'custom_${newId()}';
    final g = {
      'id': id,
      'name': name,
      'tagline': _tagline.text.trim(),
      'style': _style.text.trim().isEmpty ? 'A $name story.' : _style.text.trim(),
      'health': _health.text.trim(),
      'scene': _scene,
      'time': _time,
      'icon': _icon,
      'color': _color,
      'music': const {'castle': 'forest', 'forest': 'forest', 'town': 'tavern', 'tavern': 'tavern', 'coast': 'tavern'}[_scene] ?? 'mystery',
      'ambience': const {'tavern': 'crowd', 'town': 'crowd', 'coast': 'surf', 'cave': 'cave', 'crypt': 'cave', 'forest': 'forest', 'swamp': 'forest'}[_scene] ?? 'wind',
    };
    s.update((s) {
      s.customGenres.removeWhere((x) => x['id'] == id);
      s.customGenres.add(g);
    });
    Navigator.pop(context, id);
  }

  @override
  Widget build(BuildContext context) {
    final color = customGenreColors[_color];
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SheetTitle(widget.existing == null ? 'A new genre' : 'Edit genre', subtitle: 'Your own kind of story, ready to pick whenever you start one.'),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 110,
              child: Stack(fit: StackFit.expand, children: [
                SceneView(location: _scene, time: _time, mood: 'mystery', seed: _name.text.hashCode & 0xffff),
                const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xCC000000)]))),
                Positioned(
                  left: 14,
                  bottom: 10,
                  right: 14,
                  child: Row(children: [
                    Icon(customGenreIcons[_icon], size: 16, color: color),
                    const SizedBox(width: 6),
                    Expanded(child: Text(_name.text.isEmpty ? 'YOUR GENRE' : _name.text.toUpperCase(), style: T.overline(color: color), overflow: TextOverflow.ellipsis)),
                  ]),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 14),
          TextField(controller: _name, style: T.body(), decoration: const InputDecoration(labelText: 'Name', hintText: 'Cozy fantasy, Space opera, Regency romance…'), onChanged: (_) => setState(() {})),
          const SizedBox(height: 10),
          TextField(controller: _tagline, style: T.body(), decoration: const InputDecoration(labelText: 'Tagline (optional)', hintText: 'Tea, dragons and a very small bakery.')),
          const SizedBox(height: 10),
          TextField(controller: _style, style: T.body(), minLines: 3, maxLines: 6, decoration: const InputDecoration(labelText: 'How these stories feel', hintText: 'Warm, low-stakes fantasy about community. Gentle humor, found family, small magical problems.')),
          const SizedBox(height: 10),
          TextField(controller: _health, style: T.body(), decoration: const InputDecoration(labelText: 'What the health bar means (optional)', hintText: 'Health, Sanity, Reputation, Courage…')),
          const SectionLabel('Backdrop'),
          CompactChips(child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final p in genreScenes) ChoiceChip(label: Text(p[0].toUpperCase() + p.substring(1)), selected: _scene == p, onSelected: (_) => setState(() => _scene = p)),
          ])),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [ButtonSegment(value: 'day', label: Text('Day')), ButtonSegment(value: 'dusk', label: Text('Dusk')), ButtonSegment(value: 'night', label: Text('Night'))],
            selected: {_time},
            onSelectionChanged: (v) => setState(() => _time = v.first),
          ),
          const SectionLabel('Icon & color'),
          CompactChips(child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final (i, ic) in customGenreIcons.indexed)
              ChoiceChip(label: Icon(ic, size: 18, color: i == _icon ? color : AppColors.textMuted), selected: i == _icon, onSelected: (_) => setState(() => _icon = i)),
          ])),
          const SizedBox(height: 10),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final (i, c) in customGenreColors.indexed)
              GestureDetector(
                onTap: () => setState(() => _color = i),
                child: Container(width: 32, height: 32, decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: i == _color ? AppColors.text : Colors.transparent, width: 3))),
              ),
          ]),
          const SizedBox(height: 18),
          AppButton(label: 'Save genre', icon: Icons.check, onPressed: _save),
          if (widget.existing != null) ...[
            const SizedBox(height: 8),
            AppButton(
              label: 'Delete genre',
              kind: ButtonKind.ghost,
              onPressed: () async {
                if (!await confirm(context, title: 'Delete ${widget.existing!['name']}?', message: 'Stories already started keep their look.', action: 'Delete')) return;
                if (!context.mounted) return;
                context.read<SettingsController>().update((s) => s.customGenres.removeWhere((x) => x['id'] == widget.existing!['id']));
                Navigator.pop(context);
              },
            ),
          ],
        ]),
      ),
    );
  }
}

/// Create or edit your own D&D setting. Returns its name when saved.
Future<String?> showSettingEditor(BuildContext context, {Map<String, String>? existing}) => showAppSheet<String>(context, builder: (_) => _SettingEditor(existing: existing));

const dndPlaces = ['forest', 'ruins', 'crypt', 'coast', 'desert', 'tundra', 'swamp', 'cave', 'tower', 'castle', 'town', 'mountain', 'plains'];

class _SettingEditor extends StatefulWidget {
  const _SettingEditor({this.existing});
  final Map<String, String>? existing;

  @override
  State<_SettingEditor> createState() => _SettingEditorState();
}

class _SettingEditorState extends State<_SettingEditor> {
  late final _name = TextEditingController(text: widget.existing?['name'] ?? '');
  late final _details = TextEditingController(text: widget.existing?['details'] ?? '');
  late String _place = widget.existing?['place'] ?? 'forest';

  @override
  void dispose() {
    _name.dispose();
    _details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SheetTitle(widget.existing == null ? 'A new setting' : 'Edit setting', subtitle: 'Your own world for the AI Dungeon Master.'),
          ClipRRect(borderRadius: BorderRadius.circular(14), child: SizedBox(height: 100, child: SceneView(location: _place, time: 'dusk', mood: 'mystery', seed: _name.text.hashCode & 0xffff))),
          const SizedBox(height: 14),
          TextField(controller: _name, style: T.body(), decoration: const InputDecoration(labelText: 'Name', hintText: 'Sky islands, Clockwork empire…'), onChanged: (_) => setState(() {})),
          const SizedBox(height: 10),
          TextField(controller: _details, style: T.body(), minLines: 3, maxLines: 8, decoration: const InputDecoration(labelText: 'What the world is like', hintText: 'Floating islands linked by airships. Magic comes from storms. The sky church hunts unlicensed mages.')),
          const SectionLabel('Typical place'),
          CompactChips(child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final p in dndPlaces) ChoiceChip(label: Text(p[0].toUpperCase() + p.substring(1)), selected: _place == p, onSelected: (_) => setState(() => _place = p)),
          ])),
          const SizedBox(height: 18),
          AppButton(
            label: 'Save setting',
            icon: Icons.check,
            onPressed: () {
              final name = _name.text.trim();
              if (name.isEmpty) return;
              context.read<SettingsController>().update((s) {
                s.customSettings.removeWhere((x) => x['name'] == (widget.existing?['name'] ?? name));
                s.customSettings.add({'name': name, 'place': _place, 'details': _details.text.trim()});
              });
              Navigator.pop(context, name);
            },
          ),
          if (widget.existing != null) ...[
            const SizedBox(height: 8),
            AppButton(
              label: 'Delete setting',
              kind: ButtonKind.ghost,
              onPressed: () {
                context.read<SettingsController>().update((s) => s.customSettings.removeWhere((x) => x['name'] == widget.existing!['name']));
                Navigator.pop(context);
              },
            ),
          ],
        ]),
      ),
    );
  }
}
