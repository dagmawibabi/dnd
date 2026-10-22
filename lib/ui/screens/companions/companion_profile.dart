import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/companion.dart';
import '../../../models/world.dart';
import '../../../services/companion_life.dart';
import '../../../services/companion_store.dart';
import '../../../services/image_service.dart';
import '../../../services/narrator.dart';
import '../../../theme/ui.dart';
import '../adventure/new_adventure_screen.dart';
import 'companion_chat.dart';
import 'companion_editor.dart';
import 'companions_screen.dart';

/// Everything about a companion: who they are, what they remember, the
/// adventures they've been on, and how they feel about the player.
class CompanionProfileScreen extends StatelessWidget {
  const CompanionProfileScreen({super.key, required this.companionId});
  final String companionId;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CompanionStore>();
    final c = store.byId(companionId);
    if (c == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('This companion is gone.')));
    final b = c.bond;
    final trips = [...c.trips]..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
    Widget para(String label, String text) => text.trim().isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label.toUpperCase(), style: T.overline()),
              const SizedBox(height: 4),
              Text(text, style: T.body()),
            ]),
          );
    return Scaffold(
      appBar: AppBar(
        title: Text(c.name),
        actions: [
          IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CompanionEditor(companionId: c.id)))),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
        Center(child: CompanionAvatar(companion: c, size: 120, viewable: true)),
        const SizedBox(height: 8),
        Center(child: Builder(builder: (context) {
          final painting = context.watch<ImageService>().busy.any((k) => k.startsWith('comp_avatar_${c.id}'));
          return TextButton.icon(
            icon: painting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome, size: 18),
            label: Text(painting ? 'Painting…' : 'Paint a new picture'),
            onPressed: painting
                ? null
                : () async {
                    final images = context.read<ImageService>();
                    final path = await context.read<CompanionLife>().paintAvatar(c);
                    if (path == null && context.mounted) showToast(context, images.errors.values.lastOrNull ?? 'The picture could not be painted', icon: Icons.error_outline);
                  },
          );
        })),
        const SizedBox(height: 4),
        Center(child: Text(c.name, style: T.h2())),
        Center(child: Text(c.subtitle, style: T.small())),
        const SizedBox(height: 8),
        Center(
          child: Wrap(spacing: 6, children: [
            Tag(b.label, color: b.isHostile ? AppColors.danger : AppColors.accent, filled: true),
            if (c.origin != null) Tag('From "${c.origin!.title}"', icon: Icons.auto_stories_outlined),
          ]),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: AppButton(label: 'Chat', icon: Icons.chat_bubble_outline, onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CompanionChatScreen(companionId: c.id))))),
          const SizedBox(width: 10),
          Expanded(child: AppButton(label: 'Adventure', icon: Icons.explore_outlined, kind: ButtonKind.secondary, onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NewAdventureScreen(companionIds: [c.id]))))),
        ]),
        const SectionLabel('Your relationship'),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _Meter(label: 'Friendship', value: b.friendship, min: -100, text: b.friendshipLabel),
            if (b.romance > 0 || b.romanceClosed) ...[const SizedBox(height: 10), _Meter(label: 'Romance', value: b.romance, min: 0, text: b.romanceLabel)],
            if (b.moments.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final m in b.moments.reversed.take(4))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('${m.friendship >= 0 ? '+' : ''}${m.friendship} · ${m.text}', style: T.small()),
                ),
            ],
          ]),
        ),
        const SectionLabel('Who they are'),
        para('Personality', c.personality),
        para('Backstory', c.backstory),
        para('Looks', c.appearance),
        para('Loves', c.interests),
        if (c.profile.traits.isNotEmpty) para('Traits', c.profile.traits.join(', ')),
        if (c.profile.goals.isNotEmpty) para('Goals', c.profile.goals.map((g) => '• $g').join('\n')),
        if (c.profile.needs.isNotEmpty) para('Needs', c.profile.needs.map((g) => '• $g').join('\n')),
        if (c.profile.growth.isNotEmpty) para('How they\'ve grown', c.profile.growth.reversed.take(6).map((g) => '• $g').join('\n')),
        SectionLabel('Memories (${c.profile.memories.length})', trailing: TextButton.icon(onPressed: () => _editMemory(context, c, null), icon: const Icon(Icons.add, size: 18), label: const Text('Add'))),
        if (c.profile.memories.isEmpty) Text('Nothing yet. They remember what you talk about and what happens on adventures.', style: T.small()),
        for (final m in [...c.profile.memories.where((m) => m.pinned), ...c.profile.memories.reversed.where((m) => !m.pinned)])
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: AppCard(
              padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
              onTap: () => _editMemory(context, c, m),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(m.text, style: T.body()),
                    const SizedBox(height: 2),
                    Text(_source(m.source), style: T.caption()),
                  ]),
                ),
                IconButton(
                  tooltip: m.pinned ? 'Unpin' : 'Pin (never forgotten)',
                  icon: Icon(m.pinned ? Icons.push_pin : Icons.push_pin_outlined, size: 18, color: m.pinned ? AppColors.accent : null),
                  onPressed: () {
                    m.pinned = !m.pinned;
                    store.changed();
                  },
                ),
              ]),
            ),
          ),
        SectionLabel('Adventures together (${trips.length})'),
        if (trips.isEmpty) Text('None yet. Start one from here, or add ${c.name.split(' ').first} when you begin a new adventure.', style: T.small()),
        for (final t in trips)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(t.kind == 'dnd' ? Icons.shield_outlined : Icons.menu_book_outlined, size: 18, color: AppColors.textMuted),
                  const SizedBox(width: 8),
                  Expanded(child: Text(t.title, style: T.h3())),
                  if (t.origin) const Tag('Origin', color: AppColors.accent),
                ]),
                if (t.name.isNotEmpty && t.name != c.name) Text('Known there as ${t.name}', style: T.caption()),
                if (t.summary.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(t.summary, style: T.small(color: AppColors.text))),
              ]),
            ),
          ),
        const SectionLabel('Settings'),
        RowGroup(children: [
          ListRow(
            leading: const Icon(Icons.record_voice_over_outlined, size: 20),
            title: 'Voice',
            subtitle: c.voice.isEmpty ? 'Picked to match them' : context.watch<Narrator>().labelOfVoice(c.voice),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CompanionEditor(companionId: c.id))),
          ),
          SwitchListTile(title: Text('Texts you first', style: T.body()), value: c.proactive, onChanged: (v) {
            c.proactive = v;
            store.changed();
          }),
          SwitchListTile(title: Text('Sends pictures', style: T.body()), value: c.sendsPictures, onChanged: (v) {
            c.sendsPictures = v;
            store.changed();
          }),
          ListRow(
            leading: const Icon(Icons.mark_chat_unread_outlined, size: 20),
            title: 'Ask them to text now',
            subtitle: 'Try a message from them right away',
            onTap: () async {
              await context.read<CompanionLife>().checkIn(force: true);
            },
          ),
          ListRow(
            leading: const Icon(Icons.delete_outline, size: 20),
            title: 'Remove ${c.name.split(' ').first}',
            danger: true,
            onTap: () async {
              final ok = await confirm(context, title: 'Remove ${c.name}?', message: 'Their chat and memories are deleted. Stories they were in keep them as a character.', action: 'Remove');
              if (!ok || !context.mounted) return;
              store.remove(c);
              Navigator.of(context).pop();
            },
          ),
        ]),
      ]),
    );
  }

  static String _source(String s) => s.startsWith('story:')
      ? 'From ${s.substring(6)}'
      : switch (s) {
          'chat' => 'From your chats',
          'player' => 'Added by you',
          'companion' => 'Becoming a companion',
          _ => 'From a story',
        };

  static Future<void> _editMemory(BuildContext context, Companion c, CharacterMemory? m) async {
    final ctl = TextEditingController(text: m?.text ?? '');
    final store = context.read<CompanionStore>();
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(m == null ? 'Add a memory' : 'Edit memory'),
        content: TextField(controller: ctl, autofocus: true, minLines: 2, maxLines: 6, decoration: InputDecoration(hintText: 'Something ${c.name.split(' ').first} should remember')),
        actions: [
          if (m != null) TextButton(onPressed: () => Navigator.pop(ctx, '\u0000delete'), child: const Text('Delete', style: TextStyle(color: AppColors.danger))),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('Save')),
        ],
      ),
    );
    ctl.dispose();
    if (r == null) return;
    if (r == '\u0000delete') {
      c.profile.memories.remove(m);
    } else if (r.trim().isNotEmpty) {
      if (m == null) {
        c.profile.memories.add(CharacterMemory(text: r.trim(), source: 'player', pinned: true));
      } else {
        m.text = r.trim();
      }
    }
    store.changed();
  }
}

class _Meter extends StatelessWidget {
  const _Meter({required this.label, required this.value, required this.min, required this.text});
  final String label;
  final int value;
  final int min;
  final String text;

  @override
  Widget build(BuildContext context) {
    final f = ((value - min) / (100 - min)).clamp(0.0, 1.0);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(label, style: T.small())),
        Text('$text · $value', style: T.caption(color: AppColors.text)),
      ]),
      const SizedBox(height: 6),
      ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: f, minHeight: 6, color: value < 0 ? AppColors.danger : AppColors.accent, backgroundColor: AppColors.surface2)),
    ]);
  }
}
