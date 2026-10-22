import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/character.dart';
import '../../../models/companion.dart';
import '../../../services/companion_life.dart';
import '../../../services/companion_store.dart';
import '../../../services/image_service.dart';
import '../../../services/narrator.dart';
import '../../../theme/ui.dart';
import '../../widgets/media_import.dart';
import '../../widgets/voice_picker.dart';
import 'companions_screen.dart';

const _kinds = ['Human', 'Elf', 'Dwarf', 'Robot', 'Android', 'Talking animal', 'Spirit', 'Dragon', 'Alien', 'Vampire', 'Ghost'];

/// Makes a new companion, or edits one ([companionId]).
class CompanionEditor extends StatefulWidget {
  const CompanionEditor({super.key, this.companionId});
  final String? companionId;

  @override
  State<CompanionEditor> createState() => _CompanionEditorState();
}

class _CompanionEditorState extends State<CompanionEditor> {
  late final Companion _c;
  late final bool _isNew;
  final _idea = TextEditingController();
  late final _name = TextEditingController(text: _c.name);
  late final _kind = TextEditingController(text: _c.kind);
  late final _pronouns = TextEditingController(text: _c.pronouns);
  late final _personality = TextEditingController(text: _c.personality);
  late final _backstory = TextEditingController(text: _c.backstory);
  late final _appearance = TextEditingController(text: _c.appearance);
  late final _interests = TextEditingController(text: _c.interests);
  late final _goals = TextEditingController(text: _c.profile.goals.join('\n'));
  bool _writing = false;

  @override
  void initState() {
    super.initState();
    final existing = CompanionStore.instance.byId(widget.companionId);
    _isNew = existing == null;
    _c = existing ?? Companion(id: newId(), name: '', portrait: PortraitSpec.random('human'));
  }

