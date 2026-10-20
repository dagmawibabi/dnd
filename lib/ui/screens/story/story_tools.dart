import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../art/scene_painter.dart';
import '../../../game/story_host.dart';
import '../../../game/adventure_controller.dart';
import '../../../game/tale_controller.dart';
import '../../../game/module_engine.dart';
import '../../../models/tale.dart';
import '../../../models/character.dart' show Character;
import '../../../services/game_store.dart';
import '../adventure/adventure_screen.dart';
import '../adventure/text_adventure_screen.dart';
import '../tales/tales_hub.dart' show taleRoute;
import '../tales/tale_tools.dart' show restartTale;
import '../../../models/adventure.dart';
import '../../../models/character.dart' show newId;
import '../../../models/world.dart';
import '../../../services/ai/story_ai.dart';
import '../../../services/export.dart';
import '../../../services/image_service.dart';
import '../../../services/narrator.dart';
import '../../../services/settings.dart';
import '../../../services/usage.dart';
import '../../../theme/ui.dart';
import '../../widgets/media_view.dart';
import '../../../art/render_png.dart';
import '../../../models/character.dart' show PortraitSpec;
import '../adventure/map_screen.dart' show MapPreview;
import 'notes_screen.dart';
import '../settings/settings_screen.dart';
import '../../widgets/error_card.dart';
import '../../widgets/portrait.dart';
import '../adventure/adventure_extras.dart' show showStoryUsage;

const romanceColor = Color(0xFFF472B6);

// ------------------------------------------------------------------ journal

/// The journal shared by every kind of story: mode-specific tabs first, then
/// People, Memory and Gallery.
Future<void> showStoryJournal(BuildContext context, StoryHost host, {List<(String, WidgetBuilder)> leading = const [], String? initial}) {
  final tabs = <(String, WidgetBuilder)>[
    ...leading,
    ('People', (ctx) => PeopleTab(host: host)),
    ('Memory', (ctx) => MemoryTab(host: host)),
    ('Gallery', (ctx) => GalleryTab(host: host)),
    ('Notes', (ctx) => NotesTab(host: host)),
  ];
  final index = initial == null ? 0 : tabs.indexWhere((t) => t.$1 == initial).clamp(0, tabs.length - 1);
  return showAppSheet(context, builder: (ctx) {
    return DefaultTabController(
      length: tabs.length,
      initialIndex: index,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: ListenableBuilder(
          listenable: host,
          builder: (ctx, _) => Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 4),
              child: Row(children: [
                Expanded(child: Text('Journal', style: T.h2())),
                IconButton(tooltip: 'AI tools', icon: const Icon(Icons.psychology_outlined, size: 20), onPressed: () => showAiTools(context, host)),
                IconButton(tooltip: 'Export', icon: const Icon(Icons.ios_share, size: 20), onPressed: () => showStoryExport(context, host)),
              ]),
            ),
            TabBar(isScrollable: tabs.length > 4, tabAlignment: tabs.length > 4 ? TabAlignment.start : TabAlignment.center, tabs: [for (final t in tabs) Tab(text: t.$1)]),
            Expanded(child: TabBarView(children: [for (final t in tabs) Builder(builder: t.$2)])),
          ]),
        ),
      ),
    );
  });
}

// -------------------------------------------------------------- relationships

/// Friendship and romance meters.
class BondBars extends StatelessWidget {
  const BondBars({super.key, required this.bond, this.compact = false});
  final Bond bond;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final f = bond.friendship;
    final fColor = f >= 20 ? AppColors.success : (f <= -20 ? AppColors.danger : AppColors.textMuted);
    Widget row(IconData icon, Color color, String label, int value, int max, {int min = 0}) => Padding(
          padding: EdgeInsets.only(top: compact ? 4 : 8),
          child: Row(children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 6),
            SizedBox(width: compact ? 92 : 112, child: Text(label, style: T.caption(color: color), overflow: TextOverflow.ellipsis)),
            Expanded(child: Bar(value: value - min, max: max - min, color: color)),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      row(f < 0 ? Icons.heart_broken_outlined : Icons.handshake_outlined, fColor, '${bond.friendshipLabel} · $f', f, 100, min: -100),
      if (bond.romance > 0 || bond.romanceClosed) row(Icons.favorite, bond.romanceClosed ? AppColors.textFaint : romanceColor, '${bond.romanceLabel} · ${bond.romance}', bond.romance, 100),
    ]);
  }
}

class PeopleTab extends StatelessWidget {
  const PeopleTab({super.key, required this.host});
  final StoryHost host;

  @override
  Widget build(BuildContext context) {
    final people = host.people;
    return ListView(padding: const EdgeInsets.all(16), children: [
      AppCard(
        onTap: () => _talkToSomeone(context, host),
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          const Icon(Icons.person_add_alt, size: 20, color: AppColors.textMuted),
          const SizedBox(width: 12),
          Expanded(child: Text('Talk to someone else from the story', style: T.body())),
          const Icon(Icons.chevron_right, size: 18, color: AppColors.textFaint),
        ]),
      ),
      const SizedBox(height: 12),
      if (people.isEmpty) const EmptyState(icon: Icons.people_outline, title: 'No one met yet', message: 'Characters appear here as you meet them. You can talk to any of them.'),
      for (final n in people)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AppCard(
            onTap: () => showPersonSheet(context, host, n),
            padding: const EdgeInsets.all(12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              NpcPortrait(npc: n, size: 46, viewable: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(n.name, style: T.h3(), overflow: TextOverflow.ellipsis)),
                    if (host.world.bondFor(n).status.isNotEmpty) Tag(host.world.bondFor(n).status, color: host.world.bondFor(n).isRomantic ? romanceColor : AppColors.info),
                  ]),
                  if (n.role.isNotEmpty) Text(n.role, style: T.caption(), maxLines: 1, overflow: TextOverflow.ellipsis),
                  BondBars(bond: host.world.bondFor(n), compact: true),
                ]),
              ),
              IconButton(tooltip: 'Talk to ${n.name}', icon: const Icon(Icons.chat_bubble_outline, size: 20), onPressed: () => showCharacterChat(context, host, n)),
            ]),
          ),
        ),
    ]);
  }
}

