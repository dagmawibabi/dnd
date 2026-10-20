import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../art/map_painter.dart';
import '../../../art/render_png.dart';
import '../../../game/story_host.dart';
import '../../../models/adventure.dart';
import '../../../services/image_service.dart';
import '../../../services/settings.dart';
import '../../../theme/ui.dart';

void openMapScreen(BuildContext context, StoryHost ctl) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => MapScreen(ctl: ctl)));
}

/// Compact animated preview used in side panels.
class MapPreview extends StatefulWidget {
  const MapPreview({super.key, required this.map});
  final MapState map;

  @override
  State<MapPreview> createState() => _MapPreviewState();
}

class _MapPreviewState extends State<MapPreview> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.map.aiImagePath != null) {
      return GeneratedImage(path: widget.map.aiImagePath, fallback: const SizedBox(), service: context.read<ImageService>());
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(fit: StackFit.expand, children: [
        RepaintBoundary(child: CustomPaint(painter: MapBasePainter(state: widget.map))),
        AnimatedBuilder(animation: _pulse, builder: (_, _) => CustomPaint(painter: MapMarkerPainter(state: widget.map, pulse: _pulse.value, showLabels: false))),
      ]),
    );
  }
}

/// Full-screen, zoomable map with tappable locations.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key, required this.ctl});
  final StoryHost ctl;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();
  final _tx = TransformationController();
  int? _selected;
  bool _labels = true;
  bool _showAi = true;
  Size _canvas = Size.zero;
  Size _viewport = Size.zero;
  bool _fitted = false;

  StoryHost get ctl => widget.ctl;

  @override
  void initState() {
    super.initState();
    ctl.addListener(_refresh);
  }

  @override
  void dispose() {
    ctl.removeListener(_refresh);
    _pulse.dispose();
    _tx.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  double get _scale => _tx.value.getMaxScaleOnAxis();

  void _fit() {
    final s = math.min(_viewport.width / _canvas.width, _viewport.height / _canvas.height);
    final dx = (_viewport.width - _canvas.width * s) / 2;
    final dy = (_viewport.height - _canvas.height * s) / 2;
    _tx.value = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(s, s, 1, 1);
  }

  void _focus(Offset p, {double? zoom}) {
    final s = zoom ?? math.max(_scale, 1.2 * math.min(_viewport.width / _canvas.width, _viewport.height / _canvas.height) * 1.6);
    _tx.value = Matrix4.identity()
      ..translateByDouble(_viewport.width / 2 - p.dx * s, _viewport.height / 2 - p.dy * s, 0, 1)
      ..scaleByDouble(s, s, 1, 1);
  }

  void _zoom(double f) {
    final center = _tx.toScene(Offset(_viewport.width / 2, _viewport.height / 2));
    _focus(center, zoom: (_scale * f).clamp(0.2, 6));
  }

  void _onTap(Offset local, MapState m) {
    final pts = MapMarkerPainter.positions(m, _canvas);
    final gm = GeneratedMap.of(m);
    var best = -1;
    var bestD = 30 / _scale;
    for (var i = 0; i < math.min(pts.length, m.locations.length); i++) {
      final known = gm.kind != MapKind.dungeon || i <= m.current + 1 || m.locations[i].visited;
      if (!known) continue;
      final d = (pts[i] - local).distance;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    setState(() => _selected = best < 0 ? null : best);
  }

  @override
  Widget build(BuildContext context) {
    final m = ctl.map;
    if (m == null) {
      return Scaffold(appBar: AppBar(title: const Text('Map')), body: const EmptyState(icon: Icons.map_outlined, title: 'No map yet', message: 'Explore to reveal the land around you.'));
    }
    final images = context.watch<ImageService>();
    final settings = context.watch<SettingsController>();
    final aiPath = m.aiImagePath;
    final useAi = aiPath != null && _showAi;
    final aspect = m.kind == MapKind.dungeon ? 1.5 : (m.kind == MapKind.town ? 40 / 28 : 1.45);
    _canvas = Size(1400, 1400 / aspect);
    final kind = m.kind;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(m.name, style: T.h3(), overflow: TextOverflow.ellipsis),
          Text('${kind == MapKind.overworld ? 'Region' : (kind == MapKind.dungeon ? 'Dungeon' : 'Town')} · ${m.locations.length} locations', style: T.caption()),
        ]),
        actions: [
          IconButton(tooltip: _labels ? 'Hide labels' : 'Show labels', icon: Icon(_labels ? Icons.label_outline : Icons.label_off_outlined), onPressed: () => setState(() => _labels = !_labels)),
          IconButton(
            tooltip: 'Save map to device',
            icon: const Icon(Icons.download_outlined),
            onPressed: () async {
              final err = useAi ? await images.saveToDevice(aiPath) : await (() async {
                final png = await mapPng(m);
                return png == null ? 'Could not draw the map.' : await images.saveBytesToDevice(png);
              })();
              if (context.mounted) showToast(context, err ?? 'Map saved to your gallery', icon: err == null ? Icons.check_circle_outline : Icons.error_outline);
            },
          ),
          if (aiPath != null) IconButton(tooltip: 'Toggle AI image', icon: Icon(_showAi ? Icons.image_outlined : Icons.draw_outlined), onPressed: () => setState(() => _showAi = !_showAi)),
          if (settings.useAiImages)
            IconButton(
              tooltip: 'Generate AI map',
              onPressed: images.isBusy('map_${ctl.storyId}') ? null : ctl.generateMapImage,
              icon: images.isBusy('map_${ctl.storyId}') ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome_outlined),
            ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Container(height: 1, color: AppColors.border)),
      ),
      body: LayoutBuilder(builder: (ctx, box) {
        _viewport = Size(box.maxWidth, box.maxHeight);
        if (!_fitted) {
          _fitted = true;
          WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
        }
        return Stack(children: [
          Positioned.fill(child: Container(color: const Color(0xFF070708))),
          Semantics(
            label: 'Map of ${m.name}. You are at ${m.locations.isEmpty ? 'an unknown place' : m.locations[m.current.clamp(0, m.locations.length - 1)].name}. Locations: ${m.locations.map((l) => '${l.name}${l.visited ? ', visited' : ''}').join('; ')}.',
            child: InteractiveViewer(
            transformationController: _tx,
            constrained: false,
            minScale: 0.2,
            maxScale: 6,
            boundaryMargin: const EdgeInsets.all(600),
            child: GestureDetector(
              onTapUp: (d) => _onTap(d.localPosition, m),
              child: SizedBox(
                width: _canvas.width,
                height: _canvas.height,
                child: Stack(fit: StackFit.expand, children: [
                  if (useAi)
                    GeneratedImage(path: aiPath, fallback: const SizedBox(), service: images)
                  else
                    RepaintBoundary(child: CustomPaint(painter: MapBasePainter(state: m))),
                  AnimatedBuilder(
                    // Pan and zoom repaint only the markers, never the whole screen.
                    animation: Listenable.merge([_pulse, _tx]),
                    builder: (_, _) => RepaintBoundary(child: CustomPaint(painter: MapMarkerPainter(state: m, pulse: _pulse.value, selected: _selected, showLabels: _labels, scale: _scale))),
                  ),
                ]),
              ),
            ),
          ),
          ),
          Positioned(
            right: 12,
            top: 12,
            child: Column(children: [
              CircleIconButton(icon: Icons.add, tooltip: 'Zoom in', onPressed: () => _zoom(1.4)),
              const SizedBox(height: 8),
              CircleIconButton(icon: Icons.remove, tooltip: 'Zoom out', onPressed: () => _zoom(1 / 1.4)),
              const SizedBox(height: 8),
              CircleIconButton(icon: Icons.fit_screen_outlined, tooltip: 'Fit', onPressed: _fit),
              const SizedBox(height: 8),
              CircleIconButton(
                icon: Icons.my_location,
                tooltip: 'Current location',
                onPressed: () {
                  final pts = MapMarkerPainter.positions(m, _canvas);
                  if (m.current < pts.length) {
                    _focus(pts[m.current]);
                    setState(() => _selected = m.current);
                  }
                },
              ),
            ]),
          ),
          Positioned(left: 12, top: 12, child: _Legend(map: m)),
          if (_selected != null && _selected! < m.locations.length)
            Positioned(left: 12, right: 12, bottom: 12, child: SafeArea(top: false, child: ContentWidth(maxWidth: 520, child: _locationCard(m, _selected!)))),
        ]);
      }),
    );
  }

  Widget _locationCard(MapState m, int i) {
    final loc = m.locations[i];
    final kind = locationKind(loc.name, map: m.kind);
    final current = i == m.current;
    final visited = loc.visited || i < m.current;
    final canTravel = !current && ctl.canTravelTo(loc);
    return AppCard(
      color: AppColors.surface,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: current ? AppColors.accentSoft : AppColors.surface2, borderRadius: BorderRadius.circular(12)),
            child: Icon(locIcon(kind), color: current ? AppColors.accent : AppColors.text, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(loc.name, style: T.h3()),
              Text('${locKindLabel(kind)} · stop ${i + 1} of ${m.locations.length}', style: T.caption()),
            ]),
          ),
          IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _selected = null)),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          if (current) const Tag('You are here', color: AppColors.accent, filled: true),
          if (!current && visited) const Tag('Visited', icon: Icons.check),
          if (!current && !visited) const Tag('Unexplored'),
          if (i == m.current + 1) const Tag('Next stop', color: AppColors.success, filled: true),
        ]),
        if (canTravel) ...[
          const SizedBox(height: 12),
          AppButton(
            label: 'Travel here',
            icon: Icons.directions_walk,
            height: 42,
            onPressed: () {
              Navigator.pop(context);
              ctl.travelTo(loc);
            },
          ),
        ] else if (!current && !ctl.isAi && !visited) ...[
          const SizedBox(height: 10),
          Text("You can't travel there from here yet. Follow the story to reach it.", style: T.caption()),
        ],
      ]),
    );
  }
}

