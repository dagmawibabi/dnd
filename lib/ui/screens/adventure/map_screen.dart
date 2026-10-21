import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../art/map_painter.dart';
import '../../../art/render_png.dart';
import '../../../game/story_host.dart';
import '../../../models/adventure.dart';
import '../../../services/image_service.dart';
import '../../../models/world.dart' show MediaItem;
import '../../../services/settings.dart';
import '../../../services/studio.dart';
import '../../../theme/ui.dart';
import '../../widgets/media_import.dart';
import '../../widgets/portrait.dart';

void openMapScreen(BuildContext context, StoryHost ctl) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => MapScreen(ctl: ctl)));
}

/// Icons and colours a player can give their own pins.
const pinIcons = [Icons.push_pin, Icons.star, Icons.flag, Icons.warning_amber, Icons.diamond_outlined, Icons.home_outlined, Icons.help_outline, Icons.dangerous_outlined, Icons.local_dining_outlined, Icons.auto_awesome];
const pinColors = [Color(0xFF8B7CF6), Color(0xFFFBBF24), Color(0xFF4ADE80), Color(0xFFF87171), Color(0xFF60A5FA), Color(0xFFF472B6)];

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
    final picture = widget.map.aiImagePath ?? context.watch<StudioStore?>()?.mapImageFor(widget.map.kind.name, widget.map.seed);
    if (picture != null) {
      return GeneratedImage(path: picture, fallback: const SizedBox(), service: context.read<ImageService>());
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

/// What the story knows about one place on the map.
class PlaceInfo {
  PlaceInfo(StoryHost host, MapLocation loc) : name = loc.name {
    final key = loc.name.trim().toLowerCase();
    bool same(String s) => s.trim().toLowerCase() == key;
    final w = host.world.chronicle;
    facts = [for (final f in w.facts) if (same(f.name)) f.state.isEmpty ? '' : '${f.state}${f.reputation != 0 ? ' · reputation ${f.reputation > 0 ? '+' : ''}${f.reputation}' : ''}'].where((s) => s.isNotEmpty).toList();
    history = [for (final h in w.history.reversed) if (same(h.name)) '${h.before.isEmpty ? '' : '${h.before} → '}${h.after}  ·  ${h.reason}'].take(3).toList();
    canon = [for (final c in host.canon) if (same(c.name) || (key.length > 3 && c.text.toLowerCase().contains(key))) '${c.name}: ${c.text}'].take(3).toList();
    people = [for (final p in host.people) if (key.length > 3 && '${p.role} ${p.description} ${p.notes}'.toLowerCase().contains(key)) p].take(5).toList();
    final said = [for (final e in host.log) if ((e.kind == LogKind.narration || e.kind == LogKind.dialogue) && key.length > 3 && e.text.toLowerCase().contains(key)) e.text];
    mentions = said.length;
    lastMention = said.isEmpty ? '' : said.last;
  }
  final String name;
  late final List<String> facts, history, canon;
  late final List<Npc> people;
  late final int mentions;
  late final String lastMention;

  bool get remembered => facts.isNotEmpty || history.isNotEmpty || canon.isNotEmpty;
}

/// Full-screen, zoomable map with tappable locations, your own pins and notes,
/// a ruler, layers, and everything the story remembers about each place.
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
  String? _pin;
  bool _labels = true;
  bool _showAi = true;
  bool _showPins = true;
  bool _showMemory = true;
  bool _showRoute = true;
  bool _fog = false;
  bool _measure = false;
  Offset? _ma, _mb;
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

  void _changed() {
    ctl.refresh();
    ctl.save();
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

  bool _known(MapState m, GeneratedMap gm, int i) => gm.kind != MapKind.dungeon || i <= m.current + 1 || m.locations[i].visited;
  bool _visited(MapState m, int i) => m.locations[i].visited || i <= m.current;

  void _selectLocation(MapState m, int i, {bool focus = false}) {
    setState(() {
      _selected = i;
      _pin = null;
    });
    if (focus) {
      final pts = MapMarkerPainter.positions(m, _canvas);
      if (i < pts.length) _focus(pts[i]);
    }
  }

  void _onTap(Offset local, MapState m) {
    if (_measure) {
      setState(() {
        if (_ma == null || _mb != null) {
          _ma = local;
          _mb = null;
        } else {
          _mb = local;
        }
      });
      return;
    }
    final reach = 30 / _scale;
    if (_showPins) {
      for (final p in m.pins.reversed) {
        if ((Offset(p.x * _canvas.width, p.y * _canvas.height) - local).distance < reach) {
          setState(() {
            _pin = p.id;
            _selected = null;
          });
          return;
        }
      }
    }
    final pts = MapMarkerPainter.positions(m, _canvas);
    final gm = GeneratedMap.of(m);
    var best = -1;
    var bestD = reach;
    for (var i = 0; i < math.min(pts.length, m.locations.length); i++) {
      if (!_known(m, gm, i)) continue;
      final d = (pts[i] - local).distance;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    setState(() {
      _selected = best < 0 ? null : best;
      _pin = null;
    });
  }

  Future<void> _addPin(Offset local, MapState m) async {
    if (_measure) return;
    final pin = MapPin(x: (local.dx / _canvas.width).clamp(0, 1), y: (local.dy / _canvas.height).clamp(0, 1));
    final saved = await showPinEditor(context, pin, isNew: true);
    if (saved == null || !mounted) return;
    m.pins.add(saved);
    _changed();
    setState(() {
      _pin = saved.id;
      _selected = null;
      _showPins = true;
    });
  }

  /// Distance between the two ruler points in story terms.
  String _distance(MapState m, double d) {
    final gm = GeneratedMap.of(m);
    switch (m.kind) {
      case MapKind.overworld:
        final days = d / kMapDayLength;
        return days < 1 ? '${(days * 8).round().clamp(1, 8)} hours on foot' : '${days.toStringAsFixed(days < 3 ? 1 : 0)} days on foot · ${(days * 24).round()} miles';
      case MapKind.town:
        final mins = d / _canvas.width * 25;
        return '${mins.round().clamp(1, 999)} min walk';
      case MapKind.dungeon:
        final feet = d / (_canvas.width / gm.cols) * 5;
        return '${(feet / 5).round() * 5} ft';
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = ctl.map;
    if (m == null) {
      return Scaffold(appBar: AppBar(title: const Text('Map')), body: const EmptyState(icon: Icons.map_outlined, title: 'No map yet', message: 'Explore to reveal the land around you.'));
    }
    final images = context.watch<ImageService>();
    final settings = context.watch<SettingsController>();
    // AI art or the player's own picture for this map, else the drawn map.
    final aiPath = m.aiImagePath ?? context.watch<StudioStore?>()?.mapImageFor(m.kind.name, m.seed);
    final useAi = aiPath != null && _showAi;
    final aspect = m.kind == MapKind.dungeon ? 1.5 : (m.kind == MapKind.town ? 40 / 28 : 1.45);
    _canvas = Size(1400, 1400 / aspect);
    final kind = m.kind;
    final gm = GeneratedMap.of(m);
    final explored = [for (var i = 0; i < m.locations.length; i++) if (_visited(m, i)) i].length;
    final remembered = <int>{
      if (_showMemory)
        for (var i = 0; i < m.locations.length; i++)
          if (_known(m, gm, i) && PlaceInfo(ctl, m.locations[i]).remembered) i,
    };
    final noted = <int>{for (var i = 0; i < m.locations.length; i++) if (m.locations[i].note.isNotEmpty) i};
    final pin = m.pins.where((p) => p.id == _pin).firstOrNull;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(m.name, style: T.h3(), overflow: TextOverflow.ellipsis),
          Text('${kind == MapKind.overworld ? 'Region' : (kind == MapKind.dungeon ? 'Dungeon' : 'Town')} · $explored of ${m.locations.length} explored${m.pins.isEmpty ? '' : ' · ${m.pins.length} pins'}', style: T.caption()),
        ]),
        actions: [
          IconButton(tooltip: 'Places', icon: const Icon(Icons.list_alt), onPressed: () => _showPlaces(m)),
          IconButton(tooltip: 'Layers', icon: const Icon(Icons.layers_outlined), onPressed: () => _showLayers(aiPath != null)),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (v) async {
              switch (v) {
                case 'save':
                  final err = useAi ? await images.saveToDevice(aiPath) : await (() async {
                    final png = await mapPng(m);
                    return png == null ? 'Could not draw the map.' : await images.saveBytesToDevice(png);
                  })();
                  if (context.mounted) showToast(context, err ?? 'Map saved to your gallery', icon: err == null ? Icons.check_circle_outline : Icons.error_outline);
                case 'ai':
                  ctl.generateMapImage();
                case 'own':
                  final picked = await chooseImages(context, title: 'A picture for this map');
                  if (picked.isEmpty) return;
                  m.aiImagePath = picked.first.path;
                  ctl.world.addMedia(MediaItem(path: picked.first.path, kind: 'map', caption: m.name, turn: ctl.turns));
                  _changed();
                  setState(() => _showAi = true);
                case 'drawn':
                  m.aiImagePath = null;
                  _changed();
                case 'clear':
                  if (await confirm(context, title: 'Remove all pins?', message: 'Your ${m.pins.length} pins on this map will be removed.', action: 'Remove')) {
                    m.pins.clear();
                    _changed();
                    setState(() => _pin = null);
                  }
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'save', child: ListTile(leading: Icon(Icons.download_outlined), title: Text('Save map to device'))),
              const PopupMenuItem(value: 'own', child: ListTile(leading: Icon(Icons.add_photo_alternate_outlined), title: Text('Use my own picture'))),
              if (m.aiImagePath != null) const PopupMenuItem(value: 'drawn', child: ListTile(leading: Icon(Icons.draw_outlined), title: Text('Go back to the drawn map'))),
              if (settings.useAiImages)
                PopupMenuItem(value: 'ai', enabled: !images.isBusy('map_${ctl.storyId}'), child: const ListTile(leading: Icon(Icons.auto_awesome_outlined), title: Text('Paint an AI map'))),
              if (m.pins.isNotEmpty) const PopupMenuItem(value: 'clear', child: ListTile(leading: Icon(Icons.wrong_location_outlined), title: Text('Remove all pins'))),
            ],
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: LinearProgressIndicator(value: m.locations.isEmpty ? 0 : explored / m.locations.length, minHeight: 3, color: AppColors.accent, backgroundColor: AppColors.border),
        ),
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
                onLongPressStart: (d) => _addPin(d.localPosition, m),
                child: SizedBox(
                  width: _canvas.width,
                  height: _canvas.height,
                  child: Stack(fit: StackFit.expand, children: [
                    if (useAi)
                      GeneratedImage(path: aiPath, fallback: const SizedBox(), service: images)
                    else
                      RepaintBoundary(child: CustomPaint(painter: MapBasePainter(state: m))),
                    if (_fog && kind != MapKind.dungeon) RepaintBoundary(child: CustomPaint(painter: _FogPainter(state: m))),
                    AnimatedBuilder(
                      // Pan and zoom repaint only the markers, never the whole screen.
                      animation: Listenable.merge([_pulse, _tx]),
                      builder: (_, _) => RepaintBoundary(
                        child: CustomPaint(
                          painter: MapMarkerPainter(state: m, pulse: _pulse.value, selected: _selected, showLabels: _labels, scale: _scale),
                          foregroundPainter: _OverlayPainter(
                            state: m,
                            scale: _scale,
                            pins: _showPins ? m.pins : const [],
                            selectedPin: _pin,
                            labels: _labels,
                            remembered: remembered,
                            noted: noted,
                            route: _showRoute ? _selected : null,
                            measureA: _measure ? _ma : null,
                            measureB: _measure ? _mb : null,
                            measureLabel: _measure && _ma != null && _mb != null ? _distance(m, (_mb! - _ma!).distance) : null,
                          ),
                        ),
                      ),
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
                  if (m.current < m.locations.length) _selectLocation(m, m.current, focus: true);
                },
              ),
              const SizedBox(height: 8),
              CircleIconButton(
                icon: Icons.straighten,
                tooltip: _measure ? 'Stop measuring' : 'Measure distance',
                color: _measure ? AppColors.accent : null,
                onPressed: () => setState(() {
                  _measure = !_measure;
                  _ma = _mb = null;
                  if (_measure) {
                    _selected = null;
                    _pin = null;
                  }
                }),
              ),
            ]),
          ),
          Positioned(left: 12, top: 12, child: _Legend(map: m, memory: _showMemory, pins: _showPins && m.pins.isNotEmpty)),
          if (_measure)
            Positioned(
              left: 12,
              right: 72,
              bottom: 12,
              child: SafeArea(
                top: false,
                child: Center(
                  child: _Hint(
                    icon: Icons.straighten,
                    text: _ma == null ? 'Tap two points to measure' : (_mb == null ? 'Tap the second point' : _distance(m, (_mb! - _ma!).distance)),
                  ),
                ),
              ),
            )
          else if (pin != null)
            Positioned(left: 12, right: 12, bottom: 12, child: SafeArea(top: false, child: ContentWidth(maxWidth: 520, child: _pinCard(m, pin))))
          else if (_selected != null && _selected! < m.locations.length)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: SafeArea(
                top: false,
                child: ContentWidth(
                  maxWidth: 520,
                  child: ConstrainedBox(constraints: BoxConstraints(maxHeight: box.maxHeight * 0.58), child: _locationCard(m, _selected!)),
                ),
              ),
            )
          else if (m.pins.isEmpty)
            const Positioned(left: 12, right: 72, bottom: 12, child: SafeArea(top: false, child: Center(child: _Hint(icon: Icons.touch_app_outlined, text: 'Tap a place to learn about it · long-press to drop a pin')))),
        ]);
      }),
    );
  }

  // ------------------------------------------------------------- cards

  Widget _locationCard(MapState m, int i) {
    final loc = m.locations[i];
    final kind = locationKind(loc.name, map: m.kind);
    final current = i == m.current;
    final visited = _visited(m, i) && !current;
    final canTravel = !current && ctl.canTravelTo(loc);
    final info = PlaceInfo(ctl, loc);
    final stops = (i - m.current).abs();
    Widget section(IconData icon, String title, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(icon, size: 14, color: AppColors.textMuted), const SizedBox(width: 6), Text(title.toUpperCase(), style: T.overline())]),
            const SizedBox(height: 6),
            ...children,
          ]),
        );
    return AppCard(
      color: AppColors.surface,
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
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
                Text('${locKindLabel(kind)} · stop ${i + 1} of ${m.locations.length}${current ? '' : ' · $stops ${stops == 1 ? 'stop' : 'stops'} ${i > m.current ? 'ahead' : 'back'}'}', style: T.caption()),
              ]),
            ),
            IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _selected = null)),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            if (current) const Tag('You are here', color: AppColors.accent, filled: true),
            if (visited) const Tag('Visited', icon: Icons.check),
            if (!current && !visited) const Tag('Unexplored'),
            if (i == m.current + 1) const Tag('Next stop', color: AppColors.success, filled: true),
            if (info.mentions > 0) Tag('${info.mentions} ${info.mentions == 1 ? 'mention' : 'mentions'}', icon: Icons.menu_book_outlined),
            if (info.remembered) const Tag('Remembered', icon: Icons.public, color: AppColors.warning),
          ]),
          if (info.facts.isNotEmpty || info.history.isNotEmpty)
            section(Icons.public, 'The world remembers', [
              for (final f in info.facts) Text(f, style: T.body()),
              for (final h in info.history) Padding(padding: const EdgeInsets.only(top: 4), child: Text(h, style: T.small())),
            ]),
          if (info.canon.isNotEmpty)
            section(Icons.psychology_alt_outlined, 'Known facts', [
              for (final c in info.canon) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(c, style: T.small(color: AppColors.text))),
            ]),
          if (info.people.isNotEmpty)
            section(Icons.people_outline, 'People connected', [
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final p in info.people)
                  Row(mainAxisSize: MainAxisSize.min, children: [NpcPortrait(npc: p, size: 26), const SizedBox(width: 6), Text(p.name, style: T.small(color: AppColors.text))]),
              ]),
            ]),
          if (info.lastMention.isNotEmpty)
            section(Icons.format_quote, 'Last in the story', [
              Text(info.lastMention, style: T.small(), maxLines: 4, overflow: TextOverflow.ellipsis),
            ]),
          section(Icons.edit_note, 'Your note', [
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _editNote(loc),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
                child: Text(loc.note.isEmpty ? 'Add a note about ${loc.name}…' : loc.note, style: T.small(color: loc.note.isEmpty ? AppColors.textFaint : AppColors.text)),
              ),
            ),
          ]),
          if (!info.remembered && info.mentions == 0 && !visited && !current)
            Padding(padding: const EdgeInsets.only(top: 12), child: Text('Nothing is known about this place yet. Explore it to fill in the map.', style: T.caption())),
          if (canTravel) ...[
            const SizedBox(height: 14),
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
      ),
    );
  }

  Widget _pinCard(MapState m, MapPin p) {
    final color = pinColors[p.color % pinColors.length];
    return AppCard(
      color: AppColors.surface,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12)),
            child: Icon(pinIcons[p.icon % pinIcons.length], color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.label.isEmpty ? 'Pin' : p.label, style: T.h3()),
              Text('Your pin', style: T.caption()),
            ]),
          ),
          IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () async {
            final saved = await showPinEditor(context, p);
            if (saved == null) return;
            if (saved.label == '\u0000') {
              m.pins.removeWhere((x) => x.id == p.id);
              setState(() => _pin = null);
            }
            _changed();
          }),
          IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _pin = null)),
        ]),
        if (p.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(p.note, style: T.body())),
      ]),
    );
  }

  Future<void> _editNote(MapLocation loc) async {
    final c = TextEditingController(text: loc.note);
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.name),
        content: TextField(controller: c, autofocus: true, minLines: 3, maxLines: 8, style: T.body(), decoration: const InputDecoration(hintText: 'What do you want to remember about this place?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: T.h3(color: AppColors.textMuted))),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (text == null) return;
    loc.note = text;
    _changed();
  }

  // ------------------------------------------------------------- sheets

  void _showPlaces(MapState m) {
    var query = '';
    var filter = 'all';
    showAppSheet(context, builder: (sheet) {
      return StatefulBuilder(builder: (sheet, set) {
        final gm = GeneratedMap.of(m);
        final rows = <Widget>[];
        for (var i = 0; i < m.locations.length; i++) {
          final l = m.locations[i];
          final known = _known(m, gm, i);
          final visited = _visited(m, i);
          final info = known ? PlaceInfo(ctl, l) : null;
          if (filter == 'visited' && !visited) continue;
          if (filter == 'unexplored' && visited) continue;
          if (filter == 'remembered' && !(info?.remembered ?? false) && l.note.isEmpty) continue;
          final name = known ? l.name : 'Unknown room';
          if (query.isNotEmpty && !name.toLowerCase().contains(query.toLowerCase()) && !l.note.toLowerCase().contains(query.toLowerCase())) continue;
          final kind = locationKind(l.name, map: m.kind);
          rows.add(ListRow(
            leading: Icon(known ? locIcon(kind) : Icons.help_outline, size: 20, color: i == m.current ? AppColors.accent : (visited ? AppColors.textMuted : AppColors.text)),
            title: name,
            subtitle: [
              i == m.current ? 'You are here' : (visited ? 'Visited' : 'Unexplored'),
              if (known) locKindLabel(kind),
              if (info?.remembered ?? false) 'remembered',
              if (l.note.isNotEmpty) 'note',
            ].join(' · '),
            onTap: !known
                ? null
                : () {
                    Navigator.pop(sheet);
                    _selectLocation(m, i, focus: true);
                  },
          ));
        }
        for (final p in m.pins) {
          if (filter != 'all' && filter != 'pins') continue;
          if (query.isNotEmpty && !'${p.label} ${p.note}'.toLowerCase().contains(query.toLowerCase())) continue;
          rows.add(ListRow(
            leading: Icon(pinIcons[p.icon % pinIcons.length], size: 20, color: pinColors[p.color % pinColors.length]),
            title: p.label.isEmpty ? 'Pin' : p.label,
            subtitle: p.note.isEmpty ? 'Your pin' : p.note,
            onTap: () {
              Navigator.pop(sheet);
              setState(() {
                _pin = p.id;
                _selected = null;
                _showPins = true;
              });
              _focus(Offset(p.x * _canvas.width, p.y * _canvas.height));
            },
          ));
        }
        return SizedBox(
          height: MediaQuery.sizeOf(sheet).height * 0.75,
          child: Column(children: [
            SheetTitle('Places', subtitle: '${m.locations.length} locations · ${m.pins.length} pins'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(style: T.body(), decoration: const InputDecoration(hintText: 'Search places, notes and pins', prefixIcon: Icon(Icons.search, size: 18)), onChanged: (v) => set(() => query = v)),
            ),
            SizedBox(
              height: 48,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), children: [
                for (final (id, label) in const [('all', 'All'), ('visited', 'Visited'), ('unexplored', 'Unexplored'), ('remembered', 'Remembered'), ('pins', 'Pins')])
                  Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: Text(label), selected: filter == id, onSelected: (_) => set(() => filter = id))),
              ]),
            ),
            Expanded(
              child: rows.isEmpty
                  ? const EmptyState(icon: Icons.search_off, title: 'Nothing here', message: 'Try another search or filter.')
                  : ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [RowGroup(children: rows)]),
            ),
          ]),
        );
      });
    });
  }

  void _showLayers(bool hasAi) {
    showAppSheet(context, builder: (sheet) => StatefulBuilder(builder: (sheet, set) {
          Widget row(IconData icon, String title, String sub, bool value, void Function(bool) on) => ListRow(
                leading: Icon(icon, size: 20),
                title: title,
                subtitle: sub,
                trailing: Switch(value: value, onChanged: (v) {
                  setState(() => on(v));
                  set(() {});
                }),
              );
          return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
            const SheetTitle('Map layers'),
            RowGroup(children: [
              row(Icons.label_outline, 'Labels', 'Place names', _labels, (v) => _labels = v),
              row(Icons.push_pin_outlined, 'Your pins', 'Long-press the map to add one', _showPins, (v) => _showPins = v),
              row(Icons.public, 'World memory', 'Marks places the story remembers', _showMemory, (v) => _showMemory = v),
              row(Icons.route_outlined, 'Route to selection', 'How far a place is from you', _showRoute, (v) => _showRoute = v),
              row(Icons.cloud_outlined, 'Fog of the unknown', 'Darken land you haven\'t explored', _fog, (v) => _fog = v),
              if (hasAi) row(Icons.image_outlined, 'Map picture', 'Your picture or AI art. Off: the hand-drawn map', _showAi, (v) => _showAi = v),
            ]),
          ]);
        }));
  }
}