Future<void> _talkToSomeone(BuildContext context, StoryHost host) async {
  final name = await editTextDialog(context, title: 'Who do you want to talk to?', hint: 'A name from the story, e.g. Old Bram');
  if (name == null || name.trim().isEmpty || !context.mounted) return;
  final npc = host.meet(name.trim());
  await showCharacterChat(context, host, npc);
}

/// A character's profile: relationship, history, voice and portrait.
Future<void> showPersonSheet(BuildContext context, StoryHost host, Npc npc) {
  return showAppSheet(context, builder: (ctx) => _PersonSheet(host: host, npc: npc, outer: context));
}

class _PersonSheet extends StatelessWidget {
  const _PersonSheet({required this.host, required this.npc, required this.outer});
  final StoryHost host;
  final Npc npc;
  final BuildContext outer;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    return ListenableBuilder(
      listenable: host,
      builder: (ctx, _) {
        final b = host.world.bondFor(npc);
        final chat = host.world.chats[npc.id] ?? const <ChatLine>[];
        return SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.85,
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 32), children: [
            Center(child: Stack(children: [
              NpcPortrait(npc: npc, size: 120, viewable: true),
              Positioned(right: 0, bottom: 0, child: PortraitButton(host: host, npc: npc)),
            ])),
            const SizedBox(height: 12),
            Text(npc.name, textAlign: TextAlign.center, style: T.h2()),
            if (npc.role.isNotEmpty) Text(npc.role, textAlign: TextAlign.center, style: T.small()),
            const SizedBox(height: 6),
            Center(child: Tag(b.label, icon: b.isRomantic ? Icons.favorite : Icons.handshake_outlined, color: b.isRomantic ? romanceColor : AppColors.info, filled: true)),
            const SizedBox(height: 8),
            BondBars(bond: b),
            const SizedBox(height: 16),
            AppButton(label: chat.isEmpty ? 'Talk to ${npc.name.split(' ').first}' : 'Continue conversation (${chat.length})', icon: Icons.chat_bubble_outline, onPressed: () {
              Navigator.pop(context);
              showCharacterChat(outer, host, npc);
            }),
            if (npc.description.trim().isNotEmpty) ...[
              const SectionLabel('About'),
              Text(npc.description.trim(), style: T.body()),
            ],
            if (npc.notes.trim().isNotEmpty) ...[
              const SectionLabel('What they remember about you'),
              Text(npc.notes.trim(), style: T.small()),
            ],
            if (settings.useCloudVoice) ...[
              const SectionLabel('Voice'),
              _VoicePicker(host: host, npc: npc),
            ],
            const SectionLabel('History'),
            if (b.moments.isEmpty) Text('Nothing between you yet.', style: T.small()),
            for (final m in b.moments.reversed.take(20))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(m.romance != 0 ? Icons.favorite : (m.friendship >= 0 ? Icons.arrow_upward : Icons.arrow_downward), size: 14, color: m.romance > 0 ? romanceColor : (m.friendship + m.romance >= 0 ? AppColors.success : AppColors.danger)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(m.text, style: T.small(color: AppColors.text))),
                  Text([if (m.friendship != 0) '${m.friendship > 0 ? '+' : ''}${m.friendship}', if (m.romance != 0) '${m.romance > 0 ? '+' : ''}${m.romance}♥'].join(' '), style: T.caption()),
                ]),
              ),
          ]),
        );
      },
    );
  }
}

class _VoicePicker extends StatelessWidget {
  const _VoicePicker({required this.host, required this.npc});
  final StoryHost host;
  final Npc npc;

  @override
  Widget build(BuildContext context) {
    final narrator = context.watch<Narrator>();
    final settings = context.read<SettingsController>();
    if (settings.useElevenLabs && narrator.elevenVoices.isEmpty && !narrator.elevenLoading) narrator.loadElevenVoices();
    final options = narrator.voiceOptions;
    final current = host.world.voices[npc.id] ?? narrator.aiVoiceFor(npc.name);
    if (narrator.elevenLoading) return const LinearProgressIndicator(minHeight: 2);
    if (options.isEmpty) return Text(settings.useElevenLabs ? 'No ElevenLabs voices found. Check your key in Settings → Voice.' : 'This voice model has no named voices.', style: T.small());
    return Wrap(spacing: 6, runSpacing: 6, children: [
      for (final (id, label, sample) in options)
        ChoiceChip(
          avatar: sample == null ? null : const Icon(Icons.play_arrow_rounded, size: 16),
          label: Text(label),
          selected: id == current,
          onSelected: (_) {
            host.world.voices[npc.id] = id;
            host.save();
            host.refresh();
            // Free sample clips where available; otherwise a short spoken line.
            if (sample != null) {
              narrator.playSample(sample);
            } else {
              narrator.speakNow('Hello. It\'s me, ${npc.name.split(' ').first}.', speaker: npc.name);
            }
          },
        ),
    ]);
  }
}

/// Generates or regenerates a character's AI portrait, with a spinner.
class PortraitButton extends StatefulWidget {
  const PortraitButton({super.key, required this.host, required this.npc});
  final StoryHost host;
  final Npc npc;

  @override
  State<PortraitButton> createState() => _PortraitButtonState();
}

