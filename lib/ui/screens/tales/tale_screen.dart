import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../widgets/ai_gate.dart';
import '../../../art/scene_painter.dart';
import '../../../data/tale_genres.dart';
import '../../../game/tale_controller.dart';
import '../../../models/adventure.dart';
import '../../../models/tale.dart';
import '../../../services/audio/audio_service.dart';
import '../../../services/settings.dart';
import '../../../theme/ui.dart';
import '../../../art/render_png.dart';
import '../../widgets/media_view.dart';
import '../../widgets/typewriter.dart';
import '../../widgets/error_card.dart';
import '../../../services/image_service.dart';
import '../adventure/adventure_extras.dart' show ChoiceToolbar;
import '../adventure/log_view.dart';
import '../adventure/map_screen.dart';
import '../../../services/export.dart' show showStoryExport;
import '../story/story_tools.dart';
import '../story/story_extras.dart';
import 'tale_tools.dart';
import 'tales_hub.dart' show taleRoute;
import '../../widgets/voice_input_button.dart';
import '../story/chapter_recap_screen.dart';

/// Reading and playing a text adventure (book layout).
class TaleScreen extends StatefulWidget {
  const TaleScreen({super.key, required this.tale});
  final Tale tale;

  @override
  State<TaleScreen> createState() => _TaleScreenState();
}