/// Edits (or creates) a pin. Returns the pin, or one labelled "\u0000" when
/// the player deleted it, or null when cancelled.
Future<MapPin?> showPinEditor(BuildContext context, MapPin pin, {bool isNew = false}) {
  final label = TextEditingController(text: pin.label);
  final note = TextEditingController(text: pin.note);
  var icon = pin.icon;
  var color = pin.color;
  return showDialog<MapPin>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(isNew ? 'Drop a pin' : 'Edit pin'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: label, autofocus: isNew, style: T.body(), decoration: const InputDecoration(labelText: 'Name', hintText: 'Hidden cache')),
            const SizedBox(height: 10),
            TextField(controller: note, minLines: 2, maxLines: 5, style: T.body(), decoration: const InputDecoration(labelText: 'Note')),
            const SizedBox(height: 14),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (var i = 0; i < pinIcons.length; i++)
                ChoiceChip(
                  showCheckmark: false,
                  label: Icon(pinIcons[i], size: 18, color: i == icon ? pinColors[color] : AppColors.textMuted),
                  selected: i == icon,
                  onSelected: (_) => set(() => icon = i),
                ),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 10, children: [
              for (var i = 0; i < pinColors.length; i++)
                GestureDetector(
                  onTap: () => set(() => color = i),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(color: pinColors[i], shape: BoxShape.circle, border: Border.all(color: i == color ? Colors.white : Colors.transparent, width: 2)),
                  ),
                ),
            ]),
          ]),
        ),
        actions: [
          if (!isNew)
            TextButton(onPressed: () => Navigator.pop(ctx, MapPin(id: pin.id, x: pin.x, y: pin.y, label: '\u0000')), child: Text('Delete', style: T.h3(color: AppColors.danger))),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: T.h3(color: AppColors.textMuted))),
          TextButton(
            onPressed: () {
              pin
                ..label = label.text.trim()
                ..note = note.text.trim()
                ..icon = icon
                ..color = color;
              Navigator.pop(ctx, pin);
            },
            child: Text(isNew ? 'Add' : 'Save'),
          ),
        ],
      ),
    ),
  );
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(color: AppColors.surface.withValues(alpha: 0.94), borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: AppColors.accent),
          const SizedBox(width: 8),
          Flexible(child: Text(text, style: T.small(color: AppColors.text))),
        ]),
      );
}

