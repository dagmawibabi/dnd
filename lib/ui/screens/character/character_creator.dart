import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../art/class_icon.dart';
import '../../../data/equipment.dart';
import '../../../data/inventory_rules.dart';
import '../../../data/names.dart';
import '../../../data/presets.dart';
import '../../../data/srd.dart';
import '../../../game/dice.dart';
import '../../../models/character.dart';
import '../../../services/achievements.dart';
import '../../../services/ai/dungeon_master.dart';
import '../../../services/audio/audio_service.dart';
import '../../../services/game_store.dart';
import '../../../services/image_service.dart';
import '../../../services/settings.dart';
import '../../../theme/ui.dart';
import '../../../data/spellcasting.dart';
import '../../widgets/dice.dart';
import '../../widgets/spell_picker.dart';
import '../../widgets/portrait.dart';
import '../adventure/new_adventure_screen.dart';
import 'character_sheet.dart';

enum AbilityMethod { pointBuy, standardArray, roll }

const _pointCost = {8: 0, 9: 1, 10: 2, 11: 3, 12: 4, 13: 5, 14: 7, 15: 9};
const _standardArray = [15, 14, 13, 12, 10, 8];

class CharacterCreator extends StatefulWidget {
  const CharacterCreator({super.key, this.thenStartAdventure = false, this.companionMode = false});
  final bool thenStartAdventure;
  final bool companionMode;

  @override
  State<CharacterCreator> createState() => _CharacterCreatorState();
}

class _CharacterCreatorState extends State<CharacterCreator> {
  static const _steps = ['Start', 'Race', 'Class', 'Background', 'Abilities', 'Skills', 'Appearance', 'Details', 'Review'];
  int _step = 0;

  String _raceId = 'human';
  String? _subraceId;
  String _classId = 'fighter';
  String _bgId = 'folk_hero';
  AbilityMethod _method = AbilityMethod.pointBuy;
  Map<Ability, int> _scores = {for (final a in Ability.values) a: 8};
  final List<int?> _arrayAssign = List.filled(6, null);
  List<int> _rolled = [];
  Ability? _plus2 = Ability.str;
  Ability? _plus1 = Ability.con;
  final Set<Skill> _skills = {};
  PortraitSpec _portrait = PortraitSpec.random('human');
  final _nameCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _persCtrl = TextEditingController();
  final _storyCtrl = TextEditingController();
  String _pronouns = 'he/him';
  final _lookCtrl = TextEditingController();
  String get _appearance => _lookCtrl.text;
  set _appearance(String v) => _lookCtrl.text = v;
  bool _aiBuilding = false;

  /// Working copy used to choose spells; its picks are copied into the final hero.
  Character? _spellDraft;

  // Starting equipment
  bool _buyGear = false;
  String? _weaponId;
  final Map<String, int> _cart = {};

  int get _classGold => classStartingGold[_classId] ?? 50;
  int get _cartCost => _cart.entries.fold(0, (t, e) => t + (itemById(e.key)?.value ?? 0) * e.value);

  Character _draftFor() {
    final d = _spellDraft;
    if (d != null && d.classLevels.keys.first == _classId && d.level == _startLevel && d.raceId == _raceId) return d;
    final fresh = _build(withSpells: false);
    return _spellDraft = fresh;
  }
  String _alignment = 'Neutral Good';
  int _startLevel = 1;
  bool _busyStory = false;

  @override
  void initState() {
    super.initState();
    _applyRecommended();
    _nameCtrl.text = randomName(_raceId);
    _titleCtrl.text = classById(_classId).epithet;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _titleCtrl.dispose();
    _persCtrl.dispose();
    _storyCtrl.dispose();
    _lookCtrl.dispose();
    super.dispose();
  }

  RaceDef get _race => raceById(_raceId);
  ClassDef get _class => classById(_classId);
  BackgroundDef get _bg => backgroundById(_bgId);

  void _go(int step) => setState(() => _step = step.clamp(0, _steps.length - 1));

  void _applyRecommended() {
    final rec = _class.recommendedStats;
    if (rec.isNotEmpty) {
      _scores = {for (final a in Ability.values) a: (rec[a] ?? 10).clamp(8, 15)};
      while (_pointsSpent > 27) {
        final top = _scores.entries.reduce((a, b) => a.value >= b.value ? a : b);
        _scores[top.key] = top.value - 1;
      }
    }
    _plus2 = _class.primary;
    _plus1 = _class.primary == Ability.con ? Ability.dex : Ability.con;
    _method = AbilityMethod.pointBuy;
  }

  int get _pointsSpent => _scores.values.fold(0, (a, v) => a + (_pointCost[v.clamp(8, 15)] ?? 0));

  Map<Ability, int> get _baseScores => switch (_method) {
        AbilityMethod.pointBuy => _scores,
        AbilityMethod.standardArray => {for (final a in Ability.values) a: _arrayAssign[a.index] == null ? 8 : _standardArray[_arrayAssign[a.index]!]},
        AbilityMethod.roll => {for (final a in Ability.values) a: a.index < _rolled.length ? _rolled[a.index] : 8},
      };

  Map<Ability, int> get _subraceBonus {
    if (_subraceId == null || _race.subraces.isEmpty) return {};
    return _race.subraces.firstWhere((s) => s.id == _subraceId, orElse: () => _race.subraces.first).bonuses;
  }

  int _final(Ability a) => (_baseScores[a] ?? 8) + (_plus2 == a ? 2 : 0) + (_plus1 == a ? 1 : 0) + (_subraceBonus[a] ?? 0);

