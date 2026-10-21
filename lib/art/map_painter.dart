import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/dice.dart';
import '../models/adventure.dart';
import 'noise.dart';

// ------------------------------------------------------------------ palette

const _deepWater = Color(0xFF111C27);
const _shallow = Color(0xFF1A2C3C);
const _sand = Color(0xFF34302A);
const _grass = Color(0xFF1D2A21);
const _grass2 = Color(0xFF243328);
const _forest = Color(0xFF16261B);
const _hills = Color(0xFF29292A);
const _mountain = Color(0xFF353437);
const _snow = Color(0xFF55555B);
const _road = Color(0xFF6B5E4A);
const _river = Color(0xFF2A4A63);
const _label = Color(0xFFE4E4E7);
const _muted = Color(0xFFA1A1AA);
const _accent = Color(0xFF8B7CF6);

/// What a named location probably is, for icons and legends.
enum LocKind { town, castle, cave, crypt, forest, ruins, temple, tower, camp, road, swamp, mountain, coast, room, lair, place }

LocKind locationKind(String name, {MapKind map = MapKind.overworld}) {
  final n = name.toLowerCase();
  bool has(List<String> w) => w.any(n.contains);
  if (has(['sanctum', 'throne', 'lair', 'heart', 'inner'])) return LocKind.lair;
  if (has(['tavern', 'inn', 'market', 'square', 'town', 'village', 'gate', 'hamlet', 'city', 'harbor', 'harbour', 'dock'])) return LocKind.town;
  if (has(['castle', 'keep', 'fort', 'citadel', 'manor', 'hall'])) return LocKind.castle;
  if (has(['cave', 'cavern', 'grotto', 'mine', 'deep', 'burrow', 'tunnel'])) return LocKind.cave;
  if (has(['crypt', 'tomb', 'barrow', 'ossuary', 'grave', 'catacomb'])) return LocKind.crypt;
  if (has(['temple', 'shrine', 'chapel', 'church', 'altar', 'abbey'])) return LocKind.temple;
  if (has(['tower', 'spire', 'lighthouse', 'observatory'])) return LocKind.tower;
  if (has(['camp', 'campsite'])) return LocKind.camp;
  if (has(['ruin'])) return LocKind.ruins;
  if (has(['wood', 'forest', 'grove', 'glade'])) return LocKind.forest;
  if (has(['fen', 'swamp', 'marsh', 'bog', 'mire'])) return LocKind.swamp;
  if (has(['pass', 'peak', 'mount', 'crag', 'cliff', 'ridge'])) return LocKind.mountain;
  if (has(['strand', 'coast', 'shore', 'beach', 'bay', 'cove', 'pier'])) return LocKind.coast;
  if (has(['road', 'path', 'bridge', 'crossing', 'downs'])) return LocKind.road;
  return map == MapKind.dungeon ? LocKind.room : LocKind.place;
}

IconData locIcon(LocKind k) => switch (k) {
      LocKind.town => Icons.holiday_village_outlined,
      LocKind.castle => Icons.castle_outlined,
      LocKind.cave => Icons.landscape_outlined,
      LocKind.crypt => Icons.dangerous_outlined,
      LocKind.forest => Icons.park_outlined,
      LocKind.ruins => Icons.account_balance_outlined,
      LocKind.temple => Icons.temple_buddhist_outlined,
      LocKind.tower => Icons.cell_tower,
      LocKind.camp => Icons.local_fire_department_outlined,
      LocKind.road => Icons.signpost_outlined,
      LocKind.swamp => Icons.water_outlined,
      LocKind.mountain => Icons.terrain,
      LocKind.coast => Icons.sailing_outlined,
      LocKind.room => Icons.door_front_door_outlined,
      LocKind.lair => Icons.whatshot_outlined,
      LocKind.place => Icons.place_outlined,
    };

String locKindLabel(LocKind k) => switch (k) {
      LocKind.town => 'Settlement',
      LocKind.castle => 'Stronghold',
      LocKind.cave => 'Cave',
      LocKind.crypt => 'Crypt',
      LocKind.forest => 'Forest',
      LocKind.ruins => 'Ruins',
      LocKind.temple => 'Temple',
      LocKind.tower => 'Tower',
      LocKind.camp => 'Campsite',
      LocKind.road => 'Road',
      LocKind.swamp => 'Wetland',
      LocKind.mountain => 'Mountains',
      LocKind.coast => 'Coast',
      LocKind.room => 'Chamber',
      LocKind.lair => 'Lair',
      LocKind.place => 'Point of interest',
    };

// ------------------------------------------------------------------ layout

