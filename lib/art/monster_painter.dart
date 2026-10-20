import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/dice.dart';

/// Painted creature token for enemies (and NPC silhouettes).
class MonsterPainter extends CustomPainter {
  MonsterPainter({required this.type, required this.color, required this.seed, this.hurt = 0, this.down = false});
  final String type;
  final Color color;
  final int seed;
  final double hurt;
  final bool down;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    canvas.save();
    canvas.translate((size.width - s) / 2, (size.height - s) / 2);
    canvas.scale(s / 100);
    const c = Offset(50, 50);
    final r = Rng(seed);
    final rect = Rect.fromCircle(center: c, radius: 50);
    canvas.save();
    canvas.clipPath(Path()..addOval(rect));
    canvas.drawRect(rect, Paint()..shader = RadialGradient(colors: [Color.lerp(color, Colors.black, 0.55)!, const Color(0xFF0A0605)]).createShader(rect));
    final eye = type == 'undead' ? const Color(0xFF7FE0FF) : (type == 'dragon' ? const Color(0xFFFFC040) : const Color(0xFFFF4030));
    final body = Paint()..shader = LinearGradient(colors: [Color.lerp(color, Colors.white, 0.15)!, color, Color.lerp(color, Colors.black, 0.6)!], begin: Alignment.topLeft, end: Alignment.bottomRight).createShader(rect);
    switch (type) {
      case 'undead':
        // skull
        canvas.drawOval(const Rect.fromLTWH(26, 18, 48, 50), body);
        canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(36, 58, 28, 18), const Radius.circular(4)), body);
        for (final dx in [-11.0, 11.0]) {
          canvas.drawOval(Rect.fromCenter(center: Offset(50 + dx, 44), width: 14, height: 16), Paint()..color = Colors.black);
          canvas.drawCircle(Offset(50 + dx, 45), 3, Paint()
            ..color = eye
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
        }
        canvas.drawPath(Path()..moveTo(50, 52)..lineTo(46, 60)..lineTo(54, 60)..close(), Paint()..color = Colors.black);
        for (var x = 40.0; x <= 60; x += 5) {
          canvas.drawLine(Offset(x, 64), Offset(x, 74), Paint()
            ..color = Colors.black
            ..strokeWidth = 1.2);
        }
      case 'beast':
        // wolf-like head
        final head = Path()
          ..moveTo(22, 30)
          ..lineTo(36, 40)
          ..quadraticBezierTo(50, 32, 64, 40)
          ..lineTo(78, 30)
          ..lineTo(74, 54)
          ..quadraticBezierTo(66, 80, 50, 86)
          ..quadraticBezierTo(34, 80, 26, 54)
          ..close();
        canvas.drawPath(head, body);
        for (final dx in [-12.0, 12.0]) {
          canvas.drawPath(Path()..moveTo(50 + dx - 6, 52)..lineTo(50 + dx + 6, 50)..lineTo(50 + dx, 56)..close(), Paint()..color = eye);
        }
        canvas.drawOval(const Rect.fromLTWH(44, 70, 12, 8), Paint()..color = Colors.black);
      case 'dragon':
        final head = Path()
          ..moveTo(50, 20)
          ..quadraticBezierTo(76, 30, 70, 60)
          ..lineTo(60, 88)
          ..lineTo(40, 88)
          ..lineTo(30, 60)
          ..quadraticBezierTo(24, 30, 50, 20)
          ..close();
        canvas.drawPath(head, body);
        for (final s in [-1.0, 1.0]) {
          canvas.drawPath(Path()..moveTo(50 + s * 14, 26)..lineTo(50 + s * 36, 4)..lineTo(50 + s * 22, 32)..close(), Paint()..color = Color.lerp(color, Colors.black, 0.5)!);
          canvas.drawOval(Rect.fromCenter(center: Offset(50 + s * 11, 46), width: 12, height: 6), Paint()..color = eye);
          canvas.drawCircle(Offset(50 + s * 5, 82), 1.6, Paint()..color = Colors.black);
        }
      case 'ooze':
        final blob = Path()..moveTo(18, 80);
        for (var i = 0; i <= 8; i++) {
          final x = 18 + i * 8.0;
          blob.quadraticBezierTo(x + 4, 30 + r.nextDouble() * 18, x + 8, 80);
        }
        blob.close();
        canvas.drawPath(blob, Paint()..color = color.withValues(alpha: 0.75));
        canvas.drawCircle(const Offset(40, 58), 6, Paint()..color = Colors.white.withValues(alpha: 0.4));
        canvas.drawCircle(const Offset(60, 64), 3, Paint()..color = Colors.white.withValues(alpha: 0.3));
      case 'construct':
        canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(28, 20, 44, 58), const Radius.circular(10)), body);
        canvas.drawRect(const Rect.fromLTWH(32, 42, 36, 6), Paint()..color = Colors.black);
        canvas.drawRect(const Rect.fromLTWH(34, 43, 32, 4), Paint()
          ..color = eye
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
        canvas.drawLine(const Offset(50, 50), const Offset(50, 76), Paint()
          ..color = Colors.black54
          ..strokeWidth = 2);
      case 'giant':
        canvas.drawOval(const Rect.fromLTWH(18, 16, 64, 72), body);
        for (final dx in [-12.0, 12.0]) {
          canvas.drawCircle(Offset(50 + dx, 44), 4, Paint()..color = eye);
        }
        canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(34, 62, 32, 8), const Radius.circular(3)), Paint()..color = Colors.black87);
        canvas.drawPath(Path()..moveTo(36, 62)..lineTo(38, 54)..lineTo(41, 62)..close(), Paint()..color = const Color(0xFFEDE3D1));
        canvas.drawPath(Path()..moveTo(64, 62)..lineTo(62, 54)..lineTo(59, 62)..close(), Paint()..color = const Color(0xFFEDE3D1));
      case 'monstrosity':
        canvas.drawOval(const Rect.fromLTWH(20, 22, 60, 62), body);
        final eyes = 2 + r.nextInt(4);
        for (var i = 0; i < eyes; i++) {
          final x = 32 + i * (36 / math.max(1, eyes - 1));
          canvas.drawCircle(Offset(x, 40 + (i.isEven ? 0 : 6)), 3.5, Paint()..color = eye);
        }
        final maw = Path()..moveTo(30, 62)..quadraticBezierTo(50, 82, 70, 62)..close();
        canvas.drawPath(maw, Paint()..color = Colors.black);
        for (var x = 34.0; x < 68; x += 6) {
          canvas.drawPath(Path()..moveTo(x, 63)..lineTo(x + 3, 70)..lineTo(x + 6, 63)..close(), Paint()..color = const Color(0xFFEDE3D1));
        }
      default:
        // hooded humanoid
        final hood = Path()
          ..moveTo(50, 14)
          ..quadraticBezierTo(80, 22, 78, 60)
          ..lineTo(90, 100)
          ..lineTo(10, 100)
          ..lineTo(22, 60)
          ..quadraticBezierTo(20, 22, 50, 14)
          ..close();
        canvas.drawPath(hood, body);
        canvas.drawOval(const Rect.fromLTWH(34, 34, 32, 36), Paint()..color = const Color(0xFF0A0605));
        for (final dx in [-7.0, 7.0]) {
          canvas.drawCircle(Offset(50 + dx, 50), 2.6, Paint()
            ..color = eye
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5));
        }
    }
    if (hurt > 0) {
      canvas.drawRect(rect, Paint()..color = const Color(0xFFFF0000).withValues(alpha: hurt * 0.4));
    }
    if (down) {
      canvas.drawRect(rect, Paint()..color = Colors.black.withValues(alpha: 0.6));
      final x = Paint()
        ..color = const Color(0xFFB3202A)
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(const Offset(30, 30), const Offset(70, 70), x);
      canvas.drawLine(const Offset(70, 30), const Offset(30, 70), x);
    }
    canvas.restore();
    canvas.drawCircle(c, 48.5, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFF303036));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant MonsterPainter old) => old.hurt != hurt || old.down != down || old.seed != seed || old.type != type;
}
