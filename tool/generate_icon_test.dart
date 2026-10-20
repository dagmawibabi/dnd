// Renders the launcher icon PNGs. Run with:
//   flutter test tool/generate_icon_test.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _bgTop = Color(0xFF1C1C1F);
const _bgBottom = Color(0xFF0A0A0B);

/// Geometric icosahedron (d20) seen face-on, lit from the top-left.
void paintD20(Canvas canvas, Offset c, double r) {
  Offset p(double x, double y) => c + Offset(x * r, y * r);
  final v = [p(0, -1), p(0.866, -0.5), p(0.866, 0.5), p(0, 1), p(-0.866, 0.5), p(-0.866, -0.5)];
  final t = p(0, -0.5), l = p(-0.47, 0.32), rr = p(0.47, 0.32);
  // facet, brightness 0..1
  final facets = <(List<Offset>, double)>[
    ([v[0], v[5], t], 0.78),
    ([v[0], v[1], t], 0.62),
    ([v[5], l, t], 0.58),
    ([v[1], t, rr], 0.42),
    ([v[5], v[4], l], 0.40),
    ([v[1], v[2], rr], 0.26),
    ([v[4], v[3], l], 0.22),
    ([v[2], v[3], rr], 0.14),
    ([l, rr, v[3]], 0.30),
  ];
  const dark = Color(0xFF26262A);
  const mid = Color(0xFF6B6B73);
  const light = Color(0xFFC9C9CF);
  for (final (pts, b) in facets) {
    final path = Path()..addPolygon(pts, true);
    final col = b < 0.5 ? Color.lerp(dark, mid, b / 0.5)! : Color.lerp(mid, light, (b - 0.5) / 0.5)!;
    canvas.drawPath(path, Paint()..color = col);
  }
  // Front face: brightest, with a soft vertical gradient.
  final front = Path()..addPolygon([t, l, rr], true);
  canvas.drawPath(
    front,
    Paint()
      ..shader = ui.Gradient.linear(t, Offset(c.dx, l.dy), const [Color(0xFFFAFAFA), Color(0xFFB4B4BA)]),
  );
  // Edges
  final edge = Paint()
    ..color = Colors.white.withValues(alpha: 0.85)
    ..style = PaintingStyle.stroke
    ..strokeWidth = r * 0.028
    ..strokeJoin = StrokeJoin.round;
  canvas.drawPath(Path()..addPolygon(v, true), edge);
  final inner = Paint()
    ..color = Colors.white.withValues(alpha: 0.45)
    ..style = PaintingStyle.stroke
    ..strokeWidth = r * 0.018
    ..strokeJoin = StrokeJoin.round;
  canvas.drawPath(front, inner);
  for (final (a, b) in [(v[0], t), (v[5], t), (v[1], t), (v[5], l), (v[4], l), (v[3], l), (v[1], rr), (v[2], rr), (v[3], rr)]) {
    canvas.drawLine(a, b, inner);
  }
  // A small geometric pip in the front face instead of a number.
  final pc = Offset(c.dx, (t.dy + l.dy * 2) / 3);
  final pip = Path()
    ..moveTo(pc.dx, pc.dy - r * 0.11)
    ..lineTo(pc.dx + r * 0.095, pc.dy + r * 0.055)
    ..lineTo(pc.dx - r * 0.095, pc.dy + r * 0.055)
    ..close();
  canvas.drawPath(pip, Paint()..color = const Color(0xFF26262A));
}

Future<void> _write(String path, int size, void Function(Canvas, Size) paint) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  paint(canvas, Size(size.toDouble(), size.toDouble()));
  final img = await rec.endRecording().toImage(size, size);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  final f = File(path)..createSync(recursive: true);
  f.writeAsBytesSync(data!.buffer.asUint8List());
}

void main() {
  test('generate launcher icons', () async {
    const size = 1024;
    // Full icon with background (iOS, web, desktop, legacy Android).
    await _write('assets/icon/icon.png', size, (canvas, s) {
      final rect = Offset.zero & s;
      canvas.drawRect(rect, Paint()..shader = ui.Gradient.radial(Offset(s.width * 0.35, s.height * 0.25), s.width * 0.95, const [_bgTop, _bgBottom]));
      // Faint geometric rings
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white.withValues(alpha: 0.05);
      for (var i = 1; i <= 3; i++) {
        canvas.drawCircle(s.center(Offset.zero), s.width * (0.24 + i * 0.09), ring);
      }
      canvas.drawCircle(s.center(Offset.zero), s.width * 0.36, Paint()
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.06)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 90));
      paintD20(canvas, s.center(Offset.zero), s.width * 0.33);
    });
    // Adaptive foreground: transparent, kept inside the 66% safe zone.
    await _write('assets/icon/icon_foreground.png', size, (canvas, s) {
      paintD20(canvas, s.center(Offset.zero), s.width * 0.25);
    });
    // Monochrome (Android 13 themed icons).
    await _write('assets/icon/icon_monochrome.png', size, (canvas, s) {
      final c = s.center(Offset.zero);
      final r = s.width * 0.25;
      final v = [for (var i = 0; i < 6; i++) c + Offset(math.cos(-math.pi / 2 + i * math.pi / 3), math.sin(-math.pi / 2 + i * math.pi / 3)) * r];
      canvas.drawPath(Path()..addPolygon(v, true), Paint()..color = Colors.white);
      final t = c + Offset(0, -0.5 * r), l = c + Offset(-0.47 * r, 0.32 * r), rr = c + Offset(0.47 * r, 0.32 * r);
      canvas.drawPath(Path()..addPolygon([t, l, rr], true), Paint()
        ..blendMode = BlendMode.clear
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.06);
    });
    expect(File('assets/icon/icon.png').existsSync(), isTrue);
  });
}