/// Darkens everything far from the places you have been.
class _FogPainter extends CustomPainter {
  _FogPainter({required this.state});
  final MapState state;

  @override
  void paint(Canvas canvas, Size size) {
    final pts = MapMarkerPainter.positions(state, size);
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xD9050506));
    final clear = Paint()..blendMode = BlendMode.dstOut;
    for (var i = 0; i < math.min(pts.length, state.locations.length); i++) {
      final seen = state.locations[i].visited || i <= state.current;
      final next = i == state.current + 1;
      if (!seen && !next) continue;
      final r = seen ? 210.0 : 120.0;
      clear.shader = RadialGradient(colors: [Colors.black, Colors.black.withValues(alpha: seen ? 0.9 : 0.5), Colors.transparent], stops: const [0, 0.55, 1])
          .createShader(Rect.fromCircle(center: pts[i], radius: r));
      canvas.drawCircle(pts[i], r, clear);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FogPainter old) => true;
}

/// Pins, memory marks, the route to the selected place and the ruler.
class _OverlayPainter extends CustomPainter {
  _OverlayPainter({
    required this.state,
    required this.scale,
    required this.pins,
    required this.selectedPin,
    required this.labels,
    required this.remembered,
    required this.noted,
    this.route,
    this.measureA,
    this.measureB,
    this.measureLabel,
  });
  final MapState state;
  final double scale;
  final List<MapPin> pins;
  final String? selectedPin;
  final bool labels;
  final Set<int> remembered, noted;
  final int? route;
  final Offset? measureA, measureB;
  final String? measureLabel;

