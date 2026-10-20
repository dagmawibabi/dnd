import 'package:flutter/material.dart';

import '../../../game/adventure_controller.dart';
import '../../../game/oracle.dart';
import '../../../models/adventure.dart';
import '../../../theme/ui.dart';
import '../../../data/inventory_rules.dart';
import '../../widgets/portrait.dart';
import '../character/character_sheet.dart';
import '../story/story_tools.dart';
export '../story/story_tools.dart' show editTextDialog;

/// The D&D journal: Quests, then the shared People, Memory and Gallery tabs.
void showJournalSheet(BuildContext context, AdventureController ctl, {String? initial}) {
  showStoryJournal(context, ctl, leading: [('Quests', (_) => _QuestsTab(ctl: ctl))], initial: initial);
}

class _QuestsTab extends StatelessWidget {
  const _QuestsTab({required this.ctl});
  final AdventureController ctl;

  @override
  Widget build(BuildContext context) {
    final a = ctl.adventure;
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (a.quests.isEmpty) const EmptyState(icon: Icons.flag_outlined, title: 'No quests yet'),
      if (a.quests.isNotEmpty)
        RowGroup(children: [
          for (final q in a.quests.reversed)
            ListRow(
              leading: Icon(
                q.status == QuestStatus.completed ? Icons.check_circle : (q.status == QuestStatus.failed ? Icons.cancel_outlined : Icons.radio_button_unchecked),
                size: 20,
                color: q.status == QuestStatus.completed ? AppColors.success : (q.status == QuestStatus.failed ? AppColors.danger : AppColors.textMuted),
              ),
              title: q.title,
              subtitle: q.description,
            ),
        ]),
    ]);
  }
}

void showPartySheet(BuildContext context, AdventureController ctl) {
  showAppSheet(context, builder: (ctx) {
    return ListenableBuilder(
      listenable: ctl,
      builder: (ctx, _) => ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 24), children: [
        const SheetTitle('Party'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: RowGroup(children: [
            for (final c in ctl.adventure.party)
              InkWell(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CharacterSheetScreen(character: c, onChanged: ctl.save))),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    CharacterPortrait(character: c, size: 44, viewable: true),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(c.name, style: T.h3())),
                          Text('${c.hp}/${c.maxHp} HP', style: T.caption()),
                        ]),
                        const SizedBox(height: 2),
                        Text('Level ${c.level} ${c.classSummary} · AC ${c.armorClass}', style: T.small()),
                        const SizedBox(height: 8),
                        Bar(value: c.hp, max: c.maxHp, color: AppColors.hp),
                        if (c.isCompanion) ...[
                          const SizedBox(height: 8),
                          Row(children: [
                            Icon(Icons.favorite_border, size: 13, color: _loyaltyColor(c.loyalty)),
                            const SizedBox(width: 6),
                            Text('${c.loyaltyLabel} · ${c.loyalty}', style: T.caption(color: _loyaltyColor(c.loyalty))),
                            const SizedBox(width: 8),
                            Expanded(child: Bar(value: c.loyalty, max: 100, color: _loyaltyColor(c.loyalty))),
                          ]),
                          if (c.personality.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(c.personality, style: T.caption())),
                          if (c.personalQuest.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text('Personal quest: ${c.personalQuest}', style: T.caption(color: AppColors.textMuted))),
                        ],
                      ]),
                    ),
                    const SizedBox(width: 8),
                    if (c.isCompanion)
                      IconButton(tooltip: 'Talk to ${c.name}', icon: const Icon(Icons.chat_bubble_outline), onPressed: () {
                        Navigator.pop(ctx);
                        showNpcChat(context, ctl, ctl.adventure.personNamed(c.name)!);
                      })
                    else const Icon(Icons.chevron_right, size: 20, color: AppColors.textFaint),
                  ]),
                ),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(children: [
            Expanded(
              child: AppButton(
                label: 'Short rest',
                kind: ButtonKind.secondary,
                onPressed: ctl.inCombat ? null : () => _rest(ctx, ctl, false),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AppButton(
                label: ctl.turnsUntilLongRest > 0 ? 'Long rest · ${ctl.turnsUntilLongRest}' : 'Long rest',
                kind: ButtonKind.secondary,
                onPressed: ctl.inCombat ? null : () => _rest(ctx, ctl, true),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: Text('Long rests use a ration and need ${AdventureController.longRestCooldown} turns between them. Resting in the wild can be interrupted.', style: T.caption()),
        ),
      ]),
    );
  });
}

