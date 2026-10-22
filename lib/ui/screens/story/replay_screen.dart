import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../art/scene_painter.dart';
import '../../../game/story_host.dart';
import '../../../models/adventure.dart';
import '../../../services/narrator.dart';
import '../../../theme/ui.dart';
import '../../widgets/media_view.dart';

/// One step of a replay: a place, a passage, a remark or a pictured moment.
class _Beat {
  _Beat({required this.index, required this.text, this.speaker, this.scene, this.media, this.place = ''});
  final int index;
  final String text;
  final String? speaker;
  final SceneInfo? scene;
  final String? media;
  final String place;
  bool get spoken => scene == null && media == null;
}

Future<void> openReplay(BuildContext context, StoryHost host) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReplayScreen(host: host)));

/// Plays a story back like a picture book: scene art behind each passage,
/// read aloud with the saved narration, offline.
class ReplayScreen extends StatefulWidget {
  const ReplayScreen({super.key, required this.host});
  final StoryHost host;

  @override
  State<ReplayScreen> createState() => _ReplayScreenState();
}

class _ReplayScreenState extends State<ReplayScreen> {
  late final List<_Beat> _beats = _build();
  int _i = 0;
  bool _auto = false;
  bool _voice = true;
  Timer? _timer;
  late final Narrator _narrator = context.read<Narrator>();

  List<_Beat> _build() {
    final out = <_Beat>[];
    SceneInfo? scene;
    var place = widget.host.storyTitle;
    final log = widget.host.log;
    for (var i = 0; i < log.length; i++) {
      final e = log[i];
      final raw = e.meta['scene'];
      if (raw is Map) {
        scene = SceneInfo.fromJson(Map<String, dynamic>.from(raw));
        place = e.text;
        out.add(_Beat(index: i, text: e.text, scene: scene, place: place));
      } else if (e.meta['media'] is String) {
        out.add(_Beat(index: i, text: e.text, media: e.meta['media'] as String, place: place));
      } else if (e.kind == LogKind.narration || e.kind == LogKind.dialogue || e.kind == LogKind.companion) {
        out.add(_Beat(index: i, text: e.text, speaker: e.kind == LogKind.narration ? null : e.speaker, place: place));
      } else if (e.kind == LogKind.player) {
        out.add(_Beat(index: i, text: '› ${e.text}', speaker: '\u0000you', place: place));
      }
    }
    return out;
  }

  @override
  void initState() {
    super.initState();
    _narrator.addListener(_onNarrator);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _narrator.removeListener(_onNarrator);
    _narrator.stop();
    super.dispose();
  }

  bool _waiting = false;

  void _onNarrator() {
    // When a passage finishes reading during autoplay, turn the page.
    if (_auto && _waiting && !_narrator.speaking) {
      _waiting = false;
      _timer?.cancel();
      _timer = Timer(const Duration(milliseconds: 700), _next);
    }
  }

  void _show(int i) {
    _timer?.cancel();
    setState(() => _i = i.clamp(0, _beats.length - 1));
    final b = _beats[_i];
    if (_voice && b.spoken && !b.text.startsWith('›')) {
      _waiting = true;
      final clips = widget.host.world.replayAudio['${widget.host.log[b.index].at.millisecondsSinceEpoch}'];
      if (clips != null && clips.isNotEmpty) {
        _narrator.playFiles(clips, label: b.text, speaker: b.speaker);
      } else {
        _narrator.speakNow(b.text, speaker: b.speaker);
      }
    } else {
      _narrator.stop();
      _waiting = false;
      if (_auto) _timer = Timer(Duration(milliseconds: b.spoken ? 1800 + b.text.length * 25 : 3000), _next);
    }
  }

  void _next() {
    if (_i >= _beats.length - 1) {
      setState(() => _auto = false);
      return;
    }
    _show(_i + 1);
  }

