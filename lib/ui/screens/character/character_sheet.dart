import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../art/class_icon.dart';
import '../../../data/srd.dart';
import '../../../game/dice.dart';
import '../../../models/character.dart';
import '../../../services/audio/audio_service.dart';
import '../../../services/game_store.dart';
import '../../../services/image_service.dart';
import '../../../services/settings.dart';
import '../../../theme/ui.dart';
import '../../../data/inventory_rules.dart';
import '../../../data/spellcasting.dart';
import '../../widgets/character_card.dart';
import '../../widgets/spell_picker.dart';
import '../../widgets/portrait.dart';
import '../adventure/new_adventure_screen.dart';
import 'level_up_sheet.dart';

class CharacterSheetScreen extends StatelessWidget {
  const CharacterSheetScreen({super.key, this.characterId, this.character, this.onChanged});
  final String? characterId;
  final Character? character;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<GameStore>();
    final c = character ?? store.character(characterId ?? '');
    if (c == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: Icons.person_off_outlined, title: 'Character not found'),
      );
    }
    final inAdventure = character != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(c.name),
        actions: [
          IconButton(
            tooltip: 'Share character card',
            icon: const Icon(Icons.ios_share),
            onPressed: () => showCharacterCard(context, c),
          ),
          IconButton(
            tooltip: 'Copy character sheet',
            icon: const Icon(Icons.copy_outlined, size: 20),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: characterSheetText(c)));
              showToast(context, 'Character sheet copied to clipboard');
            },
          ),
          if (!inAdventure)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz),
              onSelected: (v) async {
                if (v == 'delete') {
                  if (await confirm(context, title: 'Delete character?', message: '${c.name} will be removed. Adventures keep their own copy.')) {
                    await store.deleteCharacter(c.id);
                    if (context.mounted) Navigator.pop(context);
                  }
                } else if (v == 'rest') {
                  c.longRest();
                  store.saveCharacter(c);
                  showToast(context, 'HP and spell slots restored');
                }
              },
              itemBuilder: (_) => const [PopupMenuItem(value: 'rest', child: Text('Long rest')), PopupMenuItem(value: 'delete', child: Text('Delete'))],
            ),
        ],
      ),
      body: CharacterSheetBody(character: c, onChanged: () => inAdventure ? onChanged?.call() : store.saveCharacter(c)),
      bottomNavigationBar: inAdventure
          ? null
          : SafeArea(
              child: ContentWidth(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: AppButton(
                    label: 'Start an adventure',
                    icon: Icons.play_arrow_rounded,
                    onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => NewAdventureScreen(heroId: c.id))),
                  ),
                ),
              ),
            ),
    );
  }
}

class CharacterSheetBody extends StatefulWidget {
  const CharacterSheetBody({super.key, required this.character, required this.onChanged});
  final Character character;
  final VoidCallback onChanged;

  @override
  State<CharacterSheetBody> createState() => _CharacterSheetBodyState();
}

