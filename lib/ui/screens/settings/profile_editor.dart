import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../services/image_service.dart';
import '../../../services/settings.dart';
import '../../../theme/ui.dart';
import '../../widgets/media_view.dart';
import '../../widgets/image_viewer.dart';

String initialsOf(String name) {
  final n = name.trim().isEmpty ? 'Adventurer' : name.trim();
  return n.split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0].toUpperCase()).join();
}

/// The player's avatar: their picture, or initials on a gradient.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, this.size = 56, this.path, this.name, this.viewable = false});
  final double size;

  /// Defaults to the saved profile.
  final String? path;
  final String? name;
  final bool viewable;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsController>();
    final p = path ?? (s.playerAvatar.isEmpty ? null : s.playerAvatar);
    final n = name ?? s.playerName;
    final initials = Container(
      alignment: Alignment.center,
      decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.accent, Color(0xFF4F46E5)])),
      child: Text(initialsOf(n), style: T.h2(color: Colors.white).copyWith(fontSize: size * 0.36)),
    );
    final avatar = ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: p == null ? initials : GeneratedImage(path: p, fallback: initials, service: context.read<ImageService>(), cacheWidth: (size * 3).round()),
      ),
    );
    if (!viewable || p == null) return avatar;
    return GestureDetector(
      onTap: () => openImageViewer(
        context,
        title: n.trim().isEmpty ? 'Profile picture' : n.trim(),
        actions: mediaActions(context, p, name: 'profile'),
        builder: (_) => GeneratedImage(path: p, fallback: initials, service: context.read<ImageService>(), fit: BoxFit.contain),
      ),
      child: avatar,
    );
  }
}

/// Pick a profile picture: camera, gallery or AI. Reports the new path (null = removed).
class AvatarPicker extends StatefulWidget {
  const AvatarPicker({super.key, required this.path, required this.name, required this.bio, required this.onChanged});
  final String? path;
  final String name;
  final String bio;
  final ValueChanged<String?> onChanged;

  @override
  State<AvatarPicker> createState() => _AvatarPickerState();
}

class _AvatarPickerState extends State<AvatarPicker> {
  final _picker = ImagePicker();
  bool _busy = false;

  Future<void> _pick(ImageSource source) async {
    try {
      final f = await _picker.pickImage(source: source, maxWidth: 768, maxHeight: 768, imageQuality: 88, preferredCameraDevice: CameraDevice.front);
      if (f == null || !mounted) return;
      final bytes = await f.readAsBytes();
      if (!mounted) return;
      widget.onChanged(await context.read<ImageService>().savePhoto(bytes));
    } catch (e) {
      if (mounted) showToast(context, 'Couldn\'t open the ${source == ImageSource.camera ? 'camera' : 'gallery'}: $e', icon: Icons.error_outline);
    }
  }

  Future<void> _generate() async {
    final images = context.read<ImageService>();
    images.resume();
    setState(() => _busy = true);
    final key = 'portrait_profile_${DateTime.now().millisecondsSinceEpoch}';
    final who = widget.bio.trim().isEmpty ? 'a bold adventurer who loves tabletop stories' : widget.bio.trim();
    final path = await images.generate(key, 'Profile picture for a player: a stylized fantasy character portrait that captures this person: $who');
    if (!mounted) return;
    setState(() => _busy = false);
    if (path != null) {
      widget.onChanged(path);
    } else if (images.errors[key] != null) {
      showToast(context, images.errors[key]!, icon: Icons.error_outline);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ai = context.watch<SettingsController>().useAiImages;
    return Column(children: [
      Stack(children: [
        ProfileAvatar(size: 112, path: widget.path, name: widget.name, viewable: true),
        if (_busy) const Positioned.fill(child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
      ]),
      const SizedBox(height: 12),
      Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(onPressed: _busy ? null : () => _pick(ImageSource.camera), icon: const Icon(Icons.photo_camera_outlined, size: 18), label: const Text('Camera')),
        OutlinedButton.icon(onPressed: _busy ? null : () => _pick(ImageSource.gallery), icon: const Icon(Icons.photo_library_outlined, size: 18), label: const Text('Gallery')),
        if (ai) OutlinedButton.icon(onPressed: _busy ? null : _generate, icon: const Icon(Icons.auto_awesome_outlined, size: 18), label: const Text('Paint with AI')),
        if (widget.path != null) TextButton(onPressed: _busy ? null : () => widget.onChanged(null), child: const Text('Remove')),
      ]),
    ]);
  }
}

/// Full-screen profile editor: picture, name and bio.
class ProfileEditorScreen extends StatefulWidget {
  const ProfileEditorScreen({super.key});

  @override
  State<ProfileEditorScreen> createState() => _ProfileEditorScreenState();
}

class _ProfileEditorScreenState extends State<ProfileEditorScreen> {
  late final SettingsController _s = context.read<SettingsController>();
  late final _name = TextEditingController(text: _s.playerName);
  late final _bio = TextEditingController(text: _s.playerBio);
  late String? _avatar = _s.playerAvatar.isEmpty ? null : _s.playerAvatar;

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    super.dispose();
  }

  void _save() {
    _s.update((s) => s
      ..playerName = _name.text.trim()
      ..playerBio = _bio.text.trim()
      ..playerAvatar = _avatar ?? '');
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (_, _) => _save(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Your profile'),
          actions: [
            TextButton(
              onPressed: () {
                _save();
                Navigator.pop(context);
                showToast(context, 'Profile saved');
              },
              child: const Text('Save'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: ContentWidth(
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 40), children: [
            AvatarPicker(path: _avatar, name: _name.text, bio: _bio.text, onChanged: (p) => setState(() => _avatar = p)),
            const SizedBox(height: 24),
            TextField(
              controller: _name,
              style: T.body(),
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Name', hintText: 'What should the app call you?'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _bio,
              style: T.body(),
              minLines: 4,
              maxLines: 8,
              maxLength: 400,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Bio', hintText: 'A few words about you: favorite genres, the hero you always play, how you like your stories…', alignLabelWithHint: true),
            ),
            const SizedBox(height: 6),
            Text('Your profile stays on this device and is included in backups.', style: T.caption()),
          ]),
        ),
      ),
    );
  }
}
