import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/dice.dart';
import 'noise.dart';
import 'paint_cache.dart';

/// Animated, procedurally painted scene backdrop for a location.
class SceneView extends StatefulWidget {
  const SceneView({super.key, required this.location, this.time = 'day', this.mood = 'calm', this.seed = 0, this.animate = false, this.own = true});
  final String location;
  final String time;
  final String mood;
  final int seed;
  final bool animate;

  /// Show the player's own picture for this place when they chose one.
  final bool own;

  /// Set by the app: the player's picture for a place, how to show it, and
  /// what to listen to for changes.
  static String? Function(String location, int seed)? ownImage;
  static Widget Function(String path, Widget painted)? showOwn;
  static Listenable? ownChanges;

  @override
  State<SceneView> createState() => _SceneViewState();
}

class _SceneViewState extends State<SceneView> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 20));

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final find = SceneView.ownImage, show = SceneView.showOwn;
    if (!widget.own || find == null || show == null) return _painted();
    return ListenableBuilder(
      listenable: SceneView.ownChanges ?? _c,
      builder: (context, _) {
        final path = find(widget.location, widget.seed);
        return path == null ? _painted() : show(path, _painted());
      },
    );
  }

  Widget _painted() {
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          CachedPaint(
            cacheKey: 'scene:${widget.location}:${widget.time}:${widget.mood}:${widget.seed}',
            painter: ScenePainter(location: widget.location, time: widget.time, mood: widget.mood, seed: widget.seed),
          ),
          if (widget.animate)
            AnimatedBuilder(
              animation: _c,
              builder: (context, _) => CustomPaint(painter: _ParticlePainter(location: widget.location, time: widget.time, mood: widget.mood, t: _c.value, seed: widget.seed)),
            ),
        ],
      ),
    );
  }
}

class _Sky {
  const _Sky(this.top, this.bottom, this.glow);
  final Color top;
  final Color bottom;
  final Color glow;
}

const _skies = {
  'dawn': _Sky(Color(0xFF2A2440), Color(0xFFD08A60), Color(0xFFFFC08A)),
  'day': _Sky(Color(0xFF3A5A7A), Color(0xFFB0A080), Color(0xFFFFF0C0)),
  'dusk': _Sky(Color(0xFF1E1430), Color(0xFFB0503A), Color(0xFFFF8A4A)),
  'night': _Sky(Color(0xFF05070F), Color(0xFF1A2236), Color(0xFFCFD8E3)),
};

bool _isInterior(String loc) => const {'dungeon', 'cave', 'crypt', 'tavern', 'sewer', 'temple', 'tower'}.contains(loc);

