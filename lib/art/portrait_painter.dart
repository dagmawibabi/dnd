import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/srd.dart';
import '../game/dice.dart';
import '../models/character.dart';

const _bgPalettes = [
  [Color(0xFF26262B)],
  [Color(0xFF1F2633)],
  [Color(0xFF29233A)],
  [Color(0xFF1E2B25)],
  [Color(0xFF2E2820)],
  [Color(0xFF2B2124)],
];

Color _shade(Color c, double amt) => amt >= 0 ? Color.lerp(c, Colors.white, amt)! : Color.lerp(c, Colors.black, -amt)!;

/// Procedurally painted character bust, in the spirit of generated avatars.
class PortraitPainter extends CustomPainter {
  PortraitPainter({required this.spec, required this.raceId, this.classId, this.frame = true});

  final PortraitSpec spec;
  final String raceId;
  final String? classId;
  final bool frame;

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    canvas.save();
    canvas.translate((size.width - s) / 2, (size.height - s) / 2);
    canvas.scale(s / 200);
    final rect = const Rect.fromLTWH(0, 0, 200, 200);
    final r = Rng(spec.seed);
    final race = raceById(raceId);
    final cls = classId == null ? null : classById(classId!);
    final accent = cls?.color ?? const Color(0xFFC9A55C);

    // Flat, muted background
    final pal = _bgPalettes[spec.background % _bgPalettes.length];
    canvas.drawRect(rect, Paint()..color = Color.lerp(pal[0], accent, 0.12)!);

    final skin = spec.skin;
    final hair = spec.hair;
    final fem = spec.feminine;
    final isDragon = race.scales;
    final small = race.size == 'Small';
    final headScale = small ? 1.08 : 1.0;
    final headW = (race.id == 'half-orc' || race.id == 'dwarf' ? 62.0 : 56.0) - fem * 5;
    final headH = 72.0 - (race.id == 'dwarf' ? 4 : 0);
    const cx = 100.0;
    final cy = small ? 92.0 : 88.0;

    // Back hair
    if (!isDragon) _backHair(canvas, cx, cy, headW, headH, hair, spec.hairStyle);

    // Shoulders / outfit
    _outfit(canvas, accent, cls, skin, r);