class _PortraitButtonState extends State<PortraitButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final images = context.watch<ImageService>();
    final settings = context.watch<SettingsController>();
    if (!settings.useAiImages) return const SizedBox.shrink();
    final key = widget.host.portraitKey(widget.npc);
    final busy = _busy || images.isBusy(key);
    return Material(
      color: AppColors.surface2,
      shape: const CircleBorder(side: BorderSide(color: AppColors.border)),
      child: IconButton(
        tooltip: widget.npc.portrait.aiImagePath == null ? 'Paint AI portrait' : 'Repaint AI portrait',
        icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome_outlined, size: 18),
        onPressed: busy
            ? null
            : () async {
                setState(() => _busy = true);
                try {
                  images.resume();
                  await widget.host.paintPortrait(widget.npc);
                  if (context.mounted && images.errors[key] != null) showIssueSheet(context, images.errors[key]!, label: 'Portrait');
                } finally {
                  if (mounted) setState(() => _busy = false);
                }
              },
      ),
    );
  }
}

// ------------------------------------------------------------------- chat

/// A private, saved conversation with any character.
Future<void> showCharacterChat(BuildContext context, StoryHost host, Npc npc) {
  return showAppSheet(context, builder: (ctx) => _Chat(host: host, npc: npc, outer: context));
}

class _Chat extends StatefulWidget {
  const _Chat({required this.host, required this.npc, required this.outer});
  final StoryHost host;
  final Npc npc;
  final BuildContext outer;

  @override
  State<_Chat> createState() => _ChatState();
}

class _ChatState extends State<_Chat> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send([String? text]) async {
    final line = (text ?? _ctrl.text).trim();
    if (line.isEmpty || _busy) return;
    _ctrl.clear();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.host.talkTo(widget.npc, line);
    } catch (e) {
      final chat = widget.host.world.chatWith(widget.npc.id);
      if (chat.isNotEmpty && chat.last.fromPlayer) chat.removeLast();
      if (mounted) {
        setState(() => _error = '$e');
        _ctrl.text = line;
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final npc = widget.npc;
    final host = widget.host;
    final settings = context.watch<SettingsController>();
    final first = npc.name.split(' ').first;
    return ListenableBuilder(
      listenable: host,
      builder: (context, _) {
        final chat = host.world.chats[npc.id] ?? const <ChatLine>[];
        final b = host.world.bondFor(npc);
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.78,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      showPersonSheet(widget.outer, host, npc);
                    },
                    child: NpcPortrait(npc: npc, size: 48),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(npc.name, style: T.h3()),
                      Text([if (npc.role.isNotEmpty) npc.role, b.label].join(' · '), style: T.small(), maxLines: 1, overflow: TextOverflow.ellipsis),
                      BondBars(bond: b, compact: true),
                    ]),
                  ),
                  PortraitButton(host: host, npc: npc),
                ]),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_error != null) ErrorCard(error: _error!, label: 'No reply'),
                    if (_busy) Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text('$first is replying…', style: T.small()))),
                    for (final l in chat.reversed) _bubble(context, l, settings),
                    if (chat.isEmpty && !_busy)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: Column(children: [
                          Text(host.isAi && settings.useAiNpcChat ? 'Say anything. $first remembers what you talk about, and it can change how they feel about you.' : 'Turn on AI character chats in Settings for free-form conversations.', textAlign: TextAlign.center, style: T.small()),
                          const SizedBox(height: 12),
                          Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
                            for (final s in ['How are you holding up?', 'What do you know about this place?', 'Tell me about yourself.', 'I\'m glad you\'re here.'])
                              ActionChip(label: Text(s), onPressed: () => _send(s)),
                          ]),
                        ]),
                      ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(children: [
                    Expanded(child: TextField(controller: _ctrl, style: T.body(), textInputAction: TextInputAction.send, decoration: InputDecoration(hintText: 'Message $first'), onSubmitted: (_) => _send())),
                    const SizedBox(width: 8),
                    CircleIconButton(icon: Icons.arrow_upward, size: 44, tooltip: 'Send', onPressed: _busy ? null : _send),
                  ]),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }

  Widget _bubble(BuildContext context, ChatLine l, SettingsController settings) {
    final me = l.fromPlayer;
    return Align(
      alignment: me ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(crossAxisAlignment: me ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
        GestureDetector(
          onLongPress: () {
            Clipboard.setData(ClipboardData(text: l.text));
            showToast(context, 'Copied');
          },
          child: Container(
            margin: const EdgeInsets.only(top: 6, bottom: 2),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: const BoxConstraints(maxWidth: 320),
            decoration: BoxDecoration(color: me ? AppColors.text : AppColors.surface2, borderRadius: BorderRadius.circular(16)),
            child: Text(l.text, style: T.chat(color: me ? AppColors.bg : AppColors.text)),
          ),
        ),
        if (!me)
          Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Listen',
              icon: const Icon(Icons.volume_up_outlined, size: 16, color: AppColors.textFaint),
              onPressed: () => context.read<Narrator>().speakNow(l.text, speaker: widget.npc.name),
            ),
            if (settings.costPerMessage && (l.tokens > 0 || l.cost > 0)) CostBadge(tokens: l.tokens, cost: l.cost),
          ]),
      ]),
    );
  }
}

// ----------------------------------------------------------------- memory

IconData canonIcon(String kind) => switch (kind) {
      'npc' => Icons.person_outline,
      'place' => Icons.place_outlined,
      'item' => Icons.diamond_outlined,
      'quest' => Icons.flag_outlined,
      'promise' => Icons.handshake_outlined,
      'clue' => Icons.search,
      'lore' => Icons.auto_stories_outlined,
      _ => Icons.lightbulb_outline,
    };

/// Structured memory: the summary plus canon entries the AI must respect.
class MemoryTab extends StatelessWidget {
  const MemoryTab({super.key, required this.host});
  final StoryHost host;

  Future<void> _editSummary(BuildContext context) async {
    final t = await editTextDialog(context, title: 'Story so far', initial: host.summary, hint: 'A short summary the storyteller reads every turn', lines: 8);
    if (t != null) {
      host.summary = t.trim();
      host.save();
      host.refresh();
    }
  }

