import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/srd.dart';
import '../../../game/adventure_controller.dart';
import '../../../game/combat.dart';
import '../../../game/dice.dart';
import '../../../models/adventure.dart';
import '../../../services/audio/audio_service.dart';
import '../../../services/settings.dart';
import '../../../theme/ui.dart';
import '../../widgets/details_sheet.dart';
import '../../widgets/typewriter.dart';
import '../../../services/export.dart';
import 'adventure_screen.dart';
import 'adventure_extras.dart';
import 'campaign_flow.dart';
import 'combat_panel.dart';
import 'shop_sheet.dart';
import '../../../game/oracle.dart';
import 'map_screen.dart';
import 'sheets.dart';
import '../story/notes_screen.dart';
import '../story/story_tools.dart';

/// Minimal, classic text-adventure presentation of the same game.
class TextAdventureScreen extends StatefulWidget {
  const TextAdventureScreen({super.key, required this.adventure});
  final Adventure adventure;

  @override
  State<TextAdventureScreen> createState() => _TextAdventureScreenState();
}

class _TextAdventureScreenState extends State<TextAdventureScreen> {
  late final AdventureController _ctl = createController(context, widget.adventure);
  // Looked up eagerly: dispose() can't read providers once the tree is unmounting.
  late final AudioService _audio;
  final _scroll = ScrollController();
  final _input = TextEditingController();
  final _focus = FocusNode();
  bool _levelOpen = false;
  bool _choicesCollapsed = false;
  PendingRoll? _handledRoll;
  String? _targetId;
  String? _hint;

