import 'package:flutter/material.dart';

import 'battle_grid.dart';

import '../../../data/srd.dart';
import '../../../game/adventure_controller.dart';
import '../../../game/combat.dart';
import '../../../game/dice.dart';
import '../../../models/adventure.dart';
import '../../../theme/ui.dart';
import '../../widgets/dice.dart';
import '../../widgets/portrait.dart';

/// Turn-based combat controls: turn order, targets and actions.
class CombatPanel extends StatefulWidget {
  const CombatPanel({super.key, required this.controller});
  final AdventureController controller;

  @override
  State<CombatPanel> createState() => _CombatPanelState();
}

class _CombatPanelState extends State<CombatPanel> {
  String? _targetId;
  bool _moving = false;
  AdventureController get ctl => widget.controller;

  void _orderSheet(Combatant ally) {
    final engine = CombatEngine(ctl.adventure);
    final current = engine.orderOf(ally);
    final target = _targetId == null ? null : engine.byId(_targetId!);
    showAppSheet(context, builder: (ctx) => ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 24), children: [
          SheetTitle('Command ${ally.name}', subtitle: 'Orders last until you change them. Companions with low loyalty may act on their own.'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: RowGroup(children: [
              for (final e in CombatEngine.orders.entries)
                ListRow(
                  leading: Icon(
                    switch (e.key) { 'focus' => Icons.gps_fixed, 'defend' => Icons.shield_outlined, 'heal' => Icons.healing, 'hold' => Icons.pan_tool_outlined, _ => Icons.auto_awesome_outlined },
                    size: 20,
                    color: current == e.key ? AppColors.accent : null,
                  ),
                  title: e.key == 'focus' && target != null ? 'Attack ${target.name}' : e.value.$1,
                  subtitle: e.key == 'focus' && target == null ? 'Select an enemy on the grid first.' : e.value.$2,
                  trailing: current == e.key ? const Icon(Icons.check, size: 18, color: AppColors.accent) : null,
                  onTap: e.key == 'focus' && target == null
                      ? null
                      : () {
                          Navigator.pop(ctx);
                          ctl.orderCompanion(ally.id, e.key, targetId: target?.id);
                        },
                ),
            ]),
          ),
        ]));
  }

  @override
  Widget build(BuildContext context) {
    final st = ctl.adventure.combat;
    if (st == null) return const SizedBox();
    final live = st.enemies.where((e) => !e.down).toList();
    if (_targetId == null || live.every((e) => e.id != _targetId)) _targetId = live.isEmpty ? null : live.first.id;
    final myTurn = ctl.isPlayerTurn;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(children: [
          Tag('Round ${st.round}', color: AppColors.danger, filled: true),
          const SizedBox(width: 10),
          Expanded(child: Text(myTurn ? 'Your turn' : '${st.current.name} is acting…', style: T.h3(color: myTurn ? AppColors.text : AppColors.textMuted), overflow: TextOverflow.ellipsis)),
          SizedBox(
            height: 28,
            child: ListView(
              shrinkWrap: true,
              scrollDirection: Axis.horizontal,
              children: [
                for (final (i, c) in st.combatants.indexed)
                  Opacity(
                    opacity: c.down ? 0.3 : (i == st.turn ? 1 : 0.55),
                    child: Container(
                      margin: const EdgeInsets.only(left: 4),
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: i == st.turn ? AppColors.text : Colors.transparent, width: 1.5)),
                      child: _avatar(c, 24),
                    ),
                  ),
              ],
            ),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
        child: BattleGrid(
          controller: ctl,
          targetId: _targetId,
          moving: _moving,
          onTarget: (e) => setState(() {
            _targetId = e.id;
            _moving = false;
          }),
          onAlly: _orderSheet,
          onMove: (x, y) async {
            setState(() => _moving = false);
            await ctl.playerMove(x, y);
          },
          onInfo: (c) => c.isEnemy ? _enemyInfo(c) : (c.isAlly ? _orderSheet(c) : null),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        child: Text(
          !myTurn
              ? '${st.current.name} is acting…'
              : (_moving ? 'Tap a highlighted square to move · ${CombatEngine(ctl.adventure).movesLeft(st.current) * 5} ft left' : 'Tap an enemy to target · tap a companion to give orders · long-press for details'),
          style: T.caption(),
          textAlign: TextAlign.center,
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Row(children: [
          for (final a in st.allies)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(a.name.split(' ').first, style: T.caption(color: a.isPlayer ? AppColors.text : AppColors.textMuted), overflow: TextOverflow.ellipsis)),
                    if (a.isAlly && CombatEngine(ctl.adventure).orderOf(a) != 'free')
                      Padding(padding: const EdgeInsets.only(right: 4), child: Text(CombatEngine.orders[CombatEngine(ctl.adventure).orderOf(a)]!.$1.toUpperCase(), style: T.overline(color: AppColors.accent).copyWith(fontSize: 8))),
                    if (a.isPlayer && ctl.hero.concentration != null)
                      Padding(padding: const EdgeInsets.only(right: 4), child: Tooltip(message: 'Concentrating on ${spellById(ctl.hero.concentration!)?.name ?? ''}', child: const Icon(Icons.blur_circular, size: 12, color: AppColors.accent))),
                    Text('${a.hp}/${a.maxHp}', style: T.caption()),
                  ]),
                  const SizedBox(height: 4),
                  Bar(value: a.hp, max: a.maxHp, color: a.hp / a.maxHp < 0.3 ? AppColors.danger : AppColors.success),
                ]),
              ),
            ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Row(children: [
          _action(Icons.sports_kabaddi_outlined, 'Attack', myTurn && _targetId != null ? _attack : null, primary: true),
          _action(Icons.auto_fix_high_outlined, 'Spell', myTurn && ctl.hero.isCaster ? _spell : null),
          _action(Icons.local_drink_outlined, 'Potion', myTurn && ctl.hero.inventory.any((i) => i.def?.type == ItemType.potion) ? _potion : null),
          _action(Icons.open_with, _moving ? 'Cancel' : 'Move', myTurn && CombatEngine(ctl.adventure).movesLeft(st.current) > 0 ? () => setState(() => _moving = !_moving) : null),
          _action(Icons.star_outline, 'Ability', myTurn ? _ability : null),
          _action(Icons.directions_run, 'Flee', myTurn ? _flee : null),
        ]),
      ),
    ]);
  }

  static const _shownConditions = {'Paralyzed', 'Restrained', 'Prone', 'Frightened', 'Poisoned', 'Outlined', 'Banished', 'Surprised', 'Slowed'};


  void _enemyInfo(Combatant e) {
    final engine = CombatEngine(ctl.adventure);
    final abil = engine.abilitiesOf(e);
    showAppSheet(context, builder: (ctx) => ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 28), children: [
          Row(children: [
            MonsterToken(combatant: e, size: 48),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.name, style: T.h2()),
                Text('${e.type} · AC ${e.ac} · ${e.hp}/${e.maxHp} HP · ${CombatEngine(ctl.adventure).dist(CombatEngine(ctl.adventure).state.current, e) * 5} ft away', style: T.small()),
              ]),
            ),
          ]),
          const SizedBox(height: 16),
          Text('ATTACK', style: T.overline()),
          const SizedBox(height: 4),
          Text('${e.attackName} ${signed(e.attackBonus)} to hit · ${e.damage}${e.multi > 1 ? ' · ${e.multi} attacks' : ''}', style: T.body()),
          if (abil.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('ABILITIES', style: T.overline()),
            const SizedBox(height: 4),
            for (final a in abil) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('• ${monsterAbilityText(a)}', style: T.small(color: AppColors.text))),
          ],
          if (e.conditions.where((c) => _shownConditions.contains(c)).isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('CONDITIONS', style: T.overline()),
            const SizedBox(height: 4),
            for (final c in e.conditions.where((c) => _shownConditions.contains(c))) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('$c: ${conditionText(c)}', style: T.small())),
          ],
        ]));
  }

  Widget _avatar(Combatant c, double size) {
    final ch = c.characterId == null ? null : ctl.adventure.party.where((p) => p.id == c.characterId).firstOrNull;
    return ch != null ? CharacterPortrait(character: ch, size: size) : MonsterToken(combatant: c, size: size);
  }

  Widget _action(IconData icon, String label, VoidCallback? onTap, {bool primary = false}) {
    final on = onTap != null;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Opacity(
          opacity: on ? 1 : 0.35,
          child: Material(
            color: primary ? AppColors.text : AppColors.surface2,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(children: [
                  Icon(icon, size: 20, color: primary ? AppColors.bg : AppColors.text),
                  const SizedBox(height: 4),
                  Text(label, style: T.caption(color: primary ? AppColors.bg : AppColors.text)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _attack() => CombatActions.attack(context, ctl, _targetId);
  Future<void> _spell() => CombatActions.spell(context, ctl, _targetId);
  Future<void> _potion() => CombatActions.potion(context, ctl);
  Future<void> _ability() => CombatActions.ability(context, ctl);
  Future<void> _flee() => CombatActions.flee(context, ctl);
}

/// Player combat actions shared by the standard and text layouts.
/// With [interactive] false, dice are rolled automatically.
class CombatActions {
  static Future<int?> _roll(BuildContext context, bool interactive, {required String label, String subtitle = '', required int modifier, int? dc, RollMode mode = RollMode.normal, bool attack = false}) async {
    if (!interactive) return rollDie(20);
    return DiceCheckSheet.show(context, label: label, subtitle: subtitle, modifier: modifier, dc: dc, mode: mode, attack: attack);
  }

  static Combatant? _target(AdventureController ctl, String? id) {
    final engine = CombatEngine(ctl.adventure);
    final t = id == null ? null : engine.byId(id);
    if (t != null && !t.down) return t;
    return engine.state.enemies.where((e) => !e.down).firstOrNull;
  }

  static Future<void> attack(BuildContext context, AdventureController ctl, String? targetId, {bool interactive = true}) async {
    final t = _target(ctl, targetId);
    if (t == null) return;
    final engine = CombatEngine(ctl.adventure);
    final cover = engine.coverBonus(engine.state.current, t);
    final nat = await _roll(context, interactive,
        label: 'Attack ${t.name}',
        subtitle: '${ctl.hero.weaponName} · ${ctl.hero.weaponDamage}${ctl.hero.weaponExtraDice != null ? ' + ${ctl.hero.weaponExtraDice} ${ctl.hero.weaponExtraType ?? ''}' : ''}${cover > 0 ? ' · target has half cover' : ''}',
        modifier: ctl.hero.attackBonus,
        dc: t.ac + cover,
        mode: engine.rollModeFor(engine.state.current, t),
        attack: true);
    if (nat != null) await ctl.playerAttack(t.id, nat);
  }

  static Future<void> spell(BuildContext context, AdventureController ctl, String? targetId, {bool interactive = true, SpellDef? preset}) async {
    final hero = ctl.hero;
    final spells = hero.knownSpellDefs.where((s) => !s.reaction && (s.kind != SpellKind.utility || const {'magic_missile', 'sleep', 'cloud_of_daggers', 'misty_step'}.contains(s.id))).toList();
    final reactions = hero.knownSpellDefs.where((s) => s.reaction).toList();
    final picked = preset ??
        await showAppSheet<SpellDef>(context, builder: (ctx) {
          return ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 24), children: [
            SheetTitle('Cast a spell', subtitle: 'Spell attack ${signed(hero.spellAttack)} · save DC ${hero.spellDc}${hero.concentration != null ? ' · concentrating on ${spellById(hero.concentration!)?.name}' : ''}'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: RowGroup(children: [
                for (final s in spells)
                  Builder(builder: (_) {
                    final can = s.level == 0 || hero.availableSlot(s.level) != null;
                    return Opacity(
                      opacity: can ? 1 : 0.4,
                      child: ListRow(
                        title: s.name,
                        subtitle: '${s.level == 0 ? 'Cantrip' : 'Level ${s.level} · ${hero.slotsRemaining(s.level)} slots'}${s.concentration ? ' · concentration' : ''} · ${s.description}${s.dice != null ? ' ${s.dice}' : ''}',
                        onTap: can ? () => Navigator.pop(ctx, s) : null,
                      ),
                    );
                  }),
              ]),
            ),
            if (reactions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Text('Reactions (${reactions.map((s) => s.name).join(', ')}) trigger automatically when they matter.', style: T.caption()),
              ),
          ]);
        });
    if (picked == null || !context.mounted) return;
    final engine = CombatEngine(ctl.adventure);
    List<String> targets;
    int? nat;
    switch (picked.kind) {
      case SpellKind.heal:
        final ally = interactive ? await pickAlly(context, ctl) : engine.state.allies.reduce((a, b) => a.hp / a.maxHp <= b.hp / b.maxHp ? a : b).id;
        if (ally == null) return;
        targets = [ally];
      case SpellKind.buff:
        if (const {'haste', 'greater_invisibility', 'blur'}.contains(picked.id) && interactive) {
          final ally = await pickAlly(context, ctl);
          if (ally == null) return;
          targets = [ally];
        } else {
          targets = [engine.state.current.id];
        }
      case SpellKind.attack:
        final t = _target(ctl, targetId);
        if (t == null || !context.mounted) return;
        nat = await _roll(context, interactive, label: picked.name, subtitle: 'Spell attack vs ${t.name}', modifier: hero.spellAttack, dc: t.ac, mode: engine.rollModeFor(engine.state.current, t), attack: true);
        if (nat == null) return;
        targets = [t.id];
      default:
        final live = engine.state.enemies.where((e) => !e.down).toList();
        final first = _target(ctl, targetId)?.id;
        if (picked.aoe) {
          live.sort((a, b) => a.id == first ? -1 : (b.id == first ? 1 : 0));
          targets = live.take(3).map((e) => e.id).toList();
        } else {
          targets = [?first];
        }
    }
    await ctl.playerCast(picked, targets, nat);
  }

  static Future<String?> pickAlly(BuildContext context, AdventureController ctl) {
    final allies = ctl.adventure.combat!.allies;
    return showAppSheet<String>(context, builder: (ctx) {
      return ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 24), children: [
        const SheetTitle('Choose a target'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: RowGroup(children: [
            for (final a in allies) ListRow(title: a.name, trailing: Text('${a.hp}/${a.maxHp} HP', style: T.small()), onTap: () => Navigator.pop(ctx, a.id)),
          ]),
        ),
      ]);
    });
  }

  static Future<void> potion(BuildContext context, AdventureController ctl) async {
    final allies = ctl.adventure.combat!.allies;
    final id = allies.length == 1 ? allies.first.id : await pickAlly(context, ctl);
    if (id != null) await ctl.playerPotion(id);
  }

  static const abilityLabels = {
    'dodge': ('Dodge', 'Attacks against you have disadvantage until your next turn.'),
    'second_wind': ('Second Wind', 'Regain 1d10 + level HP. Bonus action.'),
    'rage': ('Rage', '+2 damage and resist physical damage. Bonus action.'),
    'lay_on_hands': ('Lay on Hands', 'Heal yourself from your divine pool.'),
    'hide': ('Hide', 'Advantage on your next attack. Bonus action.'),
    'move': ('Move', 'Switch between the front and back row. Leaving melee provokes an opportunity attack. Free.'),
    'smite': ('Divine Smite', 'Spend a level 1 slot: your next melee hit deals +2d8 radiant. Bonus action.'),
    'fey_presence': ('Fey Presence', 'Frighten every enemy that fails a WIS save. Once per rest.'),
    'disengage': ('Disengage', "Your movement won't provoke opportunity attacks this turn."),
    'action_surge': ('Action Surge', 'Take one more action this turn. Once per rest.'),
    'offhand': ('Off-hand attack', 'Two-weapon fighting: a bonus attack with your other light weapon.'),
    'flurry': ('Flurry of Blows', 'Spend 1 ki for two unarmed strikes. Bonus action.'),
    'inspire': ('Bardic Inspiration', 'Allies add 1d6 to their next attack. Bonus action.'),
    'turn_undead': ('Turn Undead', 'Undead must make a WIS save or flee. Once per rest.'),
    'shove': ('Shove', 'Athletics contest: knock a foe prone so attacks against it have advantage.'),
  };

  static Future<void> ability(BuildContext context, AdventureController ctl, {String? preset}) async {
    final abilities = CombatEngine(ctl.adventure).availableAbilities(ctl.hero);
    final picked = preset ??
        await showAppSheet<String>(context, builder: (ctx) {
          return ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 24), children: [
            const SheetTitle('Abilities'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: RowGroup(children: [for (final a in abilities) ListRow(title: abilityLabels[a]!.$1, subtitle: abilityLabels[a]!.$2, onTap: () => Navigator.pop(ctx, a))]),
            ),
          ]);
        });
    if (picked != null) await ctl.playerAbility(picked);
  }

  static Future<void> flee(BuildContext context, AdventureController ctl, {bool interactive = true}) async {
    final st = ctl.adventure.combat!;
    final hero = ctl.hero;
    final skill = hero.skillMod(Skill.athletics) >= hero.skillMod(Skill.acrobatics) ? Skill.athletics : Skill.acrobatics;
    final nat = await _roll(context, interactive, label: 'Flee', subtitle: skill.label, modifier: hero.skillMod(skill), dc: 8 + st.enemies.where((e) => !e.down).length * 2);
    if (nat != null) await ctl.playerFlee(nat);
  }
}
