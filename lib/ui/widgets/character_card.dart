import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../art/class_icon.dart';
import '../../data/srd.dart';
import '../../game/dice.dart';
import '../../models/character.dart';
import '../../services/export.dart';
import '../../theme/ui.dart';
import 'portrait.dart';

/// Opens a preview of a shareable character card with share/save actions.
void showCharacterCard(BuildContext context, Character c) {
  showAppSheet(context, builder: (ctx) => _CardSheet(character: c));
}

enum CardStyle { poster, classic, tarot, minimal }

const _styleLabels = {CardStyle.poster: 'Poster', CardStyle.classic: 'Classic', CardStyle.tarot: 'Tarot', CardStyle.minimal: 'Minimal'};

class _CardSheet extends StatefulWidget {
  const _CardSheet({required this.character});
  final Character character;

  @override
  State<_CardSheet> createState() => _CardSheetState();
}

class _CardSheetState extends State<_CardSheet> {
  final _key = GlobalKey();
  bool _busy = false;
  CardStyle _style = CardStyle.poster;

  Future<Uint8List?> _render() async {
    final boundary = _key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final img = await boundary.toImage(pixelRatio: 1080 / CharacterCard.width);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final png = await _render();
      if (png == null || !mounted) return;
      final name = '${widget.character.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}-${_style.name}.png';
      final ok = await deliverFile(context, name: name, bytes: png, mime: 'image/png', text: '${widget.character.name}, my DnD hero');
      if (ok && mounted) showToast(context, 'Character card ready');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(children: [
        Text('Character card', style: T.h2()),
        const SizedBox(height: 4),
        Text('A 1080 × 1350 image, ready for chats and socials.', style: T.small()),
        const SizedBox(height: 12),
        SegmentedButton<CardStyle>(
          showSelectedIcon: false,
          segments: [for (final s in CardStyle.values) ButtonSegment(value: s, label: Text(_styleLabels[s]!))],
          selected: {_style},
          onSelectionChanged: (v) => setState(() => _style = v.first),
        ),
        const SizedBox(height: 16),
        FittedBox(child: RepaintBoundary(key: _key, child: CharacterCard(character: widget.character, style: _style))),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: AppButton(
              label: 'Copy as text',
              kind: ButtonKind.secondary,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: characterCardText(widget.character)));
                showToast(context, 'Copied');
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(flex: 2, child: AppButton(label: 'Share image', icon: Icons.ios_share, busy: _busy, onPressed: _share)),
        ]),
      ]),
    );
  }
}

String characterCardText(Character c) => [
      '${c.name}${c.title.isNotEmpty ? ', ${c.title}' : ''}',
      'Level ${c.level} ${c.raceLabel} ${c.classSummary}${c.subclassDefs.isEmpty ? '' : ' (${c.subclassDefs.map((s) => s.name).join(', ')})'}',
      'HP ${c.maxHp} · AC ${c.armorClass} · Speed ${c.speed}',
      Ability.values.map((a) => '${a.short} ${c.score(a)}').join(' · '),
      if (c.personality.isNotEmpty) c.personality,
      'Made in DnD',
    ].join('\n');

String _roman(int n) {
  const v = [(10, 'X'), (9, 'IX'), (5, 'V'), (4, 'IV'), (1, 'I')];
  final b = StringBuffer();
  var x = n.clamp(1, 39);
  for (final (k, s) in v) {
    while (x >= k) {
      b.write(s);
      x -= k;
    }
  }
  return b.toString();
}

/// A fixed-size, self-contained card for rendering to an image.
class CharacterCard extends StatelessWidget {
  const CharacterCard({super.key, required this.character, this.style = CardStyle.poster});
  final Character character;
  final CardStyle style;

  static const width = 360.0;
  static const height = 450.0;

  @override
  Widget build(BuildContext context) {
    // Rendered at 3× for export: decode portraits at that density, not the
    // preview's, or they come out pixelated.
    final mq = (MediaQuery.maybeOf(context) ?? const MediaQueryData()).copyWith(textScaler: TextScaler.noScaling, devicePixelRatio: 3);
    final card = switch (style) {
      CardStyle.poster => _poster(),
      CardStyle.classic => _classic(),
      CardStyle.tarot => _tarot(),
      CardStyle.minimal => _minimal(),
    };
    return MediaQuery(data: mq, child: SizedBox(width: width, height: height, child: card));
  }

  Character get c => character;
  Color get _color => c.primaryClass.color;
  String get _blurb => c.personality.isNotEmpty ? c.personality : (c.backstory.split(RegExp(r'(?<=[.!?])\s')).firstOrNull ?? '');