class _Legend extends StatefulWidget {
  const _Legend({required this.map});
  final MapState map;

  @override
  State<_Legend> createState() => _LegendState();
}

class _LegendState extends State<_Legend> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final kinds = widget.map.locations.map((l) => locationKind(l.name, map: widget.map.kind)).toSet().toList();
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      alignment: Alignment.topLeft,
      child: Container(
        decoration: BoxDecoration(color: AppColors.surface.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
        child: _open
            ? Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('Legend', style: T.small(color: AppColors.text)),
                    const SizedBox(width: 24),
                    GestureDetector(onTap: () => setState(() => _open = false), child: const Icon(Icons.close, size: 16)),
                  ]),
                  const SizedBox(height: 6),
                  _row(Container(width: 12, height: 12, decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle)), 'You are here'),
                  _row(Container(width: 12, height: 12, decoration: const BoxDecoration(color: Color(0xFF3F3F46), shape: BoxShape.circle)), 'Visited'),
                  _row(Container(width: 12, height: 12, decoration: const BoxDecoration(color: AppColors.text, shape: BoxShape.circle)), 'Not yet visited'),
                  _row(Container(width: 16, height: 2, color: AppColors.accent), 'Route travelled'),
                  for (final k in kinds) _row(Icon(locIcon(k), size: 14, color: AppColors.textMuted), locKindLabel(k)),
                ]),
              )
            : InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => _open = true),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.info_outline, size: 16), const SizedBox(width: 6), Text('Legend', style: T.small(color: AppColors.text))]),
                ),
              ),
      ),
    );
  }

  Widget _row(Widget leading, String label) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(mainAxisSize: MainAxisSize.min, children: [SizedBox(width: 18, child: Center(child: leading)), const SizedBox(width: 8), Text(label, style: T.caption(color: AppColors.textMuted))]),
      );
}