  Future<void> _edit(BuildContext context, CanonEntry? e) async {
    final r = await showAppSheet<CanonEntry>(context, builder: (ctx) => _CanonEditor(entry: e));
    if (r == null) return;
    if (e == null) host.canon.add(r..turn = host.turns);
    host.save();
    host.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final canon = host.canon;
    final pinned = canon.where((c) => c.pinned).toList();
    final rest = canon.where((c) => !c.pinned).toList()..sort((x, y) => y.turn.compareTo(x.turn));
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(host.isAi ? 'The storyteller reads this every turn. Pinned facts are always included; others by recency.' : 'Facts recorded during your story.', style: T.small()),
      SectionLabel('Story so far', trailing: GestureDetector(onTap: () => _editSummary(context), child: Text('Edit', style: T.caption(color: AppColors.textMuted)))),
      AppCard(
        onTap: () => _editSummary(context),
        child: Text(host.summary.isEmpty ? 'No summary yet. It is written automatically as the story grows, or tap to write your own.' : host.summary, style: T.small(color: host.summary.isEmpty ? AppColors.textFaint : AppColors.text)),
      ),
      SectionLabel('Canon · ${canon.length}', trailing: GestureDetector(onTap: () => _edit(context, null), child: Text('Add', style: T.caption(color: AppColors.textMuted)))),
      if (canon.isEmpty) const EmptyState(icon: Icons.psychology_outlined, title: 'Nothing remembered yet', message: 'People, places, promises and clues appear here as you play.'),
      if (canon.isNotEmpty)
        RowGroup(children: [
          for (final c in [...pinned, ...rest])
            ListRow(
              leading: Icon(canonIcon(c.kind), size: 20),
              title: c.name,
              subtitle: '${c.kind}${c.text.isEmpty ? '' : ' · ${c.text}'}',
              onTap: () => _edit(context, c),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: c.pinned ? 'Unpin' : 'Pin',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(c.pinned ? Icons.push_pin : Icons.push_pin_outlined, size: 18, color: c.pinned ? AppColors.accent : AppColors.textFaint),
                  onPressed: () {
                    c.pinned = !c.pinned;
                    host.save();
                    host.refresh();
                  },
                ),
                IconButton(
                  tooltip: 'Forget',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 18, color: AppColors.textFaint),
                  onPressed: () {
                    canon.remove(c);
                    host.save();
                    host.refresh();
                  },
                ),
              ]),
            ),
        ]),
    ]);
  }
}

class _CanonEditor extends StatefulWidget {
  const _CanonEditor({this.entry});
  final CanonEntry? entry;

  @override
  State<_CanonEditor> createState() => _CanonEditorState();
}

class _CanonEditorState extends State<_CanonEditor> {
  late final _name = TextEditingController(text: widget.entry?.name ?? '');
  late final _text = TextEditingController(text: widget.entry?.text ?? '');
  late String _kind = widget.entry?.kind ?? 'fact';
  late bool _pinned = widget.entry?.pinned ?? false;

  @override
  void dispose() {
    _name.dispose();
    _text.dispose();
    super.dispose();
  }

  void _save() {
    if (_name.text.trim().isEmpty) return;
    final e = widget.entry;
    if (e != null) {
      e
        ..name = _name.text.trim()
        ..text = _text.text.trim()
        ..kind = _kind
        ..pinned = _pinned;
      Navigator.pop(context, e);
    } else {
      Navigator.pop(context, CanonEntry(id: newId(), kind: _kind, name: _name.text.trim(), text: _text.text.trim(), pinned: _pinned));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.entry == null ? 'Remember something' : 'Edit memory', style: T.h2()),
          const SizedBox(height: 16),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final k in canonKinds) ChoiceChip(label: Text(k), selected: _kind == k, onSelected: (_) => setState(() => _kind = k)),
          ]),
          const SizedBox(height: 14),
          TextField(controller: _name, style: T.body(), decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 10),
          TextField(controller: _text, style: T.body(), minLines: 2, maxLines: 5, decoration: const InputDecoration(labelText: 'What is true about it')),
          const SizedBox(height: 6),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: Text('Pin (always remembered)', style: T.body()), value: _pinned, onChanged: (v) => setState(() => _pinned = v)),
          const SizedBox(height: 8),
          AppButton(label: 'Save', onPressed: _save),
        ]),
      ),
    );
  }
}

Future<String?> editTextDialog(BuildContext context, {required String title, String initial = '', String hint = '', int lines = 1}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 420,
        child: TextField(controller: c, autofocus: true, minLines: lines, maxLines: lines + 4, style: T.body(), decoration: InputDecoration(hintText: hint)),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: T.h3(color: AppColors.textMuted))),
        TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Save')),
      ],
    ),
  );
}

// ---------------------------------------------------------------- gallery

/// One picture in the gallery: AI media or art drawn on the device.
class _Pic {
  _Pic({required this.title, required this.kind, required this.art, this.path, this.video = false, this.cost = 0, this.render, this.aspect = 16 / 9});
  final String title;

  /// scene | portrait | effect | map
  final String kind;
  final Widget art;
  final String? path;
  final bool video;
  final double cost;

  /// Renders drawn art to PNG for saving and sharing.
  final Future<Uint8List?> Function()? render;
  final double aspect;
  bool get drawn => path == null;
}

class GalleryTab extends StatefulWidget {
  const GalleryTab({super.key, required this.host});
  final StoryHost host;

  @override
  State<GalleryTab> createState() => _GalleryTabState();
}

class _GalleryTabState extends State<GalleryTab> {
  String _filter = 'all';

