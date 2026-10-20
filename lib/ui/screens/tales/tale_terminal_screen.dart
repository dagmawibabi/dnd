import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../widgets/ai_gate.dart';
import '../../../art/scene_painter.dart';
import '../../../game/tale_controller.dart';
import '../../../models/adventure.dart';
import '../../../models/tale.dart';
import '../../../services/audio/audio_service.dart';
import '../../../services/settings.dart';
import '../../../theme/ui.dart';
import '../../widgets/media_view.dart';
import '../../widgets/typewriter.dart';
import '../../widgets/error_card.dart';
import '../adventure/adventure_extras.dart' show ChoiceToolbar;
import '../adventure/log_view.dart' show questOf, showQuestSheet;
import '../adventure/map_screen.dart';
import '../../../services/export.dart' show showStoryExport;
import '../story/notes_screen.dart';
import '../story/story_tools.dart';
import '../story/story_extras.dart';
import 'tale_tools.dart';
import 'tales_hub.dart' show taleRoute;

/// Classic terminal layout for text adventures: monospace log and a > prompt.
class TaleTerminalScreen extends StatefulWidget {
  const TaleTerminalScreen({super.key, required this.tale});
  final Tale tale;

  @override
  State<TaleTerminalScreen> createState() => _TaleTerminalScreenState();
}