    // Neck
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, cy + headH * 0.55), width: headW * 0.48, height: 34), const Radius.circular(10)),
      Paint()..color = _shade(skin, -0.25),
    );

    canvas.save();
    canvas.translate(cx, cy);
    canvas.scale(headScale);
    canvas.translate(-cx, -cy);

    // Ears behind head
    _ears(canvas, cx, cy, headW, skin, race.earStyle, isDragon);

    if (isDragon) {
      _dragonHead(canvas, cx, cy, skin, spec.eyes, r);
    } else {
      // Head
      final jaw = 0.62 + fem * 0.18;
      final head = Path()
        ..moveTo(cx, cy - headH / 2)
        ..cubicTo(cx + headW / 2 + 2, cy - headH / 2, cx + headW / 2 + 2, cy + 4, cx + headW / 2 * jaw + 4, cy + headH * 0.32)
        ..quadraticBezierTo(cx, cy + headH / 2 + 4 - fem * 3, cx - headW / 2 * jaw - 4, cy + headH * 0.32)
        ..cubicTo(cx - headW / 2 - 2, cy + 4, cx - headW / 2 - 2, cy - headH / 2, cx, cy - headH / 2)
        ..close();
      canvas.drawPath(
        head,
        Paint()
          ..shader = RadialGradient(center: const Alignment(-0.3, -0.3), radius: 1.0, colors: [_shade(skin, 0.12), skin, _shade(skin, -0.3)])
              .createShader(Rect.fromCenter(center: Offset(cx, cy), width: headW, height: headH)),
      );
      // Cheek blush
      canvas.drawCircle(Offset(cx - 15, cy + 10), 7, Paint()..color = const Color(0xFFE07070).withValues(alpha: 0.10 + fem * 0.08));
      canvas.drawCircle(Offset(cx + 15, cy + 10), 7, Paint()..color = const Color(0xFFE07070).withValues(alpha: 0.10 + fem * 0.08));

      _eyes(canvas, cx, cy, spec.eyes, fem, hair, race.id == 'tiefling' || (race.id == 'elf' && spec.seed.isOdd));
      // Nose
      final nose = Path()
        ..moveTo(cx - 1, cy + 2)
        ..quadraticBezierTo(cx + 4, cy + 12, cx - 3, cy + 14);
      canvas.drawPath(nose, Paint()
        ..color = _shade(skin, -0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round);
      // Mouth
      final smile = (r.nextDouble() - 0.4) * 4;
      final mouth = Path()
        ..moveTo(cx - 8 + fem, cy + 22)
        ..quadraticBezierTo(cx, cy + 23 + smile, cx + 8 - fem, cy + 22);
      canvas.drawPath(mouth, Paint()
        ..color = Color.lerp(_shade(skin, -0.45), const Color(0xFF8A2A2A), fem * 0.6)!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 + fem
        ..strokeCap = StrokeCap.round);
      if (race.tusks) {
        final tusk = Paint()..color = const Color(0xFFEDE3D1);
        canvas.drawPath(Path()..moveTo(cx - 8, cy + 23)..lineTo(cx - 10, cy + 15)..lineTo(cx - 5, cy + 22)..close(), tusk);
        canvas.drawPath(Path()..moveTo(cx + 8, cy + 23)..lineTo(cx + 10, cy + 15)..lineTo(cx + 5, cy + 22)..close(), tusk);
      }
      if (spec.beard > 0) _beard(canvas, cx, cy, headW, hair, spec.beard);
      if (spec.scar) {
        canvas.drawLine(Offset(cx + 12, cy - 12), Offset(cx + 22, cy + 8), Paint()
          ..color = _shade(skin, -0.4).withValues(alpha: 0.8)
          ..strokeWidth = 1.6);
      }
      if (spec.accessory == 5) {
        final paint = Paint()..color = accent.withValues(alpha: 0.75);
        canvas.drawRect(Rect.fromLTWH(cx - 24, cy - 2, 10, 3), paint);
        canvas.drawRect(Rect.fromLTWH(cx + 14, cy - 2, 10, 3), paint);
        canvas.drawRect(Rect.fromLTWH(cx - 2, cy - 30, 4, 12), paint);
      }
      // Front hair
      _frontHair(canvas, cx, cy, headW, headH, hair, spec.hairStyle);
      if (race.horns) _horns(canvas, cx, cy, headW, headH, r);
    }
    _accessory(canvas, cx, cy, headW, headH, accent, spec.accessory, isDragon);
    canvas.restore();

    canvas.restore();
  }

  void _outfit(Canvas canvas, Color accent, ClassDef? cls, Color skin, Rng r) {
    final id = cls?.id ?? 'fighter';
    final heavy = ['fighter', 'paladin', 'cleric'].contains(id);
    final robe = ['wizard', 'sorcerer', 'warlock', 'druid'].contains(id);
    final base = heavy
        ? const Color(0xFF8A8F99)
        : robe
            ? Color.lerp(accent, Colors.black, 0.45)!
            : Color.lerp(const Color(0xFF5A3E28), accent, 0.2)!;
    final body = Path()
      ..moveTo(18, 200)
      ..cubicTo(22, 150, 50, 132, 100, 130)
      ..cubicTo(150, 132, 178, 150, 182, 200)
      ..close();
    canvas.drawPath(body, Paint()..shader = LinearGradient(colors: [_shade(base, 0.15), base, _shade(base, -0.4)], begin: Alignment.topLeft, end: Alignment.bottomRight).createShader(const Rect.fromLTWH(18, 130, 164, 70)));
    if (heavy) {
      // pauldrons
      for (final x in [42.0, 158.0]) {
        canvas.drawOval(Rect.fromCenter(center: Offset(x, 158), width: 54, height: 34), Paint()..shader = RadialGradient(colors: [_shade(base, 0.35), _shade(base, -0.3)]).createShader(Rect.fromCenter(center: Offset(x, 158), width: 54, height: 34)));
        canvas.drawOval(Rect.fromCenter(center: Offset(x, 158), width: 54, height: 34), Paint()
          ..style = PaintingStyle.stroke
          ..color = accent.withValues(alpha: 0.8)
          ..strokeWidth = 2);
      }
      // tabard
      canvas.drawPath(Path()..moveTo(80, 140)..lineTo(120, 140)..lineTo(114, 200)..lineTo(86, 200)..close(), Paint()..color = Color.lerp(accent, Colors.black, 0.3)!);
      _miniSigil(canvas, const Offset(100, 168), accent);
    } else if (robe) {
      // collar
      final collar = Path()
        ..moveTo(68, 136)
        ..lineTo(100, 175)
        ..lineTo(132, 136)
        ..lineTo(124, 132)
        ..lineTo(100, 160)
        ..lineTo(76, 132)
        ..close();
      canvas.drawPath(collar, Paint()..color = accent.withValues(alpha: 0.9));
      canvas.drawLine(const Offset(100, 175), const Offset(100, 200), Paint()
        ..color = accent.withValues(alpha: 0.6)
        ..strokeWidth = 2);
    } else {
      // leather straps / cloak
      canvas.drawLine(const Offset(60, 145), const Offset(130, 200), Paint()
        ..color = _shade(base, -0.5)
        ..strokeWidth = 7);
      canvas.drawCircle(const Offset(84, 163), 4, Paint()..color = accent);
      final cloak = Path()
        ..moveTo(18, 200)
        ..cubicTo(20, 160, 40, 140, 66, 134)
        ..lineTo(74, 150)
        ..cubicTo(52, 160, 40, 180, 40, 200)
        ..close();
      canvas.drawPath(cloak, Paint()..color = Color.lerp(accent, Colors.black, 0.55)!);
      canvas.drawPath(cloak.transform((Matrix4.identity()..translateByDouble(200.0, 0.0, 0.0, 1.0)..scaleByDouble(-1.0, 1.0, 1.0, 1.0)).storage), Paint()..color = Color.lerp(accent, Colors.black, 0.55)!);
    }
    // neckline skin
    canvas.drawPath(Path()..moveTo(86, 132)..quadraticBezierTo(100, 146, 114, 132)..close(), Paint()..color = _shade(skin, -0.2));
  }

  void _miniSigil(Canvas canvas, Offset c, Color accent) {
    final p = Paint()
      ..color = _shade(accent, 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    canvas.drawCircle(c, 7, p);
    canvas.drawLine(c.translate(0, -10), c.translate(0, 10), p);
    canvas.drawLine(c.translate(-10, 0), c.translate(10, 0), p);
  }

  void _ears(Canvas canvas, double cx, double cy, double headW, Color skin, int style, bool dragon) {
    if (dragon) return;
    final p = Paint()..color = _shade(skin, -0.12);
    for (final side in [-1.0, 1.0]) {
      final x = cx + side * headW / 2;
      final path = Path()..moveTo(x, cy - 6);
      if (style == 0) {
        path.quadraticBezierTo(x + side * 10, cy - 2, x + side * 2, cy + 12);
      } else if (style == 1) {
        path.quadraticBezierTo(x + side * 14, cy - 14, x + side * 2, cy + 12);
      } else {
        path
          ..lineTo(x + side * 30, cy - 24)
          ..quadraticBezierTo(x + side * 12, cy + 2, x + side * 2, cy + 12);
      }
      path.close();
      canvas.drawPath(path, p);
    }
  }

  void _eyes(Canvas canvas, double cx, double cy, Color iris, double fem, Color hair, bool solid) {
    for (final side in [-1.0, 1.0]) {
      final c = Offset(cx + side * 13, cy - 2);
      final white = Path()
        ..moveTo(c.dx - 8, c.dy)
        ..quadraticBezierTo(c.dx, c.dy - 6 - fem * 1.5, c.dx + 8, c.dy)
        ..quadraticBezierTo(c.dx, c.dy + 5, c.dx - 8, c.dy)
        ..close();
      canvas.drawPath(white, Paint()..color = solid ? iris : const Color(0xFFF2EDE4));
      if (!solid) {
        canvas.save();
        canvas.clipPath(white);
        canvas.drawCircle(c, 4.2, Paint()..color = iris);
        canvas.drawCircle(c, 2, Paint()..color = Colors.black);
        canvas.drawCircle(c.translate(-1.2, -1.4), 1, Paint()..color = Colors.white);
        canvas.restore();
      } else {
        canvas.drawPath(white, Paint()
          ..color = iris.withValues(alpha: 0.6)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
      }
      canvas.drawPath(
        Path()
          ..moveTo(c.dx - 9, c.dy)
          ..quadraticBezierTo(c.dx, c.dy - 7 - fem * 1.5, c.dx + 9, c.dy - 1),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4 + fem * 0.8,
      );
      // brow
      final brow = Path()
        ..moveTo(c.dx - 9 * side.sign, c.dy - 10 + fem * 0)
        ..quadraticBezierTo(c.dx, c.dy - 13 - fem * 2, c.dx + 9 * side.sign, c.dy - 9 - (side > 0 ? 0 : 0));
      canvas.drawPath(brow, Paint()
        ..color = _shade(hair, -0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2 - fem * 1.4
        ..strokeCap = StrokeCap.round);
    }
  }

  void _backHair(Canvas canvas, double cx, double cy, double w, double h, Color hair, int style) {
    final p = Paint()..shader = LinearGradient(colors: [_shade(hair, 0.15), _shade(hair, -0.35)], begin: Alignment.topCenter, end: Alignment.bottomCenter).createShader(Rect.fromLTWH(cx - 60, cy - 50, 120, 140));
    switch (style) {
      case 1: // long straight
      case 6:
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(cx - w / 2 - 8, cy - h / 2 - 2, cx + w / 2 + 8, cy + (style == 6 ? 70 : 55)), const Radius.circular(26)), p);
      case 4: // braid
        canvas.drawOval(Rect.fromCenter(center: Offset(cx, cy - 6), width: w + 14, height: h + 6), p);
        for (var i = 0; i < 5; i++) {
          canvas.drawOval(Rect.fromCenter(center: Offset(cx + w / 2 + 2, cy + 20 + i * 11.0), width: 12, height: 14), p);
        }
      case 3: // ponytail
        canvas.drawOval(Rect.fromCenter(center: Offset(cx, cy - 8), width: w + 12, height: h + 2), p);
        canvas.drawPath(Path()..moveTo(cx + 10, cy - h / 2)..quadraticBezierTo(cx + 60, cy - 10, cx + 34, cy + 60)..quadraticBezierTo(cx + 30, cy + 10, cx + 10, cy - h / 2 + 10)..close(), p);
      case 7: // mohawk / shaved: none
        break;
      default:
        canvas.drawOval(Rect.fromCenter(center: Offset(cx, cy - 6), width: w + 12, height: h + 4), p);
    }
  }

  void _frontHair(Canvas canvas, double cx, double cy, double w, double h, Color hair, int style) {
    final p = Paint()..shader = LinearGradient(colors: [_shade(hair, 0.2), hair, _shade(hair, -0.25)], begin: Alignment.topLeft, end: Alignment.bottomRight).createShader(Rect.fromLTWH(cx - 40, cy - 50, 80, 60));
    final top = cy - h / 2;
    switch (style) {
      case 0: // short messy
        final path = Path()..moveTo(cx - w / 2 - 2, cy - 6);
        for (var i = 0; i <= 8; i++) {
          final x = cx - w / 2 + i * w / 8;
          path.lineTo(x, top + (i.isEven ? 4 : 14));
        }
        path
          ..lineTo(cx + w / 2 + 2, cy - 6)
          ..quadraticBezierTo(cx + w / 2 + 4, top - 8, cx, top - 8)
          ..quadraticBezierTo(cx - w / 2 - 4, top - 8, cx - w / 2 - 2, cy - 6)
          ..close();
        canvas.drawPath(path, p);
      case 2: // swept
        canvas.drawPath(
            Path()
              ..moveTo(cx - w / 2 - 3, cy - 2)
              ..quadraticBezierTo(cx - w / 2 - 4, top - 10, cx + 6, top - 8)
              ..quadraticBezierTo(cx + w / 2 + 6, top - 4, cx + w / 2 + 3, cy - 4)
              ..quadraticBezierTo(cx + 10, top + 4, cx - w / 2 + 6, top + 18)
              ..close(),
            p);
      case 5: // bald/top knot for dwarves
        canvas.drawOval(Rect.fromCenter(center: Offset(cx, top - 4), width: 18, height: 14), p);
      case 7: // mohawk
        canvas.drawPath(Path()..moveTo(cx - 6, top + 6)..lineTo(cx, top - 16)..lineTo(cx + 6, top + 6)..close(), p);
        canvas.drawRect(Rect.fromLTWH(cx - 5, top - 10, 10, 30), p);
      default: // parted / fringe
        canvas.drawPath(
            Path()
              ..moveTo(cx - w / 2 - 3, cy + 6)
              ..quadraticBezierTo(cx - w / 2 - 2, top - 10, cx, top - 8)
              ..quadraticBezierTo(cx + w / 2 + 2, top - 10, cx + w / 2 + 3, cy + 6)
              ..quadraticBezierTo(cx + w / 2 - 6, top + 10, cx + 2, top + 12)
              ..quadraticBezierTo(cx - w / 2 + 6, top + 10, cx - w / 2 - 3, cy + 6)
              ..close(),
            p);
    }
  }

  void _beard(Canvas canvas, double cx, double cy, double w, Color hair, int style) {
    final p = Paint()..color = _shade(hair, -0.05);
    if (style == 1) {
      // stubble / goatee
      canvas.drawOval(Rect.fromCenter(center: Offset(cx, cy + 30), width: 16, height: 12), p..color = hair.withValues(alpha: 0.85));
      canvas.drawLine(Offset(cx - 9, cy + 17), Offset(cx + 9, cy + 17), Paint()
        ..color = hair
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round);
    } else {
      final len = style == 3 ? 44.0 : 26.0;
      final path = Path()
        ..moveTo(cx - w / 2 + 2, cy + 4)
        ..quadraticBezierTo(cx - w / 2 + 4, cy + 30, cx - 10, cy + len)
        ..lineTo(cx, cy + len + 8)
        ..lineTo(cx + 10, cy + len)
        ..quadraticBezierTo(cx + w / 2 - 4, cy + 30, cx + w / 2 - 2, cy + 4)
        ..quadraticBezierTo(cx + 12, cy + 18, cx, cy + 18)
        ..quadraticBezierTo(cx - 12, cy + 18, cx - w / 2 + 2, cy + 4)
        ..close();
      canvas.drawPath(path, p);
      canvas.drawPath(
          Path()
            ..moveTo(cx - 8, cy + 23)
            ..quadraticBezierTo(cx, cy + 24, cx + 8, cy + 23),
          Paint()
            ..color = Colors.black.withValues(alpha: 0.5)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
      if (style == 3) {
        for (final dx in [-6.0, 6.0]) {
          canvas.drawCircle(Offset(cx + dx, cy + len - 2), 2.5, Paint()..color = const Color(0xFFC9A55C));
        }
      }
    }
  }

  void _horns(Canvas canvas, double cx, double cy, double w, double h, Rng r) {
    final p = Paint()..shader = const LinearGradient(colors: [Color(0xFF3A2A2A), Color(0xFF8A7A6A)], begin: Alignment.bottomCenter, end: Alignment.topCenter).createShader(Rect.fromLTWH(cx - 60, cy - 80, 120, 60));
    final curl = r.nextDouble() * 10;
    for (final side in [-1.0, 1.0]) {
      final bx = cx + side * 14;
      final by = cy - h / 2 + 8;
      final path = Path()
        ..moveTo(bx - side * 5, by)
        ..quadraticBezierTo(bx + side * (24 + curl), by - 26, bx + side * (30 + curl), by - 44)
        ..quadraticBezierTo(bx + side * (12 + curl), by - 24, bx + side * 6, by + 2)
        ..close();
      canvas.drawPath(path, p);
    }
  }

  void _dragonHead(Canvas canvas, double cx, double cy, Color skin, Color eyes, Rng r) {
    final head = Path()
      ..moveTo(cx - 30, cy - 30)
      ..quadraticBezierTo(cx, cy - 46, cx + 30, cy - 30)
      ..quadraticBezierTo(cx + 36, cy, cx + 22, cy + 22)
      ..quadraticBezierTo(cx + 12, cy + 42, cx, cy + 44)
      ..quadraticBezierTo(cx - 12, cy + 42, cx - 22, cy + 22)
      ..quadraticBezierTo(cx - 36, cy, cx - 30, cy - 30)
      ..close();
    canvas.drawPath(head, Paint()..shader = RadialGradient(center: const Alignment(-0.3, -0.4), colors: [_shade(skin, 0.2), skin, _shade(skin, -0.45)]).createShader(Rect.fromCenter(center: Offset(cx, cy), width: 80, height: 90)));
    // scales
    final sp = Paint()
      ..color = _shade(skin, -0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var y = -24.0; y < 30; y += 9) {
      for (var x = -24.0; x < 26; x += 10) {
        canvas.drawArc(Rect.fromCenter(center: Offset(cx + x + (y % 18 == 0 ? 5 : 0), cy + y), width: 9, height: 7), 0, math.pi, false, sp);
      }
    }
    // frills / horns
    final hp = Paint()..color = _shade(skin, -0.5);
    for (final side in [-1.0, 1.0]) {
      canvas.drawPath(Path()..moveTo(cx + side * 22, cy - 34)..lineTo(cx + side * 46, cy - 62)..lineTo(cx + side * 30, cy - 26)..close(), hp);
      canvas.drawPath(Path()..moveTo(cx + side * 30, cy - 6)..lineTo(cx + side * 50, cy - 2)..lineTo(cx + side * 30, cy + 10)..close(), hp);
      final e = Offset(cx + side * 13, cy - 10);
      canvas.drawOval(Rect.fromCenter(center: e, width: 14, height: 7), Paint()..color = eyes);
      canvas.drawOval(Rect.fromCenter(center: e, width: 3, height: 7), Paint()..color = Colors.black);
      canvas.drawCircle(Offset(cx + side * 5, cy + 32), 1.8, Paint()..color = Colors.black);
    }
    canvas.drawPath(Path()..moveTo(cx - 12, cy + 38)..quadraticBezierTo(cx, cy + 42, cx + 12, cy + 38), Paint()
      ..color = Colors.black54
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);
  }

  void _accessory(Canvas canvas, double cx, double cy, double w, double h, Color accent, int a, bool dragon) {
    final gold = const Color(0xFFD9B46A);
    switch (a) {
      case 1: // circlet
        canvas.drawArc(Rect.fromCenter(center: Offset(cx, cy - 18), width: w + 6, height: 28), math.pi * 1.05, math.pi * 0.9, false, Paint()
          ..color = gold
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5);
        canvas.drawCircle(Offset(cx, cy - 32), 3.5, Paint()..color = accent);
      case 2: // hood
        final hood = Path()
          ..moveTo(cx - w / 2 - 16, cy + 40)
          ..quadraticBezierTo(cx - w / 2 - 18, cy - h / 2 - 20, cx, cy - h / 2 - 22)
          ..quadraticBezierTo(cx + w / 2 + 18, cy - h / 2 - 20, cx + w / 2 + 16, cy + 40)
          ..lineTo(cx + w / 2 + 4, cy + 40)
          ..quadraticBezierTo(cx + w / 2 + 6, cy - h / 2 - 6, cx, cy - h / 2 - 8)
          ..quadraticBezierTo(cx - w / 2 - 6, cy - h / 2 - 6, cx - w / 2 - 4, cy + 40)
          ..close();
        canvas.drawPath(hood, Paint()..color = Color.lerp(accent, Colors.black, 0.6)!);
      case 3: // earring
        if (!dragon) {
          canvas.drawCircle(Offset(cx - w / 2 - 1, cy + 14), 3, Paint()
            ..color = gold
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
        }
      case 4: // eyepatch
        canvas.drawLine(Offset(cx - w / 2, cy - 14), Offset(cx + w / 2, cy - 2), Paint()
          ..color = Colors.black87
          ..strokeWidth = 1.5);
        canvas.drawOval(Rect.fromCenter(center: Offset(cx + 13, cy - 2), width: 16, height: 12), Paint()..color = const Color(0xFF1B1210));
    }
  }

  @override
  bool shouldRepaint(covariant PortraitPainter old) => true;
}