  void _glyph(Canvas canvas, IconData icon, Offset c, double size, Color color) {
    final tp = TextPainter(
      text: TextSpan(text: String.fromCharCode(icon.codePoint), style: TextStyle(fontFamily: icon.fontFamily, package: icon.fontPackage, fontSize: size, color: color)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  void _label(Canvas canvas, String text, Offset topCenter, double inv, {Color color = const Color(0xFFE4E4E7)}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontFamily: 'Inter', fontSize: 11 * inv, fontWeight: FontWeight.w600, color: color)),
      textDirection: TextDirection.ltr,
      maxLines: 2,
      textAlign: TextAlign.center,
    )..layout(maxWidth: 150 * inv);
    final box = Rect.fromCenter(center: topCenter + Offset(0, tp.height / 2 + 3 * inv), width: tp.width + 12 * inv, height: tp.height + 6 * inv);
    canvas.drawRRect(RRect.fromRectAndRadius(box, Radius.circular(6 * inv)), Paint()..color = const Color(0xE60A0A0B));
    tp.paint(canvas, box.topLeft + Offset(6 * inv, 3 * inv));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final inv = 1 / scale.clamp(0.25, 4);
    final pts = MapMarkerPainter.positions(state, size);
    final n = math.min(pts.length, state.locations.length);

    // Route from where you are to the selected place.
    final r = route;
    if (r != null && r != state.current && r < n && state.current < n) {
      final a = pts[state.current], b = pts[r];
      final glow = Paint()
        ..color = const Color(0x554ADE80)
        ..strokeWidth = 8 * inv
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(a, b, glow);
      final line = Paint()
        ..color = const Color(0xFF4ADE80)
        ..strokeWidth = 2 * inv;
      final total = (b - a).distance;
      final dir = (b - a) / total;
      for (var d = 18 * inv; d < total - 18 * inv; d += 14 * inv) {
        canvas.drawLine(a + dir * d, a + dir * math.min(d + 7 * inv, total), line);
      }
    }

    // Places the story remembers, and places you wrote a note about.
    for (var i = 0; i < n; i++) {
      final p = pts[i] + Offset(12 * inv, -12 * inv);
      if (remembered.contains(i)) {
        canvas.drawCircle(p, 7 * inv, Paint()..color = const Color(0xFF0A0A0B));
        canvas.drawCircle(p, 5.5 * inv, Paint()..color = const Color(0xFFFBBF24));
        _glyph(canvas, Icons.public, p, 8 * inv, const Color(0xFF0A0A0B));
      }
      if (noted.contains(i)) {
        final q = pts[i] + Offset(-12 * inv, -12 * inv);
        canvas.drawCircle(q, 7 * inv, Paint()..color = const Color(0xFF0A0A0B));
        canvas.drawCircle(q, 5.5 * inv, Paint()..color = const Color(0xFF60A5FA));
        _glyph(canvas, Icons.edit, q, 8 * inv, const Color(0xFF0A0A0B));
      }
    }

    // Your pins: a teardrop with an icon.
    for (final pin in pins) {
      final color = pinColors[pin.color % pinColors.length];
      final tip = Offset(pin.x * size.width, pin.y * size.height);
      final head = tip - Offset(0, 22 * inv);
      final rad = 11 * inv;
      final selected = pin.id == selectedPin;
      final path = Path()
        ..moveTo(tip.dx, tip.dy)
        ..quadraticBezierTo(head.dx - rad * 1.1, head.dy + rad * 0.9, head.dx - rad, head.dy)
        ..arcToPoint(Offset(head.dx + rad, head.dy), radius: Radius.circular(rad))
        ..quadraticBezierTo(head.dx + rad * 1.1, head.dy + rad * 0.9, tip.dx, tip.dy)
        ..close();
      canvas.drawPath(path.shift(Offset(0, 2 * inv)), Paint()..color = Colors.black.withValues(alpha: 0.45));
      canvas.drawPath(path, Paint()..color = color);
      if (selected) {
        canvas.drawPath(path, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * inv
          ..color = Colors.white);
      }
      _glyph(canvas, pinIcons[pin.icon % pinIcons.length], head, 12 * inv, const Color(0xFF0A0A0B));
      if (labels && pin.label.isNotEmpty) _label(canvas, pin.label, tip + Offset(0, 4 * inv), inv, color: color);
    }

    // Ruler
    final a = measureA, b = measureB;
    if (a != null) {
      final dot = Paint()..color = Colors.white;
      canvas.drawCircle(a, 5 * inv, dot);
      if (b != null) {
        final line = Paint()
          ..color = Colors.white
          ..strokeWidth = 2 * inv;
        final total = (b - a).distance;
        if (total > 0) {
          final dir = (b - a) / total;
          for (var d = 0.0; d < total; d += 12 * inv) {
            canvas.drawLine(a + dir * d, a + dir * math.min(d + 7 * inv, total), line);
          }
        }
        canvas.drawCircle(b, 5 * inv, dot);
        if (measureLabel != null) _label(canvas, measureLabel!, Offset.lerp(a, b, 0.5)! + Offset(0, 8 * inv), inv);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter old) => true;
}

class _Legend extends StatefulWidget {
  const _Legend({required this.map, this.memory = false, this.pins = false});
  final MapState map;
  final bool memory;
  final bool pins;

  @override
  State<_Legend> createState() => _LegendState();
}

class _LegendState extends State<_Legend> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final kinds = widget.map.locations.map((l) => locationKind(l.name, map: widget.map.kind)).toSet().toList();
    Widget dot(Color c) => Container(width: 12, height: 12, decoration: BoxDecoration(color: c, shape: BoxShape.circle));
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
                  _row(dot(AppColors.accent), 'You are here'),
                  _row(dot(const Color(0xFF3F3F46)), 'Visited'),
                  _row(dot(AppColors.text), 'Not yet visited'),
                  _row(Container(width: 16, height: 2, color: AppColors.accent), 'Route travelled'),
                  if (widget.memory) _row(dot(AppColors.warning), 'The world remembers'),
                  _row(dot(AppColors.info), 'Your note'),
                  if (widget.pins) _row(const Icon(Icons.push_pin, size: 14, color: AppColors.accent), 'Your pins'),
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