  Widget _stats({required Color fg, required Color sub, required Color tile, double size = 17}) => Row(children: [
        for (final (label, value) in [('HP', '${c.maxHp}'), ('AC', '${c.armorClass}'), ('SPD', '${c.speed}'), ('PROF', signed(c.proficiency))])
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 7),
              decoration: BoxDecoration(color: tile, borderRadius: BorderRadius.circular(10)),
              child: Column(children: [
                Text(value, style: T.number(size, color: fg)),
                Text(label, style: T.caption(color: sub).copyWith(fontSize: 9.5, letterSpacing: 1)),
              ]),
            ),
          ),
      ]);

  Widget _abilities({required Color fg, required Color sub}) => Row(children: [
        for (final a in Ability.values)
          Expanded(
            child: Column(children: [
              Text('${c.score(a)}', style: T.number(15, color: fg)),
              Text(a.short, style: T.caption(color: sub).copyWith(fontSize: 9.5, letterSpacing: 1)),
            ]),
          ),
      ]);

  Widget _brand(Color fg, Color sub) => Row(children: [
        ClipRRect(borderRadius: BorderRadius.circular(5), child: Image.asset('assets/icon/icon.png', width: 16, height: 16, errorBuilder: (_, _, _) => const SizedBox(width: 16))),
        const SizedBox(width: 6),
        Text('DnD', style: T.h3(color: fg).copyWith(fontSize: 12)),
        const Spacer(),
        Text(c.alignment, style: T.caption(color: sub).copyWith(fontSize: 11)),
      ]);

  // A full-bleed portrait with the details on a gradient.
  Widget _poster() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(fit: StackFit.expand, children: [
        Container(color: Color.lerp(Colors.black, _color, 0.25)),
        Positioned(left: 0, right: 0, top: 0, height: 330, child: PortraitFill(character: c)),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.0, 0.42, 0.68, 1.0],
              colors: [Colors.black.withValues(alpha: 0.15), Colors.transparent, Color.lerp(Colors.black, _color, 0.18)!.withValues(alpha: 0.96), Colors.black],
            ),
          ),
        ),
        Positioned(
          top: 16,
          left: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(999), border: Border.all(color: Colors.white24)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              ClassIcon(classId: c.classLevels.keys.first, size: 14),
              const SizedBox(width: 6),
              Text('LEVEL ${c.level}', style: T.overline(color: Colors.white)),
            ]),
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: 16,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.name, style: T.h1(color: Colors.white).copyWith(fontSize: 30, height: 1.02, shadows: const [Shadow(blurRadius: 18, color: Colors.black)]), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text([if (c.title.isNotEmpty) c.title, '${c.raceLabel} ${c.classSummary}'].join(' · '), style: T.small(color: Colors.white.withValues(alpha: 0.8)), maxLines: 1, overflow: TextOverflow.ellipsis),
            if (_blurb.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('“$_blurb”', style: T.small(color: Colors.white.withValues(alpha: 0.7)).copyWith(fontStyle: FontStyle.italic, fontSize: 11.5), maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 12),
            _stats(fg: Colors.white, sub: Colors.white54, tile: Colors.white.withValues(alpha: 0.09)),
            const SizedBox(height: 10),
            _abilities(fg: Colors.white, sub: Colors.white54),
            const SizedBox(height: 12),
            _brand(Colors.white, Colors.white38),
          ]),
        ),
      ]),
    );
  }

  Widget _classic() {
    final blurb = c.backstory.isNotEmpty ? c.backstory : c.personality;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color.lerp(AppColors.bg, _color, 0.28)!, AppColors.bg]),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(borderRadius: BorderRadius.circular(18), child: CharacterPortrait(character: c, size: 112, circle: false)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('LEVEL ${c.level}', style: T.overline(color: Colors.white70)),
              const SizedBox(height: 4),
              Text(c.name, style: T.h2(color: Colors.white).copyWith(fontSize: 22, height: 1.1), maxLines: 2, overflow: TextOverflow.ellipsis),
              if (c.title.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 3), child: Text(c.title, style: T.small(color: Colors.white70), maxLines: 1, overflow: TextOverflow.ellipsis)),
              const SizedBox(height: 8),
              Row(children: [
                ClassIcon(classId: c.classLevels.keys.first, size: 18),
                const SizedBox(width: 6),
                Expanded(child: Text('${c.raceLabel} ${c.classSummary}', style: T.caption(color: Colors.white), maxLines: 2, overflow: TextOverflow.ellipsis)),
              ]),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        _stats(fg: Colors.white, sub: Colors.white54, tile: Colors.white.withValues(alpha: 0.06)),
        const SizedBox(height: 10),
        _abilities(fg: Colors.white, sub: Colors.white54),
        const SizedBox(height: 12),
        Wrap(spacing: 5, runSpacing: 5, children: [
          for (final s in c.subclassDefs) _chip(s.name, _color),
          for (final f in c.feats.take(2)) _chip(f.replaceAll('_', ' '), Colors.white24),
          for (final s in c.skills.take(4)) _chip(s.label, Colors.white24),
        ]),
        const Spacer(),
        if (blurb.isNotEmpty) Text(blurb, style: T.small(color: Colors.white70).copyWith(fontSize: 12, height: 1.4), maxLines: 4, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 12),
        _brand(Colors.white, Colors.white38),
      ]),
    );
  }

  // An ornate gold-framed card with an arched portrait.
  Widget _tarot() {
    const gold = Color(0xFFD4AF37);
    const ink = Color(0xFF15110B);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const RadialGradient(center: Alignment(0, -0.4), radius: 1.1, colors: [Color(0xFF2A2116), ink]),
        border: Border.all(color: gold, width: 2),
      ),
      padding: const EdgeInsets.all(8),
      child: CustomPaint(
        painter: _TarotFramePainter(gold),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
          child: Column(children: [
            Text(_roman(c.level), style: T.h3(color: gold).copyWith(fontFamily: 'serif', fontSize: 18, letterSpacing: 4)),
            const SizedBox(height: 8),
            ClipPath(
              clipper: _ArchClipper(),
              child: Container(
                width: 210,
                height: 236,
                decoration: BoxDecoration(border: Border.all(color: gold, width: 2)),
                child: PortraitFill(character: c),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(border: Border.symmetric(horizontal: BorderSide(color: gold.withValues(alpha: 0.8)))),
              child: Text(c.name.toUpperCase(), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.h3(color: const Color(0xFFF5E6B8)).copyWith(fontFamily: 'serif', fontSize: 17, letterSpacing: 2.5)),
            ),
            const SizedBox(height: 6),
            Text('${c.title.isNotEmpty ? c.title : 'The ${c.primaryClass.name}'} · ${c.raceLabel}', textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.caption(color: gold.withValues(alpha: 0.85)).copyWith(fontStyle: FontStyle.italic)),
            const Spacer(),
            _abilities(fg: const Color(0xFFF5E6B8), sub: gold.withValues(alpha: 0.7)),
            const SizedBox(height: 8),
            Text('HP ${c.maxHp}  ✦  AC ${c.armorClass}  ✦  ${c.alignment}', style: T.caption(color: gold).copyWith(fontSize: 10.5, letterSpacing: 1)),
          ]),
        ),
      ),
    );
  }

  // A clean, light card.
  Widget _minimal() {
    const paper = Color(0xFFF7F5F0);
    const ink = Color(0xFF1C1B19);
    const sub = Color(0xFF7A766E);
    return Container(
      decoration: BoxDecoration(color: paper, borderRadius: BorderRadius.circular(22)),
      padding: const EdgeInsets.all(22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: _color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text('${c.primaryClass.name.toUpperCase()} · LEVEL ${c.level}', style: T.overline(color: sub)),
        ]),
        const SizedBox(height: 14),
        ClipRRect(borderRadius: BorderRadius.circular(16), child: SizedBox(width: double.infinity, height: 168, child: PortraitFill(character: c))),
        const SizedBox(height: 14),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(c.name, style: T.h1(color: ink).copyWith(fontSize: 26, height: 1.05), maxLines: 1)),
        const SizedBox(height: 2),
        Text([if (c.title.isNotEmpty) c.title, c.raceLabel].join(' · '), style: T.small(color: sub), maxLines: 1, overflow: TextOverflow.ellipsis),
        const Spacer(),
        _stats(fg: ink, sub: sub, tile: Colors.black.withValues(alpha: 0.05), size: 16),
        const SizedBox(height: 10),
        _abilities(fg: ink, sub: sub),
        const SizedBox(height: 12),
        _brand(ink, sub),
      ]),
    );
  }

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(999), border: Border.all(color: color.withValues(alpha: 0.5))),
        child: Text(text, style: T.caption(color: Colors.white).copyWith(fontSize: 10)),
      );
}

class _ArchClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size s) => Path()
    ..moveTo(0, s.height)
    ..lineTo(0, s.width / 2)
    ..arcToPoint(Offset(s.width, s.width / 2), radius: Radius.circular(s.width / 2))
    ..lineTo(s.width, s.height)
    ..close();

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _TarotFramePainter extends CustomPainter {
  _TarotFramePainter(this.gold);
  final Color gold;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = gold.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12));
    canvas.drawRRect(r, p);
    canvas.drawRRect(r.deflate(4), p..color = gold.withValues(alpha: 0.3));
    // Corner stars.
    final fill = Paint()..color = gold;
    for (final o in [const Offset(12, 12), Offset(size.width - 12, 12), Offset(12, size.height - 12), Offset(size.width - 12, size.height - 12)]) {
      final path = Path();
      for (var i = 0; i < 8; i++) {
        final a = i * math.pi / 4;
        final len = i.isEven ? 6.0 : 2.2;
        final pt = o + Offset(math.cos(a) * len, math.sin(a) * len);
        i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(path..close(), fill);
    }
  }

  @override
  bool shouldRepaint(covariant _TarotFramePainter old) => old.gold != gold;
}