  List<_Pic> _pictures() {
    final host = widget.host;
    final out = <_Pic>[];
    final aiPaths = <String>{};
    for (final m in host.world.gallery.reversed) {
      aiPaths.add(m.path);
      final fallback = Container(color: AppColors.surface2, child: Icon(m.video ? Icons.movie_outlined : Icons.image_outlined, color: AppColors.textFaint));
      out.add(_Pic(title: m.caption.isEmpty ? m.kind : m.caption, kind: m.kind, path: m.path, video: m.video, cost: m.cost, aspect: m.kind == 'portrait' ? 1 : 16 / 9, art: m.video ? fallback : MediaView(path: m.path, fallback: fallback, cacheWidth: 360)));
    }
    // Scenes drawn on device (one per place).
    final seen = <String>{};
    for (final e in host.log.reversed) {
      final raw = e.meta['scene'];
      if (raw is! Map || !seen.add(e.text)) continue;
      final ai = host.record.sceneImages[e.text];
      if (ai != null && aiPaths.contains(ai)) continue;
      final sc = SceneInfo.fromJson(Map<String, dynamic>.from(raw));
      out.add(_Pic(title: e.text, kind: 'scene', art: SceneView(location: sc.location, time: sc.time, mood: sc.mood, seed: sc.seed), path: ai, render: () => scenePng(sc)));
    }
    // Everyone's portrait, drawn or painted.
    final record = host.record;
    final cast = <(String, PortraitSpec, String, String?)>[
      if (record is Adventure) (record.hero.name, record.hero.portrait, record.hero.raceId, record.hero.classLevels.keys.first),
      for (final n in host.people) (n.name, n.portrait, n.raceId, null),
    ];
    for (final (name, spec, race, cls) in cast) {
      if (spec.aiImagePath != null && aiPaths.contains(spec.aiImagePath)) continue;
      out.add(_Pic(
        title: name,
        kind: 'portrait',
        aspect: 1,
        path: spec.aiImagePath,
        art: PortraitView(spec: spec, raceId: race, classId: cls, size: 180, circle: false),
        render: () => portraitPng(spec, race, classId: cls),
      ));
    }
    final m = host.map;
    if (m != null && (m.aiImagePath == null || !aiPaths.contains(m.aiImagePath))) {
      out.add(_Pic(title: m.name, kind: 'map', aspect: 1.45, path: m.aiImagePath, art: MapPreview(map: m), render: () => mapPng(m)));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final host = widget.host;
    final settings = context.watch<SettingsController>();
    final all = _pictures();
    final items = all.where((p) => _filter == 'all' || p.kind == _filter || (_filter == 'effect' && p.video)).toList();
    final total = host.world.gallery.fold<double>(0, (t, m) => t + m.cost);
    const filters = [('all', 'All'), ('scene', 'Scenes'), ('portrait', 'Characters'), ('effect', 'Moments'), ('map', 'Map')];
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        Expanded(child: Text('${all.length} pictures${total > 0 ? ' · ${fmtCost(total)} of AI art' : ''}', style: T.small())),
        if (settings.useAiImages)
          TextButton.icon(
            onPressed: () {
              host.paintScene();
              showToast(context, 'Painting this scene…', icon: Icons.brush_outlined);
            },
            icon: const Icon(Icons.brush_outlined, size: 16),
            label: const Text('Paint scene'),
          ),
        if (settings.useAiVideo)
          TextButton.icon(
            onPressed: () {
              host.filmScene();
              showToast(context, 'Filming this scene. Videos take a minute or two.', icon: Icons.movie_outlined);
            },
            icon: const Icon(Icons.movie_outlined, size: 16),
            label: const Text('Film'),
          ),
      ]),
      const SizedBox(height: 6),
      SizedBox(
        height: 36,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final (id, label) in filters)
            Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: Text(label), selected: _filter == id, onSelected: (_) => setState(() => _filter = id))),
        ]),
      ),
      const SizedBox(height: 10),
      if (items.isEmpty) const EmptyState(icon: Icons.photo_library_outlined, title: 'Nothing here yet', message: 'Scenes, characters and maps appear as you play. Tap any picture to save it to your phone.'),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 180, mainAxisSpacing: 8, crossAxisSpacing: 8),
        itemBuilder: (ctx, i) {
          final p = items[i];
          return GestureDetector(
            onTap: () => openMedia(
              context,
              path: p.path,
              fallback: p.art,
              title: p.title,
              subtitle: '${p.kind[0].toUpperCase()}${p.kind.substring(1)}${p.drawn ? ' · drawn on device' : ''}${p.cost > 0 ? ' · ${fmtCost(p.cost)}' : ''}',
              aspectRatio: p.aspect,
              render: p.render,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(fit: StackFit.expand, children: [
                FittedBox(fit: BoxFit.cover, clipBehavior: Clip.hardEdge, child: SizedBox(width: 180, height: 180 / (p.aspect > 1.2 ? 1 : p.aspect).clamp(0.8, 1.2), child: p.art)),
                if (p.video) const Center(child: Icon(Icons.play_circle_outline, color: Colors.white70, size: 36)),
                if (p.drawn)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(999)),
                      child: Text('Drawn', style: T.caption(color: Colors.white70).copyWith(fontSize: 10)),
                    ),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
                    decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xB3000000)])),
                    child: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.caption(color: Colors.white)),
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    ]);
  }
}

// --------------------------------------------------------------- AI tools

/// Layout switch and start over, shared by every story's tools sheet.
List<Widget> storyLayoutRows(BuildContext context, BuildContext sheet, StoryHost host) => [
      RowGroup(children: [
        ListRow(
          leading: const Icon(Icons.terminal, size: 20),
          title: 'Terminal layout',
          subtitle: 'Classic monospace text with a prompt',
          trailing: Switch(
            value: host.record is Tale ? (host.record as Tale).terminal : (host.record as Adventure).textMode,
            onChanged: host.busy
                ? null
                : (v) {
                    Navigator.pop(sheet);
                    _changeStoryLayout(context, host, v);
                  },
          ),
        ),
        ListRow(
          leading: const Icon(Icons.replay, size: 20),
          title: 'Start over',
          subtitle: host.record is Tale ? 'A fresh copy; this story is kept' : 'Restart with your current party; this save is kept',
          onTap: host.busy
              ? null
              : () {
                  Navigator.pop(sheet);
                  _restartStory(context, host);
                },
        ),
      ]),
    ];