class GenRoom {
  GenRoom(this.rect, this.feature);
  final Rect rect; // grid cells
  final int feature; // 0 none, 1 pillars, 2 rubble, 3 chest, 4 altar, 5 stairs, 6 pool, 7 table, 8 bones
  Offset get center => rect.center;
}

/// Deterministic layout derived from a MapState.
class GeneratedMap {
  GeneratedMap._(this.kind, this.cols, this.rows, this.tiles, this.rooms, this.points, this.doors);

  final MapKind kind;
  final int cols;
  final int rows;

  /// dungeon: 0 rock, 1 floor, 3 water. town: 0 grass, 1 road, 2 building, 3 water, 4 plaza.
  final List<int> tiles;
  final List<GenRoom> rooms;

  /// Normalized (0..1) positions of each location.
  final List<Offset> points;
  final List<Offset> doors;

  static final _cache = <String, GeneratedMap>{};

  static GeneratedMap of(MapState m) {
    final key = '${m.kind.name}-${m.seed}-${m.locations.length}';
    return _cache.putIfAbsent(key, () {
      final n = math.max(3, m.locations.length);
      return switch (m.kind) {
        MapKind.dungeon => _dungeon(m.seed, n),
        MapKind.town => _town(m.seed, n),
        MapKind.overworld => _overworld(m.seed, n),
      };
    });
  }

  static GeneratedMap _dungeon(int seed, int count) {
    final r = Rng(seed);
    const cols = 48, rows = 32;
    final tiles = List<int>.filled(cols * rows, 0);
    final rooms = <GenRoom>[];
    var attempts = 0;
    while (rooms.length < count && attempts < 800) {
      attempts++;
      final w = r.range(5, 9);
      final h = r.range(4, 7);
      final x = ((rooms.length / count) * (cols - w - 2)).round() + r.range(-3, 3);
      final y = r.range(1, rows - h - 2);
      final rect = Rect.fromLTWH(x.clamp(1, cols - w - 1).toDouble(), y.toDouble(), w.toDouble(), h.toDouble());
      if (rooms.any((o) => o.rect.inflate(1.5).overlaps(rect))) continue;
      final idx = rooms.length;
      final feature = idx == 0 ? 5 : (idx == count - 1 ? 4 : r.pick([0, 1, 2, 3, 6, 7, 8, 1, 2]));
      rooms.add(GenRoom(rect, feature));
    }
    for (var i = 0; i < 5 && attempts < 1500; attempts++) {
      final w = r.range(3, 6), h = r.range(3, 5);
      final rect = Rect.fromLTWH(r.range(1, cols - w - 1).toDouble(), r.range(1, rows - h - 1).toDouble(), w.toDouble(), h.toDouble());
      if (rooms.any((o) => o.rect.inflate(1.5).overlaps(rect))) continue;
      rooms.add(GenRoom(rect, r.pick([0, 2, 8, 3])));
      i++;
    }
    for (final rm in rooms) {
      for (var y = rm.rect.top.toInt(); y < rm.rect.bottom.toInt(); y++) {
        for (var x = rm.rect.left.toInt(); x < rm.rect.right.toInt(); x++) {
          tiles[y * cols + x] = 1;
        }
      }
    }
    final doors = <Offset>[];
    bool inRoom(int x, int y) => rooms.any((rm) => x >= rm.rect.left && x < rm.rect.right && y >= rm.rect.top && y < rm.rect.bottom);
    void corridor(Offset a, Offset b) {
      var x = a.dx.toInt(), y = a.dy.toInt();
      final tx = b.dx.toInt(), ty = b.dy.toInt();
      var wasRoom = inRoom(x, y);
      void step() {
        final room = inRoom(x, y);
        if (room != wasRoom) doors.add(Offset(x + 0.5, y + 0.5));
        wasRoom = room;
        if (tiles[y * cols + x] == 0) tiles[y * cols + x] = 1;
      }

      if (r.chance(0.5)) {
        while (x != tx) {
          step();
          x += (tx - x).sign;
        }
        while (y != ty) {
          step();
          y += (ty - y).sign;
        }
      } else {
        while (y != ty) {
          step();
          y += (ty - y).sign;
        }
        while (x != tx) {
          step();
          x += (tx - x).sign;
        }
      }
    }

    final main = rooms.take(count).toList();
    for (var i = 0; i < main.length - 1; i++) {
      corridor(main[i].center, main[i + 1].center);
    }
    for (final extra in rooms.skip(count)) {
      var best = main.first;
      for (final m in main) {
        if ((m.center - extra.center).distance < (best.center - extra.center).distance) best = m;
      }
      corridor(extra.center, best.center);
    }
    final pts = main.map((rm) => Offset(rm.center.dx / cols, rm.center.dy / rows)).toList();
    return GeneratedMap._(MapKind.dungeon, cols, rows, tiles, rooms, pts, doors);
  }

