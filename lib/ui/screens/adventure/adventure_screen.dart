import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../widgets/ai_gate.dart';
import '../../../game/adventure_controller.dart';
import '../../../game/dice.dart';
import '../../../models/adventure.dart';
import '../../../services/achievements.dart';
import '../../../services/audio/audio_service.dart';
import '../../../services/game_store.dart';
import '../../../services/image_service.dart';
import '../../../services/narrator.dart';
import '../../../services/settings.dart';
import '../../../services/usage.dart';
import '../../../theme/ui.dart';
import '../../widgets/dice.dart';
import '../../widgets/error_card.dart';
import '../../widgets/portrait.dart';
import '../../../data/srd.dart';
import '../character/character_sheet.dart';
import '../../../data/spellcasting.dart';
import '../../widgets/spell_picker.dart';
import '../character/level_up_sheet.dart';
import 'adventure_extras.dart';
import 'combat_panel.dart';
import 'campaign_flow.dart';
import 'shop_sheet.dart';
import 'log_view.dart';
import 'map_screen.dart';
import 'sheets.dart';
import '../story/story_tools.dart';
import '../story/story_extras.dart';

/// Hooks a controller's pending rolls / level-ups to dialogs.
mixin AdventureDialogs<T extends StatefulWidget> on State<T> {
  AdventureController get ctl;
  bool _rollOpen = false;
  bool _levelOpen = false;

  void handleControllerPrompts() {
    final pr = ctl.pendingRoll;
    if (pr != null && !_rollOpen) {
      _rollOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final nat = await DiceCheckSheet.show(context, label: pr.label, subtitle: pr.subtitle, modifier: pr.modifier, dc: pr.dc, mode: pr.mode, sides: pr.sides);
        _rollOpen = false;
        await pr.onResult(nat ?? rollDie(pr.sides));
      });
    }
    if (ctl.pendingLevelUp && !_levelOpen && !ctl.busy && !ctl.inCombat && pr == null) {
      _levelOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await runLevelUp(context, ctl);
        _levelOpen = false;
      });
    }
  }
}

/// Opens the level-up flow and applies the result.
Future<void> runLevelUp(BuildContext context, AdventureController ctl) async {
  final r = await showLevelUpSheet(context, ctl.hero);
  if (r != null) {
    ctl.applyLevelUp(r.classId, roll: r.rollHp, subclassId: r.subclassId, asi: r.asi, feat: r.feat);
    if (ctl.hero.hasSpellChoices && context.mounted) {
      await showSpellPicker(context, ctl.hero, onChanged: ctl.save, title: 'Choose new spells');
      ctl.refresh();
    }
  } else {
    ctl.pendingLevelUp = false;
  }
}

AdventureController createController(BuildContext context, Adventure a) => AdventureController(
      adventure: a,
      settings: context.read<SettingsController>(),
      store: context.read<GameStore>(),
      audio: context.read<AudioService>(),
      images: context.read<ImageService>(),
      usage: context.read<UsageTracker>(),
      narrator: context.read<Narrator>(),
      achievements: context.read<Achievements>(),
    );

class AdventureScreen extends StatefulWidget {
  const AdventureScreen({super.key, required this.adventure});
  final Adventure adventure;

  @override
  State<AdventureScreen> createState() => _AdventureScreenState();
}

class _AdventureScreenState extends State<AdventureScreen> with AdventureDialogs {
  late final AdventureController _ctl = createController(context, widget.adventure);
  // Looked up eagerly: dispose() can't read providers once the tree is unmounting.
  late final AudioService _audio;
  final _scroll = ScrollController();
  final _input = TextEditingController();
  int _lastLogLen = 0;
  bool _choicesCollapsed = false;
  late final DateTime _lastPlayed = widget.adventure.updatedAt;