class ScenePainter extends CustomPainter {
  ScenePainter({required this.location, required this.time, required this.mood, required this.seed});
  final String location;
  final String time;
  final String mood;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rng(seed ^ stableHash(location));
    final noise = ValueNoise(seed ^ 991);
    if (_isInterior(location)) {
      _interior(canvas, size, r, noise);
    } else {
      _exterior(canvas, size, r, noise);
    }
    // mood tint
    final tint = switch (mood) {
      'combat' => const Color(0xFF8A1010),
      'eerie' || 'mystery' => const Color(0xFF203A40),
      'tense' => const Color(0xFF3A2010),
      'triumph' || 'festive' => const Color(0xFFC09030),
      'sad' => const Color(0xFF203050),
      _ => Colors.transparent,
    };
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = tint.withValues(alpha: tint == Colors.transparent ? 0 : 0.16));
    // vignette and bottom fade into UI
    canvas.drawRect(rect, Paint()..shader = RadialGradient(colors: [Colors.transparent, Colors.black.withValues(alpha: 0.35)], stops: const [0.5, 1], radius: 1.0).createShader(rect));
    canvas.drawRect(rect, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, const Color(0xFF0A0A0B).withValues(alpha: 0.85)], stops: const [0.55, 1]).createShader(rect));
  }

  void _exterior(Canvas canvas, Size size, Rng r, ValueNoise noise) {
    final w = size.width, h = size.height;
    final sky = _skies[time] ?? _skies['day']!;
    final rect = Offset.zero & size;
    final desert = location == 'desert';
    final top = desert ? Color.lerp(sky.top, const Color(0xFF8A5A30), 0.3)! : sky.top;
    canvas.drawRect(rect, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [top, sky.bottom]).createShader(rect));
    // celestial body
    final celestial = Offset(w * r.rangeD(0.15, 0.85), h * r.rangeD(0.12, 0.3));
    final isNight = time == 'night';
    canvas.drawCircle(celestial, h * 0.18, Paint()
      ..color = sky.glow.withValues(alpha: 0.18)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * 0.08));
    canvas.drawCircle(celestial, h * (isNight ? 0.05 : 0.06), Paint()..color = sky.glow.withValues(alpha: 0.95));
    if (isNight) {
      canvas.drawCircle(celestial.translate(h * 0.018, -h * 0.01), h * 0.045, Paint()..color = sky.top);
      final star = Paint()..color = Colors.white;
      for (var i = 0; i < 90; i++) {
        star.color = Colors.white.withValues(alpha: r.rangeD(0.2, 0.9));
        canvas.drawCircle(Offset(r.nextDouble() * w, r.nextDouble() * h * 0.6), r.rangeD(0.3, 1.3), star);
      }
    }
    // clouds
    for (var i = 0; i < 5; i++) {
      final cy = h * r.rangeD(0.08, 0.35);
      final cx = w * r.nextDouble();
      final cloud = Paint()
        ..color = Color.lerp(sky.bottom, Colors.white, isNight ? 0.05 : 0.3)!.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
      canvas.drawOval(Rect.fromCenter(center: Offset(cx, cy), width: w * r.rangeD(0.2, 0.45), height: h * 0.05), cloud);
    }
    final fogColor = Color.lerp(sky.bottom, Colors.black, 0.2)!;
    final layers = switch (location) {
      'mountain' || 'tundra' => [0.35, 0.5, 0.65],
      'coast' => [0.55, 0.62],
      'plains' || 'road' => [0.55, 0.65, 0.75],
      'desert' => [0.55, 0.65, 0.78],
      _ => [0.45, 0.58, 0.72],
    };
    for (var li = 0; li < layers.length; li++) {
      final base = h * layers[li];
      final amp = location == 'mountain' || location == 'tundra' ? h * (0.28 - li * 0.06) : h * (0.10 - li * 0.02);
      final col = Color.lerp(Color.lerp(fogColor, const Color(0xFF0A0806), (li + 1) / (layers.length + 1))!, desert ? const Color(0xFF6A4A2A) : (location == 'swamp' ? const Color(0xFF1A2A1A) : const Color(0xFF14201A)), li / layers.length * 0.4)!;
      final path = Path()..moveTo(0, h);
      for (var x = 0.0; x <= w; x += 4) {
        final n = noise.fbm(x / (w * (location == 'mountain' ? 0.25 : 0.4)) + li * 10, li * 3.3, octaves: 4);
        var y = base - n * amp * (location == 'mountain' || location == 'tundra' ? 1.6 : 1.0);
        if (desert) y = base - math.sin(x / w * math.pi * 2 + li) * amp * 0.6 - n * amp * 0.4;
        path.lineTo(x, y);
      }
      path
        ..lineTo(w, h)
        ..close();
      canvas.drawPath(path, Paint()..color = col);
      if ((location == 'mountain' || location == 'tundra') && li == 0) {
        // snow caps
        canvas.save();
        canvas.clipPath(path);
        canvas.drawRect(Rect.fromLTWH(0, 0, w, base - amp * 0.5), Paint()..color = Colors.white.withValues(alpha: 0.25));
        canvas.restore();
      }
      // trees on this layer
      if (['forest', 'swamp', 'road', 'camp', 'ruins', 'plains'].contains(location) && li >= 1) {
        final count = location == 'forest' ? 26 : (location == 'plains' ? 4 : 10);
        for (var i = 0; i < count; i++) {
          final x = r.nextDouble() * w;
          final n = noise.fbm(x / (w * 0.4) + li * 10, li * 3.3, octaves: 4);
          final y = base - n * amp + 6;
          final th = h * r.rangeD(0.08, 0.18) * (li == layers.length - 1 ? 1.5 : 1);
          if (location == 'swamp') {
            _deadTree(canvas, Offset(x, y), th, col);
          } else {
            _pine(canvas, Offset(x, y), th, Color.lerp(col, Colors.black, 0.2)!);
          }
        }
      }
    }
    // location features
    switch (location) {
      case 'town':
        _town(canvas, size, r);
      case 'castle':
        _castle(canvas, size, r);
      case 'ruins':
        _ruins(canvas, size, r);
      case 'coast':
        _sea(canvas, size, r, sky);
      case 'swamp':
        canvas.drawRect(Rect.fromLTWH(0, h * 0.75, w, h * 0.25), Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [const Color(0xFF1E2A22), const Color(0xFF0A100C)]).createShader(Rect.fromLTWH(0, h * 0.75, w, h * 0.25)));
        for (var i = 0; i < 14; i++) {
          final y = h * r.rangeD(0.77, 0.98);
          canvas.drawLine(Offset(r.nextDouble() * w, y), Offset(r.nextDouble() * w, y), Paint()
            ..color = sky.glow.withValues(alpha: 0.12)
            ..strokeWidth = 1);
        }
      case 'camp':
        _campfire(canvas, Offset(w * 0.5, h * 0.82), h * 0.12);
      case 'road':
        final road = Path()
          ..moveTo(w * 0.45, h * 0.6)
          ..quadraticBezierTo(w * 0.55, h * 0.75, w * 0.3, h)
          ..lineTo(w * 0.75, h)
          ..quadraticBezierTo(w * 0.6, h * 0.75, w * 0.52, h * 0.6)
          ..close();
        canvas.drawPath(road, Paint()..color = const Color(0xFF3A2E22).withValues(alpha: 0.8));
      default:
        break;
    }
    // ground fog
    canvas.drawRect(Rect.fromLTWH(0, h * 0.6, w, h * 0.4), Paint()
      ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, fogColor.withValues(alpha: 0.25), Colors.transparent]).createShader(Rect.fromLTWH(0, h * 0.6, w, h * 0.4)));
  }

  void _pine(Canvas canvas, Offset base, double h, Color c) {
    final p = Paint()..color = c;
    final w = h * 0.35;
    for (var i = 0; i < 3; i++) {
      final y = base.dy - h * (0.3 + i * 0.25);
      final ww = w * (1 - i * 0.25);
      canvas.drawPath(Path()..moveTo(base.dx, y - h * 0.35)..lineTo(base.dx + ww, y + h * 0.1)..lineTo(base.dx - ww, y + h * 0.1)..close(), p);
    }
    canvas.drawRect(Rect.fromLTWH(base.dx - h * 0.03, base.dy - h * 0.25, h * 0.06, h * 0.25), p);
  }

  void _deadTree(Canvas canvas, Offset base, double h, Color c) {
    final p = Paint()
      ..color = Color.lerp(c, Colors.black, 0.4)!
      ..strokeWidth = h * 0.05
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(base, base.translate(0, -h), p);
    p.strokeWidth = h * 0.025;
    canvas.drawLine(base.translate(0, -h * 0.6), base.translate(h * 0.3, -h * 0.9), p);
    canvas.drawLine(base.translate(0, -h * 0.4), base.translate(-h * 0.25, -h * 0.7), p);
  }

  void _town(Canvas canvas, Size size, Rng r) {
    final w = size.width, h = size.height;
    var x = -10.0;
    while (x < w) {
      final bw = w * r.rangeD(0.07, 0.13);
      final bh = h * r.rangeD(0.12, 0.24);
      final base = h * 0.78;
      final body = Rect.fromLTWH(x, base - bh, bw, bh);
      final col = Color.lerp(const Color(0xFF1A120C), const Color(0xFF2A1E14), r.nextDouble())!;
      canvas.drawRect(body, Paint()..color = col);
      canvas.drawPath(Path()..moveTo(x - 4, base - bh)..lineTo(x + bw / 2, base - bh - bh * 0.45)..lineTo(x + bw + 4, base - bh)..close(), Paint()..color = Color.lerp(col, Colors.black, 0.3)!);
      // windows
      for (var i = 0; i < 2; i++) {
        if (r.chance(0.6)) {
          final wr = Rect.fromLTWH(x + bw * (0.2 + i * 0.4), base - bh * r.rangeD(0.4, 0.8), bw * 0.18, bh * 0.14);
          canvas.drawRect(wr, Paint()..color = const Color(0xFFFFB040));
          canvas.drawCircle(wr.center, bw * 0.3, Paint()
            ..color = const Color(0xFFFFA030).withValues(alpha: 0.18)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
        }
      }
      if (r.chance(0.4)) {
        canvas.drawRect(Rect.fromLTWH(x + bw * 0.65, base - bh - bh * 0.5, bw * 0.12, bh * 0.3), Paint()..color = Color.lerp(col, Colors.black, 0.2)!);
      }
      x += bw + r.rangeD(2, 10);
    }
    canvas.drawRect(Rect.fromLTWH(0, h * 0.78, w, h * 0.22), Paint()..color = const Color(0xFF120C08));
  }

  void _castle(Canvas canvas, Size size, Rng r) {
    final w = size.width, h = size.height;
    final p = Paint()..color = const Color(0xFF0E0A0C);
    final cx = w * r.rangeD(0.35, 0.65);
    final base = h * 0.7;
    canvas.drawRect(Rect.fromLTWH(cx - w * 0.22, base - h * 0.18, w * 0.44, h * 0.3), p);
    for (final dx in [-0.22, -0.08, 0.08, 0.2]) {
      final tw = w * 0.06;
      final th = h * r.rangeD(0.28, 0.42);
      final tx = cx + w * dx;
      canvas.drawRect(Rect.fromLTWH(tx - tw / 2, base - th, tw, th + h * 0.1), p);
      canvas.drawPath(Path()..moveTo(tx - tw * 0.7, base - th)..lineTo(tx, base - th - h * 0.1)..lineTo(tx + tw * 0.7, base - th)..close(), p);
      if (r.chance(0.6)) canvas.drawRect(Rect.fromLTWH(tx - 2, base - th * 0.7, 4, 7), Paint()..color = const Color(0xFFFFA040));
    }
    for (var x = cx - w * 0.22; x < cx + w * 0.22; x += 10) {
      canvas.drawRect(Rect.fromLTWH(x, base - h * 0.18 - 6, 6, 6), p);
    }
  }

  void _ruins(Canvas canvas, Size size, Rng r) {
    final w = size.width, h = size.height;
    final p = Paint()..color = const Color(0xFF1A1612);
    for (var i = 0; i < 6; i++) {
      final x = w * r.nextDouble();
      final ph = h * r.rangeD(0.12, 0.3);
      final pw = w * 0.035;
      canvas.drawRect(Rect.fromLTWH(x, h * 0.8 - ph, pw, ph), p);
      canvas.drawRect(Rect.fromLTWH(x - pw * 0.2, h * 0.8 - ph, pw * 1.4, pw * 0.4), p);
    }
    canvas.drawRect(Rect.fromLTWH(0, h * 0.8, w, h * 0.2), Paint()..color = const Color(0xFF120E0A));
  }

  void _sea(Canvas canvas, Size size, Rng r, _Sky sky) {
    final w = size.width, h = size.height;
    final rect = Rect.fromLTWH(0, h * 0.62, w, h * 0.38);
    canvas.drawRect(rect, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color.lerp(sky.bottom, const Color(0xFF0A2030), 0.6)!, const Color(0xFF050A10)]).createShader(rect));
    for (var i = 0; i < 30; i++) {
      final y = h * r.rangeD(0.63, 0.95);
      final x = r.nextDouble() * w;
      canvas.drawLine(Offset(x, y), Offset(x + w * r.rangeD(0.03, 0.12), y), Paint()
        ..color = sky.glow.withValues(alpha: 0.18)
        ..strokeWidth = 1);
    }
  }

  void _campfire(Canvas canvas, Offset c, double s) {
    canvas.drawCircle(c, s * 2.2, Paint()
      ..color = const Color(0xFFFF8030).withValues(alpha: 0.25)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, s));
    final log = Paint()
      ..color = const Color(0xFF3A2414)
      ..strokeWidth = s * 0.18
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(c.translate(-s * 0.6, s * 0.2), c.translate(s * 0.6, -s * 0.05), log);
    canvas.drawLine(c.translate(s * 0.6, s * 0.2), c.translate(-s * 0.6, -s * 0.05), log);
    canvas.drawPath(Path()..moveTo(c.dx - s * 0.4, c.dy)..quadraticBezierTo(c.dx, c.dy - s * 1.4, c.dx + s * 0.4, c.dy)..close(), Paint()..color = const Color(0xFFFF9030));
    canvas.drawPath(Path()..moveTo(c.dx - s * 0.2, c.dy)..quadraticBezierTo(c.dx, c.dy - s * 0.8, c.dx + s * 0.2, c.dy)..close(), Paint()..color = const Color(0xFFFFE080));
  }

  void _interior(Canvas canvas, Size size, Rng r, ValueNoise noise) {
    final w = size.width, h = size.height;
    final rect = Offset.zero & size;
    final warm = location == 'tavern';
    final base = switch (location) {
      'tavern' => const Color(0xFF2A1A10),
      'crypt' => const Color(0xFF14161A),
      'cave' => const Color(0xFF16120E),
      'sewer' => const Color(0xFF121812),
      'temple' => const Color(0xFF1C1612),
      'tower' => const Color(0xFF16122A),
      _ => const Color(0xFF15110E),
    };
    canvas.drawRect(rect, Paint()..color = base);
    // stone blocks / cave texture
    if (location == 'cave') {
      for (var y = 0.0; y < h; y += 6) {
        for (var x = 0.0; x < w; x += 6) {
          final n = noise.fbm(x / 60, y / 60);
          canvas.drawRect(Rect.fromLTWH(x, y, 6, 6), Paint()..color = Color.lerp(base, const Color(0xFF3A3028), n * 0.7)!);
        }
      }
    } else {
      final brick = Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      final bh = h / 14;
      for (var row = 0; row < 14; row++) {
        final y = row * bh;
        final off = row.isEven ? 0.0 : bh;
        for (var x = -off; x < w; x += bh * 2) {
          final shade = r.rangeD(-0.08, 0.1);
          canvas.drawRect(Rect.fromLTWH(x, y, bh * 2, bh), Paint()..color = Color.lerp(base, shade > 0 ? Colors.white : Colors.black, shade.abs())!);
          canvas.drawRect(Rect.fromLTWH(x, y, bh * 2, bh), brick);
        }
      }
    }
    // central arch / passage
    final archW = w * 0.34;
    final archH = h * 0.62;
    final ax = w / 2 - archW / 2;
    final ay = h * 0.78 - archH;
    final arch = Path()
      ..moveTo(ax, h * 0.78)
      ..lineTo(ax, ay + archW / 2)
      ..arcToPoint(Offset(ax + archW, ay + archW / 2), radius: Radius.circular(archW / 2))
      ..lineTo(ax + archW, h * 0.78)
      ..close();
    canvas.drawPath(arch, Paint()..shader = RadialGradient(center: const Alignment(0, 0.3), colors: [warm ? const Color(0xFF6A4020) : const Color(0xFF1A1A22), Colors.black]).createShader(arch.getBounds()));
    canvas.drawPath(arch, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = Color.lerp(base, Colors.white, 0.08)!);
    // pillars
    for (final px in [w * 0.12, w * 0.88]) {
      canvas.drawRect(Rect.fromLTWH(px - w * 0.04, 0, w * 0.08, h * 0.85), Paint()..shader = LinearGradient(colors: [Color.lerp(base, Colors.black, 0.4)!, Color.lerp(base, Colors.white, 0.1)!, Color.lerp(base, Colors.black, 0.5)!]).createShader(Rect.fromLTWH(px - w * 0.04, 0, w * 0.08, h)));
    }
    // floor
    canvas.drawRect(Rect.fromLTWH(0, h * 0.78, w, h * 0.22), Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color.lerp(base, Colors.white, 0.05)!, Colors.black]).createShader(Rect.fromLTWH(0, h * 0.78, w, h * 0.22)));
    // torches
    for (final tx in [w * 0.25, w * 0.75]) {
      final tc = Offset(tx, h * 0.4);
      canvas.drawCircle(tc, h * 0.25, Paint()
        ..color = (location == 'tower' ? const Color(0xFF8A60FF) : const Color(0xFFFF8030)).withValues(alpha: 0.16)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * 0.1));
      canvas.drawRect(Rect.fromCenter(center: tc.translate(0, h * 0.04), width: 4, height: h * 0.07), Paint()..color = const Color(0xFF3A2414));
    }
    if (location == 'tavern') {
      // beams & tables
      for (var i = 0; i < 4; i++) {
        canvas.drawRect(Rect.fromLTWH(0, h * (0.05 + i * 0.001), w, h * 0.04), Paint()..color = const Color(0xFF1A0E06));
      }
      for (final tx in [0.2, 0.55, 0.85]) {
        canvas.drawOval(Rect.fromCenter(center: Offset(w * tx, h * 0.86), width: w * 0.2, height: h * 0.05), Paint()..color = const Color(0xFF4A2E18));
        canvas.drawCircle(Offset(w * tx, h * 0.82), 4, Paint()..color = const Color(0xFFFFC060));
      }
    }
    if (location == 'crypt' || location == 'temple') {
      for (final sx in [0.3, 0.7]) {
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(w * sx, h * 0.84), width: w * 0.16, height: h * 0.07), const Radius.circular(4)), Paint()..color = const Color(0xFF2A2A30));
      }
    }
  }

  @override
  bool shouldRepaint(covariant ScenePainter old) => old.location != location || old.time != time || old.mood != mood || old.seed != seed;
}