  static GeneratedMap _overworld(int seed, int count) {
    final r = Rng(seed);
    final pts = <Offset>[];
    var y = r.rangeD(0.35, 0.65);
    for (var i = 0; i < count; i++) {
      final x = 0.1 + i / math.max(1, count - 1) * 0.8;
      y = (y + r.rangeD(-0.2, 0.2)).clamp(0.18, 0.82);
      pts.add(Offset(x, y));
    }
    return GeneratedMap._(MapKind.overworld, 0, 0, const [], const [], pts, const []);
  }

  static GeneratedMap _town(int seed, int count) {
    final r = Rng(seed);
    const cols = 40, rows = 28;
    final tiles = List<int>.filled(cols * rows, 0);
    final mainY = r.range(12, 15);
    for (var x = 0; x < cols; x++) {
      tiles[mainY * cols + x] = 1;
    }
    final crossXs = [r.range(6, 10), r.range(17, 22), r.range(28, 32)];
    for (final cx in crossXs) {
      for (var y = 2; y < rows - 2; y++) {
        tiles[y * cols + cx] = 1;
      }
    }
    // plaza
    final px = crossXs[1], py = mainY;
    for (var y = py - 2; y <= py + 2; y++) {
      for (var x = px - 3; x <= px + 3; x++) {
        tiles[y * cols + x] = 4;
      }
    }
    var rx = r.range(34, 37);
    for (var y = 0; y < rows; y++) {
      rx = (rx + r.range(-1, 1)).clamp(33, cols - 3);
      for (var k = 0; k < 2; k++) {
        if (tiles[y * cols + rx + k] != 1) tiles[y * cols + rx + k] = 3;
      }
    }
    final rooms = <GenRoom>[];
    for (var i = 0; i < 70; i++) {
      final w = r.range(2, 3), h = r.range(2, 3);
      final x = r.range(1, cols - w - 1), y = r.range(1, rows - h - 1);
      var ok = true;
      for (var yy = y - 1; yy <= y + h && ok; yy++) {
        for (var xx = x - 1; xx <= x + w && ok; xx++) {
          if (tiles[yy * cols + xx] != 0) ok = false;
        }
      }
      if (!ok) continue;
      for (var yy = y; yy < y + h; yy++) {
        for (var xx = x; xx < x + w; xx++) {
          tiles[yy * cols + xx] = 2;
        }
      }
      rooms.add(GenRoom(Rect.fromLTWH(x.toDouble(), y.toDouble(), w.toDouble(), h.toDouble()), 0));
    }
    final pts = <Offset>[Offset((px + 0.5) / cols, (py + 0.5) / rows)];
    for (var i = 1; i < count; i++) {
      final rm = rooms.isEmpty ? null : rooms[(i * 11) % rooms.length];
      pts.add(rm == null ? Offset(0.2 + i * 0.15, 0.5) : Offset(rm.center.dx / cols, rm.center.dy / rows));
    }
    return GeneratedMap._(MapKind.town, cols, rows, tiles, rooms, pts, const []);
  }
}

// ------------------------------------------------------------ base painter

/// Static terrain layer. Expensive; wrap in a RepaintBoundary.
class MapBasePainter extends CustomPainter {
  MapBasePainter({required this.state});
  final MapState state;

  @override
  void paint(Canvas canvas, Size size) {
    final gm = GeneratedMap.of(state);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    switch (gm.kind) {
      case MapKind.overworld:
        _overworld(canvas, size, gm);
      case MapKind.dungeon:
        _dungeon(canvas, size, gm);
      case MapKind.town:
        _town(canvas, size, gm);
    }
    canvas.restore();
  }

  double _elev(ValueNoise n, GeneratedMap gm, double nx, double ny) {
    var e = n.fbm(nx * 3.2, ny * 3.2, octaves: 5);
    // Keep the edges more likely to be water and route points on land.
    final edge = math.min(math.min(nx, 1 - nx), math.min(ny, 1 - ny));
    e -= (0.12 - edge).clamp(0.0, 0.12) * 2.2;
    for (final p in gm.points) {
      final d = (Offset(nx, ny) - p).distance;
      if (d < 0.09) e = math.max(e, 0.47 + (0.09 - d) * 0.5);
    }
    return e;
  }