Future<void> _changeStoryLayout(BuildContext context, StoryHost host, bool terminal) async {
  if (host is TaleController) {
    host.tale.terminal = terminal;
    await host.flush();
    if (context.mounted) Navigator.of(context).pushReplacement(taleRoute(host.tale));
  } else if (host is AdventureController) {
    host.adventure.textMode = terminal;
    await host.flush();
    if (context.mounted) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => terminal
        ? TextAdventureScreen(adventure: host.adventure) : AdventureScreen(adventure: host.adventure)));
    }
  }
}

Future<void> _restartStory(BuildContext context, StoryHost host) async {
  if (host is TaleController) {
    await host.flush();
    if (!context.mounted) return;
    final fresh = await restartTale(context, host.tale);
    if (context.mounted) Navigator.of(context).pushReplacement(taleRoute(fresh));
  } else if (host is AdventureController) {
    await host.flush();
    if (!context.mounted) return;
    final old = host.adventure;
    Character freshHero(Character hero) => Character.fromJson({...hero.toJson(), 'id': newId()})
      ..dead = false
      ..longRest();
    final fresh = Adventure(
      id: newId(), title: old.title, premise: old.premise,
      hero: freshHero(old.hero), companions: old.companions.map(freshHero).toList(),
      engine: old.engine, setting: old.setting, tone: old.tone, difficulty: old.difficulty,
      textMode: old.textMode, coverSeed: old.coverSeed, chaos: old.chaos,
      hardcore: old.hardcore, showDcs: old.showDcs,
      offline: old.engine == StoryEngine.module ? ModuleEngine.createState(old.offline['module'] as String) : null,
    );
    await context.read<GameStore>().saveAdventure(fresh, syncHero: false);
    if (context.mounted) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => fresh.textMode
        ? TextAdventureScreen(adventure: fresh) : AdventureScreen(adventure: fresh)));
    }
  }
}

/// Recap, lore questions, ideas and a diary entry.
Future<void> showAiTools(BuildContext context, StoryHost host) {
  return showAppSheet(context, builder: (ctx) => _AiTools(host: host, outer: context));
}

class _AiTools extends StatefulWidget {
  const _AiTools({required this.host, required this.outer});
  final StoryHost host;
  final BuildContext outer;

  @override
  State<_AiTools> createState() => _AiToolsState();
}

class _AiToolsState extends State<_AiTools> {
  String? _busy;
  String? _title;
  String? _text;
  List<String> _ideas = [];
  AiResult? _last;
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _run(String title, Future<AiResult> Function(StoryAi ai) call) async {
    setState(() {
      _busy = title;
      _text = null;
      _ideas = [];
    });
    try {
      final r = await call(StoryAi(widget.host.settings));
      if (!mounted) return;
      setState(() {
        _title = title;
        _last = r;
        if (r.value is List) {
          _ideas = [for (final x in r.value as List) x.toString()];
        } else {
          _text = r.value.toString();
        }
      });
    } catch (e) {
      if (mounted) showIssueSheet(context, '$e', label: title);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final host = widget.host;
    final settings = context.watch<SettingsController>();
    final on = settings.useAiText;
    Widget tool(IconData icon, String title, String sub, VoidCallback onTap) => ListRow(
          leading: _busy == title ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(icon, size: 20),
          title: title,
          subtitle: sub,
          onTap: on && _busy == null ? onTap : null,
        );
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: ListView(padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(context).bottom + 24), children: [
        SheetTitle('AI tools', subtitle: on ? 'Helpers that don\'t spend a turn' : 'Add an AI key and turn on AI story in Settings to use these'),
        const _AiControls(),
        const SectionLabel('Helpers'),
        RowGroup(children: [
          tool(Icons.history_edu_outlined, 'Previously on…', 'A short recap of your story so far', () => _run('Previously on…', (ai) => ai.recap(host))),
          tool(Icons.lightbulb_outline, 'Inspire me', 'Three fresh ideas for what to do next', () => _run('Ideas', (ai) => ai.inspire(host))),
          tool(Icons.edit_note, 'Write a diary entry', 'Your character\'s private thoughts', () => _run('Diary', (ai) => ai.diary(host))),
        ]),
        const SectionLabel('Ask about the world'),
        Row(children: [
          Expanded(child: TextField(controller: _q, style: T.body(), textInputAction: TextInputAction.search, decoration: const InputDecoration(hintText: 'Who is the masked stranger?'), onSubmitted: (_) => _ask())),
          const SizedBox(width: 8),
          CircleIconButton(icon: Icons.arrow_upward, size: 44, onPressed: on && _busy == null ? _ask : null),
        ]),
        if (_busy != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text('Thinking…', style: T.small())),
        if (_text != null) ...[
          SectionLabel(_title ?? ''),
          AppCard(child: SelectableText(_text!, style: T.reading())),
          Row(children: [
            TextButton.icon(onPressed: () => context.read<Narrator>().speakNow(_text!), icon: const Icon(Icons.volume_up_outlined, size: 16), label: const Text('Listen')),
            TextButton.icon(onPressed: () => Clipboard.setData(ClipboardData(text: _text!)), icon: const Icon(Icons.copy, size: 16), label: const Text('Copy')),
            if (_title == 'Diary')
              TextButton.icon(
                onPressed: () {
                  host.canon.add(CanonEntry(id: newId(), kind: 'lore', name: 'Diary · turn ${host.turns}', text: _text!, turn: host.turns));
                  host.save();
                  showToast(context, 'Saved to Memory');
                },
                icon: const Icon(Icons.bookmark_add_outlined, size: 16),
                label: const Text('Keep'),
              ),
            const Spacer(),
            if (_last != null && settings.costPerMessage) CostBadge(tokens: _last!.tokens, cost: _last!.cost),
          ]),
        ],
        if (_ideas.isNotEmpty) ...[
          const SectionLabel('Ideas'),
          for (final idea in _ideas)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                onTap: host.busy
                    ? null
                    : () {
                        Navigator.pop(context);
                        host.act(idea);
                      },
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  const Icon(Icons.bolt_outlined, size: 18, color: AppColors.accent),
                  const SizedBox(width: 10),
                  Expanded(child: Text(idea, style: T.body())),
                  const Icon(Icons.send_outlined, size: 16, color: AppColors.textFaint),
                ]),
              ),
            ),
        ],
      ]),
    );
  }

  void _ask() {
    final q = _q.text.trim();
    if (q.isEmpty) return;
    _run('Lore', (ai) => ai.lore(widget.host, q));
  }
}