  Character _build({bool withSpells = true}) {
    final c = Character.build(
      name: _nameCtrl.text.trim().isEmpty ? randomName(_raceId) : _nameCtrl.text.trim(),
      title: _titleCtrl.text.trim(),
      raceId: _raceId,
      subraceId: _subraceId,
      classId: _classId,
      backgroundId: _bgId,
      baseScores: _baseScores.map((k, v) => MapEntry(k, v + (_subraceBonus[k] ?? 0))),
      plus2: _plus2,
      plus1: _plus1,
      skills: _skills,
      portrait: _portrait,
      level: _startLevel,
      alignment: _alignment,
      personality: _persCtrl.text.trim(),
      backstory: _storyCtrl.text.trim(),
      pronouns: _pronouns,
    );
    c.isCompanion = widget.companionMode;
    c.appearance = _appearance;
    _applyEquipment(c);
    final d = _spellDraft;
    if (withSpells && d != null && d.classLevels.keys.first == _classId && d.level == _startLevel) {
      c.spells = List.of(d.spells);
      c.spellbook = List.of(d.spellbook);
    }
    return c;
  }

  void _applyEquipment(Character c) {
    if (_buyGear) {
      c.inventory.removeWhere((i) => _class.startingItems.contains(i.itemId));
      for (final e in _cart.entries) {
        final def = itemById(e.key);
        if (def == null) continue;
        c.inventory.add(InventoryItem.of(e.key, qty: e.value));
      }
      // Equip the best of what was bought.
      InventoryItem? best(ItemType t, int Function(ItemDef) score) {
        final list = c.inventory.where((i) => i.def?.type == t).toList()..sort((a, b) => score(b.def!).compareTo(score(a.def!)));
        return list.firstOrNull;
      }

      best(ItemType.weapon, (d) => d.value)?.equipped = true;
      best(ItemType.armor, (d) => d.ac ?? 0)?.equipped = true;
      best(ItemType.shield, (d) => d.ac ?? 0)?.equipped = true;
      c.gold = backgroundById(_bgId).gold + _classGold - _cartCost;
    } else if (_weaponId != null) {
      final current = c.inventory.where((i) => i.def?.type == ItemType.weapon && i.equipped).firstOrNull;
      if (current?.itemId != _weaponId) {
        if (current != null) c.inventory.remove(current);
        c.inventory.insert(0, InventoryItem.of(_weaponId!, equipped: true, qty: _weaponId == 'darts' ? 10 : 1));
      }
    }
  }

