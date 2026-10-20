import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../services/export.dart';
import '../../services/image_service.dart';
import '../../services/settings.dart';
import '../../services/usage.dart';
import '../../theme/ui.dart';
import 'image_viewer.dart';

bool isVideoPath(String? p) {
  if (p == null) return false;
  final l = p.toLowerCase();
  return l.endsWith('.mp4') || l.endsWith('.webm') || l.endsWith('.mov') || l.endsWith('.m4v');
}

/// An AI image or a looping AI video clip, with the procedural [fallback].
class MediaView extends StatelessWidget {
  const MediaView({super.key, required this.path, required this.fallback, this.fit = BoxFit.cover, this.cacheWidth, this.controls = false});
  final String? path;
  final Widget fallback;
  final BoxFit fit;
  final int? cacheWidth;

  /// Full-screen viewing: sound on, tap to pause.
  final bool controls;

  @override
  Widget build(BuildContext context) {
    final p = path;
    if (isVideoPath(p) && !kIsWeb && File(p!).existsSync()) return VideoClip(path: p, fit: fit, fallback: fallback, controls: controls);
    if (isVideoPath(p)) return fallback;
    return GeneratedImage(path: p, fallback: fallback, fit: fit, cacheWidth: cacheWidth, service: context.read<ImageService>());
  }
}

/// A silent looping clip (with sound and pause in [controls] mode).
class VideoClip extends StatefulWidget {
  const VideoClip({super.key, required this.path, this.fit = BoxFit.cover, required this.fallback, this.controls = false});
  final String path;
  final BoxFit fit;
  final Widget fallback;
  final bool controls;

  @override
  State<VideoClip> createState() => _VideoClipState();
}

class _VideoClipState extends State<VideoClip> {
  VideoPlayerController? _c;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void didUpdateWidget(VideoClip old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      _c?.dispose();
      _c = null;
      _open();
    }
  }

  Future<void> _open() async {
    final c = VideoPlayerController.file(File(widget.path));
    try {
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(widget.controls ? 1 : 0);
      if (!mounted) {
        await c.dispose();
        return;
      }
      if (!MediaQuery.of(context).disableAnimations || widget.controls) await c.play();
      setState(() => _c = c);
    } catch (_) {
      await c.dispose();
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (_failed) return widget.fallback;
    if (c == null || !c.value.isInitialized) return Stack(fit: StackFit.expand, children: [widget.fallback, const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70)))]);
    final video = FittedBox(fit: widget.fit, clipBehavior: Clip.hardEdge, child: SizedBox(width: c.value.size.width, height: c.value.size.height, child: VideoPlayer(c)));
    if (!widget.controls) return video;
    return GestureDetector(
      onTap: () => setState(() => c.value.isPlaying ? c.pause() : c.play()),
      child: Stack(fit: StackFit.expand, children: [
        video,
        if (!c.value.isPlaying) const Center(child: Icon(Icons.play_circle_outline, size: 64, color: Colors.white70)),
        Positioned(left: 0, right: 0, bottom: 0, child: VideoProgressIndicator(c, allowScrubbing: true, colors: const VideoProgressColors(playedColor: AppColors.accent))),
      ]),
    );
  }
}

/// A small "1.2K tok · $0.004" pill.
class CostBadge extends StatelessWidget {
  const CostBadge({super.key, this.tokens = 0, required this.cost, this.onImage = false});
  final num tokens;
  final num cost;
  final bool onImage;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: onImage ? Colors.black54 : AppColors.surface2, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.toll_outlined, size: 11, color: onImage ? Colors.white70 : AppColors.textFaint),
        const SizedBox(width: 4),
        Text(itemCostLabel(tokens, cost), style: T.caption(color: onImage ? Colors.white70 : AppColors.textFaint).copyWith(fontSize: 10.5)),
      ]),
    );
  }
}

/// Save to gallery and share buttons for the viewer's app bar.
List<Widget> mediaActions(BuildContext context, String? path, {bool video = false, String name = 'image', Future<Uint8List?> Function()? render}) {
  final images = context.read<ImageService>();
  final file = name.replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '').trim().replaceAll(' ', '_');
  if (path == null || path.isEmpty) {
    // Drawn on device: render a full-size PNG when asked.
    if (render == null) return const [];
    return [
      IconButton(
        tooltip: 'Save to device',
        icon: const Icon(Icons.download_outlined, color: Colors.white),
        onPressed: () async {
          final bytes = await render();
          if (bytes == null) return;
          final err = await images.saveBytesToDevice(bytes);
          if (context.mounted) showToast(context, err ?? 'Saved to your gallery', icon: err == null ? Icons.check_circle_outline : Icons.error_outline);
        },
      ),
      IconButton(
        tooltip: 'Share',
        icon: const Icon(Icons.ios_share, color: Colors.white),
        onPressed: () async {
          final bytes = await render();
          if (bytes == null || !context.mounted) return;
          await deliverFile(context, name: '${file.isEmpty ? 'art' : file}.png', bytes: bytes, mime: 'image/png');
        },
      ),
    ];
  }
  return [
    IconButton(
      tooltip: 'Save to device',
      icon: const Icon(Icons.download_outlined, color: Colors.white),
      onPressed: () async {
        final err = await images.saveToDevice(path, video: video || isVideoPath(path));
        if (context.mounted) showToast(context, err ?? 'Saved to your gallery', icon: err == null ? Icons.check_circle_outline : Icons.error_outline);
      },
    ),
    IconButton(
      tooltip: 'Share',
      icon: const Icon(Icons.ios_share, color: Colors.white),
      onPressed: () async {
        final bytes = await images.bytesOf(path);
        if (bytes == null || !context.mounted) return;
        final v = video || isVideoPath(path);
        await deliverFile(context, name: '${name.replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '').trim().replaceAll(' ', '_')}.${v ? 'mp4' : 'png'}', bytes: bytes, mime: v ? 'video/mp4' : 'image/png');
      },
    ),
  ];
}

/// Full-screen view of a generated image or video with save and share.
Future<void> openMedia(BuildContext context, {required String? path, required Widget fallback, required String title, String? subtitle, double aspectRatio = 16 / 9, Future<Uint8List?> Function()? render}) {
  return openImageViewer(
    context,
    title: title,
    subtitle: subtitle,
    aspectRatio: aspectRatio,
    actions: mediaActions(context, path, name: title, render: render),
    builder: (_) => MediaView(path: path, fallback: fallback, fit: BoxFit.contain, controls: true),
  );
}

/// Whether per-item cost labels are on for this kind of media.
bool showItemCost(BuildContext context, {bool video = false, bool message = false}) {
  final s = context.watch<SettingsController>();
  return message ? s.costPerMessage : (video ? s.costPerVideo : s.costPerImage);
}