class _TaleTerminalScreenState extends State<TaleTerminalScreen> {
  late final TaleController _ctl;
  late final AudioService _audio;
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final Set<String> _animated = {};
  final List<String> _echo = []; // command output (not saved)
  String? _hint;
  bool _choicesCollapsed = false;
  late final DateTime _lastPlayed = widget.tale.updatedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) checkLocalAi(context);
    });
    _audio = context.read<AudioService>();
    _ctl = createTaleController(context, widget.tale);
    for (final e in widget.tale.log) {
      _animated.add('${e.at.microsecondsSinceEpoch}');
    }
    _ctl.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ctl.start());
  }

  @override
  void dispose() {
    _ctl.removeListener(_changed);
    _ctl.flush();
    _ctl.dispose();
    _audio.stopMusic();
    _audio.stopAmbience();
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients && _scroll.offset > 0) _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  TextStyle _mono({Color color = AppColors.text, double size = 14}) => T.monoStory(size, color: color);

  Future<void> _switchLayout() async {
    _ctl.tale.terminal = false;
    await _ctl.flush();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(taleRoute(_ctl.tale));
  }

  void _say(String s) {
    setState(() {
      _echo.add(s);
      _hint = null;
    });
  }

  Future<void> _submit() async {
    final raw = _input.text.trim();
    _input.clear();
    _focus.requestFocus();
    if (raw.isEmpty) return;
    final t = raw.toLowerCase();
    final tale = _ctl.tale;
    final g = _ctl.genre;
    switch (t) {
      case 'help' || '?':
        _say('commands: 1-9 (choose) · look · inv · status · people · talk <name> · goals · map · memory · gallery · notes · ideas · recap · export · layout · help${_ctl.isAi ? ' · anything else is sent to the narrator' : ' · or type part of an option'}');
        return;
      case 'people' || 'who':
        _say(tale.npcs.isEmpty ? 'you have met no one yet.' : tale.npcs.map((n) => '${n.name}${n.role.isEmpty ? '' : ' (${n.role})'} · ${tale.bondFor(n).label.toLowerCase()}').join('\n  '));
        return;
      case 'goals' || 'journal' || 'j':
        unawaited(showTaleJournal(context, _ctl));
        return;
      case 'map' || 'm':
        openMapScreen(context, _ctl);
        return;
      case 'memory':
        unawaited(showTaleJournal(context, _ctl, initial: 'Memory'));
        return;
      case 'notes' || 'note':
        unawaited(openNotes(context, _ctl));
        return;
      case 'gallery' || 'art':
        unawaited(showTaleJournal(context, _ctl, initial: 'Gallery'));
        return;
      case 'ideas' || 'recap' || 'tools' || 'ai':
        unawaited(showAiTools(context, _ctl));
        return;
      case 'export' || 'save':
        showStoryExport(context, _ctl);
        return;
      case 'i' || 'inv' || 'inventory':
        _say(tale.inventory.isEmpty ? 'you carry nothing.' : 'you carry: ${tale.inventory.join(', ')}.');
        return;
      case 'status' || 'hp' || 'stats':
        _say('${g.healthLabel.toLowerCase()} ${tale.health}/100${tale.status.isNotEmpty ? ' · ${tale.status.toLowerCase()}' : ''} · ${tale.turns} turns');
        return;
      case 'look' || 'l':
        final last = tale.log.lastWhere((e) => e.kind == LogKind.narration, orElse: () => LogEntry(kind: LogKind.system, text: 'nothing yet.'));
        _say(last.text);
        return;
      case 'layout' || 'book':
        await _switchLayout();
        return;
    }
    if (t.startsWith('talk ') || t.startsWith('ask ')) {
      final name = raw.substring(raw.indexOf(' ') + 1).trim();
      final who = tale.personNamed(name) ?? tale.npcs.where((n) => n.name.toLowerCase().contains(name.toLowerCase())).firstOrNull;
      // Anyone can be talked to: unknown names join the cast.
      if (!mounted) return;
      unawaited(showCharacterChat(context, _ctl, who ?? _ctl.meet(name)));
      return;
    }
    final n = int.tryParse(t);
    if (n != null) {
      if (n >= 1 && n <= tale.choices.length) {
        await _ctl.choose(tale.choices[n - 1]);
      } else {
        setState(() => _hint = 'pick 1-${tale.choices.length}.');
      }
      return;
    }
    await _ctl.freeText(raw);
  }

  @override
  Widget build(BuildContext context) {
    final t = _ctl.tale;
    final g = _ctl.genre;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => showStoryOverview(context, _ctl), child: Text(t.title, style: T.h3(), overflow: TextOverflow.ellipsis)),
        actions: [
          IconButton(tooltip: 'Map', icon: Badge(isLabelVisible: t.map != null, smallSize: 6, child: const Icon(Icons.map_outlined)), onPressed: () => openMapScreen(context, _ctl)),
          IconButton(tooltip: 'Journal', icon: const Icon(Icons.book_outlined), onPressed: () => showTaleJournal(context, _ctl)),
          IconButton(
            tooltip: 'More',
            icon: const Icon(Icons.more_horiz),
            onPressed: () => showTaleMenu(context, _ctl),
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(29),
          child: Container(
            height: 29,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
            child: Row(children: [
              Text('${g.name.toUpperCase()} · ${g.healthLabel.toLowerCase()} ${t.health}', style: _mono(color: t.health < 30 ? AppColors.danger : AppColors.textMuted, size: 12)),
              const Spacer(),
              Flexible(
                child: Text(
                  t.inventory.isEmpty ? 'empty pockets' : '${t.inventory.length} item${t.inventory.length == 1 ? '' : 's'}',
                  style: _mono(color: AppColors.textFaint, size: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ContentWidth(
          maxWidth: 760,
          child: Column(children: [
            TaleStatusBar(ctl: _ctl, mono: true),
            RecapBanner(host: _ctl, lastPlayed: _lastPlayed),
            Expanded(child: _feed()),
            _actions(),
          ]),
        ),
      ),
    );
  }

  Widget _feed() {
    final t = _ctl.tale;
    final s = context.watch<SettingsController>();
    final g = _ctl.genre;
    final tail = <Widget>[
      for (final e in _echo) Padding(padding: const EdgeInsets.only(top: 8), child: Text('  $e', style: _mono(color: AppColors.info, size: 13))),
      if ((_ctl.streaming ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_ctl.streaming!, style: _mono())),
      if (_ctl.busy && (_ctl.streaming ?? '').isEmpty) ThinkingIndicator(mono: true, first: t.log.isEmpty),
      if (_ctl.error != null)
        InkWell(
          onTap: () => showIssueSheet(context, _ctl.error!, label: 'Story', onRetry: _ctl.isAi ? _ctl.retry : null),
          child: Padding(padding: const EdgeInsets.only(top: 8), child: Text('error: ${describeIssue(_ctl.error!).title.toLowerCase()} — tap for details', style: _mono(color: AppColors.danger, size: 13))),
        ),
      if (t.finished) ...[
        Padding(
          padding: const EdgeInsets.only(top: 18),
          child: Text(
            switch (t.ending) { 'good' => '*** THE END · A GOOD ENDING ***', 'bad' => '*** THE END · YOU DID NOT MAKE IT ***', _ => '*** THE END ***' },
            style: _mono(color: t.ending == 'bad' ? AppColors.danger : g.color),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Wrap(spacing: 8, children: [
            TextButton(
              onPressed: () async {
                final fresh = await restartTale(context, t);
                if (!mounted) return;
                Navigator.of(context).pushReplacement(taleRoute(fresh));
              },
              child: Text('[ play again ]', style: _mono(color: AppColors.accent, size: 13)),
            ),
            TextButton(onPressed: () => showStoryExport(context, _ctl), child: Text('[ export ]', style: _mono(color: AppColors.textMuted, size: 13))),
            TextButton(onPressed: () => Navigator.pop(context), child: Text('[ more stories ]', style: _mono(color: AppColors.textMuted, size: 13))),
          ]),
        ),
      ],
    ];
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
      itemCount: t.log.length + 2,
      itemBuilder: (ctx, i) {
        if (i == 0) return Column(crossAxisAlignment: CrossAxisAlignment.start, children: tail);
        if (i == t.log.length + 1) {
          // Title card, like an old game's boot screen.
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text('${t.title.toUpperCase()}\n${'=' * t.title.length.clamp(4, 36)}\n${g.name} · ${_ctl.isAi ? 'narrated by AI' : 'type help for commands'}', style: _mono(color: g.color, size: 13)),
          );
        }
        final e = t.log[t.log.length - i];
        final id = '${e.at.microsecondsSinceEpoch}';
        switch (e.kind) {
          case LogKind.narration:
            return GestureDetector(
              onLongPress: () => showPassageSheet(context, _ctl, e),
              child: Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 2),
                child: TypewriterText(
                  key: ValueKey(id),
                  text: e.text,
                  animate: s.typewriter && !_animated.contains(id),
                  speed: s.typeSpeed * 3,
                  onDone: () => _animated.add(id),
                  style: _mono(),
                ),
              ),
            );
          case LogKind.player:
            return Padding(padding: const EdgeInsets.only(top: 14), child: Text('> ${e.text}', style: _mono(color: g.color)));
          case LogKind.system when e.meta['scene'] != null:
            final art = t.sceneImages[e.text];
            final sc = e.meta['scene'] is Map ? SceneInfo.fromJson(Map<String, dynamic>.from(e.meta['scene'])) : null;
            return Padding(
              padding: const EdgeInsets.only(top: 22, bottom: 2),
              child: Row(children: [
                Text('== ${e.text.toUpperCase()} ==', style: _mono(color: AppColors.textFaint, size: 12.5)),
                if (art != null && sc != null)
                  TextButton(
                    onPressed: () => openMedia(context, path: art, fallback: SceneView(location: sc.location, time: sc.time, mood: sc.mood, seed: sc.seed), title: e.text),
                    child: Text('[${isVideoPath(art) ? 'play' : 'view'}]', style: _mono(color: g.color, size: 12)),
                  ),
              ]),
            );
          case LogKind.system when e.meta['media'] != null:
            final path = e.meta['media'] as String;
            return InkWell(
              onTap: () => openMedia(context, path: path, fallback: const SizedBox(), title: 'Moment', subtitle: e.text),
              child: Padding(padding: const EdgeInsets.only(top: 6), child: Text('  [${isVideoPath(path) ? 'video' : 'image'}] ${e.text}', style: _mono(color: g.color, size: 12.5))),
            );
          case LogKind.system when e.meta['bond'] != null:
            return Text('  ♥ ${e.text}', style: _mono(color: const Color(0xFFF472B6), size: 12.5));
          case LogKind.dialogue || LogKind.companion:
            final who = t.personNamed(e.speaker);
            return InkWell(
              onTap: who == null ? null : () => showCharacterChat(context, _ctl, who),
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text('${(e.speaker ?? '?').toUpperCase()}: ${e.kind == LogKind.companion ? '"${e.text}"' : e.text}', style: _mono(color: e.kind == LogKind.companion ? AppColors.info : AppColors.text, size: e.kind == LogKind.companion ? 13 : 14)),
              ),
            );
          case LogKind.levelup:
            final quest = questOf(e);
            return InkWell(
              onTap: quest == null ? null : () => showQuestSheet(context, e, onJournal: () => showTaleJournal(context, _ctl)),
              child: Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 2),
                child: Text(quest == null ? '  * ${e.text}' : '  [${quest['state'] == 'done' ? 'x' : quest['state'] == 'failed' ? '-' : ' '}] ${(quest['state'] == 'new' ? 'new goal' : quest['state'] == 'done' ? 'goal complete' : 'goal failed').toUpperCase()}: ${quest['title']}', style: _mono(color: g.color, size: 13)),
              ),
            );
          case LogKind.loot:
            return Text('  + ${e.text}', style: _mono(color: AppColors.success, size: 13));
          case LogKind.combat:
            return Text('  ${e.text}', style: _mono(color: AppColors.danger, size: 13));
          case LogKind.roll:
            final ok = e.meta['ok'] == true;
            return Text('  [risk ${e.meta['chance']}%] ${ok ? 'success' : 'failure'}', style: _mono(color: ok ? AppColors.success : AppColors.warning, size: 13));
          default:
            return Text(e.text, style: _mono(color: AppColors.textFaint, size: 13));
        }
      },
    );
  }

  Widget _actions() {
    final t = _ctl.tale;
    final g = _ctl.genre;
    return Container(
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const NowReading(),
        ChoiceToolbar(host: _ctl, collapsed: _choicesCollapsed, hasChoices: !t.finished && t.choices.isNotEmpty,
          onToggle: () => setState(() => _choicesCollapsed = !_choicesCollapsed)),
        if (!_choicesCollapsed && !_ctl.busy && !t.finished && t.choices.isNotEmpty)
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.3),
            child: SingleChildScrollView(
              child: Column(children: [
                for (final (i, c) in t.choices.indexed)
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _ctl.choose(c),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(
                          width: 22,
                          alignment: Alignment.center,
                          margin: const EdgeInsets.only(right: 10, top: 1),
                          padding: const EdgeInsets.symmetric(vertical: 1),
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(5), border: Border.all(color: AppColors.borderStrong)),
                          child: Text('${i + 1}', style: _mono(color: g.color, size: 12)),
                        ),
                        Expanded(child: Text(c.text, style: _mono(size: 13.5))),
                        if (c.data['risk'] != null) Text(' ${((c.data['risk'] as num) * 100).round()}%', style: _mono(color: AppColors.textFaint, size: 11.5)),
                      ]),
                    ),
                  ),
              ]),
            ),
          ),
        if (_hint != null) Padding(padding: const EdgeInsets.only(top: 6, left: 4), child: Text(_hint!, style: _mono(color: AppColors.textFaint, size: 12))),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.only(left: 12, right: 4),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
          child: Row(children: [
            IconButton(tooltip: 'Story tools', icon: const Icon(Icons.lightbulb_outline, size: 20),
              onPressed: () => showStoryActions(context, _ctl)),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _input,
                focusNode: _focus,
                style: _mono(),
                cursorColor: g.color,
                decoration: InputDecoration(
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  hintText: _ctl.isAi ? 'a number, an action, or help' : 'type a number, look, inv, or help',
                  hintStyle: _mono(color: AppColors.textFaint, size: 13),
                ),
                onSubmitted: (_) => unawaited(_submit()),
              ),
            ),
            IconButton(icon: const Icon(Icons.keyboard_return, size: 18), onPressed: () => unawaited(_submit())),
          ]),
        ),
      ]),
    );
  }
}