  void _overworld(Canvas canvas, Size size, GeneratedMap gm) {
    final w = size.width, h = size.height;
    final n = ValueNoise(state.seed * 7 + 3);
    final m = ValueNoise(state.seed * 13 + 1);
    final r = Rng(state.seed);
    const step = 5.0;
    final cols = (w / step).ceil() + 1, rows = (h / step).ceil() + 1;
    final elev = List<double>.filled(cols * rows, 0);
    for (var j = 0; j < rows; j++) {
      for (var i = 0; i < cols; i++) {
        elev[j * cols + i] = _elev(n, gm, i * step / w, j * step / h);
      }
    }
    double e(int i, int j) => elev[j.clamp(0, rows - 1) * cols + i.clamp(0, cols - 1)];
    final paint = Paint();
    for (var j = 0; j < rows; j++) {
      for (var i = 0; i < cols; i++) {
        final v = e(i, j);
        final moist = m.fbm(i * step / w * 4, j * step / h * 4, octaves: 3);
        Color c;
        if (v < 0.34) {
          c = Color.lerp(_deepWater, _shallow, (v / 0.34).clamp(0, 1))!;
        } else if (v < 0.37) {
          c = _sand;
        } else if (v < 0.62) {
          c = moist > 0.52 ? _forest : Color.lerp(_grass, _grass2, moist)!;
        } else if (v < 0.69) {
          c = _hills;
        } else if (v < 0.77) {
          c = _mountain;
        } else {
          c = _snow;
        }
        if (v >= 0.34) {
          // Hill shading from the north-west.
          final shade = ((e(i - 1, j - 1) - v) * 9).clamp(-0.25, 0.25);
          c = shade > 0 ? Color.lerp(c, Colors.black, shade)! : Color.lerp(c, Colors.white, -shade * 0.6)!;
        }
        paint.color = c;
        canvas.drawRect(Rect.fromLTWH(i * step, j * step, step + 0.6, step + 0.6), paint);
      }
    }
    // Coastline highlight
    final coast = Paint()..color = const Color(0x22FFFFFF);
    for (var j = 1; j < rows - 1; j++) {
      for (var i = 1; i < cols - 1; i++) {
        if (e(i, j) >= 0.34 && (e(i + 1, j) < 0.34 || e(i - 1, j) < 0.34 || e(i, j + 1) < 0.34 || e(i, j - 1) < 0.34)) {
          canvas.drawRect(Rect.fromLTWH(i * step, j * step, step, step), coast);
        }
      }
    }
    // Rivers flow downhill from high ground to water.
    final riverPaint = Paint()
      ..color = _river
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (var k = 0; k < 4; k++) {
      var bi = 0, bj = 0;
      var best = -1.0;
      for (var t = 0; t < 40; t++) {
        final i = r.range(2, cols - 3), j = r.range(2, rows - 3);
        if (e(i, j) > best && e(i, j) < 0.74) {
          best = e(i, j);
          bi = i;
          bj = j;
        }
      }
      final path = Path()..moveTo(bi * step, bj * step);
      var i = bi, j = bj;
      for (var s = 0; s < 400 && e(i, j) >= 0.34; s++) {
        var ni = i, nj = j;
        var lowest = e(i, j) + 0.02;
        for (final d in const [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, 1), (1, -1), (-1, -1)]) {
          final v = e(i + d.$1, j + d.$2) + r.nextDouble() * 0.004;
          if (v < lowest) {
            lowest = v;
            ni = i + d.$1;
            nj = j + d.$2;
          }
        }
        if (ni == i && nj == j) {
          ni = i + (r.chance(0.5) ? 1 : -1);
          nj = j + 1;
        }
        i = ni.clamp(0, cols - 1);
        j = nj.clamp(0, rows - 1);
        path.lineTo(i * step + step / 2, j * step + step / 2);
      }
      canvas.drawPath(path, riverPaint..strokeWidth = 2.2);
    }
    // Glyphs: trees and peaks
    final tree = Paint()..color = const Color(0xFF0F1712);
    final peakDark = Paint()..color = const Color(0xFF242326);
    final peakLight = Paint()..color = const Color(0xFF4A494E);
    final glyphRng = Rng(state.seed + 99);
    for (var t = 0; t < (w * h / 900).round(); t++) {
      final x = glyphRng.nextDouble() * w, y = glyphRng.nextDouble() * h;
      final v = _elev(n, gm, x / w, y / h);
      final moist = m.fbm(x / w * 4, y / h * 4, octaves: 3);
      if (v >= 0.37 && v < 0.62 && moist > 0.52) {
        final s = glyphRng.rangeD(3, 5.5);
        canvas.drawPath(Path()..moveTo(x, y - s * 2)..lineTo(x + s, y)..lineTo(x - s, y)..close(), tree);
      } else if (v >= 0.67 && glyphRng.chance(0.5)) {
        final s = glyphRng.rangeD(7, 13);
        canvas.drawPath(Path()..moveTo(x - s, y)..lineTo(x, y - s * 1.1)..lineTo(x + s, y)..close(), peakDark);
        canvas.drawPath(Path()..moveTo(x, y - s * 1.1)..lineTo(x + s, y)..lineTo(x + s * 0.2, y)..close(), peakLight);
        if (v > 0.72) canvas.drawPath(Path()..moveTo(x - s * 0.3, y - s * 0.75)..lineTo(x, y - s * 1.1)..lineTo(x + s * 0.3, y - s * 0.75)..close(), Paint()..color = const Color(0xFF8A8A92));
      }
    }
    // Roads between locations
    final pts = gm.points.map((p) => Offset(p.dx * w, p.dy * h)).toList();
    final road = Paint()
      ..color = _road.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (var i = 0; i < pts.length - 1; i++) {
      for (final metric in _routePath(pts[i], pts[i + 1], i).computeMetrics()) {
        for (var d = 0.0; d < metric.length; d += 9) {
          canvas.drawPath(metric.extractPath(d, math.min(d + 5, metric.length)), road);
        }
      }
    }
    // Faint graticule
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.025)
      ..strokeWidth = 1;
    for (var x = 0.0; x < w; x += w / 8) {
      canvas.drawLine(Offset(x, 0), Offset(x, h), grid);
    }
    for (var y = 0.0; y < h; y += h / 6) {
      canvas.drawLine(Offset(0, y), Offset(w, y), grid);
    }
  }

  void _dungeon(Canvas canvas, Size size, GeneratedMap gm) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF0E0E10));
    final cw = size.width / gm.cols, ch = size.height / gm.rows;
    final r = Rng(state.seed + 5);
    bool rock(int x, int y) => x < 0 || y < 0 || x >= gm.cols || y >= gm.rows || gm.tiles[y * gm.cols + x] == 0;
    // Rock texture hatching near walls
    final hatch = Paint()
      ..color = const Color(0xFF1B1B1F)
      ..strokeWidth = 1;
    for (var y = 0; y < gm.rows; y++) {
      for (var x = 0; x < gm.cols; x++) {
        if (!rock(x, y)) continue;
        var near = false;
        for (var dy = -1; dy <= 1 && !near; dy++) {
          for (var dx = -1; dx <= 1 && !near; dx++) {
            if (!rock(x + dx, y + dy)) near = true;
          }
        }
        if (!near) continue;
        final o = Offset(x * cw, y * ch);
        canvas.drawLine(o + Offset(0, ch * 0.3), o + Offset(cw * 0.7, ch), hatch);
        canvas.drawLine(o + Offset(cw * 0.3, 0), o + Offset(cw, ch * 0.7), hatch);
      }
    }
    // Floor with subtle tile variation
    for (var y = 0; y < gm.rows; y++) {
      for (var x = 0; x < gm.cols; x++) {
        final t = gm.tiles[y * gm.cols + x];
        if (t == 0) continue;
        final v = ((x * 7 + y * 13) % 5) / 100;
        final base = t == 3 ? const Color(0xFF1C2A38) : Color.lerp(const Color(0xFF26262B), const Color(0xFF2E2E34), v * 4)!;
        canvas.drawRect(Rect.fromLTWH(x * cw, y * ch, cw + 0.5, ch + 0.5), Paint()..color = base);
      }
    }
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.035)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;
    for (var y = 0; y < gm.rows; y++) {
      for (var x = 0; x < gm.cols; x++) {
        if (!rock(x, y)) canvas.drawRect(Rect.fromLTWH(x * cw, y * ch, cw, ch), grid);
      }
    }
    // Walls with a soft shadow
    final wall = Paint()
      ..color = const Color(0xFF5A5A63)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.square;
    final shadow = Paint()..color = Colors.black.withValues(alpha: 0.35);
    for (var y = 0; y < gm.rows; y++) {
      for (var x = 0; x < gm.cols; x++) {
        if (rock(x, y)) continue;
        final l = x * cw, t = y * ch, rr = l + cw, b = t + ch;
        if (rock(x, y - 1)) canvas.drawRect(Rect.fromLTWH(l, t, cw, ch * 0.25), shadow);
        if (rock(x - 1, y)) canvas.drawLine(Offset(l, t), Offset(l, b), wall);
        if (rock(x + 1, y)) canvas.drawLine(Offset(rr, t), Offset(rr, b), wall);
        if (rock(x, y - 1)) canvas.drawLine(Offset(l, t), Offset(rr, t), wall);
        if (rock(x, y + 1)) canvas.drawLine(Offset(l, b), Offset(rr, b), wall);
      }
    }
    // Doors
    final door = Paint()..color = const Color(0xFF7A6248);
    for (final d in gm.doors) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(d.dx * cw, d.dy * ch), width: cw * 0.7, height: ch * 0.7), const Radius.circular(2)), door);
    }
    // Room features
    final detail = Paint()..color = const Color(0xFF45454D);
    final detailLight = Paint()..color = const Color(0xFF6B6B74);
    for (final rm in gm.rooms) {
      final rect = Rect.fromLTWH(rm.rect.left * cw, rm.rect.top * ch, rm.rect.width * cw, rm.rect.height * ch);
      final c = rect.center;
      switch (rm.feature) {
        case 1: // pillars
          for (final dx in [-0.3, 0.3]) {
            for (final dy in [-0.3, 0.3]) {
              canvas.drawCircle(c + Offset(rect.width * dx, rect.height * dy), cw * 0.35, detailLight);
            }
          }
        case 2: // rubble
          for (var i = 0; i < 7; i++) {
            canvas.drawCircle(Offset(rect.left + r.nextDouble() * rect.width, rect.top + r.nextDouble() * rect.height), cw * r.rangeD(0.12, 0.3), detail);
          }
        case 3: // chest
          canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: c + Offset(rect.width * 0.25, -rect.height * 0.2), width: cw * 1.2, height: ch * 0.8), const Radius.circular(2)), Paint()..color = const Color(0xFF8A6A3A));
        case 4: // altar / throne
          canvas.drawRect(Rect.fromCenter(center: c - Offset(0, rect.height * 0.25), width: cw * 2, height: ch * 0.9), detailLight);
          canvas.drawCircle(c - Offset(0, rect.height * 0.25), cw * 0.25, Paint()..color = const Color(0xFFF87171));
        case 5: // stairs
          for (var i = 0; i < 4; i++) {
            canvas.drawRect(Rect.fromLTWH(rect.left + cw * 0.5, rect.top + ch * 0.5 + i * ch * 0.35, cw * 1.6, ch * 0.2), detailLight);
          }
        case 6: // pool
          canvas.drawOval(Rect.fromCenter(center: c, width: rect.width * 0.45, height: rect.height * 0.4), Paint()..color = const Color(0xFF1C2E40));
        case 7: // table
          canvas.drawRect(Rect.fromCenter(center: c, width: cw * 2.4, height: ch * 1.1), Paint()..color = const Color(0xFF4A3D2E));
        case 8: // bones
          for (var i = 0; i < 4; i++) {
            final p = Offset(rect.left + r.nextDouble() * rect.width, rect.top + r.nextDouble() * rect.height);
            canvas.drawLine(p, p + Offset(cw * 0.6, ch * 0.2), Paint()
              ..color = const Color(0xFF8A8A80)
              ..strokeWidth = 1.4);
          }
      }
    }
    // Torches
    final torch = Paint()
      ..color = const Color(0xFFFBBF24).withValues(alpha: 0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    for (final rm in gm.rooms.take(gm.points.length)) {
      final tl = Offset(rm.rect.left * cw + cw * 0.6, rm.rect.top * ch + ch * 0.6);
      canvas.drawCircle(tl, cw * 2, torch);
      canvas.drawCircle(tl, 1.8, Paint()..color = const Color(0xFFFBBF24));
    }
  }

  void _town(Canvas canvas, Size size, GeneratedMap gm) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _grass);
    final cw = size.width / gm.cols, ch = size.height / gm.rows;
    final r = Rng(state.seed + 3);
    for (var y = 0; y < gm.rows; y++) {
      for (var x = 0; x < gm.cols; x++) {
        final cell = Rect.fromLTWH(x * cw, y * ch, cw + 0.5, ch + 0.5);
        switch (gm.tiles[y * gm.cols + x]) {
          case 1:
            canvas.drawRect(cell, Paint()..color = const Color(0xFF332E27));
          case 3:
            canvas.drawRect(cell, Paint()..color = _shallow);
          case 4:
            canvas.drawRect(cell, Paint()..color = const Color(0xFF3A342C));
        }
      }
    }
    // Bridges where roads cross the river
    for (var y = 0; y < gm.rows; y++) {
      for (var x = 1; x < gm.cols - 1; x++) {
        if (gm.tiles[y * gm.cols + x] == 1 && (gm.tiles[y * gm.cols + x - 1] == 3 || gm.tiles[y * gm.cols + x + 1] == 3)) {
          canvas.drawRect(Rect.fromLTWH(x * cw - cw, y * ch, cw * 3, ch), Paint()..color = const Color(0xFF4A3D2E));
        }
      }
    }
    // Buildings with lit and shaded roof halves
    for (final b in gm.rooms) {
      final rect = Rect.fromLTWH(b.rect.left * cw + 1, b.rect.top * ch + 1, b.rect.width * cw - 2, b.rect.height * ch - 2);
      final hue = r.pick(const [Color(0xFF4A3A33), Color(0xFF3F3A40), Color(0xFF4A4235), Color(0xFF3A3F45)]);
      canvas.drawRect(rect.shift(const Offset(2, 2)), Paint()..color = Colors.black.withValues(alpha: 0.35));
      canvas.drawRect(rect, Paint()..color = hue);
      canvas.drawRect(Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height / 2), Paint()..color = Color.lerp(hue, Colors.white, 0.1)!);
      canvas.drawLine(Offset(rect.left, rect.center.dy), Offset(rect.right, rect.center.dy), Paint()
        ..color = Colors.black.withValues(alpha: 0.3)
        ..strokeWidth = 1);
    }
    // Trees
    final tree = Paint()..color = const Color(0xFF16231A);
    for (var i = 0; i < 90; i++) {
      final x = r.range(0, gm.cols - 1), y = r.range(0, gm.rows - 1);
      if (gm.tiles[y * gm.cols + x] != 0) continue;
      canvas.drawCircle(Offset(x * cw + cw / 2, y * ch + ch / 2), cw * r.rangeD(0.35, 0.55), tree);
    }
    // Plaza fountain
    final plaza = gm.points.first;
    canvas.drawCircle(Offset(plaza.dx * size.width, plaza.dy * size.height), cw * 1.1, Paint()..color = const Color(0xFF1E2E3E));
  }

  @override
  bool shouldRepaint(covariant MapBasePainter old) => old.state.seed != state.seed || old.state.kind != state.kind || old.state.locations.length != state.locations.length;
}

