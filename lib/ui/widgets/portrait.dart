import 'package:flutter/material.dart';

import '../../art/paint_cache.dart';
import 'package:provider/provider.dart';

import '../../art/monster_painter.dart';
import '../../art/portrait_painter.dart';
import '../../models/adventure.dart';
import '../../models/character.dart';
import '../../services/image_service.dart';
import '../../theme/app_theme.dart';
import '../../art/render_png.dart';
import 'image_viewer.dart';
import 'media_view.dart' show mediaActions;

/// Avatar for a character (procedural or AI image). Tap opens a full-screen
/// viewer when [viewable] is set.
class CharacterPortrait extends StatelessWidget {
  const CharacterPortrait({super.key, required this.character, this.size = 48, this.circle = true, this.viewable = false});
  final Character character;
  final double size;
  final bool circle;
  final bool viewable;

  @override
  Widget build(BuildContext context) {
    final c = character;
    return PortraitView(
      spec: c.portrait,
      raceId: c.raceId,
      classId: c.classLevels.keys.first,
      size: size,
      circle: circle,
      viewTitle: viewable ? c.name : null,
      viewSubtitle: '${c.raceLabel} ${c.classSummary}',
    );
  }
}

/// A character's portrait filling its parent (cropped to cover), for cards.
class PortraitFill extends StatelessWidget {
  const PortraitFill({super.key, required this.character});
  final Character character;

  @override
  Widget build(BuildContext context) {
    final c = character;
    return LayoutBuilder(builder: (context, box) {
      final side = box.biggest.longestSide.isFinite ? box.biggest.longestSide : 400.0;
      final painted = FittedBox(fit: BoxFit.cover, clipBehavior: Clip.hardEdge, child: SizedBox.square(dimension: side, child: CustomPaint(painter: PortraitPainter(spec: c.portrait, raceId: c.raceId, classId: c.classLevels.keys.first, frame: false))));
      return SizedBox.expand(child: GeneratedImage(path: c.portrait.aiImagePath, fallback: painted, service: context.read<ImageService>(), fit: BoxFit.cover, alignment: const Alignment(0, -0.35)));
    });
  }
}

class PortraitView extends StatelessWidget {
  const PortraitView({super.key, required this.spec, required this.raceId, this.classId, this.size = 48, this.circle = true, this.viewTitle, this.viewSubtitle});
  final PortraitSpec spec;
  final String raceId;
  final String? classId;
  final double size;
  final bool circle;

  /// When set, tapping opens the full-screen viewer with this title.
  final String? viewTitle;
  final String? viewSubtitle;

  Widget _image(BuildContext context, double s, {bool full = false}) {
    final images = context.read<ImageService>();
    final key = 'p${Object.hash(spec.seed, spec.skin.toARGB32(), spec.hair.toARGB32(), spec.eyes.toARGB32(), spec.hairStyle, spec.beard, spec.scar, spec.accessory, spec.background, (spec.feminine * 100).round(), raceId, classId)}';
    final painted = SizedBox.square(dimension: s, child: CachedPaint(cacheKey: key, painter: PortraitPainter(spec: spec, raceId: raceId, classId: classId, frame: false)));
    final px = (s * (MediaQuery.maybeDevicePixelRatioOf(context) ?? 2)).round();
    return GeneratedImage(path: spec.aiImagePath, fallback: painted, service: images, cacheWidth: full ? null : px, fit: full ? BoxFit.contain : BoxFit.cover);
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(circle ? size : size * 0.22);
    final avatar = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(borderRadius: radius, border: Border.all(color: AppColors.border)),
      child: ClipRRect(borderRadius: radius, child: SizedBox.expand(child: _image(context, size))),
    );
    if (viewTitle == null) return avatar;
    return MouseRegion(
      cursor: SystemMouseCursors.zoomIn,
      child: GestureDetector(
        onTap: () => openImageViewer(
          context,
          title: viewTitle!,
          subtitle: viewSubtitle,
          actions: mediaActions(context, spec.aiImagePath, name: viewTitle!, render: () => portraitPng(spec, raceId, classId: classId)),
          builder: (ctx) => SizedBox.expand(child: _image(ctx, 600, full: true)),
        ),
        child: avatar,
      ),
    );
  }
}

class NpcPortrait extends StatelessWidget {
  const NpcPortrait({super.key, required this.npc, this.size = 40, this.viewable = false});
  final Npc npc;
  final double size;
  final bool viewable;

  @override
  Widget build(BuildContext context) {
    final color = npc.disposition >= 25
        ? AppColors.success
        : npc.disposition <= -25
            ? AppColors.danger
            : AppColors.textFaint;
    return Stack(clipBehavior: Clip.none, children: [
      PortraitView(
        spec: npc.portrait,
        raceId: npc.raceId,
        size: size,
        viewTitle: viewable ? npc.name : null,
        viewSubtitle: [if (npc.role.isNotEmpty) npc.role, npc.attitude].join(' · '),
      ),
      Positioned(
        right: 0,
        bottom: 0,
        child: IgnorePointer(
          child: Container(
            width: size * 0.26,
            height: size * 0.26,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: AppColors.bg, width: 2)),
          ),
        ),
      ),
    ]);
  }
}

class MonsterToken extends StatelessWidget {
  const MonsterToken({super.key, required this.combatant, this.size = 48, this.flash = false, this.viewable = false});
  final Combatant combatant;
  final double size;
  final bool flash;
  final bool viewable;

  @override
  Widget build(BuildContext context) {
    final c = combatant;
    final token = TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: flash ? 1 : 0),
      duration: const Duration(milliseconds: 220),
      builder: (context, v, _) => CustomPaint(
        size: Size.square(size),
        painter: MonsterPainter(type: c.type, color: Color(c.colorValue), seed: c.id.hashCode, hurt: v, down: c.down),
      ),
    );
    if (!viewable) return token;
    return GestureDetector(
      onLongPress: () => openImageViewer(
        context,
        title: c.name,
        subtitle: '${c.type[0].toUpperCase()}${c.type.substring(1)} · AC ${c.ac} · ${c.hp}/${c.maxHp} HP',
        actions: mediaActions(context, null, name: c.name, render: () => paintPng(const Size.square(1024), (cv, s) => MonsterPainter(type: c.type, color: Color(c.colorValue), seed: c.id.hashCode, down: c.down).paint(cv, s))),
        builder: (ctx) => CustomPaint(painter: MonsterPainter(type: c.type, color: Color(c.colorValue), seed: c.id.hashCode, down: c.down)),
      ),
      child: token,
    );
  }
}
