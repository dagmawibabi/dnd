import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../game/adventure_controller.dart';
import '../../../game/combat.dart';
import '../../../models/adventure.dart';
import '../../../theme/ui.dart';
import '../../widgets/portrait.dart';

/// Top-down tactical grid: every square is 5 feet.
class BattleGrid extends StatelessWidget {
  const BattleGrid({
    super.key,
    required this.controller,
    required this.targetId,
    required this.moving,
    required this.onTarget,
    required this.onAlly,
    required this.onMove,
    required this.onInfo,
  });

  final AdventureController controller;
  final String? targetId;
  final bool moving;
  final ValueChanged<Combatant> onTarget;
  final ValueChanged<Combatant> onAlly;
  final void Function(int x, int y) onMove;
  final ValueChanged<Combatant> onInfo;

  @override
  Widget build(BuildContext context) {
    final engine = CombatEngine(controller.adventure);
    final st = engine.state;
    final current = st.current;
    final reach = moving && controller.isPlayerTurn ? engine.reachable(current) : const <math.Point<int>>{};
    final target = targetId == null ? null : engine.byId(targetId!);
    return LayoutBuilder(builder: (context, box) {
      final cell = math.min(box.maxWidth / CombatEngine.gridW, 46.0);
      final w = cell * CombatEngine.gridW, h = cell * CombatEngine.gridH;
      return Center(
        child: Semantics(
          label: 'Battle grid. ${st.combatants.where((c) => !c.down).map((c) => '${c.name} at column ${c.x + 1}, row ${c.y + 1}').join('; ')}',
          child: SizedBox(
            width: w,
            height: h,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned.fill(child: CustomPaint(painter: _GridPainter(cell: cell, reach: reach, env: st.environment))),
              // Line of attack to the selected target.
              if (target != null && !target.down && controller.isPlayerTurn)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(painter: _LinePainter(from: Offset((current.x + .5) * cell, (current.y + .5) * cell), to: Offset((target.x + .5) * cell, (target.y + .5) * cell))),
                  ),
                ),
              // Empty squares accept move taps.
              if (moving)
                for (final p in reach)
                  Positioned(
                    left: p.x * cell,
                    top: p.y * cell,
                    width: cell,
                    height: cell,
                    child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => onMove(p.x, p.y)),
                  ),
              for (final c in st.combatants.where((c) => !c.down || !c.isEnemy))
                AnimatedPositioned(
                  key: ValueKey(c.id),
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  left: c.x * cell,
                  top: c.y * cell,
                  width: cell,
                  height: cell,
                  child: _Token(
                    combatant: c,
                    controller: controller,
                    size: cell,
                    isTurn: c == current,
                    isTarget: c.id == targetId,
                    flash: controller.flashTargetId == c.id,
                    order: c.isAlly ? engine.orderOf(c) : null,
                    onTap: () => c.isEnemy ? onTarget(c) : (c.isAlly ? onAlly(c) : null),
                    onLongPress: () => onInfo(c),
                  ),
                ),
            ]),
          ),
        ),
      );
    });
  }
}

class _Token extends StatelessWidget {
  const _Token({required this.combatant, required this.controller, required this.size, required this.isTurn, required this.isTarget, required this.flash, required this.onTap, required this.onLongPress, this.order});
  final Combatant combatant;
  final AdventureController controller;
  final double size;
  final bool isTurn;
  final bool isTarget;
  final bool flash;
  final String? order;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = combatant;
    final ch = c.characterId == null ? null : controller.adventure.party.where((p) => p.id == c.characterId).firstOrNull;
    final inner = size - 8;
    final ring = isTarget ? AppColors.danger : (isTurn ? AppColors.text : (c.isEnemy ? AppColors.danger.withValues(alpha: 0.35) : AppColors.accent.withValues(alpha: 0.5)));
    final frac = c.maxHp == 0 ? 0.0 : (c.hp / c.maxHp).clamp(0.0, 1.0);
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Opacity(
        opacity: c.down ? 0.35 : 1,
        child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: inner,
            height: inner,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ring, width: isTarget || isTurn ? 2 : 1.2)),
            padding: const EdgeInsets.all(1.5),
            child: ClipOval(
              child: ch != null ? CharacterPortrait(character: ch, size: inner - 4) : MonsterToken(combatant: c, size: inner - 4, flash: flash),
            ),
          ),
          Positioned(
            bottom: 1,
            left: 6,
            right: 6,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(value: frac, minHeight: 3, backgroundColor: Colors.black54, color: c.isEnemy ? AppColors.danger : (frac < .3 ? AppColors.danger : AppColors.success)),
            ),
          ),
          if (order != null && order != 'free')
            Positioned(
              top: -2,
              right: -2,
              child: Container(
                width: 14,
                height: 14,
                decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                child: Icon(_orderIcon(order!), size: 9, color: Colors.white),
              ),
            ),
          if (c.conditions.any((x) => const ['Paralyzed', 'Stunned', 'Prone', 'Restrained', 'Frightened', 'Turned'].contains(x)))
            const Positioned(top: -2, left: -2, child: Icon(Icons.warning_amber_rounded, size: 13, color: AppColors.warning)),
        ]),
      ),
    );
  }
}

IconData _orderIcon(String o) => switch (o) {
      'focus' => Icons.gps_fixed,
      'defend' => Icons.shield_outlined,
      'heal' => Icons.healing,
      'hold' => Icons.pan_tool_outlined,
      _ => Icons.circle,
    };

class _GridPainter extends CustomPainter {
  _GridPainter({required this.cell, required this.reach, required this.env});
  final double cell;
  final Set<math.Point<int>> reach;
  final String env;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12));
    final floor = switch (env) {
      'forest' || 'swamp' || 'plains' => const Color(0xFF15201A),
      'dungeon' || 'crypt' || 'cave' || 'sewer' => const Color(0xFF17171C),
      'desert' || 'coast' => const Color(0xFF221E16),
      'town' || 'tavern' || 'castle' => const Color(0xFF1C1A18),
      _ => const Color(0xFF18181B),
    };
    canvas.drawRRect(r, Paint()..color = floor);
    canvas.save();
    canvas.clipRRect(r);
    final reachPaint = Paint()..color = AppColors.accent.withValues(alpha: 0.22);
    for (final p in reach) {
      canvas.drawRect(Rect.fromLTWH(p.x * cell + 1, p.y * cell + 1, cell - 2, cell - 2), reachPaint);
    }
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1;
    for (var x = 1; x < CombatEngine.gridW; x++) {
      canvas.drawLine(Offset(x * cell, 0), Offset(x * cell, size.height), line);
    }
    for (var y = 1; y < CombatEngine.gridH; y++) {
      canvas.drawLine(Offset(0, y * cell), Offset(size.width, y * cell), line);
    }
    canvas.restore();
    canvas.drawRRect(r, Paint()
      ..style = PaintingStyle.stroke
      ..color = AppColors.border);
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) => old.cell != cell || old.reach.length != reach.length || old.env != env || !old.reach.containsAll(reach);
}

class _LinePainter extends CustomPainter {
  _LinePainter({required this.from, required this.to});
  final Offset from;
  final Offset to;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = AppColors.danger.withValues(alpha: 0.5)
      ..strokeWidth = 1.5;
    const dash = 5.0;
    final d = to - from;
    final len = d.distance;
    if (len == 0) return;
    final dir = d / len;
    for (var t = 0.0; t < len; t += dash * 2) {
      canvas.drawLine(from + dir * t, from + dir * math.min(t + dash, len), p);
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) => old.from != from || old.to != to;
}