  @override
  void dispose() {
    for (final t in [_idea, _name, _kind, _pronouns, _personality, _backstory, _appearance, _interests, _goals]) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _write() async {
    final life = context.read<CompanionLife>();
    if (!life.canTalk) {
      showToast(context, 'Add an AI key in Settings to write companions', icon: Icons.key_outlined);
      return;
    }
    setState(() => _writing = true);
    try {
      final d = await life.ai.draft(_idea.text.trim(), name: _name.text.trim(), kind: _isNew ? '' : _kind.text.trim());
      if (!mounted) return;
      setState(() {
        if (d.name.isNotEmpty) _name.text = d.name;
        if (d.kind.isNotEmpty) _kind.text = d.kind;
        if (d.pronouns.isNotEmpty) _pronouns.text = d.pronouns;
        if (d.gender.isNotEmpty) _c.gender = d.gender;
        if (d.personality.isNotEmpty) _personality.text = d.personality;
        if (d.backstory.isNotEmpty) _backstory.text = d.backstory;
        if (d.appearance.isNotEmpty) _appearance.text = d.appearance;
        if (d.interests.isNotEmpty) _interests.text = d.interests;
        if (d.goals.isNotEmpty) _goals.text = d.goals.join('\n');
      });
    } catch (e) {
      if (mounted) showToast(context, 'Could not write them: $e', icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  void _apply() {
    _c
      ..name = _name.text.trim()
      ..kind = _kind.text.trim().isEmpty ? 'Human' : _kind.text.trim()
      ..pronouns = _pronouns.text.trim()
      ..personality = _personality.text.trim()
      ..backstory = _backstory.text.trim()
      ..appearance = _appearance.text.trim()
      ..interests = _interests.text.trim();
    _c.profile.goals = [for (final g in _goals.text.split('\n')) if (g.trim().isNotEmpty) g.trim()];
    if (_c.gender.isEmpty) {
      final p = _c.pronouns.toLowerCase();
      _c.gender = p.startsWith('she') ? 'female' : p.startsWith('he') ? 'male' : '';
    }
    // The drawn portrait (until they have a picture) should match them.
    final face = _c.portrait;
    face.feminine = switch (_c.gender) { 'female' => 0.9, 'male' => 0.1, _ => 0.5 };
    if (_c.gender == 'female') face.beard = 0;
  }

  void _save() {
    _apply();
    if (_c.name.isEmpty) {
      showToast(context, 'Give them a name', icon: Icons.edit_outlined);
      return;
    }
    final store = context.read<CompanionStore>();
    if (_isNew) {
      store.add(_c);
      Navigator.of(context).pop(_c);
    } else {
      store.changed();
      Navigator.of(context).pop(_c);
    }
  }

  Future<void> _avatarFromPhotos() async {
    final picked = await chooseImages(context, title: 'Their picture');
    if (picked.isEmpty || !mounted) return;
    context.read<CompanionLife>().setAvatar(_c, picked.first.path);
    setState(() {});
  }

  Future<void> _paintAvatar() async {
    _apply();
    final images = context.read<ImageService>();
    setState(() {});
    final path = await context.read<CompanionLife>().paintAvatar(_c);
    if (!mounted) return;
    setState(() {});
    if (path == null) showToast(context, images.errors.values.lastOrNull ?? 'The portrait could not be painted', icon: Icons.error_outline);
  }

  Future<void> _pickVoice() async {
    _apply();
    final v = await showVoicePicker(context, title: '${_c.name.isEmpty ? 'Their' : '${_c.name}\'s'} voice', current: _c.voice.isEmpty ? null : _c.voice, gender: _c.gender, sample: 'Hey, it\'s me. Got time for an adventure?', allowAutomatic: true);
    if (v == null || !mounted) return;
    setState(() => _c.voice = v);
  }

  @override
  Widget build(BuildContext context) {
    final images = context.watch<ImageService>();
    final narrator = context.watch<Narrator>();
    final painting = images.busy.any((k) => k.startsWith('comp_avatar_${_c.id}'));
    Widget field(TextEditingController c, String label, {String? hint, int lines = 1}) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(controller: c, style: T.body(), minLines: 1, maxLines: lines, decoration: InputDecoration(labelText: label, hintText: hint)),
        );
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'New companion' : 'Edit ${_c.name}'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
        Center(
          child: Column(children: [
            CompanionAvatar(companion: _c, size: 104),
            const SizedBox(height: 10),
            CompactChips(child: Wrap(spacing: 8, alignment: WrapAlignment.center, children: [
              ActionChip(avatar: const Icon(Icons.photo_outlined, size: 18), label: const Text('Choose a picture'), onPressed: _avatarFromPhotos),
              ActionChip(avatar: painting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome, size: 18), label: Text(painting ? 'Painting…' : 'Paint with AI'), onPressed: painting ? null : _paintAvatar),
            ])),
            if (_c.avatars.length > 1) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 56,
                child: ListView(scrollDirection: Axis.horizontal, shrinkWrap: true, children: [
                  for (final a in _c.avatars.reversed)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: GestureDetector(
                        onTap: () => setState(() => context.read<CompanionLife>().setAvatar(_c, a)),
                        child: Container(
                          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: a == _c.portrait.aiImagePath ? AppColors.accent : AppColors.border, width: 2)),
                          child: PortraitPreview(path: a, size: 50),
                        ),
                      ),
                    ),
                ]),
              ),
            ],
          ]),
        ),
        const SectionLabel('Start from an idea'),
        Row(children: [
          Expanded(child: TextField(controller: _idea, style: T.body(), decoration: const InputDecoration(hintText: 'A grumpy robot chef who secretly writes poetry'))),
          const SizedBox(width: 8),
          AppButton(label: _writing ? 'Writing…' : 'Write it', icon: Icons.auto_awesome, expand: false, busy: _writing, onPressed: _writing ? null : _write),
        ]),
        const SectionLabel('Who they are'),
        field(_name, 'Name'),
        field(_kind, 'What they are', hint: 'Human, robot, talking cat, anything'),
        CompactChips(child: Wrap(spacing: 6, runSpacing: 6, children: [
          for (final k in _kinds) ChoiceChip(label: Text(k), selected: _kind.text == k, onSelected: (_) => setState(() => _kind.text = k)),
        ])),
        const SizedBox(height: 12),
        CompactChips(child: Wrap(spacing: 6, runSpacing: 6, children: [
          for (final (g, label, p) in const [('female', 'Woman', 'she/her'), ('male', 'Man', 'he/him'), ('', 'Not saying', '')])
            ChoiceChip(label: Text(label), selected: _c.gender == g, onSelected: (_) => setState(() {
                  _c.gender = g;
                  _pronouns.text = p;
                })),
        ])),
        const SizedBox(height: 12),
        field(_pronouns, 'Pronouns'),
        field(_personality, 'Personality', lines: 3),
        field(_backstory, 'Backstory', lines: 6),
        field(_appearance, 'Appearance', hint: 'Used to keep pictures of them consistent', lines: 3),
        field(_interests, 'Loves talking about'),
        field(_goals, 'Goals (one per line)', lines: 4),
        const SectionLabel('Voice and habits'),
        RowGroup(children: [
          ListRow(
            leading: const Icon(Icons.record_voice_over_outlined, size: 20),
            title: 'Voice',
            subtitle: _c.voice.isEmpty ? 'Picked to match them' : narrator.labelOfVoice(_c.voice),
            onTap: _pickVoice,
          ),
          SwitchListTile(title: Text('Texts you first', style: T.body()), subtitle: Text('Messages you after some time apart', style: T.small()), value: _c.proactive, onChanged: (v) => setState(() => _c.proactive = v)),
          SwitchListTile(title: Text('Sends pictures', style: T.body()), subtitle: Text('AI-painted selfies and snapshots in chat', style: T.small()), value: _c.sendsPictures, onChanged: (v) => setState(() => _c.sendsPictures = v)),
          SwitchListTile(title: Text('Reads replies aloud', style: T.body()), subtitle: Text('In their voice, when narration is on', style: T.small()), value: _c.speaks, onChanged: (v) => setState(() => _c.speaks = v)),
        ]),
        const SizedBox(height: 20),
        AppButton(label: _isNew ? 'Add companion' : 'Save', onPressed: _save),
      ]),
    );
  }
}

/// A small round preview of an image file.
class PortraitPreview extends StatelessWidget {
  const PortraitPreview({super.key, required this.path, this.size = 48});
  final String path;
  final double size;

  @override
  Widget build(BuildContext context) => ClipOval(
        child: SizedBox(width: size, height: size, child: GeneratedImage(path: path, fallback: const ColoredBox(color: AppColors.surface2))),
      );
}