  @override
  void initState() {
    super.initState();
    _audio = context.read<AudioService>();
    for (final e in widget.adventure.log) {
      _ctl.animated.add('${e.at.microsecondsSinceEpoch}');
    }
    _ctl.addListener(_onChange);
    _ctl.openShop = (kind, name) => showShopSheet(context, _ctl, kind: kind, name: name);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ctl.start());
  }

  @override
  void dispose() {
    _ctl.removeListener(_onChange);
    _ctl.flush();
    _ctl.dispose();
    _scroll.dispose();
    _input.dispose();
    _focus.dispose();
    _audio.stopMusic();
    _audio.stopAmbience();
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    final pr = _ctl.pendingRoll;
    if (pr != null && !identical(pr, _handledRoll)) {
      // Text mode rolls automatically; the result is printed in the log.
      _handledRoll = pr;
      _audio.play('dice');
      unawaited(Future(() => pr.onResult(rollDie(pr.sides))));
    }
    if (_ctl.pendingLevelUp && !_levelOpen && !_ctl.busy && !_ctl.inCombat) {
      _levelOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await runLevelUp(context, _ctl);
        _levelOpen = false;
      });
    }
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients && _scroll.offset > 0) _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  TextStyle _mono({Color color = AppColors.text, double size = 14}) => T.monoStory(size, color: color);

  Future<void> _submit() async {
    final t = _input.text.trim();
    _input.clear();
    _focus.requestFocus();
    if (t.isEmpty) return;
    setState(() => _hint = null);
    final lower = t.toLowerCase();
    if (_ctl.inCombat) {
      await _combatCommand(lower);
      return;
    }
    switch (lower) {
      case 'map':
        openMapScreen(context, _ctl);
        return;
      case 'party':
        showPartySheet(context, _ctl);
        return;
      case 'journal':
        showJournalSheet(context, _ctl);
        return;
      case 'memory':
        showJournalSheet(context, _ctl, initial: 'Memory');
        return;
      case 'rewind' || 'undo':
        if (_ctl.canRewind) {
          _ctl.rewind();
        } else {
          setState(() => _hint = _ctl.adventure.hardcore ? 'No rewinds in hardcore mode.' : 'Nothing to rewind.');
        }
        return;
      case 'export':
        showStoryExport(context, _ctl);
        return;
      case 'people' || 'who':
        showJournalSheet(context, _ctl, initial: 'People');
        return;
      case 'notes' || 'note':
        openNotes(context, _ctl);
        return;
      case 'gallery' || 'art':
        showJournalSheet(context, _ctl, initial: 'Gallery');
        return;
      case 'tools' || 'ai' || 'ideas' || 'recap':
        showAiTools(context, _ctl);
        return;
      case 'oracle':
        showOracleSheet(context, _ctl);
        return;
    }
    if (lower.startsWith('oracle ') || lower.startsWith('? ')) {
      final q = t.substring(t.indexOf(' ') + 1).trim();
      _ctl.askOracle(q, Likelihood.even);
      return;
    }
    if (lower.startsWith('talk ')) {
      final name = lower.substring(5);
      final npc = _ctl.adventure.personNamed(name) ?? _ctl.adventure.people.where((n) => n.name.toLowerCase().contains(name)).firstOrNull;
      // Anyone can be talked to: unknown names join the cast.
      showNpcChat(context, _ctl, npc ?? _ctl.meet(t.substring(5).trim()));
      return;
    }
    await _ctl.freeText(t);
  }

  Future<void> _combatCommand(String t) async {
    if (!_ctl.isPlayerTurn) {
      setState(() => _hint = 'Wait for your turn.');
      return;
    }
    final engine = CombatEngine(_ctl.adventure);
    final foes = engine.state.enemies.where((e) => !e.down).toList();
    String? pick(String s) {
      final n = int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), ''));
      if (n != null && n >= 1 && n <= foes.length) return foes[n - 1].id;
      for (final f in foes) {
        if (s.contains(f.name.toLowerCase().split(' ').first)) return f.id;
      }
      return _targetId;
    }

    final parts = t.split(' ');
    final rest = parts.skip(1).join(' ');
    switch (parts.first) {
      case 'a' || 'attack' || 'hit':
        await CombatActions.attack(context, _ctl, pick(rest), interactive: false);
      case 'c' || 'cast':
        final spell = _ctl.hero.knownSpellDefs.where((s) => rest.contains(s.name.toLowerCase()) || rest.contains(s.id)).firstOrNull;
        if (spell == null) {
          setState(() => _hint = 'Known spells: ${_ctl.hero.knownSpellDefs.map((s) => s.name).join(', ')}');
          return;
        }
        await CombatActions.spell(context, _ctl, pick(rest.replaceAll(spell.name.toLowerCase(), '')), interactive: false, preset: spell);
      case 'p' || 'potion' || 'drink':
        await _ctl.playerPotion(engine.state.current.id);
      case 'd' || 'dodge':
        await _ctl.playerAbility('dodge');
      case 'f' || 'flee' || 'run':
        await CombatActions.flee(context, _ctl, interactive: false);
      case 'g' || 'grid':
        setState(() => _hint = _asciiGrid(engine));
      case 'm' || 'move':
        // "move c3": column letter + row number.
        final m = RegExp(r'([a-h])\s*([1-5])').firstMatch(rest);
        if (m == null) {
          setState(() => _hint = 'Move with a square like "move c3" (columns a–h, rows 1–5). Type "grid" to see the battlefield.');
          return;
        }
        await _ctl.playerMove(m.group(1)!.codeUnitAt(0) - 97, int.parse(m.group(2)!) - 1);
        setState(() => _hint = _asciiGrid(CombatEngine(_ctl.adventure)));
      case 'o' || 'order':
        final ally = engine.state.allies.where((a) => a.isAlly && rest.contains(a.name.toLowerCase().split(' ').first)).firstOrNull;
        final order = CombatEngine.orders.keys.where((k) => rest.contains(k)).firstOrNull;
        if (ally == null || order == null) {
          setState(() => _hint = 'Order a companion: order <name> focus|defend|heal|hold|free');
          return;
        }
        _ctl.orderCompanion(ally.id, order, targetId: pick(''));
      default:
        final abilities = engine.availableAbilities(_ctl.hero);
        final match = abilities.where((a) => t.replaceAll(' ', '_').contains(a)).firstOrNull;
        if (match != null) {
          await _ctl.playerAbility(match);
        } else {
          setState(() => _hint = 'Try: attack 1 · cast <spell> · move c3 · grid · order <name> focus · potion · dodge · flee');
        }
    }
  }

  /// The battlefield as text: allies are letters, enemies are numbers.
  String _asciiGrid(CombatEngine engine) {
    final foes = engine.state.enemies.where((e) => !e.down).toList();
    final b = StringBuffer('   a b c d e f g h\n');
    for (var y = 0; y < CombatEngine.gridH; y++) {
      b.write(' ${y + 1} ');
      for (var x = 0; x < CombatEngine.gridW; x++) {
        final c = engine.occupant(x, y);
        b.write(c == null ? '. ' : (c.isEnemy ? '${foes.indexOf(c) + 1} ' : (c.isPlayer ? '@ ' : '${c.name[0].toUpperCase()} ')));
      }
      b.write('\n');
    }
    b.write('@ you · numbers = enemies (attack 1, attack 2…) · ${engine.movesLeft(engine.state.current) * 5} ft of movement left');
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final a = _ctl.adventure;
    final h = a.hero;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(a.title, style: T.h3(), overflow: TextOverflow.ellipsis),
        actions: [
          UsageChip(usage: a.usage, title: a.title, turns: a.turns, storyId: a.id),
          IconButton(tooltip: 'Map', icon: const Icon(Icons.map_outlined), onPressed: () => openMapScreen(context, _ctl)),
          IconButton(tooltip: 'Journal', icon: const Icon(Icons.book_outlined), onPressed: () => showJournalSheet(context, _ctl)),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz),
            onSelected: (v) {
              if (v == 'party') showPartySheet(context, _ctl);
              if (v == 'layout') {
                a.textMode = false;
                _ctl.save();
                Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => AdventureScreen(adventure: a)));
              }
              if (v == 'help') _ctl.freeText('help');
              if (v == 'more') {
                showAppSheet(context, builder: (ctx) => ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: adventureMenuRows(context, ctx, _ctl)));
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'more', child: Text('AI tools, people, gallery, export…')),
              PopupMenuItem(value: 'party', child: Text('Party')),
              PopupMenuItem(value: 'help', child: Text('Commands')),
              PopupMenuItem(value: 'layout', child: Text('Switch to standard layout')),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(29),
          child: Container(
            height: 29,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
            child: Row(children: [
              Expanded(
                child: Text(
                  '${h.name.split(' ').first} · HP ${h.hp}/${h.maxHp} · AC ${h.armorClass} · ${h.gold} gp',
                  style: _mono(color: h.hp / h.maxHp < 0.3 ? AppColors.danger : AppColors.textMuted, size: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  _ctl.inCombat ? 'IN COMBAT' : a.scene.title,
                  style: _mono(color: _ctl.inCombat ? AppColors.danger : AppColors.textFaint, size: 12),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                ),
              ),
            ]),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ContentWidth(
          maxWidth: 760,
          child: Column(children: [
            Expanded(child: _feed()),
            _actions(),
          ]),
        ),
      ),
    );
  }

  Widget _feed() {
    final a = _ctl.adventure;
    final settings = context.watch<SettingsController>();
    final tail = <Widget>[
      if ((_ctl.streaming ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_ctl.streaming!, style: _mono())),
      if (_ctl.busy && (_ctl.streaming ?? '').isEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text('…', style: _mono(color: AppColors.textFaint))),
      if (_ctl.error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('error: ${_ctl.error}', style: _mono(color: AppColors.danger, size: 13))),
      if (a.finished) Padding(padding: const EdgeInsets.only(top: 16), child: Text(a.hero.dead ? '*** YOU HAVE DIED ***' : '*** THE END ***', style: _mono(color: a.hero.dead ? AppColors.danger : AppColors.accent))),
      if (a.finished) Padding(padding: const EdgeInsets.only(top: 12), child: FinishedActions(controller: _ctl)),
    ];
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
      itemCount: a.log.length + 1,
      itemBuilder: (ctx, i) {
        if (i == 0) return Column(crossAxisAlignment: CrossAxisAlignment.start, children: tail);
        final idx = a.log.length - i;
        return _line(a.log[idx], settings);
      },
    );
  }

  Widget _line(LogEntry e, SettingsController settings) {
    final id = '${e.at.microsecondsSinceEpoch}';
    Widget w;
    switch (e.kind) {
      case LogKind.narration:
      case LogKind.dialogue:
        w = Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 2),
          child: TypewriterText(
            key: ValueKey(id),
            text: e.speaker != null ? '${e.speaker}: ${e.text}' : e.text,
            animate: settings.typewriter && !_ctl.animated.contains(id),
            speed: settings.typeSpeed * 3,
            onDone: () => _ctl.animated.add(id),
            style: _mono(),
          ),
        );
      case LogKind.player:
        w = Padding(padding: const EdgeInsets.only(top: 14), child: Text('> ${e.text}', style: _mono(color: AppColors.accent)));
      case LogKind.roll:
        final ok = e.meta['ok'] == true;
        w = Text('  [d20] ${e.meta['label'] ?? 'Roll'}: ${e.meta['total']} vs DC ${e.meta['dc']} — ${ok ? 'success' : 'failure'}', style: _mono(color: ok ? AppColors.success : AppColors.danger, size: 13));
      case LogKind.combat:
        final c = switch (e.meta['fx']) { 'hit' || 'death' => AppColors.danger, 'crit' => AppColors.warning, 'heal' => AppColors.success, 'spell' => AppColors.accent, _ => AppColors.textMuted };
        w = Text('  ${e.text}', style: _mono(color: c, size: 13));
      case LogKind.loot:
        w = Text('  + ${e.text}', style: _mono(color: AppColors.success, size: 13));
      case LogKind.levelup:
        w = Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text('* ${e.text}', style: _mono(color: AppColors.accent)));
      case LogKind.companion:
        w = Text('  ${e.speaker}: "${e.text}"', style: _mono(color: AppColors.textMuted, size: 13));
      case LogKind.oracle:
        w = Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('  [oracle] ${e.meta['q'] ?? ''} -> ${e.text}${e.meta['event'] != null ? '  ! ${e.meta['event']}' : ''}', style: _mono(color: AppColors.info, size: 13)),
        );
      case LogKind.system:
        if (e.meta['scene'] != null) {
          w = Padding(padding: const EdgeInsets.only(top: 22, bottom: 2), child: Text('== ${e.text.toUpperCase()} ==', style: _mono(color: AppColors.textFaint, size: 12.5)));
        } else {
          w = Text(e.text, style: _mono(color: AppColors.textFaint, size: 13));
        }
    }
    if (!hasDetails(e)) return w;
    return InkWell(
      onTap: () => showLogDetails(context, e),
      borderRadius: BorderRadius.circular(6),
      child: Row(children: [Expanded(child: w), Text(' ⓘ', style: _mono(color: AppColors.textFaint, size: 11))]),
    );
  }

  // ------------------------------------------------------------ actions

  Widget _actions() {
    return Container(
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_ctl.inCombat) _combatActions() else ...[
          if (_ctl.adventure.choices.isNotEmpty)
            TextButton.icon(onPressed: () => setState(() => _choicesCollapsed = !_choicesCollapsed),
              icon: Icon(_choicesCollapsed ? Icons.expand_more : Icons.expand_less),
              label: Text(_choicesCollapsed ? 'Show choices' : 'Hide choices')),
          if (!_choicesCollapsed) _choiceActions(),
        ],
        if (_hint != null) Padding(padding: const EdgeInsets.only(top: 6, left: 4), child: Text(_hint!, style: _mono(color: AppColors.textFaint, size: 12))),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.only(left: 12, right: 4),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
          child: Row(children: [
            Text('>', style: _mono(color: AppColors.accent, size: 16)),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _input,
                focusNode: _focus,
                style: _mono(),
                cursorColor: AppColors.accent,
                decoration: InputDecoration(
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  hintText: _ctl.inCombat ? 'attack 1, cast fire bolt 2, potion, flee' : 'type a number, an action, or help',
                  hintStyle: _mono(color: AppColors.textFaint, size: 13),
                ),
                onSubmitted: (_) => _submit(),
              ),
            ),
            IconButton(icon: const Icon(Icons.keyboard_return, size: 18), onPressed: _submit),
          ]),
        ),
      ]),
    );
  }

  Widget _choiceActions() {
    final a = _ctl.adventure;
    if (_ctl.busy || a.choices.isEmpty) return const SizedBox.shrink();
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.3),
      child: SingleChildScrollView(
        child: Column(children: [
          for (final (i, c) in a.choices.indexed)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _ctl.choose(c),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 22,
                    alignment: Alignment.center,
                    margin: const EdgeInsets.only(right: 10, top: 1),
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(5), border: Border.all(color: AppColors.borderStrong)),
                    child: Text('${i + 1}', style: _mono(color: AppColors.accent, size: 12)),
                  ),
                  Expanded(child: Text(c.text, style: _mono(size: 13.5))),
                  if (c.check != null) ...[
                    const SizedBox(width: 8),
                    Text('${c.check!.label} DC${c.check!.dc}', style: _mono(color: AppColors.textFaint, size: 11.5)),
                  ],
                ]),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _combatActions() {
    final st = _ctl.adventure.combat!;
    final foes = st.enemies.where((e) => !e.down).toList();
    if (_targetId == null || foes.every((f) => f.id != _targetId)) _targetId = foes.isEmpty ? null : foes.first.id;
    final my = _ctl.isPlayerTurn;
    final hero = _ctl.hero;
    Widget chip(String label, VoidCallback? onTap, {bool primary = false, bool selected = false}) => Padding(
          padding: const EdgeInsets.only(right: 6, bottom: 6),
          child: Opacity(
            opacity: onTap == null ? 0.35 : 1,
            child: Material(
              color: primary ? AppColors.text : (selected ? AppColors.surface3 : AppColors.surface),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: selected ? AppColors.danger : AppColors.border)),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: onTap,
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), child: Text(label, style: _mono(color: primary ? AppColors.bg : AppColors.text, size: 12.5))),
              ),
            ),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('ROUND ${st.round} · ${my ? 'your turn' : '${st.current.name} acts…'}', style: _mono(color: AppColors.danger, size: 12)),
      const SizedBox(height: 8),
      Wrap(children: [
        for (final (i, f) in foes.indexed)
          chip('${i + 1} ${f.name} ${f.hp}/${f.maxHp} AC${f.ac}', () => setState(() => _targetId = f.id), selected: f.id == _targetId),
      ]),
      Wrap(children: [
        chip('attack', my ? () => CombatActions.attack(context, _ctl, _targetId, interactive: false) : null, primary: true),
        if (hero.isCaster) chip('cast…', my ? () => CombatActions.spell(context, _ctl, _targetId, interactive: false) : null),
        if (hero.inventory.any((i) => i.def?.type == ItemType.potion)) chip('potion', my ? () => CombatActions.potion(context, _ctl) : null),
        chip('ability…', my ? () => CombatActions.ability(context, _ctl) : null),
        chip('flee', my ? () => CombatActions.flee(context, _ctl, interactive: false) : null),
      ]),
    ]);
  }
}