  void _toggleAuto() {
    setState(() => _auto = !_auto);
    if (_auto) {
      _show(_i);
    } else {
      _timer?.cancel();
      _narrator.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_beats.isEmpty) {
      return Scaffold(appBar: AppBar(title: const Text('Replay')), body: const EmptyState(icon: Icons.slideshow_outlined, title: 'Nothing to replay yet'));
    }
    final b = _beats[_i];
    // The backdrop is the latest place or moment up to this beat.
    String? art;
    SceneInfo? scene;
    for (var k = _i; k >= 0; k--) {
      final x = _beats[k];
      if (x.media != null && art == null && k == _i) art = x.media;
      if (x.scene != null) {
        scene = x.scene;
        art ??= widget.host.record.sceneImages[x.text];
        break;
      }
    }
    final s = scene ?? widget.host.scene;
    final painted = SceneView(location: s.location, time: s.time, mood: s.mood, seed: s.seed, animate: true);
    final you = b.speaker == '\u0000you';
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onHorizontalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) < -200) _next();
          if ((d.primaryVelocity ?? 0) > 200 && _i > 0) _show(_i - 1);
        },
        child: Stack(fit: StackFit.expand, children: [
          AnimatedSwitcher(duration: const Duration(milliseconds: 600), child: KeyedSubtree(key: ValueKey(art ?? '${s.seed}${s.title}'), child: MediaView(path: art, fallback: painted, fit: BoxFit.cover))),
          const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: [0, 0.35, 1], colors: [Color(0x99000000), Color(0x22000000), Color(0xF2000000)]))),
          SafeArea(
            child: Column(children: [
              Row(children: [
                IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(widget.host.storyTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.h3(color: Colors.white)),
                    Text(b.place, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.caption(color: Colors.white70)),
                  ]),
                ),
                IconButton(
                  tooltip: _voice ? 'Mute narration' : 'Read aloud',
                  icon: Icon(_voice ? Icons.volume_up_outlined : Icons.volume_off_outlined, color: Colors.white),
                  onPressed: () {
                    setState(() => _voice = !_voice);
                    if (!_voice) _narrator.stop();
                  },
                ),
              ]),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  child: ConstrainedBox(
                    key: ValueKey(_i),
                    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.42, maxWidth: 720),
                    child: SingleChildScrollView(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (b.scene != null) ...[
                          Text('NOW', style: T.overline(color: Colors.white60).copyWith(letterSpacing: 3)),
                          const SizedBox(height: 4),
                          Text(b.text, style: T.h1(color: Colors.white).copyWith(fontFamily: 'serif', fontSize: 30)),
                        ] else if (b.media != null) ...[
                          Text(b.text, style: T.reading(color: Colors.white).copyWith(fontStyle: FontStyle.italic)),
                        ] else ...[
                          if (b.speaker != null && !you) Text(b.speaker!, style: T.h3(color: const Color(0xFFE0B354))),
                          Text(b.text, style: you ? T.body(color: const Color(0xFF93C5FD)).copyWith(fontWeight: FontWeight.w600) : T.reading(color: Colors.white)),
                        ],
                      ]),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Slider(value: _i.toDouble(), min: 0, max: (_beats.length - 1).toDouble().clamp(1, double.infinity), onChanged: (v) => setState(() => _i = v.round()), onChangeEnd: (v) => _show(v.round())),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('${_i + 1} / ${_beats.length}', style: T.caption(color: Colors.white60)),
                  const Spacer(),
                  IconButton(iconSize: 30, color: Colors.white, icon: const Icon(Icons.skip_previous_rounded), onPressed: _i > 0 ? () => _show(_i - 1) : null),
                  const SizedBox(width: 6),
                  Material(
                    color: Colors.white,
                    shape: const CircleBorder(),
                    child: IconButton(iconSize: 34, color: Colors.black, icon: Icon(_auto ? Icons.pause_rounded : Icons.play_arrow_rounded), onPressed: _toggleAuto),
                  ),
                  const SizedBox(width: 6),
                  IconButton(iconSize: 30, color: Colors.white, icon: const Icon(Icons.skip_next_rounded), onPressed: _i < _beats.length - 1 ? _next : null),
                  const Spacer(),
                  IconButton(tooltip: 'Read this aloud', color: Colors.white70, icon: const Icon(Icons.replay), onPressed: () => _show(_i)),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