  Widget _equipmentSection() {
    final weapons = startingWeapons(_classId);
    final kitWeapon = _class.startingItems.map(itemById).whereType<ItemDef>().where((d) => d.type == ItemType.weapon).firstOrNull;
    final remaining = backgroundById(_bgId).gold + _classGold - _cartCost;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionLabel('Starting equipment'),
      SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: [
          const ButtonSegment(value: false, label: Text('Class kit'), icon: Icon(Icons.backpack_outlined, size: 16)),
          ButtonSegment(value: true, label: Text('Buy · ${_classGold + backgroundById(_bgId).gold} gp'), icon: const Icon(Icons.paid_outlined, size: 16)),
        ],
        selected: {_buyGear},
        onSelectionChanged: (v) => setState(() => _buyGear = v.first),
      ),
      const SizedBox(height: 10),
      if (!_buyGear) ...[
        Text(_class.startingItems.map((id) => itemById(id)?.name ?? id).join(', '), style: T.small()),
        const SizedBox(height: 10),
        Text('MAIN WEAPON', style: T.overline()),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final w in weapons)
            ChoiceChip(
              label: Text('${w.name} · ${w.damage}'),
              selected: (_weaponId ?? kitWeapon?.id) == w.id,
              onSelected: (_) => setState(() => _weaponId = w.id),
            ),
        ]),
      ] else ...[
        Row(children: [
          Expanded(child: Text('Spend your starting gold on gear. Unspent coins stay in your purse.', style: T.small())),
          Tag('$remaining gp left', color: remaining < 0 ? AppColors.danger : AppColors.warning),
        ]),
        const SizedBox(height: 8),
        RowGroup(children: [
          for (final d in starterShop())
            ListRow(
              title: d.name,
              subtitle: '${d.value} gp · ${[if (d.damage != null) '${d.damage} ${d.damageType ?? ''}', if (d.ac != null) d.type == ItemType.shield ? '+${d.ac} AC' : 'AC ${d.ac}', if (d.heal != null) 'heals ${d.heal}', if (d.weight > 0) '${d.weight} lb'].join(' · ')}',
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if ((_cart[d.id] ?? 0) > 0) ...[
                  IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.remove, size: 18), onPressed: () => setState(() {
                    final n = (_cart[d.id] ?? 0) - 1;
                    if (n <= 0) {
                      _cart.remove(d.id);
                    } else {
                      _cart[d.id] = n;
                    }
                  })),
                  Text('${_cart[d.id]}', style: T.small(color: AppColors.text)),
                ],
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.add, size: 18),
                  onPressed: remaining >= d.value ? () => setState(() => _cart[d.id] = (_cart[d.id] ?? 0) + 1) : null,
                ),
              ]),
            ),
        ]),
      ],
    ]);
  }

  Future<void> _create([Character? preset]) async {
    final c = preset ?? _build();
    await context.read<GameStore>().saveCharacter(c);
    if (!mounted) return;
    context.read<Achievements>().add(Stat.characters);
    context.read<AudioService>().play('success');
    if (widget.companionMode) {
      Navigator.of(context).pop(c);
    } else if (widget.thenStartAdventure) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => NewAdventureScreen(heroId: c.id)));
    } else {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => CharacterSheetScreen(characterId: c.id)));
    }
  }

  void _randomize() {
    final r = Rng.unseeded();
    _raceId = r.pick(races).id;
    _subraceId = _race.subraces.isEmpty ? null : r.pick(_race.subraces).id;
    _classId = r.pick(classes).id;
    _spellDraft = null;
    _weaponId = null;
    _buyGear = false;
    _cart.clear();
    _bgId = r.pick(backgrounds).id;
    _applyRecommended();
    _skills
      ..clear()
      ..addAll(r.sample(_class.skillChoices.where((s) => !_bg.skills.contains(s)).toList(), _class.numSkills));
    _portrait = PortraitSpec.random(_raceId);
    _nameCtrl.text = randomName(_raceId, rng: r);
    _titleCtrl.text = randomEpithet(rng: r);
    _alignment = r.pick(alignments);
    _go(_steps.length - 1);
  }

  bool get _canNext => switch (_step) {
        4 => _method == AbilityMethod.pointBuy ? _pointsSpent <= 27 : (_method == AbilityMethod.standardArray ? !_arrayAssign.contains(null) : _rolled.length == 6),
        5 => _skills.length == _class.numSkills,
        _ => true,
      };

  @override
  Widget build(BuildContext context) {
    final last = _step == _steps.length - 1;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        title: Text(_step == 0 ? (widget.companionMode ? 'New companion' : 'New character') : _steps[_step]),
        actions: [
          if (_step > 0) Center(child: Padding(padding: const EdgeInsets.only(right: 4), child: Text('$_step of ${_steps.length - 1}', style: T.caption()))),
          if (_step > 0 && !last) IconButton(tooltip: 'Randomize', icon: const Icon(Icons.shuffle), onPressed: _randomize),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: LinearProgressIndicator(value: _step / (_steps.length - 1), minHeight: 2, backgroundColor: AppColors.border),
        ),
      ),
      body: Column(children: [
        Expanded(
          child: ContentWidth(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: KeyedSubtree(key: ValueKey(_step), child: _body()),
            ),
          ),
        ),
        if (_step > 0)
          Container(
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
            child: SafeArea(
              top: false,
              child: ContentWidth(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Row(children: [
                    Expanded(child: AppButton(label: 'Back', kind: ButtonKind.secondary, onPressed: () => _go(_step - 1))),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: last
                          ? AppButton(label: widget.companionMode ? 'Add companion' : 'Create character', onPressed: () => _create())
                          : AppButton(label: 'Next', onPressed: _canNext ? () => _go(_step + 1) : null),
                    ),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _body() => switch (_step) {
        0 => _startStep(),
        1 => _raceStep(),
        2 => _classStep(),
        3 => _bgStep(),
        4 => _abilityStep(),
        5 => _skillStep(),
        6 => _appearanceStep(),
        7 => _detailsStep(),
        _ => _reviewStep(),
      };

  Widget _hint(String text) => Padding(padding: const EdgeInsets.fromLTRB(4, 4, 4, 16), child: Text(text, style: T.bodyMuted()));

  // ----------------------------------------------------------------- start

  Widget _startStep() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _aiCard(),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _startCard(Icons.tune, 'Build', 'Choose every detail', () => _go(1))),
          const SizedBox(width: 10),
          Expanded(child: _startCard(Icons.shuffle, 'Random', 'Generate one instantly', _randomize)),
        ]),
        const SectionLabel('Presets'),
        RowGroup(children: [for (final p in presets) _presetRow(p)]),
      ],
    );
  }

  Widget _aiCard() {
    final settings = context.watch<SettingsController>();
    final on = settings.useAiCreator;
    return AppCard(
      onTap: on && !_aiBuilding ? _aiCreate : null,
      borderColor: on ? AppColors.accent : null,
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: on ? AppColors.accentSoft : AppColors.surface2, borderRadius: BorderRadius.circular(12)),
          child: _aiBuilding
              ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))
              : Icon(Icons.auto_awesome, color: on ? AppColors.accent : AppColors.textFaint),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Let AI create my character', style: T.h3(color: on ? AppColors.text : AppColors.textMuted)),
            const SizedBox(height: 2),
            Text(
              !on
                  ? 'Turn on AI story and "Character creation" in Settings → AI to use this.'
                  : (_aiBuilding ? 'Designing your hero…' : 'Race, class, stats, skills, backstory, looks${settings.useAiPortraits ? ' and a portrait' : ''}. Give it an idea or let it surprise you.'),
              style: T.small(),
            ),
          ]),
        ),
        if (on && !_aiBuilding) const Icon(Icons.chevron_right, color: AppColors.textFaint),
      ]),
    );
  }

  Future<void> _aiCreate() async {
    final idea = await showAppSheet<String>(context, builder: (ctx) {
      final ctrl = TextEditingController();
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Describe your hero', style: T.h2()),
            const SizedBox(height: 4),
            Text('A sentence is plenty, or leave it blank for a surprise.', style: T.small()),
            const SizedBox(height: 14),
            TextField(controller: ctrl, autofocus: true, minLines: 2, maxLines: 4, style: T.body(), decoration: const InputDecoration(hintText: 'A retired pirate who found religion; a nervous elf wizard who collects bugs')),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final s in const ['A grumpy dwarf healer', 'A charming halfling con artist', 'A tiefling knight seeking redemption', 'A feral elf raised by wolves', 'A scholarly dragonborn sorcerer'])
                ActionChip(label: Text(s), onPressed: () => ctrl.text = s),
            ]),
            const SizedBox(height: 16),
            AppButton(label: 'Create', icon: Icons.auto_awesome, kind: ButtonKind.accent, onPressed: () => Navigator.pop(ctx, ctrl.text)),
            const SizedBox(height: 8),
            AppButton(label: 'Surprise me', kind: ButtonKind.secondary, onPressed: () => Navigator.pop(ctx, '')),
          ]),
        ),
      );
    });
    if (idea == null || !mounted) return;
    final settings = context.read<SettingsController>();
    final images = context.read<ImageService>();
    setState(() => _aiBuilding = true);
    try {
      final j = await AiDungeonMaster(settings).createCharacter(
        idea: idea,
        raceIds: races.map((r) => r.id).toList(),
        classIds: classes.map((c) => c.id).toList(),
        backgroundIds: backgrounds.map((b) => b.id).toList(),
        skills: Skill.values.map((s) => s.label).toList(),
      );
      if (j.isEmpty) throw const FormatException('The storyteller returned nothing usable.');
      if (!mounted) return;
      _applyAi(j);
      setState(() {});
      if (settings.useAiPortraits && mounted) {
        final c = _build();
        final prompt = (j['image_prompt'] ?? '').toString();
        final path = await images.generate('portrait_creator', 'Portrait of ${c.name}, a ${c.raceLabel} ${_class.name}. ${prompt.isNotEmpty ? prompt : _appearance}');
        if (path != null) _portrait.aiImagePath = path;
        if (mounted && path == null && images.errors['portrait_creator'] != null) {
          showToast(context, 'Character created. Portrait failed: ${images.errors['portrait_creator']}', icon: Icons.error_outline);
        }
      }
      if (mounted) {
        context.read<AudioService>().play('levelup');
        _go(_steps.length - 1);
      }
    } catch (e) {
      if (mounted) showToast(context, 'Couldn\'t create a character: $e', icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _aiBuilding = false);
    }
  }

  static Color? _hex(dynamic v) {
    final s = (v ?? '').toString().replaceAll('#', '');
    if (s.length != 6) return null;
    final n = int.tryParse(s, radix: 16);
    return n == null ? null : Color(0xFF000000 | n);
  }

  /// Applies an AI-designed character, clamping everything to valid rules.
  void _applyAi(Map<String, dynamic> j) {
    String pick(String key, List<String> ids, String fallback) {
      final v = (j[key] ?? '').toString().toLowerCase().trim();
      return ids.contains(v) ? v : (ids.where((id) => v.contains(id) || id.contains(v) && v.isNotEmpty).firstOrNull ?? fallback);
    }

    _raceId = pick('race', races.map((r) => r.id).toList(), 'human');
    final sub = (j['subrace'] ?? '').toString().toLowerCase();
    _subraceId = _race.subraces.isEmpty ? null : (_race.subraces.where((s) => s.id == sub).firstOrNull ?? _race.subraces.first).id;
    _classId = pick('class', classes.map((c) => c.id).toList(), 'fighter');
    _spellDraft = null;
    _weaponId = null;
    _buyGear = false;
    _cart.clear();
    _bgId = pick('background', backgrounds.map((b) => b.id).toList(), 'folk_hero');
    // Scores: clamp to 8..15 and trim until within 27 points.
    final raw = j['scores'] is Map ? Map<String, dynamic>.from(j['scores']) : <String, dynamic>{};
    _method = AbilityMethod.pointBuy;
    int number(dynamic value, int fallback) => (num.tryParse('$value')?.toInt() ?? fallback);
    _scores = {for (final a in Ability.values) a: number(raw[a.short] ?? raw[a.short.toLowerCase()], 10).clamp(8, 15)};
    while (_pointsSpent > 27) {
      final top = _scores.entries.reduce((a, b) => a.value >= b.value ? a : b);
      _scores[top.key] = top.value - 1;
    }
    Ability? ab(dynamic v) {
      try {
        return AbilityX.fromShort(v.toString());
      } catch (_) {
        return null;
      }
    }

    _plus2 = ab(j['plus2']) ?? _class.primary;
    _plus1 = ab(j['plus1']) ?? (_plus2 == Ability.con ? Ability.dex : Ability.con);
    if (_plus1 == _plus2) _plus1 = _plus2 == Ability.con ? Ability.dex : Ability.con;
    final available = _class.skillChoices.where((s) => !_bg.skills.contains(s)).toList();
    final wanted = (j['skills'] is List ? (j['skills'] as List).map((e) => e.toString().toLowerCase()).toList() : <String>[]);
    _skills
      ..clear()
      ..addAll(available.where((s) => wanted.contains(s.label.toLowerCase())).take(_class.numSkills));
    for (final s in available) {
      if (_skills.length >= _class.numSkills) break;
      _skills.add(s);
    }
    _nameCtrl.text = (j['name'] ?? randomName(_raceId)).toString();
    _titleCtrl.text = (j['title'] ?? _class.epithet).toString();
    final pr = (j['pronouns'] ?? '').toString().toLowerCase();
    _pronouns = pr.contains('she') ? 'she/her' : 'he/him';
    final al = (j['alignment'] ?? '').toString();
    _alignment = alignments.where((a) => a.toLowerCase() == al.toLowerCase()).firstOrNull ?? _alignment;
    _persCtrl.text = (j['personality'] ?? '').toString();
    final story = (j['backstory'] ?? '').toString();
    final extras = [
      if ((j['ideals'] ?? '').toString().isNotEmpty) 'Ideal: ${j['ideals']}',
      if ((j['bonds'] ?? '').toString().isNotEmpty) 'Bond: ${j['bonds']}',
      if ((j['flaws'] ?? '').toString().isNotEmpty) 'Flaw: ${j['flaws']}',
    ];
    _storyCtrl.text = [story, if (extras.isNotEmpty) extras.join('\n')].join('\n\n').trim();
    _appearance = (j['appearance'] ?? '').toString();
    final p = PortraitSpec.random(_raceId);
    p.skin = _hex(j['skin']) ?? p.skin;
    p.hair = _hex(j['hair']) ?? p.hair;
    p.eyes = _hex(j['eyes']) ?? p.eyes;
    p.hairStyle = number(j['hair_style'], p.hairStyle).clamp(0, 7);
    p.beard = _pronouns == 'she/her' ? 0 : number(j['beard'], p.beard).clamp(0, 3);
    p.accessory = number(j['accessory'], p.accessory).clamp(0, 5);
    p.feminine = _pronouns == 'she/her' ? 0.8 : 0.25;
    _portrait = p;
  }

  Widget _startCard(IconData icon, String title, String sub, VoidCallback onTap) {
    return AppCard(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: AppColors.text),
        const SizedBox(height: 16),
        Text(title, style: T.h3()),
        const SizedBox(height: 2),
        Text(sub, style: T.small()),
      ]),
    );
  }

  Widget _presetRow(CharacterPreset p) {
    final c = p.create();
    return ListRow(
      leading: CharacterPortrait(character: c, size: 44),
      title: p.name,
      subtitle: '${c.raceLabel} ${classById(p.classId).name} · ${p.personality}',
      onTap: () => _showPreset(p, c),
    );
  }

  void _showPreset(CharacterPreset p, Character c) {
    showAppSheet(context, builder: (ctx) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CharacterPortrait(character: c, size: 64),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.name, style: T.h2()),
                Text('${c.raceLabel} ${classById(p.classId).name}', style: T.small()),
              ]),
            ),
          ]),
          const SizedBox(height: 16),
          Text(p.blurb, style: T.body()),
          const SizedBox(height: 16),
          Row(children: [
            for (final a in Ability.values)
              Expanded(
                child: Column(children: [
                  Text('${c.score(a)}', style: T.number(18)),
                  Text(a.short, style: T.caption()),
                ]),
              ),
          ]),
          const SizedBox(height: 20),
          AppButton(
            label: widget.companionMode ? 'Add ${p.name.split(' ').first}' : 'Use this character',
            onPressed: () {
              Navigator.pop(ctx);
              _create(p.create());
            },
          ),
          const SizedBox(height: 8),
          AppButton(
            label: 'Customize',
            kind: ButtonKind.secondary,
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _raceId = p.raceId;
                _subraceId = p.subraceId;
                _classId = p.classId;
                _bgId = p.backgroundId;
                _method = AbilityMethod.pointBuy;
                _scores = Map.of(p.scores);
                _plus2 = p.plus2;
                _plus1 = p.plus1;
                _portrait = c.portrait;
                _nameCtrl.text = p.name;
                _titleCtrl.text = p.title;
                _persCtrl.text = p.personality;
                _storyCtrl.text = p.blurb;
                _pronouns = p.pronouns == 'she/her' ? 'she/her' : 'he/him';
                _skills
                  ..clear()
                  ..addAll(c.skills.where((s) => _class.skillChoices.contains(s) && !_bg.skills.contains(s)).take(_class.numSkills));
              });
              _go(1);
            },
          ),
        ]),
      );
    });
  }

  // ------------------------------------------------------------------ race

  Widget _raceStep() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _hint('Your ancestry affects your traits, speed and appearance.'),
        for (final r in races)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SelectCard(
              selected: r.id == _raceId,
              onTap: () => setState(() {
                _raceId = r.id;
                _subraceId = r.subraces.isEmpty ? null : r.subraces.first.id;
                _portrait = PortraitSpec.random(r.id, seed: _portrait.seed);
                _nameCtrl.text = randomName(r.id);
              }),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                PortraitView(spec: PortraitSpec.random(r.id, seed: 1000 + r.id.length * 13), raceId: r.id, size: 44),
                const SizedBox(width: 14),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 20),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(r.name, style: T.h3()),
                      const SizedBox(height: 2),
                      Text(r.description, style: T.small()),
                      if (r.id == _raceId) ...[
                        const SizedBox(height: 10),
                        Text('Speed ${r.speed} ft · ${r.size}${r.darkvision ? ' · Darkvision' : ''}', style: T.caption(color: AppColors.textMuted)),
                        const SizedBox(height: 6),
                        for (final t in r.traits) Text('• $t', style: T.small()),
                        if (r.subraces.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Wrap(spacing: 6, runSpacing: 6, children: [
                            for (final s in r.subraces) ChoiceChip(label: Text(s.name), selected: _subraceId == s.id, onSelected: (_) => setState(() => _subraceId = s.id)),
                          ]),
                        ],
                      ],
                    ]),
                  ),
                ),
              ]),
            ),
          ),
      ],
    );
  }

  // ----------------------------------------------------------------- class

  Widget _classStep() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _hint('Your class defines how you fight, cast and survive.'),
        for (final c in classes)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SelectCard(
              selected: c.id == _classId,
              onTap: () => setState(() {
                _classId = c.id;
                _titleCtrl.text = c.epithet;
                _skills.clear();
                _applyRecommended();
              }),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ClassIcon(classId: c.id, size: 40),
                const SizedBox(width: 14),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 20),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(c.name, style: T.h3()),
                      const SizedBox(height: 2),
                      Text(c.description, style: T.small()),
                      if (c.id == _classId) ...[
                        const SizedBox(height: 10),
                        Wrap(spacing: 6, runSpacing: 6, children: [
                          Tag('d${c.hitDie} hit die'),
                          Tag(c.primary.full),
                          Tag('Saves ${c.saves.map((s) => s.short).join(', ')}'),
                          if (c.caster != CasterType.none) const Tag('Spellcaster', color: AppColors.accent, filled: true),
                        ]),
                        const SizedBox(height: 10),
                        for (final f in c.features) Text('• Lv ${f.level} ${f.name} — ${f.text}', style: T.small()),
                      ],
                    ]),
                  ),
                ),
              ]),
            ),
          ),
      ],
    );
  }

  // ------------------------------------------------------------ background

  Widget _bgStep() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _hint('Where you came from. Grants two skills and starting gold.'),
        for (final b in backgrounds)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SelectCard(
              selected: b.id == _bgId,
              onTap: () => setState(() {
                _bgId = b.id;
                _skills.removeWhere((s) => b.skills.contains(s));
              }),
              child: Padding(
                padding: const EdgeInsets.only(right: 24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(b.name, style: T.h3()),
                  const SizedBox(height: 2),
                  Text(b.description, style: T.small()),
                  const SizedBox(height: 6),
                  Text('${b.skills.map((s) => s.label).join(', ')} · ${b.gold} gp', style: T.caption()),
                ]),
              ),
            ),
          ),
      ],
    );
  }

  // ------------------------------------------------------------- abilities

  Widget _abilityStep() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SegmentedButton<AbilityMethod>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: AbilityMethod.pointBuy, label: Text('Point buy')),
            ButtonSegment(value: AbilityMethod.standardArray, label: Text('Standard')),
            ButtonSegment(value: AbilityMethod.roll, label: Text('Roll')),
          ],
          selected: {_method},
          onSelectionChanged: (s) => setState(() => _method = s.first),
        ),
        const SizedBox(height: 16),
        if (_method == AbilityMethod.pointBuy)
          Row(children: [
            Text('${27 - _pointsSpent} points left', style: T.h3(color: _pointsSpent > 27 ? AppColors.danger : AppColors.text)),
            const Spacer(),
            TextButton(onPressed: () => setState(_applyRecommended), child: Text('Use recommended', style: T.small(color: AppColors.text))),
          ]),
        if (_method == AbilityMethod.standardArray) Text('Assign 15, 14, 13, 12, 10 and 8.', style: T.small()),
        if (_method == AbilityMethod.roll)
          AppButton(
            label: _rolled.length < 6 ? 'Roll ${Ability.values[_rolled.length].full}' : 'Reroll all',
            kind: ButtonKind.secondary,
            icon: Icons.casino_outlined,
            onPressed: _rollScore,
          ),
        const SizedBox(height: 12),
        AppCard(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Column(children: [
            Row(children: [
              Expanded(child: Text('ABILITY', style: T.overline())),
              SizedBox(width: 44, child: Center(child: Text('+2', style: T.overline()))),
              SizedBox(width: 44, child: Center(child: Text('+1', style: T.overline()))),
            ]),
            for (final a in Ability.values) _abilityRow(a),
          ]),
        ),
        const SizedBox(height: 10),
        Text('Pick one ability for +2 and another for +1. Subrace bonuses are added automatically.', style: T.caption()),
      ],
    );
  }

  Future<void> _rollScore() async {
    if (_rolled.length >= 6) {
      setState(() => _rolled = []);
      return;
    }
    final res = await showDialog<int>(context: context, barrierDismissible: false, builder: (ctx) => _FourD6Dialog(ability: Ability.values[_rolled.length]));
    if (res != null) setState(() => _rolled.add(res));
  }

  Widget _abilityRow(Ability a) {
    final base = _baseScores[a] ?? 8;
    final fin = _final(a);
    final Widget control = switch (_method) {
      AbilityMethod.pointBuy => Row(mainAxisSize: MainAxisSize.min, children: [
          _stepBtn(Icons.remove, base > 8 ? () => setState(() => _scores[a] = base - 1) : null),
          SizedBox(width: 28, child: Text('$base', textAlign: TextAlign.center, style: T.small())),
          _stepBtn(Icons.add, base < 15 && _pointsSpent + ((_pointCost[base + 1] ?? 99) - (_pointCost[base] ?? 0)) <= 27 ? () => setState(() => _scores[a] = base + 1) : null),
        ]),
      AbilityMethod.standardArray => DropdownButton<int>(
          value: _arrayAssign[a.index],
          hint: Text('—', style: T.small()),
          dropdownColor: AppColors.surface2,
          underline: const SizedBox(),
          borderRadius: BorderRadius.circular(12),
          items: [
            for (var i = 0; i < _standardArray.length; i++)
              DropdownMenuItem(
                value: i,
                enabled: !_arrayAssign.contains(i) || _arrayAssign[a.index] == i,
                child: Text('${_standardArray[i]}', style: T.body(color: !_arrayAssign.contains(i) || _arrayAssign[a.index] == i ? AppColors.text : AppColors.textFaint)),
              ),
          ],
          onChanged: (v) => setState(() => _arrayAssign[a.index] = v),
        ),
      AbilityMethod.roll => Text(a.index < _rolled.length ? '${_rolled[a.index]}' : '—', style: T.small()),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        AbilityIcon(a, size: 30),
        const SizedBox(width: 12),
        Expanded(child: Text(a.full, style: T.body())),
        control,
        const SizedBox(width: 8),
        SizedBox(width: 30, child: Text('$fin', textAlign: TextAlign.right, style: T.number(17))),
        SizedBox(
          width: 44,
          child: Center(
            child: _radio(_plus2 == a, () => setState(() {
                  if (_plus1 == a) _plus1 = _plus2;
                  _plus2 = a;
                })),
          ),
        ),
        SizedBox(
          width: 44,
          child: Center(
            child: _radio(_plus1 == a, () => setState(() {
                  if (_plus2 == a) _plus2 = _plus1;
                  _plus1 = a;
                })),
          ),
        ),
      ]),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback? onTap) => IconButton(
        visualDensity: VisualDensity.compact,
        onPressed: onTap,
        icon: Icon(icon, size: 16, color: onTap == null ? AppColors.textFaint : AppColors.text),
      );

  Widget _radio(bool on, VoidCallback onTap) => InkResponse(
        onTap: onTap,
        radius: 18,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 18,
          height: 18,
          decoration: BoxDecoration(shape: BoxShape.circle, color: on ? AppColors.text : Colors.transparent, border: Border.all(color: on ? AppColors.text : AppColors.borderStrong, width: 1.5)),
          child: on ? const Icon(Icons.check, size: 12, color: AppColors.bg) : null,
        ),
      );

  // ---------------------------------------------------------------- skills

  Widget _skillStep() {
    final available = _class.skillChoices.where((s) => !_bg.skills.contains(s)).toList();
    final caster = _class.spellAbility != null && _draftFor().casterClass != null;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (caster) ...[
          const SizedBox(height: 4),
        ],
        _hint('Choose ${_class.numSkills} skills. ${_bg.name} already gives you ${_bg.skills.map((s) => s.label).join(' and ')}.'),
        Text('${_skills.length} of ${_class.numSkills} selected', style: T.caption()),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in available)
            FilterChip(
              label: Text(s.label),
              showCheckmark: true,
              checkmarkColor: AppColors.accent,
              selected: _skills.contains(s),
              onSelected: (v) => setState(() {
                if (v && _skills.length < _class.numSkills) {
                  _skills.add(s);
                } else {
                  _skills.remove(s);
                }
              }),
            ),
        ]),
        if (caster) ...[
          const SectionLabel('Spells'),
          SpellPicker(character: _draftFor(), onChanged: () => setState(() {})),
        ],
      ],
    );
  }

  // ------------------------------------------------------------ appearance

  Widget _appearanceStep() {
    final settings = context.watch<SettingsController>();
    final images = context.watch<ImageService>();
    const key = 'portrait_creator';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(child: PortraitView(spec: _portrait, raceId: _raceId, classId: _classId, size: 160)),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: AppButton(label: 'Shuffle', icon: Icons.shuffle, kind: ButtonKind.secondary, height: 42, onPressed: () => setState(() => _portrait = PortraitSpec.random(_raceId)))),
          if (settings.useAiPortraits) ...[
            const SizedBox(width: 10),
            Expanded(
              child: AppButton(
                label: 'Generate with AI',
                icon: Icons.auto_awesome_outlined,
                kind: ButtonKind.secondary,
                height: 42,
                busy: images.isBusy(key),
                onPressed: () async {
                  final c = _build();
                  final path = await images.generate(key, 'Portrait of ${c.name}, a ${c.raceLabel} ${_class.name} (${c.pronouns}). ${_persCtrl.text}');
                  if (!mounted) return;
                  if (path != null) setState(() => _portrait.aiImagePath = path);
                  if (mounted && images.errors[key] != null) showToast(context, images.errors[key]!, icon: Icons.error_outline);
                },
              ),
            ),
          ],
        ]),
        const SizedBox(height: 10),
        Row(children: [
          if (_picker.supportsImageSource(ImageSource.camera)) ...[
            Expanded(child: AppButton(label: 'Camera', icon: Icons.photo_camera_outlined, kind: ButtonKind.secondary, height: 42, onPressed: () => _pickPhoto(ImageSource.camera))),
            const SizedBox(width: 10),
          ],
          Expanded(child: AppButton(label: 'Gallery', icon: Icons.photo_library_outlined, kind: ButtonKind.secondary, height: 42, onPressed: () => _pickPhoto(ImageSource.gallery))),
        ]),
        if (_portrait.aiImagePath != null)
          TextButton(onPressed: () => setState(() => _portrait.aiImagePath = null), child: Text('Use the drawn portrait instead', style: T.small(color: AppColors.textMuted))),
        const SizedBox(height: 4),
        TextField(
          controller: _lookCtrl,
          style: T.body(),
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Appearance', hintText: 'Tall, scarred, silver braids, a green travelling cloak'),
        ),
        Padding(padding: const EdgeInsets.only(top: 4, left: 4), child: Text('Used to keep AI scenes and portraits consistent.', style: T.caption())),
        const SectionLabel('Skin'),
        _swatches(_race.skinTones, _portrait.skin, (c) => setState(() => _portrait.skin = c)),
        const SectionLabel('Hair'),
        _swatches(_race.hairColors, _portrait.hair, (c) => setState(() => _portrait.hair = c)),
        const SectionLabel('Eyes'),
        _swatches(const [Color(0xFF4F7FC9), Color(0xFF5E9E4F), Color(0xFF6A4325), Color(0xFFC9A55C), Color(0xFFB3202A), Color(0xFF8A8A9A), Color(0xFF7B4FC9), Color(0xFFEDE3D1)], _portrait.eyes,
            (c) => setState(() => _portrait.eyes = c)),
        const SectionLabel('Features'),
        RowGroup(children: [
          _cycleRow('Hair style', _portrait.hairStyle, 8, (v) => setState(() => _portrait.hairStyle = v)),
          _cycleRow('Facial hair', _portrait.beard, 4, (v) => setState(() => _portrait.beard = v)),
          _cycleRow('Accessory', _portrait.accessory, 6, (v) => setState(() => _portrait.accessory = v)),
          _cycleRow('Background', _portrait.background, 6, (v) => setState(() => _portrait.background = v)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Row(children: [
              SizedBox(width: 100, child: Text('Face shape', style: T.body())),
              Expanded(child: Slider(value: _portrait.feminine, onChanged: (v) => setState(() => _portrait.feminine = v))),
            ]),
          ),
          ListRow(title: 'Scar', trailing: Switch(value: _portrait.scar, onChanged: (v) => setState(() => _portrait.scar = v))),
        ]),
      ],
    );
  }

  final _picker = ImagePicker();

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final f = await _picker.pickImage(source: source, maxWidth: 768, maxHeight: 768, imageQuality: 85, preferredCameraDevice: CameraDevice.front);
      if (f == null || !mounted) return;
      final bytes = await f.readAsBytes();
      if (!mounted) return;
      final path = await context.read<ImageService>().savePhoto(bytes);
      setState(() => _portrait.aiImagePath = path);
    } catch (e) {
      if (mounted) showToast(context, 'Couldn\'t open the ${source == ImageSource.camera ? 'camera' : 'gallery'}: $e', icon: Icons.error_outline);
    }
  }

  Widget _swatches(List<Color> colors, Color current, ValueChanged<Color> onPick) {
    return Wrap(spacing: 10, runSpacing: 10, children: [
      for (final c in colors)
        GestureDetector(
          onTap: () => onPick(c),
          child: Container(
            width: 32,
            height: 32,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.toARGB32() == current.toARGB32() ? AppColors.text : Colors.transparent, width: 1.5)),
            child: DecoratedBox(decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          ),
        ),
    ]);
  }

  Widget _cycleRow(String label, int value, int count, ValueChanged<int> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(children: [
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: T.body())),
        IconButton(onPressed: () => onChanged((value - 1) % count), icon: const Icon(Icons.chevron_left)),
        SizedBox(width: 44, child: Text('${value + 1}/$count', textAlign: TextAlign.center, style: T.small())),
        IconButton(onPressed: () => onChanged((value + 1) % count), icon: const Icon(Icons.chevron_right)),
      ]),
    );
  }

  // --------------------------------------------------------------- details

  Widget _detailsStep() {
    final settings = context.watch<SettingsController>();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _nameCtrl,
          style: T.body(),
          decoration: InputDecoration(labelText: 'Name', suffixIcon: IconButton(icon: const Icon(Icons.shuffle, size: 18), onPressed: () => setState(() => _nameCtrl.text = randomName(_raceId)))),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _titleCtrl,
          style: T.body(),
          decoration: InputDecoration(labelText: 'Title', suffixIcon: IconButton(icon: const Icon(Icons.shuffle, size: 18), onPressed: () => setState(() => _titleCtrl.text = randomEpithet()))),
        ),
        const SectionLabel('Gender'),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'he/him', label: Text('Male'), icon: Icon(Icons.male, size: 16)),
            ButtonSegment(value: 'she/her', label: Text('Female'), icon: Icon(Icons.female, size: 16)),
          ],
          selected: {_pronouns == 'she/her' ? 'she/her' : 'he/him'},
          onSelectionChanged: (v) => setState(() => _pronouns = v.first),
        ),
        const SectionLabel('Alignment'),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final a in alignments) ChoiceChip(label: Text(a), selected: _alignment == a, onSelected: (_) => setState(() => _alignment = a)),
        ]),
        const SectionLabel('Personality'),
        TextField(controller: _persCtrl, style: T.body(), decoration: const InputDecoration(hintText: 'Brave, sarcastic, loyal to a fault')),
        SectionLabel(
          'Backstory',
          trailing: TextButton.icon(
            onPressed: _busyStory
                ? null
                : () async {
                    setState(() => _busyStory = true);
                    try {
                      _storyCtrl.text = settings.useAiCreator ? await AiDungeonMaster(settings).backstory(_build()) : _offlineBackstory();
                    } catch (e) {
                      if (mounted) showToast(context, 'Couldn\'t write a backstory: $e', icon: Icons.error_outline);
                    } finally {
                      if (mounted) setState(() => _busyStory = false);
                    }
                  },
            icon: _busyStory ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome_outlined, size: 16),
            label: Text('Generate', style: T.small(color: AppColors.text)),
          ),
        ),
        TextField(controller: _storyCtrl, style: T.body(), maxLines: 7, minLines: 4, decoration: const InputDecoration(hintText: 'Where they come from and what drives them')),
        _equipmentSection(),
        SectionLabel('Starting level', trailing: Text('$_startLevel', style: T.number(15))),
        Slider(value: _startLevel.toDouble(), min: 1, max: 10, divisions: 9, onChanged: (v) => setState(() => _startLevel = v.round())),
      ],
    );
  }

  String _offlineBackstory() {
    final r = Rng.unseeded();
    final origin = r.pick(['a fishing village swallowed by fog', 'the slums of a great walled city', 'a monastery on a storm-lashed cliff', 'a caravan that never stayed in one place', 'a noble house fallen to ruin', 'a forest that sang at night']);
    final event = r.pick(['lost everything to a raid', 'witnessed a miracle no one believes', 'made a promise to a dying stranger', 'stole something they should not have', 'was marked by a strange sigil', 'survived a plague that took their family']);
    final goal = r.pick(['to find the one who wronged them', 'to earn a name worth remembering', 'to break a curse that grows each year', 'to repay an impossible debt', 'to discover the truth of their birth']);
    final secret = r.pick(['They still dream of a door they have never opened.', 'Someone powerful is quietly searching for them.', 'They carry a letter they have never dared read.', 'Their shadow sometimes moves on its own.']);
    final name = _nameCtrl.text.split(' ').first;
    return '$name grew up in $origin as a ${_bg.name.toLowerCase()}, until the day they $event. Now a ${_class.name.toLowerCase()}, $name travels $goal. $secret';
  }

  // ---------------------------------------------------------------- review

  Widget _reviewStep() {
    final c = _build();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          CharacterPortrait(character: c, size: 72, viewable: true),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.name, style: T.h2()),
              const SizedBox(height: 2),
              Text('Level ${c.level} ${c.raceLabel} ${c.classSummary}', style: T.small()),
              Text('${c.background.name} · ${c.alignment}', style: T.caption()),
            ]),
          ),
        ]),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: StatTile(label: 'HP', value: '${c.maxHp}')),
          const SizedBox(width: 8),
          Expanded(child: StatTile(label: 'AC', value: '${c.armorClass}')),
          const SizedBox(width: 8),
          Expanded(child: StatTile(label: 'Init', value: signed(c.initiative))),
          const SizedBox(width: 8),
          Expanded(child: StatTile(label: 'Speed', value: '${c.speed}')),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          for (final (i, a) in Ability.values.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: StatTile(label: a.short, value: '${c.score(a)}')),
          ],
        ]),
        const SectionLabel('Skills'),
        Wrap(spacing: 6, runSpacing: 6, children: [for (final s in c.skills) Tag('${s.label} ${signed(c.skillMod(s))}')]),
        if (c.spells.isNotEmpty) ...[
          const SectionLabel('Spells'),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final s in c.knownSpellDefs) Tag(s.name)]),
        ],
        if (_storyCtrl.text.trim().isNotEmpty) ...[
          const SectionLabel('Backstory'),
          Text(_storyCtrl.text.trim(), style: T.small(color: AppColors.text)),
        ],
        if (_appearance.trim().isNotEmpty) ...[
          const SectionLabel('Appearance'),
          Text(_appearance.trim(), style: T.small()),
        ],
        const SectionLabel('Equipment'),
        Text(c.inventory.map((i) => i.qty > 1 ? '${i.name} ×${i.qty}' : i.name).join(', '), style: T.small()),
      ],
    );
  }
}