class _CharacterSheetBodyState extends State<CharacterSheetBody> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 7, vsync: this);
  Timer? _notesTimer;
  late final _notes = TextEditingController(text: widget.character.notes);
  Character get c => widget.character;

  @override
  void dispose() {
    _notesTimer?.cancel();
    _notes.dispose();
    _tabs.dispose();
    super.dispose();
  }

  void _changed() {
    setState(() {});
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return ContentWidth(
      child: NestedScrollView(
        headerSliverBuilder: (ctx, _) => [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            sliver: SliverList.list(children: [_header(), const SizedBox(height: 20), _vitals(), const SizedBox(height: 12), _abilities(), const SizedBox(height: 12)]),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabHeader(
              TabBar(
                controller: _tabs,
                isScrollable: true,
                tabs: const [
                  Tab(text: 'Skills'),
                  Tab(text: 'Combat'),
                  Tab(text: 'Spells'),
                  Tab(text: 'Inventory'),
                  Tab(text: 'Features'),
                  Tab(text: 'Story'),
                  Tab(text: 'Notes'),
                ],
              ),
            ),
          ),
        ],
        body: TabBarView(controller: _tabs, children: [_skillsTab(), _combatTab(), _spellsTab(), _gearTab(), _featuresTab(), _storyTab(), _notesTab()]),
      ),
    );
  }

  Widget _header() {
    final settings = context.watch<SettingsController>();
    final images = context.watch<ImageService>();
    final key = 'portrait_${c.id}';
    return Row(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            CharacterPortrait(character: c, size: 76, viewable: true),
            if (settings.useAiImages)
              Positioned(
                right: -6,
                bottom: -6,
                child: CircleIconButton(
                  size: 30,
                  icon: Icons.auto_awesome_outlined,
                  tooltip: 'Generate AI portrait',
                  busy: images.isBusy(key),
                  onPressed: images.isBusy(key)
                      ? null
                      : () async {
                          final path = await images.generate(key, 'Portrait of ${c.name}, a ${c.raceLabel} ${c.classSummary} (${c.pronouns}). ${c.personality}');
                          if (!mounted) return;
                          if (path != null) {
                            c.portrait.aiImagePath = path;
                            _changed();
                          } else if (mounted && images.errors[key] != null) {
                            showToast(context, images.errors[key]!, icon: Icons.error_outline);
                          }
                        },
                ),
              ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.name, style: T.h2()),
              if (c.title.isNotEmpty) Text(c.title, style: T.small()),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final e in c.classLevels.entries)
                    Container(
                      padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ClassIcon(classId: e.key, size: 20),
                          const SizedBox(width: 6),
                          Text('${classById(e.key).name} ${e.value}', style: T.caption(color: AppColors.text)),
                        ],
                      ),
                    ),
                  Tag(c.raceLabel),
                  Tag(c.background.name),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _vitals() {
    return AppCard(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _vital('AC', '${c.armorClass}')),
              Expanded(child: _vital('Initiative', signed(c.initiative))),
              Expanded(child: _vital('Speed', '${c.speed} ft')),
              Expanded(child: _vital('Proficiency', signed(c.proficiency))),
            ],
          ),
          const SizedBox(height: 16),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: _hpSheet,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: _barRow('Hit points${c.tempHp > 0 ? ' (+${c.tempHp} temp)' : ''}  ·  tap to adjust', '${c.hp} / ${c.maxHp}', c.hp, c.maxHp, AppColors.hp),
            ),
          ),
          const SizedBox(height: 12),
          _barRow('Level ${c.level}', '${c.xp} / ${c.xpForNext} XP', c.xp - c.xpForCurrent, (c.xpForNext - c.xpForCurrent).clamp(1, 1 << 30), AppColors.xp),
          if (c.canLevelUp) ...[
            const SizedBox(height: 14),
            AppButton(
              label: 'Level up',
              icon: Icons.arrow_upward,
              kind: ButtonKind.accent,
              height: 42,
              onPressed: () async {
                final r = await showLevelUpSheet(context, c);
                if (r != null) {
                  c.levelUp(r.classId, rollHp: r.rollHp, learnSpells: false);
                  if (r.subclassId != null) c.chooseSubclass(r.classId, r.subclassId!);
                  if (r.asi != null || r.feat != null) c.applyAsi(scores: r.asi, feat: r.feat);
                  if (c.hasSpellChoices && mounted) await showSpellPicker(context, c, onChanged: _changed, title: 'Choose new spells');
                  if (mounted) context.read<AudioService>().play('levelup');
                  _changed();
                }
              },
            ),
          ],
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final x in c.conditions.where((x) => !x.endsWith('Used')))
                      GestureDetector(
                        onTap: () => showToast(context, '$x: ${conditionText(x)}', icon: Icons.info_outline),
                        child: Tag(x, color: AppColors.warning, filled: true),
                      ),
                    if (c.conditions.where((x) => !x.endsWith('Used')).isEmpty) Text('No conditions', style: T.caption()),
                  ],
                ),
              ),
              GestureDetector(
                onTap: _conditionsSheet,
                child: Text('Conditions', style: T.caption(color: AppColors.textMuted)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _vital(String label, String value) => Column(
    children: [
      Text(value, style: T.number(18)),
      const SizedBox(height: 2),
      Text(label, style: T.caption()),
    ],
  );

  Widget _barRow(String label, String value, num v, num max, Color color) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Text(label, style: T.small(color: AppColors.text)),
          const Spacer(),
          Text(value, style: T.caption(color: AppColors.textMuted)),
        ],
      ),
      const SizedBox(height: 6),
      Bar(value: v, max: max, color: color, height: 6),
    ],
  );

  Widget _abilities() {
    return GridView(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8, mainAxisExtent: 72),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (final a in Ability.values)
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 10),
            onTap: () => _roll('${a.full} check', c.mod(a)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(a.short, style: T.overline()),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('${c.score(a)}', style: T.number(20)),
                    const SizedBox(width: 6),
                    Text(signed(c.mod(a)), style: T.small()),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  void _roll(String label, int mod) {
    final r = rollD20(modifier: mod, label: label);
    context.read<AudioService>().play('dice');
    showToast(context, '$label: ${r.natural} ${signed(mod)} = ${r.total}', icon: Icons.casino_outlined);
  }

  Widget _tabList(List<Widget> children) => ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: children);

  Widget _skillsTab() {
    return _tabList([
      const SectionLabel('Saving throws', padding: EdgeInsets.fromLTRB(4, 4, 4, 10)),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final a in Ability.values) Tag('${a.short} ${signed(c.saveMod(a))}', icon: c.proficientSave(a) ? Icons.check : null, color: c.proficientSave(a) ? AppColors.text : AppColors.textMuted),
        ],
      ),
      SectionLabel('Skills', trailing: Text('Passive Perception ${c.passivePerception}', style: T.caption())),
      RowGroup(
        children: [
          for (final s in Skill.values)
            InkWell(
              onTap: () => _roll(s.label, c.skillMod(s)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                child: Row(
                  children: [
                    Icon(
                      c.expertise.contains(s) ? Icons.star : (c.skills.contains(s) ? Icons.circle : Icons.circle_outlined),
                      size: 10,
                      color: c.skills.contains(s) ? AppColors.text : AppColors.textFaint,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(s.label, style: T.body(color: c.skills.contains(s) ? AppColors.text : AppColors.textMuted)),
                    ),
                    Text(s.ability.short, style: T.caption()),
                    SizedBox(
                      width: 44,
                      child: Text(signed(c.skillMod(s)), textAlign: TextAlign.right, style: T.number(15)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 8),
      Text('Tap a skill or ability to roll it.', style: T.caption()),
    ]);
  }

  Widget _combatTab() {
    return _tabList([
      RowGroup(
        children: [
          ListRow(title: 'Weapon', subtitle: '${c.weaponName} · ${signed(c.attackBonus)} to hit · ${c.weaponDamage}'),
          ListRow(
            title: 'Attacks per turn',
            trailing: Text('${c.attacksPerTurn}', style: T.number(15)),
          ),
          if (c.sneakAttackDice > 0)
            ListRow(
              title: 'Sneak attack',
              trailing: Text('${c.sneakAttackDice}d6', style: T.number(15)),
            ),
          if (c.isCaster) ListRow(title: 'Spellcasting', subtitle: '${c.spellAbility!.full} · attack ${signed(c.spellAttack)} · save DC ${c.spellDc}'),
          ListRow(
            title: 'Hit dice',
            trailing: Text('${c.hitDiceRemaining}/${c.hitDiceTotal} d${c.primaryClass.hitDie}', style: T.number(15)),
          ),
          ListRow(title: 'Armor', subtitle: '${c.equippedArmor?.name ?? 'None'}${c.hasShield ? ' + shield' : ''}'),
          ListRow(title: 'Alignment', subtitle: c.alignment),
        ],
      ),
    ]);
  }

  Widget _spellsTab() {
    if (!c.isCaster) return const EmptyState(icon: Icons.auto_fix_off_outlined, title: 'No spellcasting');
    final slots = c.spellSlots;
    return _tabList([
      if (slots.isNotEmpty) ...[
        const SectionLabel('Spell slots', padding: EdgeInsets.fromLTRB(4, 4, 4, 10)),
        AppCard(
          child: Column(
            children: [
              for (var l = 1; l <= slots.length; l++)
                if (slots[l - 1] > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 70,
                          child: Text('Level $l', style: T.small(color: AppColors.text)),
                        ),
                        for (var i = 0; i < slots[l - 1]; i++)
                          Container(
                            margin: const EdgeInsets.only(right: 6),
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i < c.slotsRemaining(l) ? AppColors.accent : Colors.transparent,
                              border: Border.all(color: AppColors.accent),
                            ),
                          ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ],
      if (c.hasSpellChoices)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: AppCard(
            onTap: _spellsSheet,
            borderColor: AppColors.accent,
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              const Icon(Icons.auto_fix_high, size: 18, color: AppColors.accent),
              const SizedBox(width: 10),
              Expanded(child: Text('You have spells to choose', style: T.body())),
              const Icon(Icons.chevron_right, size: 18, color: AppColors.textFaint),
            ]),
          ),
        ),
      SectionLabel(
        c.prepares ? 'Prepared spells' : 'Known spells',
        trailing: GestureDetector(
          onTap: _spellsSheet,
          child: Text(c.prepares ? 'Prepare' : 'Manage', style: T.caption(color: AppColors.textMuted)),
        ),
      ),
      RowGroup(
        children: [
          for (final s in c.knownSpellDefs)
            ListRow(
              title: s.name,
              subtitle: '${s.level == 0 ? 'Cantrip' : 'Level ${s.level}'} · ${s.description}${s.dice != null ? ' (${s.dice}${s.damageType != null ? ' ${s.damageType}' : ''})' : ''}',
            ),
        ],
      ),
    ]);
  }

  Widget _gearTab() {
    bool equipable(InventoryItem i) => const [ItemType.weapon, ItemType.armor, ItemType.shield].contains(i.def?.type);
    return _tabList([
      AppCard(
        onTap: _goldSheet,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            const Icon(Icons.toll_outlined, size: 20),
            const SizedBox(width: 12),
            Text('Purse', style: T.body()),
            const Spacer(),
            Text(
              [if (c.platinum > 0) '${c.platinum} pp', '${c.gold} gp', if (c.silver > 0) '${c.silver} sp', if (c.copper > 0) '${c.copper} cp'].join(' · '),
              style: T.number(15),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.edit_outlined, size: 16, color: AppColors.textFaint),
          ],
        ),
      ),
      const SizedBox(height: 12),
      AppCard(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.fitness_center, size: 18),
            const SizedBox(width: 10),
            Text('Carrying', style: T.body()),
            const Spacer(),
            Text('${c.carriedWeight.toStringAsFixed(0)} / ${c.carryCapacity.toStringAsFixed(0)} lb', style: T.small(color: AppColors.text)),
          ]),
          const SizedBox(height: 8),
          Bar(value: c.carriedWeight, max: c.carryCapacity, color: c.encumbrance == 0 ? AppColors.success : (c.encumbrance == 1 ? AppColors.warning : AppColors.danger)),
          const SizedBox(height: 6),
          Text(
            c.encumbrance == 0
                ? 'Unencumbered · up to ${c.carryCapacity.toStringAsFixed(0)} lb before you slow down'
                : (c.encumbrance == 1 ? 'Encumbered: speed −10 ft' : 'Heavily encumbered: speed −20 ft, disadvantage on STR, DEX and CON rolls'),
            style: T.caption(color: c.encumbrance == 0 ? AppColors.textFaint : AppColors.warning),
          ),
        ]),
      ),
      if (c.inventory.any((i) => i.def?.attune ?? false)) ...[
        const SizedBox(height: 12),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            const Icon(Icons.auto_awesome, size: 18, color: AppColors.accent),
            const SizedBox(width: 10),
            Expanded(child: Text('Attunement', style: T.body())),
            for (var k = 0; k < 3; k++)
              Container(
                margin: const EdgeInsets.only(left: 6),
                width: 12,
                height: 12,
                decoration: BoxDecoration(shape: BoxShape.circle, color: k < c.attunedCount ? AppColors.accent : AppColors.surface3, border: Border.all(color: AppColors.borderStrong)),
              ),
            const SizedBox(width: 8),
            Text('${c.attunedCount}/3', style: T.caption(color: AppColors.textMuted)),
          ]),
        ),
      ],
      SectionLabel(
        'Items',
        trailing: GestureDetector(
          onTap: _addItemSheet,
          child: Text('Add item', style: T.caption(color: AppColors.textMuted)),
        ),
      ),
      RowGroup(
        children: [
          for (final i in c.inventory)
            GestureDetector(
              onLongPress: () async {
                if (await confirm(context, title: 'Remove ${i.name}?', message: 'It will be dropped from the inventory.', action: 'Remove')) {
                  c.inventory.remove(i);
                  _changed();
                }
              },
              child: ListRow(
                title: '${i.name}${i.qty > 1 ? ' ×${i.qty}' : ''}',
                subtitle: [
                  if (i.equipped) 'Equipped',
                  if (i.attuned) 'Attuned',
                  if (i.def?.isMagic ?? false) '${i.def!.rarity}${i.def!.attune && !i.attuned ? ' · needs attunement' : ''}',
                  _itemDesc(i),
                  if (i.def != null) '${(i.def!.weight * i.qty).toStringAsFixed(i.def!.weight * i.qty < 1 ? 1 : 0)} lb',
                  if (i.equipped && i.def?.ammo != null) '${c.ammoFor(i.def!)?.qty ?? 0} ${i.def!.ammo} left',
                ].where((x) => x.isNotEmpty).join(' · '),
                onTap: (i.def?.isMagic ?? false) ? () => _magicItemSheet(i) : null,
                trailing: (i.def?.attune ?? false) && !equipable(i)
                    ? TextButton(
                        onPressed: () => _toggleAttune(i),
                        child: Text(i.attuned ? 'Unattune' : 'Attune', style: T.small(color: i.attuned ? AppColors.textMuted : AppColors.accent)),
                      )
                    : equipable(i)
                    ? TextButton(
                        onPressed: () {
                          if (!i.equipped) {
                            for (final o in c.inventory) {
                              if (o.def?.type == i.def!.type) o.equipped = false;
                            }
                          }
                          i.equipped = !i.equipped;
                          _changed();
                        },
                        child: Text(i.equipped ? 'Unequip' : 'Equip', style: T.small(color: AppColors.text)),
                      )
                    : (i.def?.type == ItemType.potion
                          ? TextButton(
                              onPressed: () {
                                final h = DiceExpression.parse(i.def!.heal!).roll().total;
                                c.heal(h);
                                i.qty--;
                                if (i.qty <= 0) c.inventory.remove(i);
                                context.read<AudioService>().play('heal');
                                showToast(context, '${c.name} recovers $h HP');
                                _changed();
                              },
                              child: Text('Use', style: T.small(color: AppColors.text)),
                            )
                          : const SizedBox()),
              ),
            ),
        ],
      ),
      const SizedBox(height: 8),
      Text('Long-press an item to remove it.', style: T.caption()),
    ]);
  }

  // ------------------------------------------------------------ tools

  void _hpSheet() {
    final amount = TextEditingController(text: '5');
    showAppSheet(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          int n() => int.tryParse(amount.text) ?? 0;
          void apply(String kind) {
            final v = n().clamp(0, 999);
            if (kind == 'dmg') c.takeDamage(v);
            if (kind == 'heal') c.heal(v);
            if (kind == 'temp') c.tempHp = v;
            context.read<AudioService>().play(kind == 'dmg' ? 'hit' : 'heal');
            _changed();
            set(() {});
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(ctx).bottom + 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Hit points', style: T.h2()),
                const SizedBox(height: 4),
                Text('${c.hp} / ${c.maxHp}${c.tempHp > 0 ? ' · ${c.tempHp} temporary' : ''}', style: T.small()),
                const SizedBox(height: 12),
                Bar(value: c.hp, max: c.maxHp, color: AppColors.hp, height: 8),
                const SizedBox(height: 16),
                Row(
                  children: [
                    for (final q in [1, 5, 10])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(label: Text('$q'), selected: amount.text == '$q', onSelected: (_) => set(() => amount.text = '$q')),
                      ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: amount,
                        keyboardType: TextInputType.number,
                        style: T.body(),
                        decoration: const InputDecoration(hintText: 'Amount'),
                        onChanged: (_) => set(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(label: 'Damage', kind: ButtonKind.danger, onPressed: () => apply('dmg')),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppButton(label: 'Heal', kind: ButtonKind.secondary, onPressed: () => apply('heal')),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppButton(label: 'Temp HP', kind: ButtonKind.secondary, onPressed: () => apply('temp')),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        label: 'Spend hit die (${c.hitDiceRemaining})',
                        kind: ButtonKind.ghost,
                        onPressed: c.hitDiceRemaining > 0
                            ? () {
                                final h = c.shortRestHitDie();
                                showToast(context, h > 0 ? 'Recovered $h HP' : 'Already at full health');
                                _changed();
                                set(() {});
                              }
                            : null,
                      ),
                    ),
                    Expanded(
                      child: AppButton(
                        label: 'Long rest',
                        kind: ButtonKind.ghost,
                        onPressed: () {
                          c.longRest();
                          _changed();
                          set(() {});
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _conditionsSheet() {
    showAppSheet(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          return ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              const SheetTitle('Conditions', subtitle: 'Toggle effects on this character.'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: RowGroup(
                  children: [
                    for (final e in conditionInfo.entries.where((e) => !['Hidden', 'Dodging', 'Shielded'].contains(e.key)))
                      ListRow(
                        title: e.key,
                        subtitle: e.value,
                        trailing: Switch(
                          value: c.conditions.contains(e.key),
                          onChanged: (v) {
                            v ? c.conditions.add(e.key) : c.conditions.remove(e.key);
                            _changed();
                            set(() {});
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _goldSheet() {
    final ctrl = TextEditingController(text: '10');
    showAppSheet(
      context,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(ctx).bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Purse', style: T.h2()),
            Text('${c.platinum} pp · ${c.gold} gp · ${c.silver} sp · ${c.copper} cp (worth ${c.wealthGp.toStringAsFixed(2)} gp)', style: T.small()),
            if (c.silver > 0 || c.copper > 0 || c.platinum > 0)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: AppButton(
                  label: 'Exchange coins into gold',
                  icon: Icons.currency_exchange,
                  kind: ButtonKind.secondary,
                  height: 40,
                  onPressed: () {
                    final copperTotal = c.platinum * 1000 + c.silver * 10 + c.copper;
                    c.gold += copperTotal ~/ 100;
                    final rest = copperTotal % 100;
                    c.platinum = 0;
                    c.silver = rest ~/ 10;
                    c.copper = rest % 10;
                    context.read<AudioService>().play('coin');
                    _changed();
                    Navigator.pop(ctx);
                  },
                ),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              style: T.body(),
              decoration: const InputDecoration(labelText: 'Amount'),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Spend',
                    kind: ButtonKind.secondary,
                    onPressed: () {
                      c.gold = (c.gold - (int.tryParse(ctrl.text) ?? 0)).clamp(0, 1 << 30);
                      _changed();
                      Navigator.pop(ctx);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppButton(
                    label: 'Add',
                    onPressed: () {
                      c.gold += int.tryParse(ctrl.text) ?? 0;
                      context.read<AudioService>().play('coin');
                      _changed();
                      Navigator.pop(ctx);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _addItemSheet() {
    final name = TextEditingController();
    final desc = TextEditingController();
    showAppSheet(
      context,
      builder: (ctx) => DefaultTabController(
        length: 2,
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.7,
          child: Column(
            children: [
              const TabBar(
                tabAlignment: TabAlignment.center,
                tabs: [
                  Tab(text: 'From the rules'),
                  Tab(text: 'Custom'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        RowGroup(
                          children: [
                            for (final d in items)
                              ListRow(
                                title: d.name,
                                subtitle: '${d.type.name} · ${d.value} gp',
                                trailing: const Icon(Icons.add, size: 18),
                                onTap: () {
                                  final existing = c.inventory.where((i) => i.itemId == d.id).firstOrNull;
                                  if (existing != null) {
                                    existing.qty++;
                                  } else {
                                    c.inventory.add(InventoryItem.of(d.id));
                                  }
                                  _changed();
                                  Navigator.pop(ctx);
                                  showToast(context, 'Added ${d.name}');
                                },
                              ),
                          ],
                        ),
                      ],
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.viewInsetsOf(ctx).bottom + 16),
                      child: Column(
                        children: [
                          TextField(
                            controller: name,
                            style: T.body(),
                            decoration: const InputDecoration(labelText: 'Name'),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: desc,
                            style: T.body(),
                            maxLines: 3,
                            decoration: const InputDecoration(labelText: 'Description'),
                          ),
                          const SizedBox(height: 16),
                          AppButton(
                            label: 'Add item',
                            onPressed: () {
                              if (name.text.trim().isEmpty) return;
                              c.inventory.add(InventoryItem(name: name.text.trim(), description: desc.text.trim()));
                              _changed();
                              Navigator.pop(ctx);
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _spellsSheet() => showSpellPicker(context, c, onChanged: _changed);

  Widget _notesTab() {
    return _tabList([
      Text('Session notes, NPC names, clues — anything you want to remember.', style: T.caption()),
      const SizedBox(height: 10),
      TextField(
        controller: _notes,
        style: T.body(),
        maxLines: null,
        minLines: 12,
        decoration: const InputDecoration(hintText: 'Write notes…'),
        onChanged: (v) {
          c.notes = v;
          _notesTimer?.cancel();
          _notesTimer = Timer(const Duration(milliseconds: 600), widget.onChanged);
        },
      ),
    ]);
  }

  String _itemDesc(InventoryItem i) {
    final d = i.def;
    if (d == null) return i.description;
    final magic = [
      if (d.bonus > 0) '+${d.bonus}',
      if (d.extraDice != null) '+${d.extraDice} ${d.extraType ?? ''}'.trim(),
    ].join(' ');
    return switch (d.type) {
      ItemType.weapon => '${d.damage} ${d.damageType}${magic.isEmpty ? '' : ' · $magic'}',
      ItemType.armor => 'AC ${(d.ac ?? 10) + d.bonus}',
      ItemType.shield => '+${2 + d.bonus} AC',
      ItemType.potion => d.heal != null ? 'Heals ${d.heal}' : (d.effect ?? d.description),
      _ => d.effect ?? d.description,
    };
  }

  void _toggleAttune(InventoryItem i) {
    if (!i.attuned && c.attunedCount >= 3) {
      showToast(context, 'You can attune to at most 3 magic items. Unattune one first.', icon: Icons.block);
      return;
    }
    i.attuned = !i.attuned;
    if (i.attuned) context.read<AudioService>().play('magic');
    _changed();
  }

  void _magicItemSheet(InventoryItem i) {
    final d = i.def!;
    showAppSheet(context, builder: (ctx) => StatefulBuilder(
          builder: (ctx, set) => ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 28), children: [
            Text(i.name, style: T.h2()),
            const SizedBox(height: 4),
            Text('${d.rarity[0].toUpperCase()}${d.rarity.substring(1)} ${d.type.name}${d.attune ? ' · requires attunement' : ''}', style: T.small(color: AppColors.accent)),
            const SizedBox(height: 14),
            if (d.description.isNotEmpty) Text(d.description, style: T.body()),
            const SizedBox(height: 12),
            RowGroup(children: [
              if (d.damage != null) ListRow(title: 'Damage', trailing: Text('${d.damage} ${d.damageType ?? ''}', style: T.small(color: AppColors.text))),
              if (d.bonus > 0) ListRow(title: 'Magic bonus', trailing: Text('+${d.bonus}', style: T.small(color: AppColors.text))),
              if (d.extraDice != null) ListRow(title: 'Extra damage', trailing: Text('${d.extraDice} ${d.extraType ?? ''}', style: T.small(color: AppColors.text))),
              if (d.acBonus > 0) ListRow(title: 'Armor class', trailing: Text('+${d.acBonus}', style: T.small(color: AppColors.text))),
              if (d.saveBonus > 0) ListRow(title: 'Saving throws', trailing: Text('+${d.saveBonus}', style: T.small(color: AppColors.text))),
              if (d.speedBonus > 0) ListRow(title: 'Speed', trailing: Text('+${d.speedBonus} ft', style: T.small(color: AppColors.text))),
              if (d.setAbility != null) ListRow(title: d.setAbility!.full, trailing: Text('becomes ${d.setScore}', style: T.small(color: AppColors.text))),
              if ((d.effect ?? '').isNotEmpty) ListRow(title: 'Effect', subtitle: d.effect),
              ListRow(title: 'Value', trailing: Text('${d.value} gp', style: T.small(color: AppColors.text))),
            ]),
            if (d.attune) ...[
              const SizedBox(height: 16),
              AppButton(
                label: i.attuned ? 'End attunement' : 'Attune (short rest)',
                icon: Icons.auto_awesome,
                kind: i.attuned ? ButtonKind.secondary : ButtonKind.accent,
                onPressed: () {
                  _toggleAttune(i);
                  set(() {});
                },
              ),
              const SizedBox(height: 8),
              Text('A creature can be attuned to no more than three magic items at a time. Attuned items grant their magic; unattuned ones are just fine curios.', style: T.caption()),
            ],
          ]),
        ));
  }

  Widget _featuresTab() {
    return _tabList([
      const SectionLabel('Racial traits', padding: EdgeInsets.fromLTRB(4, 4, 4, 10)),
      RowGroup(
        children: [
          for (final t in [...c.race.traits, ...?c.subrace?.traits]) ListRow(title: t),
        ],
      ),
      const SectionLabel('Class features'),
      RowGroup(
        children: [for (final f in c.features) ListRow(title: f.name, subtitle: f.text)],
      ),
      const SectionLabel('Background'),
      RowGroup(
        children: [ListRow(title: c.background.feature, subtitle: c.background.description)],
      ),
    ]);
  }

  Widget _storyTab() {
    return _tabList([
      if (c.personality.isNotEmpty) ...[const SectionLabel('Personality', padding: EdgeInsets.fromLTRB(4, 4, 4, 10)), Text(c.personality, style: T.body())],
      const SectionLabel('Backstory'),
      Text(c.backstory.isEmpty ? 'No backstory yet.' : c.backstory, style: T.reading(color: AppColors.textMuted)),
      const SectionLabel('Pronouns'),
      Text(c.pronouns, style: T.body()),
    ]);
  }
}

class _TabHeader extends SliverPersistentHeaderDelegate {
  _TabHeader(this.tabBar);
  final TabBar tabBar;

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => Container(color: AppColors.bg, child: tabBar);

  @override
  bool shouldRebuild(covariant _TabHeader oldDelegate) => false;
}

/// Plain-text character sheet for sharing or printing.
String characterSheetText(Character c) {
  final b = StringBuffer()
    ..writeln(c.name.toUpperCase())
    ..writeln(c.title)
    ..writeln('Level ${c.level} ${c.raceLabel} — ${c.classSummary}')
    ..writeln('${c.background.name} · ${c.alignment} · ${c.pronouns}')
    ..writeln()
    ..writeln('HP ${c.hp}/${c.maxHp}   AC ${c.armorClass}   Init ${signed(c.initiative)}   Speed ${c.speed} ft   Prof ${signed(c.proficiency)}')
    ..writeln('XP ${c.xp} / ${c.xpForNext}')
    ..writeln('Inspiration: ${c.inspiration ? 'available' : 'none'}')
    ..write(c.isCompanion ? 'Loyalty: ${c.loyalty}/100 (${c.loyaltyLabel})\n' : '')
    ..write(c.personalQuest.isNotEmpty ? 'Personal quest: ${c.personalQuest}\n' : '')
    ..writeln()
    ..writeln(Ability.values.map((a) => '${a.short} ${c.score(a)} (${signed(c.mod(a))})').join('  '))
    ..writeln('Saves: ${Ability.values.where(c.proficientSave).map((a) => '${a.short} ${signed(c.saveMod(a))}').join(', ')}')
    ..writeln('Skills: ${c.skills.map((s) => '${s.label} ${signed(c.skillMod(s))}').join(', ')}')
    ..writeln('Passive Perception ${c.passivePerception}')
    ..writeln()
    ..writeln('Attack: ${c.weaponName} ${signed(c.attackBonus)} to hit, ${c.weaponDamage}');
  if (c.isCaster) {
    b
      ..writeln('Spellcasting: ${c.spellAbility!.full}, attack ${signed(c.spellAttack)}, DC ${c.spellDc}')
      ..writeln('Spells: ${c.knownSpellDefs.map((s) => s.name).join(', ')}');
  }
  b
    ..writeln()
    ..writeln('Equipment: ${c.inventory.map((i) => i.qty > 1 ? '${i.name} x${i.qty}' : i.name).join(', ')}')
    ..writeln('Gold: ${c.gold}')
    ..writeln()
    ..writeln('Features: ${c.features.map((f) => f.name).join(', ')}');
  if (c.backstory.isNotEmpty) {
    b
      ..writeln()
      ..writeln(c.backstory);
  }
  if (c.notes.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Notes:')
      ..writeln(c.notes);
  }
  return b.toString();
}
