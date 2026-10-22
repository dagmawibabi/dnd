import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../game/story_host.dart';
import '../../../models/adventure.dart';
import '../../../models/world.dart';
import '../../../services/ai/story_ai.dart';
import '../../../services/companion_store.dart';
import '../../../services/settings.dart';
import '../../../theme/ui.dart';
import '../companions/companion_profile.dart';

/// Who someone is: backstory, personality, goals and needs, their memories
/// (which you can add to and edit) and how the story has changed them.
class PersonProfileView extends StatefulWidget {
  const PersonProfileView({super.key, required this.host, required this.npc});
  final StoryHost host;
  final Npc npc;

  @override
  State<PersonProfileView> createState() => _PersonProfileViewState();
}

/// People whose profile is being written right now (so it's done once).
final _writing = <String>{};

class _PersonProfileViewState extends State<PersonProfileView> {
  bool _secret = false;
  String? _error;

  PersonProfile get p => widget.host.world.profileOf(widget.npc);

  void _companionsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    CompanionStore.instance.removeListener(_companionsChanged);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    CompanionStore.instance.addListener(_companionsChanged);
    final s = widget.host.settings;
    // Everyone has a backstory: written the first time their profile is opened.
    if (p.backstory.isEmpty && s.useAiText && widget.host.isAi && !_writing.contains(widget.npc.id)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _write());
    }
  }

  Future<void> _write({bool again = false}) async {
    final host = widget.host;
    final npc = widget.npc;
    if (_writing.contains(npc.id)) return;
    _writing.add(npc.id);
    setState(() => _error = null);
    try {
      final r = await StoryAi(host.settings).profile(host, npc);
      final made = r.value;
      final cur = host.world.profileOf(npc);
      if (again || cur.backstory.isEmpty) cur.backstory = made.backstory;
      if (again || cur.personality.isEmpty) cur.personality = made.personality;
      if (again || cur.traits.isEmpty) cur.traits = made.traits;
      if (cur.goals.isEmpty || again) cur.goals = {...cur.goals, ...made.goals}.take(5).toList();
      if (cur.needs.isEmpty || again) cur.needs = {...cur.needs, ...made.needs}.take(4).toList();
      if (cur.secret.isEmpty || again) cur.secret = made.secret;
      if (cur.age.isEmpty) cur.age = made.age;
      if (cur.occupation.isEmpty) cur.occupation = made.occupation;
      host.save();
      host.refresh();
    } catch (e) {
      if (mounted) _error = '$e';
    } finally {
      _writing.remove(npc.id);
      if (mounted) setState(() {});
    }
  }

  Future<void> _editMemory([CharacterMemory? m]) async {
    final c = TextEditingController(text: m?.text ?? '');
    final t = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(m == null ? 'A memory for ${widget.npc.name.split(' ').first}' : 'Edit memory'),
        content: SizedBox(width: 420, child: TextField(controller: c, autofocus: true, minLines: 2, maxLines: 6, style: T.body(), decoration: const InputDecoration(hintText: 'The night we shared the last of the bread by the river.'))),
        actions: [
          if (m != null)
            TextButton(onPressed: () => Navigator.pop(ctx, '\u0000delete'), child: Text('Forget', style: T.small(color: AppColors.danger))),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Save')),
        ],
      ),
    );
    if (t == null) return;
    if (t == '\u0000delete') {
      p.memories.remove(m);
    } else if (t.trim().isNotEmpty) {
      if (m == null) {
        p.remember(t, turn: widget.host.turns, source: 'player');
      } else {
        m.text = t.trim();
      }
    }
    widget.host.save();
    widget.host.refresh();
    setState(() {});
  }

  Future<void> _editList(String title, List<String> list, String hint) async {
    final c = TextEditingController(text: list.join('\n'));
    final t = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(width: 420, child: TextField(controller: c, autofocus: true, minLines: 3, maxLines: 8, style: T.body(), decoration: InputDecoration(hintText: hint, helperText: 'One per line'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Save')),
        ],
      ),
    );
    if (t == null) return;
    list
      ..clear()
      ..addAll(t.split('\n').map((x) => x.trim()).where((x) => x.isNotEmpty));
    widget.host.save();
    widget.host.refresh();
    setState(() {});
  }

  Future<void> _editText(String title, String value, void Function(String) set) async {
    final c = TextEditingController(text: value);
    final t = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(width: 420, child: TextField(controller: c, autofocus: true, minLines: 2, maxLines: 10, style: T.body())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Save')),
        ],
      ),
    );
    if (t == null) return;
    set(t.trim());
    widget.host.save();
    widget.host.refresh();
    setState(() {});
  }

  Widget _edit(VoidCallback onTap) => GestureDetector(onTap: onTap, child: Text('Edit', style: T.caption(color: AppColors.textMuted)));

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final npc = widget.npc;
    final pr = p;
    final writing = _writing.contains(npc.id);
    final canWrite = settings.useAiText;
    final mems = [...pr.memories.where((m) => m.pinned), ...pr.memories.reversed.where((m) => !m.pinned)];
    final companions = CompanionStore.instance;
    final friend = companions.companionFor(widget.host.storyId, npc.id);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 12),
      if (friend != null)
        AppCard(
          padding: const EdgeInsets.all(12),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CompanionProfileScreen(companionId: friend.id))),
          child: Row(children: [
            const Icon(Icons.diversity_1_outlined, size: 20, color: AppColors.accent),
            const SizedBox(width: 10),
            Expanded(child: Text('${npc.name.split(' ').first} is your companion. What happens here goes with them to other adventures.', style: T.small(color: AppColors.text))),
            const Icon(Icons.chevron_right, color: AppColors.textFaint),
          ]),
        )
      else if (widget.host.isAi && npc.alive)
        OutlinedButton.icon(
          icon: const Icon(Icons.diversity_1_outlined, size: 18),
          label: const Text('Make a companion'),
          onPressed: () async {
            final ok = await confirm(context, title: 'Make ${npc.name} a companion?', message: '${npc.name.split(' ').first} becomes a friend outside this story: you can chat any time and bring them into other adventures. They keep everything they know from here, and playing on here keeps adding to it.', action: 'Make a companion', danger: false);
            if (!ok || !context.mounted) return;
            final c = companions.promote(widget.host, npc);
            showToast(context, '${c.name} is now your companion', icon: Icons.diversity_1_outlined);
          },
        ),
      if (pr.age.isNotEmpty || pr.occupation.isNotEmpty || npc.gender.isNotEmpty || pr.traits.isNotEmpty) ...[
        const SizedBox(height: 14),
        Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
          if (npc.gender.isNotEmpty) Tag(npc.gender[0].toUpperCase() + npc.gender.substring(1), icon: Icons.person_outline),
          if (pr.age.isNotEmpty) Tag(pr.age, icon: Icons.cake_outlined),
          if (pr.occupation.isNotEmpty) Tag(pr.occupation, icon: Icons.work_outline),
          for (final t in pr.traits) Tag(t, color: AppColors.accent),
        ]),
      ],
      SectionLabel('Backstory', trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (canWrite && !writing) GestureDetector(onTap: () => _write(again: pr.backstory.isNotEmpty), child: Text(pr.backstory.isEmpty ? 'Write it' : 'Rewrite', style: T.caption(color: AppColors.textMuted))),
        const SizedBox(width: 12),
        _edit(() => _editText('Backstory', pr.backstory, (v) => pr.backstory = v)),
      ])),
      if (writing)
        Row(children: [
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          Text('Learning who ${npc.name.split(' ').first} is…', style: T.small()),
        ])
      else if (pr.backstory.isNotEmpty)
        Text(pr.backstory, style: T.body())
      else
        Text(_error != null ? 'Couldn\'t write it: $_error' : (canWrite ? 'Not written yet. Tap "Write it".' : 'Turn on the AI storyteller to give everyone a backstory, or write your own.'), style: T.small()),
      if (pr.personality.isNotEmpty || pr.growth.isNotEmpty) ...[
        SectionLabel('Who they are now', trailing: _edit(() => _editText('Personality', pr.personality, (v) => pr.personality = v))),
        if (pr.personality.isNotEmpty) Text(pr.personality[0].toUpperCase() + pr.personality.substring(1), style: T.body()),
        if (pr.growth.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final g in pr.growth.reversed.take(6))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.trending_up, size: 14, color: AppColors.accent)),
                const SizedBox(width: 8),
                Expanded(child: Text(g, style: T.small(color: AppColors.text))),
              ]),
            ),
        ],
      ],
      SectionLabel('Goals & needs', trailing: _edit(() async {
        await _editList('Goals', pr.goals, 'Find out who burned the mill');
        if (mounted) await _editList('Needs', pr.needs, 'To be forgiven');
      })),
      if (pr.goals.isEmpty && pr.needs.isEmpty) Text('Unknown so far.', style: T.small()),
      for (final g in pr.goals)
        Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.flag_outlined, size: 14, color: Color(0xFFE0B354))),
          const SizedBox(width: 8),
          Expanded(child: Text(g, style: T.small(color: AppColors.text))),
        ])),
      for (final n in pr.needs)
        Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.favorite_border, size: 14, color: AppColors.info)),
          const SizedBox(width: 8),
          Expanded(child: Text(n, style: T.small(color: AppColors.text))),
        ])),
      SectionLabel('Their memories · ${pr.memories.length}', trailing: GestureDetector(onTap: _editMemory, child: Text('Add', style: T.caption(color: AppColors.textMuted)))),
      if (mems.isEmpty) Text('Nothing yet. They remember what happens in the story and in your chats, and you can add memories of your own.', style: T.small()),
      if (mems.isNotEmpty)
        RowGroup(children: [
          for (final m in mems.take(30))
            ListRow(
              leading: Icon(switch (m.source) { 'chat' => Icons.chat_bubble_outline, 'player' => Icons.edit_outlined, _ => Icons.auto_stories_outlined }, size: 18, color: AppColors.textMuted),
              title: m.text,
              subtitle: '${switch (m.source) { 'chat' => 'From a conversation', 'player' => 'Added by you', _ => 'From the story' }}${m.turn > 0 ? ' · turn ${m.turn}' : ''}',
              onTap: () => _editMemory(m),
              trailing: IconButton(
                tooltip: m.pinned ? 'Unpin' : 'Always remember',
                visualDensity: VisualDensity.compact,
                icon: Icon(m.pinned ? Icons.push_pin : Icons.push_pin_outlined, size: 18, color: m.pinned ? AppColors.accent : AppColors.textFaint),
                onPressed: () {
                  setState(() => m.pinned = !m.pinned);
                  widget.host.save();
                },
              ),
            ),
        ]),
      if (pr.secret.isNotEmpty) ...[
        const SectionLabel('A secret'),
        AppCard(
          onTap: () => setState(() => _secret = !_secret),
          child: Row(children: [
            Icon(_secret ? Icons.visibility_outlined : Icons.lock_outline, size: 18, color: AppColors.textMuted),
            const SizedBox(width: 10),
            Expanded(child: Text(_secret ? pr.secret : 'They are hiding something. Tap to read it (a spoiler).', style: T.small(color: _secret ? AppColors.text : AppColors.textFaint))),
          ]),
        ),
      ],
    ]);
  }
}