void _rest(BuildContext ctx, AdventureController ctl, bool long) {
  final msg = ctl.restFromMenu(long: long);
  if (msg != null) {
    showToast(ctx, msg, icon: Icons.hourglass_bottom);
  } else {
    Navigator.pop(ctx);
  }
}

Color _loyaltyColor(int l) => l >= 60 ? AppColors.success : (l >= 30 ? AppColors.warning : AppColors.danger);

/// Opens a saved, private conversation with anyone in the story.
void showNpcChat(BuildContext context, AdventureController ctl, Npc npc) => showCharacterChat(context, ctl, npc);

// ------------------------------------------------------------------ oracle

void showOracleSheet(BuildContext context, AdventureController ctl) {
  showAppSheet(context, builder: (ctx) => _OracleSheet(ctl: ctl));
}

class _OracleSheet extends StatefulWidget {
  const _OracleSheet({required this.ctl});
  final AdventureController ctl;

  @override
  State<_OracleSheet> createState() => _OracleSheetState();
}

class _OracleSheetState extends State<_OracleSheet> {
  final _q = TextEditingController();
  Likelihood _l = Likelihood.even;
  OracleResult? _last;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctl = widget.ctl;
    final chaos = ctl.adventure.chaos;
    final chance = Oracle.chanceFor(_l, chaos);
    final r = _last;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Ask the oracle', style: T.h2()),
          const SizedBox(height: 4),
          Text('A yes/no question to fate, for when you want the world to surprise you. The answer is added to your story.', style: T.small()),
          const SizedBox(height: 16),
          TextField(controller: _q, style: T.body(), decoration: const InputDecoration(hintText: 'Is the guard asleep?'), textInputAction: TextInputAction.done),
          const SizedBox(height: 14),
          Text('LIKELIHOOD', style: T.overline()),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final l in Likelihood.values) ChoiceChip(label: Text(l.label), selected: _l == l, onSelected: (_) => setState(() => _l = l)),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Text('CHAOS FACTOR', style: T.overline()),
            const Spacer(),
            Text('$chaos · ${chaos <= 3 ? 'orderly' : chaos <= 6 ? 'balanced' : 'chaotic'}', style: T.caption(color: AppColors.textMuted)),
          ]),
          Slider(value: chaos.toDouble(), min: 1, max: 9, divisions: 8, onChanged: (v) => setState(() => ctl.setChaos(v.round()))),
          Text('$chance% chance of yes. Doubles at or below the chaos factor (11, 22…) trigger a random event.', style: T.caption()),
          const SizedBox(height: 16),
          AppButton(
            label: 'Ask',
            icon: Icons.help_outline,
            onPressed: () {
              final res = ctl.askOracle(_q.text.trim(), _l);
              setState(() => _last = res);
            },
          ),
          if (r != null) ...[
            const SizedBox(height: 16),
            FadeIn(
              key: ValueKey(r.roll * 1000 + r.chance),
              child: AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('d100 → ${r.roll}', style: T.caption()),
                  const SizedBox(height: 6),
                  Text(r.answer, style: T.h1(color: r.yes ? AppColors.success : AppColors.danger)),
                  if (r.event != null) ...[
                    const SizedBox(height: 10),
                    Text('Random event: ${r.event}', style: T.body()),
                    Text('Meaning: ${r.meaning}', style: T.small()),
                  ],
                ]),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}


// ------------------------------------------------------------------ vitals