// ----------------------------------------------------------------- recap

/// "Previously on…" shown when you come back to a story after a while.
class RecapBanner extends StatefulWidget {
  const RecapBanner({super.key, required this.host, required this.lastPlayed});
  final StoryHost host;
  final DateTime lastPlayed;

  @override
  State<RecapBanner> createState() => _RecapBannerState();
}

class _RecapBannerState extends State<RecapBanner> {
  String? _text;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    final s = widget.host.settings;
    final away = DateTime.now().difference(widget.lastPlayed) > const Duration(hours: 4);
    if (away && s.aiRecaps && s.useAiText && widget.host.isAi && widget.host.log.length > 6) {
      unawaited(StoryAi(s).recap(widget.host).then((r) {
        if (mounted) setState(() => _text = r.value);
      }).catchError((_) {}));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _text;
    if (t == null || _closed) return const SizedBox.shrink();
    return FadeIn(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 12),
        decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.accent.withValues(alpha: 0.35))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.history_edu_outlined, size: 18, color: AppColors.accent)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('PREVIOUSLY ON…', style: T.overline(color: AppColors.accent)),
              const SizedBox(height: 4),
              Text(t, style: T.small(color: AppColors.text)),
            ]),
          ),
          IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _closed = true)),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------- menu

/// Menu rows every story shares (AI tools, people, gallery, memory, export…).
List<Widget> storyMenuRows(BuildContext context, BuildContext sheetContext, StoryHost host) {
  final settings = context.read<SettingsController>();
  void go(void Function() f) {
    Navigator.pop(sheetContext);
    f();
  }

  return [
    RowGroup(children: [
      ListRow(leading: const Icon(Icons.forum_outlined, size: 20), title: 'People & relationships', subtitle: '${host.people.length} met · talk to anyone', onTap: () => go(() => showStoryJournal(context, host, initial: 'People'))),
      ListRow(leading: const Icon(Icons.photo_library_outlined, size: 20), title: 'Gallery', subtitle: 'Art, portraits and maps · save any to your phone', onTap: () => go(() => showStoryJournal(context, host, initial: 'Gallery'))),
      ListRow(leading: const Icon(Icons.psychology_alt_outlined, size: 20), title: 'Memory', subtitle: '${host.canon.length} facts remembered', onTap: () => go(() => showStoryJournal(context, host, initial: 'Memory'))),
      ListRow(leading: const Icon(Icons.text_fields, size: 20), title: 'Text & font', subtitle: '${_fontLabels[settings.readingFont] ?? 'Serif'} · ${(settings.readingScale * 100).round()}%', onTap: () => go(() => showTextStyleSheet(context))),
      ListRow(leading: const Icon(Icons.ios_share, size: 20), title: 'Export', subtitle: 'PDF, web page, Markdown or text', onTap: () => go(() => showStoryExport(context, host))),
      if (settings.useAiImages) ListRow(leading: const Icon(Icons.brush_outlined, size: 20), title: 'Paint this scene', onTap: () => go(host.paintScene)),
      if (settings.useAiVideo) ListRow(leading: const Icon(Icons.movie_outlined, size: 20), title: 'Film this scene', subtitle: '${settings.videoDuration}s clip · ${settings.videoResolution}', onTap: () => go(host.filmScene)),
      ListRow(
        leading: const Icon(Icons.record_voice_over_outlined, size: 20),
        title: 'Read aloud',
        subtitle: settings.useElevenLabs ? 'ElevenLabs voices' : settings.useAiVoice ? 'AI voices' : 'Device voice',
        trailing: Switch(
          value: settings.ttsEnabled,
          onChanged: (v) {
            settings.update((s) => s.ttsEnabled = v);
            if (!v) context.read<Narrator>().stop();
          },
        ),
      ),
      if (settings.showUsage)
        ListRow(
          leading: const Icon(Icons.toll_outlined, size: 20),
          title: 'Usage & cost',
          subtitle: '${fmtCost((host.usageTotals['cost'] ?? 0).toDouble())} in this story',
          onTap: () => go(() => showStoryUsage(context, host)),
        ),
    ]),
  ];
}

/// The scene backdrop for a story, AI art or procedural.
class SceneBackdrop extends StatelessWidget {
  const SceneBackdrop({super.key, required this.host, this.fit = BoxFit.cover});
  final StoryHost host;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final s = host.scene;
    return MediaView(path: host.record.sceneImagePath, fallback: SceneView(location: s.location, time: s.time, mood: s.mood, seed: s.seed), fit: fit);
  }
}

/// Quick switches for the AI features, right inside a story.
class _AiControls extends StatefulWidget {
  const _AiControls();

  @override
  State<_AiControls> createState() => _AiControlsState();
}

