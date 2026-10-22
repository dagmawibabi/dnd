import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/companion.dart';
import '../../../models/world.dart';
import '../../../services/companion_life.dart';
import '../../../services/companion_store.dart';
import '../../../services/image_service.dart';
import '../../../services/settings.dart';
import '../../../theme/ui.dart';
import '../../widgets/portrait.dart';
import '../../widgets/media_view.dart';
import 'companion_chat.dart';
import 'companion_editor.dart';

/// A companion's face: their avatar, or a drawn portrait.
class CompanionAvatar extends StatelessWidget {
  const CompanionAvatar({super.key, required this.companion, this.size = 48, this.badge = false, this.viewable = false});
  final Companion companion;
  final double size;
  final bool badge;

  /// Tapping opens the picture full screen (otherwise taps reach the parent).
  final bool viewable;

  @override
  Widget build(BuildContext context) {
    final face = PortraitView(spec: companion.portrait, raceId: companion.raceId, size: size, viewTitle: viewable ? companion.name : null, viewSubtitle: companion.subtitle);
    if (!badge) return face;
    return Stack(clipBehavior: Clip.none, children: [
      face,
      Positioned(
        right: -1,
        top: -1,
        child: Container(width: size * 0.26, height: size * 0.26, decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle, border: Border.all(color: AppColors.bg, width: 2))),
      ),
    ]);
  }
}

/// "Name sent you a message", with a button that opens the chat.
void showCompanionToast(ScaffoldMessengerState? messenger, GlobalKey<NavigatorState> nav, Companion c, ChatLine line) {
  if (messenger == null) return;
  messenger.showSnackBar(SnackBar(
    duration: const Duration(seconds: 6),
    content: Row(children: [
      CompanionAvatar(companion: c, size: 34),
      const SizedBox(width: 12),
      Expanded(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${c.name} sent you a message', style: T.h3()),
          Text(line.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: T.small()),
        ]),
      ),
    ]),
    action: SnackBarAction(label: 'Open', onPressed: () => nav.currentState?.push(MaterialPageRoute(builder: (_) => CompanionChatScreen(companionId: c.id)))),
  ));
}

/// The player's companions: friends to chat with and take into adventures.
class CompanionsScreen extends StatelessWidget {
  const CompanionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CompanionStore>();
    final list = [...store.companions]..sort((a, b) => CompanionLife.lastContact(b).compareTo(CompanionLife.lastContact(a)));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Companions'),
        actions: [
          if (list.length >= 2)
            IconButton(tooltip: 'Group photo', icon: const Icon(Icons.groups_outlined), onPressed: () => showGroupPhoto(context, list)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CompanionEditor())),
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('New companion'),
      ),
      body: list.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: EmptyState(
                icon: Icons.diversity_1_outlined,
                title: 'No companions yet',
                message: 'Companions are friends who live outside any one story. Chat with them, and bring them along on adventures; they remember everything you go through together.\n\nMake one here, or open anyone\'s profile in a story and tap "Make a companion".',
              ),
            )
          : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
              for (final c in list) _CompanionTile(c),
            ]),
    );
  }
}

class _CompanionTile extends StatelessWidget {
  const _CompanionTile(this.c);
  final Companion c;

  @override
  Widget build(BuildContext context) {
    final last = c.chat.isEmpty ? null : c.chat.last;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CompanionChatScreen(companionId: c.id))),
        child: Row(children: [
          CompanionAvatar(companion: c, size: 52, badge: c.unread),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(c.name, style: T.h3(), overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
                Tag(c.bond.label, color: c.bond.isHostile ? AppColors.danger : AppColors.accent),
              ]),
              const SizedBox(height: 2),
              Text(
                last == null ? [c.subtitle, if (c.trips.isNotEmpty) '${c.trips.length} adventure${c.trips.length == 1 ? '' : 's'}'].where((s) => s.isNotEmpty).join(' · ') : '${last.fromPlayer ? 'You: ' : ''}${last.text}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: T.small(color: c.unread ? AppColors.text : AppColors.textMuted),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Paints the chosen companions (and optionally the player) together.
Future<void> showGroupPhoto(BuildContext context, List<Companion> all) => showAppSheet(context, builder: (ctx) => _GroupPhoto(all: all));

class _GroupPhoto extends StatefulWidget {
  const _GroupPhoto({required this.all});
  final List<Companion> all;

  @override
  State<_GroupPhoto> createState() => _GroupPhotoState();
}

class _GroupPhotoState extends State<_GroupPhoto> {
  late final Set<String> _picked = {for (final c in widget.all.take(4)) c.id};
  final _scene = TextEditingController();
  String? _photo;
  bool _busy = false;

  @override
  void dispose() {
    _scene.dispose();
    super.dispose();
  }

  Future<void> _paint() async {
    final images = context.read<ImageService>();
    final chosen = [for (final c in widget.all) if (_picked.contains(c.id)) c];
    setState(() => _busy = true);
    final who = chosen.map((c) => '${c.name} (${c.kind}${c.appearance.isEmpty ? '' : ': ${c.appearance}'})').join('; ');
    final path = await images.generate(
      'companion_group_${DateTime.now().millisecondsSinceEpoch}',
      'A warm group photo of friends together: $who. ${_scene.text.trim().isEmpty ? 'Candid, happy, everyone clearly visible.' : _scene.text.trim()}',
      size: '1536x1024',
      category: 'companion',
      references: [
        for (final c in chosen)
          if (c.portrait.aiImagePath case final p? when p.isNotEmpty) (c.name, p),
      ],
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _photo = path;
    });
    if (path == null) showToast(context, images.errors.values.lastOrNull ?? 'The picture could not be painted', icon: Icons.error_outline);
  }

  @override
  Widget build(BuildContext context) {
    final ai = context.watch<SettingsController>().canPaint;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SheetTitle('Group photo', subtitle: 'Pick who is in it'),
        CompactChips(child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in widget.all)
            FilterChip(
              avatar: CompanionAvatar(companion: c, size: 24),
              label: Text(c.name),
              selected: _picked.contains(c.id),
              onSelected: (v) => setState(() => v ? _picked.add(c.id) : _picked.remove(c.id)),
            ),
        ])),
        const SizedBox(height: 12),
        TextField(controller: _scene, style: T.body(), decoration: const InputDecoration(hintText: 'Where and how (optional): "around a campfire, laughing"')),
        const SizedBox(height: 12),
        if (_photo != null)
          ClipRRect(borderRadius: BorderRadius.circular(14), child: AspectRatio(aspectRatio: 3 / 2, child: MediaView(path: _photo!, fallback: const ColoredBox(color: AppColors.surface2)))),
        const SizedBox(height: 12),
        AppButton(
          label: !ai ? 'Add an image model in Settings' : (_busy ? 'Painting…' : (_photo == null ? 'Paint the photo' : 'Paint another')),
          icon: Icons.auto_awesome,
          busy: _busy,
          onPressed: !ai || _busy || _picked.length < 2 ? null : _paint,
        ),
      ]),
    );
  }
}
