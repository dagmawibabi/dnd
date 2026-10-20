import 'package:flutter/material.dart';

import '../../game/dice.dart';
import '../../models/adventure.dart';
import '../../theme/ui.dart';
import 'dice.dart';

/// True if a log entry carries a tappable breakdown.
bool hasDetails(LogEntry e) => e.meta['details'] is Map;

/// Bottom sheet explaining what happened in a log entry: dice, math,
/// before/after values and the rule that applied.
void showLogDetails(BuildContext context, LogEntry e) {
  final raw = e.meta['details'];
  if (raw is! Map) return;
  final d = Map<String, dynamic>.from(raw);
  showAppSheet(context, builder: (ctx) => _DetailsSheet(d: d, fallbackText: e.text));
}

class _DetailsSheet extends StatelessWidget {
  const _DetailsSheet({required this.d, required this.fallbackText});
  final Map<String, dynamic> d;
  final String fallbackText;

  @override
  Widget build(BuildContext context) {
    final ok = d['ok'];
    final outcome = d['outcome']?.toString();
    final groups = (d['groups'] as List? ?? []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    final lines = (d['lines'] as List? ?? []).whereType<List>().toList();
    final rule = d['rule']?.toString() ?? '';
    final color = ok == true ? AppColors.success : (ok == false ? AppColors.danger : AppColors.textMuted);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(d['title']?.toString() ?? 'Details', style: T.h2()),
          if (d['subtitle'] != null && d['subtitle'].toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(d['subtitle'].toString(), style: T.small())),
          if (outcome != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Icon(ok == true ? Icons.check_circle_outline : (ok == false ? Icons.cancel_outlined : Icons.info_outline), color: color, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(outcome, style: T.h3(color: color))),
              ]),
            ),
          ],
          for (final g in groups) ...[
            const SizedBox(height: 16),
            _DiceGroupView(g: g),
          ],
          if (lines.isNotEmpty) ...[
            const SizedBox(height: 16),
            RowGroup(children: [
              for (final l in lines)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(flex: 2, child: Text(l.isNotEmpty ? l[0].toString() : '', style: T.small())),
                    const SizedBox(width: 12),
                    Expanded(flex: 3, child: Text(l.length > 1 ? l[1].toString() : '', textAlign: TextAlign.right, style: T.small(color: AppColors.text))),
                  ]),
                ),
            ]),
          ],
          if (rule.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.menu_book_outlined, size: 16, color: AppColors.textFaint),
              const SizedBox(width: 10),
              Expanded(child: Text(rule, style: T.small())),
            ]),
          ],
          if (groups.isEmpty && lines.isEmpty && rule.isEmpty) Text(fallbackText, style: T.body()),
        ]),
      ),
    );
  }
}

class _DiceGroupView extends StatelessWidget {
  const _DiceGroupView({required this.g});
  final Map<String, dynamic> g;

  @override
  Widget build(BuildContext context) {
    final dice = (g['dice'] as List? ?? []).whereType<Map>().toList();
    final mod = (g['mod'] as num?)?.toInt() ?? 0;
    final total = g['total'];
    final against = g['against']?.toString();
    final mode = g['mode']?.toString();
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(g['label']?.toString() ?? 'Roll', style: T.small(color: AppColors.text))),
          if (mode == RollMode.advantage.name) const Tag('Advantage', color: AppColors.success, filled: true),
          if (mode == RollMode.disadvantage.name) const Tag('Disadvantage', color: AppColors.danger, filled: true),
          if (g['expr'] != null) Tag(g['expr'].toString()),
        ]),
        const SizedBox(height: 12),
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 8, children: [
          for (final die in dice)
            Opacity(
              opacity: die['drop'] == true ? 0.3 : 1,
              child: SizedBox(
                width: 40,
                height: 40,
                child: CustomPaint(
                  painter: DieFacePainter(
                    sides: (die['s'] as num).toInt(),
                    value: (die['v'] as num).toInt(),
                    tint: (die['s'] == 20 && die['drop'] != true) ? (die['v'] == 20 ? AppColors.success : (die['v'] == 1 ? AppColors.danger : null)) : null,
                  ),
                ),
              ),
            ),
          if (mod != 0) Text('${mod > 0 ? '+' : '−'} ${mod.abs()}', style: T.number(16, color: AppColors.textMuted)),
          Text('=', style: T.number(16, color: AppColors.textMuted)),
          Text('$total${g['suffix'] != null ? ' ${g['suffix']}' : ''}', style: T.number(20)),
          if (against != null) Text('vs $against', style: T.small()),
        ]),
      ]),
    );
  }
}