Path _routePath(Offset a, Offset b, int i) {
  final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2) + Offset(0, (i.isEven ? -1 : 1) * 18);
  return Path()
    ..moveTo(a.dx, a.dy)
    ..quadraticBezierTo(mid.dx, mid.dy, b.dx, b.dy);
}

// ---------------------------------------------------------- marker painter

/// Dynamic layer: route progress, markers, labels, fog, compass.
class MapMarkerPainter extends CustomPainter {
  MapMarkerPainter({required this.state, this.pulse = 0, this.selected, this.showLabels = true, this.scale = 1});
  final MapState state;
  final double pulse;
  final int? selected;
  final bool showLabels;

  /// Current zoom, so labels and icons stay a readable size.
  final double scale;

  static List<Offset> positions(MapState state, Size size) => GeneratedMap.of(state).points.map((p) => Offset(p.dx * size.width, p.dy * size.height)).toList();

  @override
  void paint(Canvas canvas, Size size) {
    final gm = GeneratedMap.of(state);
    final inv = 1 / scale.clamp(0.25, 4);
    final pts = positions(state, size);
    final n = math.min(pts.length, state.locations.length);
    // Fog over unexplored dungeon rooms
    if (gm.kind == MapKind.dungeon) {
      final cw = size.width / gm.cols, ch = size.height / gm.rows;
      final fog = Paint()..color = const Color(0xF20A0A0B);
      for (var i = 0; i < gm.rooms.length; i++) {
        final known = i <= state.current + 1 || (i < state.locations.length && state.locations[i].visited);
        if (known) continue;
        final rr = gm.rooms[i].rect;
        canvas.drawRect(Rect.fromLTWH(rr.left * cw - 3, rr.top * ch - 3, rr.width * cw + 6, rr.height * ch + 6), fog);
      }
    }
    // Route
    for (var i = 0; i < n - 1; i++) {
      final travelled = i < state.current;
      final p = Paint()
        ..color = travelled ? _accent : _muted.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = (travelled ? 2.6 : 1.6) * inv
        ..strokeCap = StrokeCap.round;
      final path = gm.kind == MapKind.overworld ? _routePath(pts[i], pts[i + 1], i) : (Path()..moveTo(pts[i].dx, pts[i].dy)..lineTo(pts[i + 1].dx, pts[i + 1].dy));
      if (travelled) {
        canvas.drawPath(path, p);
      } else {
        for (final m in path.computeMetrics()) {
          for (var d = 0.0; d < m.length; d += 10 * inv) {
            canvas.drawPath(m.extractPath(d, math.min(d + 5 * inv, m.length)), p);
          }
        }
      }
    }
    // Markers
    for (var i = 0; i < n; i++) {
      final loc = state.locations[i];
      final p = pts[i];
      final current = i == state.current;
      final visited = loc.visited || i < state.current;
      final known = gm.kind != MapKind.dungeon || i <= state.current + 1 || visited;
      if (!known) continue;
      final rad = 13 * inv;
      if (current) canvas.drawCircle(p, rad + (6 + pulse * 10) * inv, Paint()..color = _accent.withValues(alpha: 0.35 * (1 - pulse)));
      if (i == selected) {
        canvas.drawCircle(p, rad + 5 * inv, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * inv
          ..color = Colors.white);
      }
      canvas.drawCircle(p + Offset(0, 1.5 * inv), rad, Paint()..color = Colors.black.withValues(alpha: 0.5));
      canvas.drawCircle(p, rad, Paint()..color = current ? _accent : (visited ? const Color(0xFF3F3F46) : const Color(0xFFF4F4F5)));
      final icon = locIcon(locationKind(loc.name, map: gm.kind));
      final ip = TextPainter(
        text: TextSpan(text: String.fromCharCode(icon.codePoint), style: TextStyle(fontFamily: icon.fontFamily, package: icon.fontPackage, fontSize: 15 * inv, color: current || visited ? Colors.white : const Color(0xFF0A0A0B))),
        textDirection: TextDirection.ltr,
      )..layout();
      ip.paint(canvas, p - Offset(ip.width / 2, ip.height / 2));
      if (!showLabels) continue;
      final tp = TextPainter(
        text: TextSpan(text: loc.name, style: TextStyle(fontFamily: 'Inter', fontSize: 11.5 * inv, fontWeight: current ? FontWeight.w600 : FontWeight.w500, color: current ? _label : _muted)),
        textDirection: TextDirection.ltr,
        maxLines: 2,
        textAlign: TextAlign.center,
      )..layout(maxWidth: 130 * inv);
      final box = Rect.fromCenter(center: p + Offset(0, rad + 6 * inv + tp.height / 2 + 3 * inv), width: tp.width + 12 * inv, height: tp.height + 6 * inv);
      final clamped = box.shift(Offset(
        box.left < 2 ? 2 - box.left : (box.right > size.width - 2 ? size.width - 2 - box.right : 0),
        box.bottom > size.height - 2 ? size.height - 2 - box.bottom : 0,
      ));
      canvas.drawRRect(RRect.fromRectAndRadius(clamped, Radius.circular(6 * inv)), Paint()..color = const Color(0xD90A0A0B));
      tp.paint(canvas, clamped.topLeft + Offset(6 * inv, 3 * inv));
    }
    _compass(canvas, Offset(size.width - 34 * inv, 34 * inv), 20 * inv);
    if (gm.kind == MapKind.overworld) _scaleBar(canvas, size, inv);
  }