class _AiControlsState extends State<_AiControls> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsController>();
    final key = s.hasApiKey;
    Widget sw(IconData icon, String title, bool value, ValueChanged<bool>? onChanged, {String? sub}) => ListRow(
          leading: Icon(icon, size: 20),
          title: title,
          subtitle: sub,
          trailing: Switch(value: value, onChanged: onChanged),
        );
    final on = [
      if (s.useAiText) 'story',
      if (s.useAiImages) 'images',
      if (s.useAiVideo) 'video',
      if (s.ttsEnabled) s.useCloudVoice ? 'AI voice' : 'voice',
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppCard(
        onTap: () => setState(() => _open = !_open),
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          const Icon(Icons.tune, size: 20, color: AppColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('AI controls', style: T.h3()),
              Text(on.isEmpty ? 'Everything runs on device' : 'On: ${on.join(', ')}', style: T.caption()),
            ]),
          ),
          Icon(_open ? Icons.expand_less : Icons.expand_more, color: AppColors.textFaint),
        ]),
      ),
      if (_open) ...[
        const SizedBox(height: 8),
        RowGroup(children: [
          sw(Icons.auto_stories_outlined, 'AI storyteller', s.aiText, key ? (v) => s.update((s) => s.aiText = v) : null, sub: key ? null : 'Add a key in Settings first'),
          sw(Icons.forum_outlined, 'Character chats', s.aiNpcChat, (v) => s.update((s) => s.aiNpcChat = v)),
          sw(Icons.history_edu_outlined, 'Recaps when you return', s.aiRecaps, (v) => s.update((s) => s.aiRecaps = v)),
          sw(Icons.sports_kabaddi_outlined, 'Narrate combat', s.aiCombatNarration, (v) => s.update((s) => s.aiCombatNarration = v)),
          sw(Icons.image_outlined, 'AI images', s.imageMode == ImageMode.ai, key ? (v) => s.update((s) => s.imageMode = v ? ImageMode.ai : ImageMode.procedural) : null),
          sw(Icons.autorenew, 'Paint automatically', s.aiAutoImages, (v) => s.update((s) => s.aiAutoImages = v)),
          sw(Icons.landscape_outlined, 'Scene art', s.aiScenes, (v) => s.update((s) => s.aiScenes = v)),
          sw(Icons.face_outlined, 'Character portraits', s.aiNpcPortraits, (v) => s.update((s) => s.aiNpcPortraits = v)),
          sw(Icons.auto_awesome_outlined, 'Special effects', s.aiEffects, (v) => s.update((s) => s.aiEffects = v)),
          sw(Icons.movie_outlined, 'Video clips', s.videoEnabled, key ? (v) => s.update((s) => s.videoEnabled = v) : null),
          sw(Icons.record_voice_over_outlined, 'Read aloud', s.ttsEnabled, (v) {
            s.update((s) => s.ttsEnabled = v);
            if (!v) context.read<Narrator>().stop();
          }),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                const ButtonSegment(value: 'device', label: Text('Device')),
                ButtonSegment(value: 'ai', label: const Text('AI voice'), enabled: key),
                ButtonSegment(value: 'elevenlabs', label: const Text('ElevenLabs', maxLines: 1), enabled: s.elevenLabsKey.isNotEmpty),
              ],
              selected: {s.voiceEngine},
              onSelectionChanged: (v) => s.update((s) => s.voiceEngine = v.first),
            ),
          ),
          ListRow(
            leading: const Icon(Icons.settings_outlined, size: 20),
            title: 'All AI settings',
            subtitle: 'Models, providers, voices, limits',
            trailing: const Icon(Icons.chevron_right, size: 18, color: AppColors.textFaint),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ]),
      ],
      const SizedBox(height: 4),
    ]);
  }
}

// --------------------------------------------------------------- text style

const _fontLabels = {'serif': 'Serif', 'sans': 'Sans', 'mono': 'Mono'};

/// Reading font and size for every story view and chat.
class ReadingControls extends StatelessWidget {
  const ReadingControls({super.key, this.preview = true});
  final bool preview;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsController>();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SegmentedButton<String>(
        showSelectedIcon: false,
        segments: [for (final e in _fontLabels.entries) ButtonSegment(value: e.key, label: Text(e.value, style: TextStyle(fontFamily: e.key == 'mono' ? 'JetBrainsMono' : (e.key == 'serif' ? 'serif' : 'Inter'))))],
        selected: {s.readingFont},
        onSelectionChanged: (v) => s.update((s) {
          s.readingFont = v.first;
          s.taleTypewriterFont = v.first == 'mono';
        }),
      ),
      const SizedBox(height: 8),
      Row(children: [
        const Icon(Icons.text_decrease, size: 18, color: AppColors.textMuted),
        Expanded(child: Slider(value: s.readingScale, min: 0.8, max: 1.6, divisions: 16, label: '${(s.readingScale * 100).round()}%', onChanged: (v) => s.update((s) => s.readingScale = v))),
        const Icon(Icons.text_increase, size: 18, color: AppColors.textMuted),
        SizedBox(width: 44, child: Text('${(s.readingScale * 100).round()}%', textAlign: TextAlign.right, style: T.caption(color: AppColors.textMuted))),
      ]),
      if (preview) ...[
        const SizedBox(height: 6),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('The lantern gutters. Somewhere below, water drips onto stone, slow as a heartbeat.', style: T.reading()),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: AppColors.text, borderRadius: BorderRadius.circular(14)),
                child: Text('Light another torch.', style: T.chat(color: AppColors.bg)),
              ),
            ),
          ]),
        ),
      ],
    ]);
  }
}

Future<void> showTextStyleSheet(BuildContext context) => showAppSheet(context, builder: (ctx) => const Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SheetTitle('Text & font', subtitle: 'For the story, chats and both layouts'),
        ReadingControls(),
      ]),
    ));