/// Tap the health bar: everything about how the hero is doing right now.
void showVitalsSheet(BuildContext context, AdventureController ctl) {
  showAppSheet(context, builder: (ctx) => ListenableBuilder(
        listenable: ctl,
        builder: (ctx, _) {
          final h = ctl.hero;
          final hpColor = h.hp / h.maxHp < 0.3 ? AppColors.danger : AppColors.hp;
          final slots = h.spellSlots;
          Widget tile(String label, String value, {Color? color}) => Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                  child: Column(children: [
                    Text(value, style: T.number(17, color: color ?? AppColors.text)),
                    Text(label, style: T.caption()),
                  ]),
                ),
              );
          return SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.8,
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 28), children: [
              Row(children: [
                CharacterPortrait(character: h, size: 52, viewable: true),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(h.name, style: T.h2()),
                    Text('Level ${h.level} ${h.raceLabel} ${h.classSummary}', style: T.small()),
                  ]),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => CharacterSheetScreen(character: h, onChanged: ctl.save)));
                  },
                  child: const Text('Sheet'),
                ),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                Text('${h.hp}', style: T.number(34, color: hpColor)),
                Text(' / ${h.maxHp} HP', style: T.h3(color: AppColors.textMuted)),
                const Spacer(),
                if (h.tempHp > 0) Tag('+${h.tempHp} temporary', icon: Icons.shield_moon_outlined, color: AppColors.info),
              ]),
              const SizedBox(height: 8),
              Bar(value: h.hp, max: h.maxHp, color: hpColor),
              if (h.hp <= 0) ...[
                const SizedBox(height: 10),
                Text('Dying · saves ${h.deathSuccesses} ✓ / ${h.deathFailures} ✗', style: T.small(color: AppColors.danger)),
              ],
              const SizedBox(height: 14),
              Row(children: [
                tile('AC', '${h.armorClass}'),
                const SizedBox(width: 8),
                tile('Speed', '${h.speed} ft'),
                const SizedBox(width: 8),
                tile('Initiative', signedNum(h.initiative)),
                const SizedBox(width: 8),
                tile('Hit dice', '${h.hitDiceRemaining}/${h.hitDiceTotal}'),
              ]),
              const SectionLabel('Conditions'),
              if (h.conditions.isEmpty && h.concentration == null) Text('Nothing affecting you.', style: T.small()),
              Wrap(spacing: 6, runSpacing: 6, children: [
                if (h.concentration != null) Tag('Concentrating', icon: Icons.blur_circular, color: AppColors.accent),
                for (final c in h.conditions.where((c) => !c.endsWith('Used') && !c.startsWith('SupUsed') && !c.startsWith('Step') && !c.startsWith('Order:')))
                  Tag(h.conditionUntil[c] == null ? c : '$c · until turn ${h.conditionUntil[c]}', color: AppColors.warning),
              ]),
              if (slots.any((x) => x > 0)) ...[
                const SectionLabel('Spell slots'),
                Wrap(spacing: 14, runSpacing: 8, children: [
                  for (var i = 0; i < slots.length; i++)
                    if (slots[i] > 0)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('L${i + 1} ', style: T.caption()),
                        for (var k = 0; k < slots[i]; k++)
                          Container(
                            margin: const EdgeInsets.only(right: 3),
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(shape: BoxShape.circle, color: k < h.slotsRemaining(i + 1) ? AppColors.accent : AppColors.surface3),
                          ),
                      ]),
                ]),
              ],
              const SectionLabel('Progress'),
              Row(children: [
                Expanded(child: Text(h.level >= 20 ? 'Max level' : 'XP ${h.xp} / ${h.xpForNext}', style: T.small(color: AppColors.text))),
                if (h.canLevelUp) const Tag('Level up ready', color: AppColors.success, filled: true),
              ]),
              const SizedBox(height: 6),
              Bar(value: h.xp, max: h.level >= 20 ? h.xp.clamp(1, 1 << 30) : h.xpForNext, color: AppColors.accent),
              const SizedBox(height: 10),
              Text('${h.gold} gp · carrying ${h.carriedWeight.toStringAsFixed(0)}/${h.carryCapacity.toStringAsFixed(0)} lb · ${h.encumbranceLabel}', style: T.small()),
              if (ctl.adventure.companions.isNotEmpty) ...[
                const SectionLabel('Party'),
                for (final c in ctl.adventure.companions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(children: [
                      CharacterPortrait(character: c, size: 30),
                      const SizedBox(width: 10),
                      SizedBox(width: 90, child: Text(c.name.split(' ').first, style: T.small(color: AppColors.text), overflow: TextOverflow.ellipsis)),
                      Expanded(child: Bar(value: c.hp, max: c.maxHp, color: c.hp / c.maxHp < 0.3 ? AppColors.danger : AppColors.hp)),
                      const SizedBox(width: 8),
                      Text('${c.hp}/${c.maxHp}', style: T.caption()),
                    ]),
                  ),
              ],
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: AppButton(label: 'Short rest', kind: ButtonKind.secondary, onPressed: ctl.inCombat ? null : () => _rest(ctx, ctl, false))),
                const SizedBox(width: 8),
                Expanded(child: AppButton(label: ctl.turnsUntilLongRest > 0 ? 'Long rest · ${ctl.turnsUntilLongRest}' : 'Long rest', kind: ButtonKind.secondary, onPressed: ctl.inCombat ? null : () => _rest(ctx, ctl, true))),
              ]),
            ]),
          );
        },
      ));
}

String signedNum(int v) => v >= 0 ? '+$v' : '$v';