  void _compass(Canvas canvas, Offset c, double r) {
    canvas.drawCircle(c, r + 4, Paint()..color = const Color(0xB30A0A0B));
    canvas.drawCircle(c, r, Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0xFF3F3F46));
    for (var i = 0; i < 4; i++) {
      final a = i * math.pi / 2 - math.pi / 2;
      final tip = c + Offset(math.cos(a), math.sin(a)) * r * 0.9;
      final l = c + Offset(math.cos(a + math.pi / 2), math.sin(a + math.pi / 2)) * r * 0.2;
      final rr = c + Offset(math.cos(a - math.pi / 2), math.sin(a - math.pi / 2)) * r * 0.2;
      canvas.drawPath(Path()..moveTo(tip.dx, tip.dy)..lineTo(l.dx, l.dy)..lineTo(rr.dx, rr.dy)..close(), Paint()..color = i == 0 ? Colors.white : const Color(0xFF52525B));
    }
  }

  void _scaleBar(Canvas canvas, Size size, double inv) {
    final o = Offset(16 * inv, size.height - 22 * inv);
    // A fixed length on the map, so it agrees with the ruler at any zoom.
    final len = kMapDayLength * size.width / 1400;
    final p = Paint()
      ..color = _muted
      ..strokeWidth = 1.5 * inv;
    canvas.drawLine(o, o + Offset(len, 0), p);
    canvas.drawLine(o, o - Offset(0, 5 * inv), p);
    canvas.drawLine(o + Offset(len, 0), o + Offset(len, -5 * inv), p);
    final tp = TextPainter(text: TextSpan(text: '1 day\'s travel', style: TextStyle(fontFamily: 'Inter', fontSize: 10 * inv, color: _muted)), textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, o + Offset(0, 4 * inv));
  }

  @override
  bool shouldRepaint(covariant MapMarkerPainter old) => true;
}

/// Combined painter for small previews (no caching needed at small sizes).
class MapPainter extends CustomPainter {
  MapPainter({required this.state, this.pulse = 0});
  final MapState state;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10)));
    MapBasePainter(state: state).paint(canvas, size);
    MapMarkerPainter(state: state, pulse: pulse, showLabels: size.width > 260).paint(canvas, size);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant MapPainter old) => true;
}

/// One day's travel on foot, in units of a 1400-wide region map.
const kMapDayLength = 120.0;

/// Small helper for a stable map seed from a name.
int mapSeed(String name) => stableHash(name) & 0x3FFFFFFF;