class _TaleScreenState extends State<TaleScreen> {
  late final TaleController _ctl;
  late final AudioService _audio;
  late final DateTime _lastPlayed = widget.tale.updatedAt;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final Set<String> _animated = {};
  int _lastLen = 0;
  bool _choicesCollapsed = false;

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
    _lastLen = widget.tale.log.length;
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
    _scroll.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    if (_ctl.tale.log.length != _lastLen || _ctl.streaming != null) {
      _lastLen = _ctl.tale.log.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients && _scroll.offset > 0) _scroll.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      });
    }
    setState(() {});
  }

  TextStyle _reading(SettingsController s, {Color color = AppColors.text}) => T.reading(color: color);

  Future<void> _playAgain() async {
    final fresh = await restartTale(context, _ctl.tale);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(taleRoute(fresh));
  }

  @override
  Widget build(BuildContext context) {
    final t = _ctl.tale;
    final g = _ctl.genre;
    final s = context.watch<SettingsController>();
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => showStoryOverview(context, _ctl),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.title, style: T.h3(), overflow: TextOverflow.ellipsis),
            Row(children: [
              Icon(g.icon, size: 12, color: g.color),
              const SizedBox(width: 4),
              Flexible(child: Text(t.scene.title.isNotEmpty ? t.scene.title : '${g.name}${_ctl.isAi ? ' · AI' : ''}', style: T.caption(color: g.color), overflow: TextOverflow.ellipsis)),
            ]),
          ]),
        ),
        actions: [
          IconButton(tooltip: 'Map', icon: Badge(isLabelVisible: t.map != null, smallSize: 6, child: const Icon(Icons.map_outlined)), onPressed: () => openMapScreen(context, _ctl)),
          IconButton(tooltip: 'Journal', icon: const Icon(Icons.book_outlined), onPressed: () => showTaleJournal(context, _ctl)),
          IconButton(tooltip: 'More', icon: const Icon(Icons.more_horiz), onPressed: () => showTaleMenu(context, _ctl)),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Container(height: 1, color: AppColors.border)),
      ),
      body: SafeArea(
        top: false,
        child: Column(children: [
          ContentWidth(maxWidth: 720, child: TaleStatusBar(ctl: _ctl)),
          ContentWidth(maxWidth: 720, child: RecapBanner(host: _ctl, lastPlayed: _lastPlayed)),
          Expanded(child: ContentWidth(maxWidth: 720, child: _feed(s, g))),
          ContentWidth(maxWidth: 720, child: ApproachBanner(host: _ctl)),
          ContentWidth(maxWidth: 720, child: _bottom(s, g)),
        ]),
      ),
    );
  }

  Widget _cover(TaleGenre g) {
    final t = _ctl.tale;
    final first = t.gallery.where((m) => m.kind == 'scene' && !m.video).firstOrNull?.path;
    final cover = SceneInfo(title: t.title, location: g.scene, time: g.time, mood: 'mystery', seed: t.seed);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20, top: 4),
      child: GestureDetector(
        onTap: () => openMedia(context, path: first, fallback: SceneView(location: g.scene, time: g.time, mood: 'mystery', seed: t.seed, animate: true), title: t.title, subtitle: g.name, render: () => scenePng(cover)),
        child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 160,
          child: Stack(fit: StackFit.expand, children: [
            MediaView(path: first, fallback: SceneView(location: g.scene, time: g.time, mood: 'mystery', seed: t.seed)),
            const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xCC000000)]))),
            Positioned(
              left: 16,
              right: 16,
              bottom: 14,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(g.name.toUpperCase(), style: T.overline(color: g.color)),
                const SizedBox(height: 2),
                Text(t.title, style: T.h2(color: Colors.white)),
                if (t.premise.isNotEmpty) Text(t.premise, maxLines: 2, overflow: TextOverflow.ellipsis, style: T.caption(color: Colors.white70)),
              ]),
            ),
            const Positioned(top: 10, right: 10, child: Icon(Icons.open_in_full, size: 16, color: Colors.white70)),
          ]),
        ),
      ),
      ),
    );
  }

  Widget _feed(SettingsController s, TaleGenre g) {
    final t = _ctl.tale;
    final items = t.log.length + 2;
    final lastScene = t.log.lastIndexWhere((e) => e.meta['scene'] is Map);
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
      itemCount: items,
      itemBuilder: (ctx, i) {
        if (i == 0) {
          if ((_ctl.streaming ?? '').isNotEmpty) return Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text(_ctl.streaming!, style: _reading(s)));
          if (_ctl.busy) return ThinkingIndicator(first: t.log.isEmpty);
          if (_ctl.error != null) return ErrorCard(error: _ctl.error!, label: 'Story', onRetry: _ctl.isAi ? _ctl.retry : null);
          final imgErr = context.watch<ImageService>().errors.entries.where((e) => e.key.contains(t.id)).firstOrNull;
          if (imgErr != null) {
            return ErrorCard(
              error: imgErr.value,
              label: imgErr.value.toLowerCase().contains('video') ? 'Video' : 'Image',
              onRetry: () {
                context.read<ImageService>()
                  ..errors.remove(imgErr.key)
                  ..resume();
                _ctl.generateMissingImages();
              },
              onDismiss: () => setState(() => context.read<ImageService>().errors.remove(imgErr.key)),
            );
          }
          if (t.finished) return _ending(g);
          return const SizedBox(height: 8);
        }
        if (i == items - 1) return _cover(g);
        final idx = t.log.length - i;
        final e = t.log[idx];
        final id = '${e.at.microsecondsSinceEpoch}';
        switch (e.kind) {
          case LogKind.narration:
            final anim = s.typewriter && !_animated.contains(id) && i <= 3;
            return GestureDetector(
              onLongPress: () => showPassageSheet(context, _ctl, e),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  TypewriterText(key: ValueKey(id), text: e.text, animate: anim, speed: s.typeSpeed * 2, onDone: () => _animated.add(id), style: _reading(s)),
                  if (s.costPerMessage && ((e.meta['tok'] ?? 0) > 0 || (e.meta['usd'] ?? 0) > 0)) Padding(padding: const EdgeInsets.only(top: 6), child: CostBadge(tokens: e.meta['tok'] ?? 0, cost: e.meta['usd'] ?? 0)),
                ]),
              ),
            );
          case LogKind.player:
            return Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('›  ', style: T.h3(color: g.color)),
                Expanded(child: Text(e.text, style: T.body(color: g.color).copyWith(fontWeight: FontWeight.w600))),
              ]),
            );
          case LogKind.system when e.meta['scene'] == true:
            return Padding(
              padding: const EdgeInsets.only(top: 22, bottom: 6),
              child: Row(children: [
                Expanded(child: Container(height: 1, color: AppColors.border)),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text(e.text.toUpperCase(), style: T.overline(color: AppColors.textMuted))),
                Expanded(child: Container(height: 1, color: AppColors.border)),
              ]),
            );
          case LogKind.dialogue || LogKind.companion || LogKind.system:
            return LogEntryView(
              entry: e,
              adventure: t,
              latestScene: idx == lastScene,
              animate: e.kind == LogKind.dialogue && s.typewriter && !_animated.contains(id) && i <= 3,
              speed: s.typeSpeed * 2,
              onAnimated: () => _animated.add(id),
              onTalk: (npc) => showCharacterChat(context, _ctl, npc),
              onJournal: () => showTaleJournal(context, _ctl),
              onPassage: (e) => showPassageSheet(context, _ctl, e),
            );
          case LogKind.loot:
            return Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text('+ ${e.text}', style: T.small(color: AppColors.success)));
          case LogKind.combat:
            return Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(e.text, style: T.small(color: AppColors.danger)));
          case LogKind.roll:
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text('${e.text} (${e.meta['chance']}% chance)', style: T.small(color: e.meta['ok'] == true ? AppColors.success : AppColors.warning)),
            );
          case LogKind.levelup when questOf(e) != null:
            return QuestCard(entry: e, onJournal: () => showTaleJournal(context, _ctl));
          case LogKind.levelup:
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Icon(Icons.flag_outlined, size: 15, color: g.color),
                const SizedBox(width: 8),
                Expanded(child: Text(e.text, style: T.small(color: AppColors.text))),
              ]),
            );
          default:
            return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(e.text, style: T.small()));
        }
      },
    );
  }

  Widget _ending(TaleGenre g) {
    final t = _ctl.tale;
    final (label, color, icon) = switch (t.ending) {
      'good' => ('A good ending', AppColors.success, Icons.emoji_events_outlined),
      'bad' => ('A bad ending', AppColors.danger, Icons.heart_broken_outlined),
      _ => ('The end', AppColors.warning, Icons.auto_stories_outlined),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: AppCard(
        borderColor: color.withValues(alpha: 0.5),
        child: Column(children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(height: 8),
          Text(label, style: T.h2()),
          const SizedBox(height: 4),
          Text('${t.turns} choices made${_ctl.preset != null ? ' · ${_ctl.preset!.endings} endings to find' : ''}', style: T.small()),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: AppButton(label: 'Play again', icon: Icons.replay, kind: ButtonKind.secondary, onPressed: _playAgain)),
            const SizedBox(width: 10),
            Expanded(child: AppButton(label: 'Export', icon: Icons.ios_share, kind: ButtonKind.secondary, onPressed: () => showStoryExport(context, _ctl))),
          ]),
          const SizedBox(height: 8),
          AppButton(label: 'What changed', icon: Icons.compare_arrows, kind: ButtonKind.secondary, onPressed: () => openChapterRecap(context, _ctl, ended: true)),
          const SizedBox(height: 8),
          AppButton(label: 'More stories', onPressed: () => Navigator.pop(context)),
        ]),
      ),
    );
  }

  Widget _bottom(SettingsController s, TaleGenre g) {
    final t = _ctl.tale;
    if (t.finished) return const SizedBox.shrink();
    final disabled = _ctl.busy;
    return Container(
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const NowReading(),
        ChoiceToolbar(host: _ctl, collapsed: _choicesCollapsed, hasChoices: t.choices.isNotEmpty,
          onToggle: () => setState(() => _choicesCollapsed = !_choicesCollapsed)),
        if (!disabled && !_choicesCollapsed)
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.34),
            child: SingleChildScrollView(
              child: Column(children: [
                for (final (i, c) in t.choices.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: AppCard(
                      radius: 12,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      onTap: () => _ctl.choose(c),
                      child: Row(children: [
                        Container(
                          width: 24,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(7), border: Border.all(color: g.color.withValues(alpha: 0.6))),
                          child: Text('${i + 1}', style: T.caption(color: g.color)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text(c.text, style: T.body())),
                        if (c.data['risk'] != null) Padding(padding: const EdgeInsets.only(left: 8), child: Tag('${((c.data['risk'] as num) * 100).round()}%', icon: Icons.casino_outlined)),
                      ]),
                    ),
                  ),
              ]),
            ),
          ),
        const SizedBox(height: 4),
        Row(children: [
          CircleIconButton(icon: Icons.lightbulb_outline, size: 44, tooltip: 'Story tools', onPressed: () => showStoryActions(context, _ctl)),
          const SizedBox(width: 8),
          if (_ctl.isAi) ...[
            Expanded(
              child: TextField(
                controller: _input,
                enabled: !disabled,
                style: T.body(),
                textInputAction: TextInputAction.send,
                decoration: InputDecoration(
                  hintText: 'Or write what you do…',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: AppColors.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: AppColors.border)),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            VoiceInputButton(controller: _input, onSubmit: _send, enabled: !disabled),
            if (context.watch<SettingsController>().voiceInput) const SizedBox(width: 8),
            CircleIconButton(icon: Icons.arrow_upward, size: 44, tooltip: 'Send', onPressed: disabled ? null : _send),
          ] else
            Expanded(child: Text('Handcrafted story · tap a choice', style: T.caption())),
        ]),
      ]),
    );
  }

  void _send() {
    final text = _input.text;
    _input.clear();
    unawaited(_ctl.freeText(text));
  }
}