class _ParticlePainter extends CustomPainter {
  _ParticlePainter({required this.location, required this.time, required this.mood, required this.t, required this.seed});
  final String location;
  final String time;
  final String mood;
  final double t;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rng(seed + 17);
    final w = size.width, h = size.height;
    final kind = switch (location) {
      'tundra' || 'mountain' => 'snow',
      'forest' || 'swamp' when time == 'night' || time == 'dusk' => 'firefly',
      'dungeon' || 'cave' || 'crypt' || 'sewer' => 'dust',
      'camp' || 'tavern' || 'town' => 'ember',
      'tower' || 'temple' => 'arcane',
      _ => mood == 'combat' ? 'ember' : 'dust',
    };
    final n = kind == 'snow' ? 60 : 28;
    for (var i = 0; i < n; i++) {
      final bx = r.nextDouble();
      final by = r.nextDouble();
      final sp = r.rangeD(0.5, 1.5);
      final ph = r.nextDouble() * math.pi * 2;
      double x, y;
      Color c;
      double rad;
      switch (kind) {
        case 'snow':
          y = ((by + t * sp * 3) % 1.0) * h;
          x = (bx * w + math.sin(t * math.pi * 6 + ph) * 12) % w;
          c = Colors.white.withValues(alpha: 0.7);
          rad = r.rangeD(0.8, 2.2);
        case 'firefly':
          x = bx * w + math.sin(t * math.pi * 4 * sp + ph) * 20;
          y = h * (0.4 + by * 0.5) + math.cos(t * math.pi * 3 * sp + ph) * 14;
          final a = (math.sin(t * math.pi * 10 * sp + ph) + 1) / 2;
          c = const Color(0xFFE0FF80).withValues(alpha: a * 0.9);
          rad = 2;
        case 'ember':
          y = h - ((by + t * sp * 2) % 1.0) * h * 0.8;
          x = bx * w + math.sin(t * math.pi * 8 + ph) * 8;
          c = const Color(0xFFFF9040).withValues(alpha: 0.8 * (y / h));
          rad = r.rangeD(0.8, 1.8);
        case 'arcane':
          y = h - ((by + t * sp) % 1.0) * h;
          x = bx * w + math.sin(t * math.pi * 4 + ph) * 16;
          c = const Color(0xFFB090FF).withValues(alpha: 0.7);
          rad = r.rangeD(1, 2.2);
        default:
          x = (bx * w + t * sp * 40) % w;
          y = by * h + math.sin(t * math.pi * 2 * sp + ph) * 10;
          c = const Color(0xFFD9C8A0).withValues(alpha: 0.25);
          rad = r.rangeD(0.6, 1.4);
      }
      canvas.drawCircle(Offset(x, y), rad, Paint()..color = c);
      if (kind == 'firefly' || kind == 'arcane' || kind == 'ember') {
        canvas.drawCircle(Offset(x, y), rad * 3, Paint()
          ..color = c.withValues(alpha: c.a * 0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
      }
    }
    // flicker for interiors
    if (_isInterior(location) || location == 'camp') {
      final f = (math.sin(t * math.pi * 60) + math.sin(t * math.pi * 37)) * 0.02 + 0.04;
      canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFF8030).withValues(alpha: f.clamp(0, 0.1)));
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter old) => old.t != t;
}