  @override
  AdventureController get ctl => _ctl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) checkLocalAi(context);
    });
    _audio = context.read<AudioService>();
    for (final e in widget.adventure.log) {
      _ctl.animated.add('${e.at.microsecondsSinceEpoch}');
    }
    _lastLogLen = widget.adventure.log.length;
    _ctl.addListener(_onChange);
    _ctl.openShop = (kind, name) => showShopSheet(context, _ctl, kind: kind, name: name);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ctl.start();
    });
  }

  @override
  void dispose() {
    _ctl.removeListener(_onChange);
    _ctl.flush();
    _ctl.dispose();
    _scroll.dispose();
    _input.dispose();
    _audio.stopMusic();
    _audio.stopAmbience();
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    handleControllerPrompts();
    if (_ctl.adventure.log.length != _lastLogLen || _ctl.streaming != null) {
      _lastLogLen = _ctl.adventure.log.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // The feed is reversed, so offset 0 is the newest content.
        if (_scroll.hasClients && _scroll.offset > 0) _scroll.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      });
    }
    setState(() {});
  }

  void _submit() {
    final t = _input.text;
    _input.clear();
    unawaited(_ctl.freeText(t));
  }

  void _menu() {
    final settings = context.read<SettingsController>();
    showAppSheet(context, builder: (ctx) {
      return ListenableBuilder(
        listenable: settings,
        builder: (ctx, _) => ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 24), children: [
          SheetTitle(_ctl.adventure.title, subtitle: '${_ctl.adventure.setting} · ${_ctl.adventure.tone} · ${_ctl.adventure.difficulty} · ${_ctl.isAi ? 'AI' : 'Offline'}'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: [
              ...adventureMenuRows(context, ctx, _ctl),
            ]),
          ),
        ]),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final a = _ctl.adventure;
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    final m = a.map;
    final scene = a.scene.title.isEmpty || a.scene.title == 'The Beginning' ? a.setting : a.scene.title;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => showStoryOverview(context, _ctl),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a.title, style: T.h3(), overflow: TextOverflow.ellipsis),
            Text(_ctl.inCombat ? 'In combat' : scene, style: T.caption(color: _ctl.inCombat ? AppColors.danger : AppColors.textFaint), overflow: TextOverflow.ellipsis),
          ]),
        ),
        actions: [
          if (!wide) IconButton(tooltip: 'Map', icon: Badge(isLabelVisible: m != null, smallSize: 6, child: const Icon(Icons.map_outlined)), onPressed: () => openMapScreen(context, _ctl)),
          IconButton(tooltip: 'Journal', icon: const Icon(Icons.book_outlined), onPressed: () => showJournalSheet(context, _ctl)),
          IconButton(tooltip: 'More', icon: const Icon(Icons.more_horiz), onPressed: _menu),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Container(height: 1, color: AppColors.border)),
      ),
      body: Row(children: [
        Expanded(
          child: Column(children: [
            _statusBar(),
            RecapBanner(host: _ctl, lastPlayed: _lastPlayed),
            Expanded(child: _feed()),
            _bottom(),
          ]),
        ),
        if (wide)
          Container(
            width: 320,
            decoration: const BoxDecoration(border: Border(left: BorderSide(color: AppColors.border))),
            child: _sidePanel(),
          ),
      ]),
    );
  }

  Widget _statusBar() {
    final hero = _ctl.hero;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
      child: ContentWidth(
        child: Row(children: [
          InkWell(onTap: () => showPartySheet(context, _ctl), customBorder: const CircleBorder(), child: CharacterPortrait(character: hero, size: 32)),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => showVitalsSheet(context, _ctl),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('HP', style: T.caption()),
                const SizedBox(width: 6),
                Text('${hero.hp}/${hero.maxHp}', style: T.caption(color: AppColors.text)),
                const Spacer(),
                Text('AC ${hero.armorClass} · ${hero.gold} gp · Lv ${hero.level}', style: T.caption()),
              ]),
              const SizedBox(height: 6),
              Bar(value: hero.hp, max: hero.maxHp, color: hero.hp / hero.maxHp < 0.3 ? AppColors.danger : AppColors.hp),
            ]),
            ),
          ),
          for (final c in _ctl.adventure.companions)
            Padding(padding: const EdgeInsets.only(left: 8), child: Opacity(opacity: c.hp > 0 ? 1 : 0.4, child: InkWell(onTap: () => showNpcChat(context, _ctl, _ctl.adventure.personNamed(c.name)!), child: CharacterPortrait(character: c, size: 26)))),
        ]),
      ),
    );
  }

  Widget _feed() {
    final a = _ctl.adventure;
    final settings = context.watch<SettingsController>();
    final images = context.watch<ImageService>();
    final imageErrors = images.errors.entries.where((e) => e.key.contains(a.id)).toList();
    final lastSceneIdx = a.log.lastIndexWhere((e) => e.meta['scene'] != null);
    return ContentWidth(
      child: ListView.builder(
        controller: _scroll,
        reverse: true,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        itemCount: a.log.length + 1,
        itemBuilder: (ctx, i) {
          if (i == 0) {
            if ((_ctl.streaming ?? '').isNotEmpty) return Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text(_ctl.streaming!, style: T.reading()));
            if (_ctl.busy || _ctl.streaming != null) return ThinkingIndicator(first: a.log.isEmpty);
            if (_ctl.error != null) return ErrorCard(error: _ctl.error!, label: 'Story');
            if (a.finished) {
              return Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Column(children: [
                  Center(
                    child: a.hero.dead
                        ? const Tag('Fallen in hardcore', icon: Icons.sentiment_very_dissatisfied_outlined, color: AppColors.danger, filled: true)
                        : const Tag('Adventure complete', icon: Icons.emoji_events_outlined, color: AppColors.warning, filled: true),
                  ),
                  const SizedBox(height: 12),
                  FinishedActions(controller: _ctl),
                ]),
              );
            }
            if (imageErrors.isNotEmpty) {
              final e = imageErrors.first;
              return ErrorCard(
                error: e.value,
                label: e.key.startsWith('fx_') ? 'Special effect' : (e.value.toLowerCase().contains('video') ? 'Video' : 'Image'),
                onRetry: () {
                  images.errors.remove(e.key);
                  images.resume();
                  _ctl.generateMissingImages();
                },
                retryLabel: 'Retry missing images',
                onDismiss: () => setState(() => images.errors.removeWhere((k, _) => k.contains(a.id))),
              );
            }
            return const SizedBox(height: 8);
          }
          final idx = a.log.length - i;
          final e = a.log[idx];
          final id = '${e.at.microsecondsSinceEpoch}';
          final anim = settings.typewriter && !_ctl.animated.contains(id) && (e.kind == LogKind.narration || e.kind == LogKind.dialogue) && idx >= a.log.length - 6;
          return FadeIn(
            key: ValueKey(id),
            child: LogEntryView(entry: e, adventure: a, onTalk: (npc) => showNpcChat(context, _ctl, npc), onJournal: () => showJournalSheet(context, _ctl), onPassage: (e) => showPassageSheet(context, _ctl, e), animate: anim, speed: settings.typeSpeed * 2, latestScene: idx == lastSceneIdx, onAnimated: () => _ctl.animated.add(id)),
          );
        },
      ),
    );
  }

  Widget _bottom() {
    return Container(
      decoration: const BoxDecoration(color: AppColors.bg, border: Border(top: BorderSide(color: AppColors.border))),
      child: SafeArea(
        top: false,
        child: ContentWidth(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 220),
            alignment: Alignment.bottomCenter,
            child: _ctl.inCombat ? CombatPanel(controller: _ctl) : _choices(),
          ),
        ),
      ),
    );
  }

  Widget _choices() {
    final a = _ctl.adventure;
    final hero = a.hero;
    final disabled = _ctl.busy || _ctl.pendingRoll != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const NowReading(),
        ChoiceToolbar(host: _ctl, collapsed: _choicesCollapsed, hasChoices: a.choices.isNotEmpty,
          onToggle: () => setState(() => _choicesCollapsed = !_choicesCollapsed),
          trailing: [
            if (MediaQuery.sizeOf(context).width < 1100)
              IconButton(tooltip: 'Party', visualDensity: VisualDensity.compact, icon: const Icon(Icons.people_outline, size: 20), onPressed: () => showPartySheet(context, _ctl)),
          ]),
        if (a.choices.isNotEmpty && !_ctl.busy && !_choicesCollapsed)
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.34),
            child: SingleChildScrollView(
              child: Column(children: [
                for (final (i, c) in a.choices.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _ChoiceRow(
                      index: i,
                      choice: c,
                      modifier: c.check == null ? null : (c.check!.save ? hero.saveMod(c.check!.ability) : (c.check!.skill != null ? hero.skillMod(c.check!.skill!) : hero.mod(c.check!.ability))),
                      showDc: a.showDcs,
                      enabled: !disabled,
                      onTap: () => _ctl.choose(c),
                    ),
                  ),
              ]),
            ),
          ),
        const SizedBox(height: 4),
        Row(children: [
          Semantics(
            label: 'Story tools',
            child: CircleIconButton(icon: Icons.lightbulb_outline, size: 44, tooltip: 'Story tools', onPressed: () => showStoryActions(context, _ctl)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _input,
              enabled: !disabled,
              style: T.body(),
              textInputAction: TextInputAction.send,
              decoration: InputDecoration(
                hintText: _ctl.isAi ? 'Or describe what you do…' : 'Type a number or command (help)',
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: AppColors.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: AppColors.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: AppColors.textMuted)),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ),
          const SizedBox(width: 8),
          CircleIconButton(icon: Icons.arrow_upward, size: 44, tooltip: 'Send', onPressed: disabled ? null : _submit),
        ]),
      ]),
    );
  }

  Widget _sidePanel() {
    final a = _ctl.adventure;
    final h = a.hero;
    final slots = h.spellSlots;
    return ListView(padding: const EdgeInsets.all(16), children: [
      const SectionLabel('Hero', padding: EdgeInsets.fromLTRB(4, 0, 4, 10)),
      AppCard(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CharacterSheetScreen(character: h, onChanged: _ctl.save))),
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CharacterPortrait(character: h, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(h.name, style: T.h3(), overflow: TextOverflow.ellipsis),
                Text('Lv ${h.level} ${h.classSummary}', style: T.caption(), overflow: TextOverflow.ellipsis),
              ]),
            ),
            const Icon(Icons.open_in_new, size: 16, color: AppColors.textFaint),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            for (final (label, value) in [('AC', '${h.armorClass}'), ('HP', '${h.hp}/${h.maxHp}'), ('Init', signed(h.initiative)), ('Spd', '${h.speed}')])
              Expanded(
                child: Column(children: [
                  Text(value, style: T.number(15)),
                  Text(label, style: T.caption()),
                ]),
              ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            for (final ab in Ability.values)
              Expanded(
                child: Column(children: [
                  Text(signed(h.mod(ab)), style: T.small(color: AppColors.text)),
                  Text(ab.short, style: T.caption().copyWith(fontSize: 10)),
                ]),
              ),
          ]),
          if (slots.any((x) => x > 0)) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 10, runSpacing: 4, children: [
              for (var i = 0; i < slots.length; i++)
                if (slots[i] > 0)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('L${i + 1} ', style: T.caption()),
                    for (var k = 0; k < slots[i]; k++)
                      Container(
                        margin: const EdgeInsets.only(right: 2),
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: k < h.slotsRemaining(i + 1) ? AppColors.accent : AppColors.surface3),
                      ),
                  ]),
            ]),
          ],
          if (h.concentration != null || h.conditions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              if (h.concentration != null) Tag('Concentrating: ${spellById(h.concentration!)?.name ?? ''}', icon: Icons.blur_circular, color: AppColors.accent),
              for (final c in h.conditions.where((c) => !c.endsWith('Used') && !c.startsWith('SupUsed')).take(4)) Tag(c),
            ]),
          ],
        ]),
      ),
      const SectionLabel('Party'),
      RowGroup(children: [
        for (final c in a.party)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              CharacterPortrait(character: c, size: 36, viewable: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Expanded(child: Text(c.name, style: T.small(color: AppColors.text), overflow: TextOverflow.ellipsis)), Text('${c.hp}/${c.maxHp}', style: T.caption())]),
                  const SizedBox(height: 6),
                  Bar(value: c.hp, max: c.maxHp, color: AppColors.hp),
                ]),
              ),
            ]),
          ),
      ]),
      if (a.map != null) ...[
        SectionLabel('Map', trailing: GestureDetector(onTap: () => openMapScreen(context, _ctl), child: Text('Open', style: T.caption(color: AppColors.textMuted)))),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(aspectRatio: 1.4, child: GestureDetector(onTap: () => openMapScreen(context, _ctl), child: MapPreview(map: a.map!))),
        ),
      ],
      if (a.quests.any((q) => q.status == QuestStatus.active)) ...[
        const SectionLabel('Quests'),
        for (final q in a.quests.where((q) => q.status == QuestStatus.active))
          Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(q.title, style: T.small(color: AppColors.text))),
      ],
      if (a.npcs.isNotEmpty) ...[
        const SectionLabel('People'),
        for (final n in a.npcs.take(8))
          InkWell(
            onTap: () => showNpcChat(context, _ctl, n),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                NpcPortrait(npc: n, size: 28),
                const SizedBox(width: 10),
                Expanded(child: Text(n.name, style: T.small(color: AppColors.text))),
                Text(n.attitude, style: T.caption()),
              ]),
            ),
          ),
      ],
    ]);
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({required this.index, required this.choice, required this.onTap, required this.enabled, this.modifier, this.showDc = true});
  final bool showDc;
  final int index;
  final Choice choice;
  final VoidCallback onTap;
  final bool enabled;
  final int? modifier;

  @override
  Widget build(BuildContext context) {
    final c = choice;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: AppCard(
        onTap: enabled ? onTap : null,
        radius: 12,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Icon(c.data['shop'] != null ? Icons.storefront_outlined : choiceIcon(c.type), size: 18, color: c.type == ChoiceType.combat ? AppColors.danger : (c.data['shop'] != null ? AppColors.warning : AppColors.textMuted)),
          const SizedBox(width: 12),
          Expanded(child: Text(c.text, style: T.body())),
          if (c.check != null) ...[
            const SizedBox(width: 8),
            Tag(showDc ? '${c.check!.label} ${signed(modifier ?? 0)} · DC ${c.check!.dc}' : '${c.check!.label} ${signed(modifier ?? 0)}'),
          ],
        ]),
      ),
    );
  }
}

class _Thinking extends StatefulWidget {
  const _Thinking();

  @override
  State<_Thinking> createState() => _ThinkingState();
}

class _ThinkingState extends State<_Thinking> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Row(children: [
          for (var i = 0; i < 3; i++)
            Container(
              margin: const EdgeInsets.only(right: 5),
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.textMuted.withValues(alpha: 0.3 + 0.7 * (((_c.value * 3 - i) % 3) < 1 ? 1 - ((_c.value * 3 - i) % 3) : 0)),
              ),
            ),
        ]),
      ),
    );
  }
}