class _FourD6Dialog extends StatefulWidget {
  const _FourD6Dialog({required this.ability});
  final Ability ability;

  @override
  State<_FourD6Dialog> createState() => _FourD6DialogState();
}

class _FourD6DialogState extends State<_FourD6Dialog> {
  final List<int?> _vals = List.filled(4, null);
  final _keys = List.generate(4, (_) => GlobalKey<RollableDieState>());

  @override
  Widget build(BuildContext context) {
    final done = !_vals.contains(null);
    final sorted = done ? (_vals.whereType<int>().toList()..sort()) : <int>[];
    final total = done ? sorted.skip(1).fold(0, (a, b) => a + b) : 0;
    return AlertDialog(
      title: Text('Roll ${widget.ability.full}'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('4d6, drop the lowest', style: T.small()),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < 4; i++) RollableDie(key: _keys[i], sides: 6, size: 56, onRolled: (v) => setState(() => _vals[i] = v)),
        ]),
        const SizedBox(height: 12),
        if (done) Text('${sorted.skip(1).join(' + ')} = $total', style: T.number(22)),
      ]),
      actions: [
        if (!done)
          TextButton(
            onPressed: () {
              for (final (i, k) in _keys.indexed) {
                Future.delayed(Duration(milliseconds: i * 80), () => k.currentState?.roll());
              }
            },
            child: const Text('Roll all'),
          )
        else
          TextButton(onPressed: () => Navigator.pop(context, total), child: Text('Keep $total')),
      ],
    );
  }
}
