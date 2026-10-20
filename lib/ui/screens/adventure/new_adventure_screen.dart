import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/names.dart';
import '../../../art/scene_painter.dart';
import '../../../data/modules.dart';
import '../../../data/presets.dart';
import '../../../game/module_engine.dart';
import '../../../game/dice.dart';
import '../../../models/adventure.dart';
import '../../../models/character.dart';
import '../../../services/ai/dungeon_master.dart';
import '../../../services/game_store.dart';
import '../../../services/settings.dart';
import '../../../theme/ui.dart';
import '../../widgets/ai_gate.dart';
import '../../widgets/bright_art.dart';
import '../../widgets/portrait.dart';
import '../character/character_creator.dart';
import 'adventure_screen.dart';
import 'text_adventure_screen.dart';

const _settings = {
  'High fantasy': 'forest',
  'Grimdark': 'ruins',
  'Gothic horror': 'crypt',
  'High seas': 'coast',
  'Desert': 'desert',
  'Frozen north': 'tundra',
  'Fey wilds': 'swamp',
  'Underdark': 'cave',
  'Arcane city': 'tower',
};
const _tones = ['Heroic', 'Dark', 'Whimsical', 'Mysterious', 'Epic', 'Comedic'];
const _difficulties = ['Story', 'Normal', 'Hard', 'Deadly'];

class NewAdventureScreen extends StatefulWidget {
  const NewAdventureScreen({super.key, this.heroId});
  final String? heroId;

  @override
  State<NewAdventureScreen> createState() => _NewAdventureScreenState();
}

class _NewAdventureScreenState extends State<NewAdventureScreen> {
  String? _heroId;
  late StoryEngine _engine;
  bool _textMode = false;
  String _setting = 'High fantasy';
  String _tone = 'Heroic';
  String _difficulty = 'Normal';
  late bool _hardcore = context.read<SettingsController>().defaultHardcore;
  late bool _showDcs = context.read<SettingsController>().defaultShowDcs;
  int _chaos = 5;
  final List<Character> _companions = [];
  final _titleCtrl = TextEditingController();
  final _premiseCtrl = TextEditingController();
  bool _generating = false;
  int _seed = math.Random().nextInt(1 << 30);
  String _moduleId = adventureModules.first.id;

  @override
  void initState() {
    super.initState();
    final store = context.read<GameStore>();
    _heroId = widget.heroId ?? (store.characters.isNotEmpty ? store.characters.first.id : null);
    _engine = context.read<SettingsController>().useAiText ? StoryEngine.ai : StoryEngine.module;
    if (store.adventures.isNotEmpty) _moduleId = 'goblin_toll';
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _premiseCtrl.dispose();
    super.dispose();
  }

  Character? get _hero => _heroId == null ? null : context.read<GameStore>().character(_heroId!);

  Future<void> _generatePremise() async {
    final hero = _hero;
    if (hero == null) return;
    setState(() => _generating = true);
    try {
      final settings = context.read<SettingsController>();
      if (_engine == StoryEngine.ai && settings.useAiPremises) {
        final r = await AiDungeonMaster(settings).premise(setting: _setting, tone: _tone, hero: hero, seedIdea: _premiseCtrl.text);
        _titleCtrl.text = r['title']!;
        _premiseCtrl.text = r['premise']!;
      } else {
        final r = Rng.unseeded();
        final place = randomPlace(rng: r);
        _titleCtrl.text = r.pick([
          'The ${r.pick(['Ashen', 'Drowned', 'Hollow', 'Silent', 'Crimson', 'Forgotten'])} ${r.pick(['Crown', 'Bell', 'Road', 'Saint', 'Vault', 'Oath'])}',
          'Shadows over $place',
          'The Last Light of $place',
        ]);
        _premiseCtrl.text = 'A ${_tone.toLowerCase()} story in a ${_setting.toLowerCase()} world. Something stirs near $place, and ${hero.name} is the one who answers.';
        _seed = r.nextInt(1 << 30);
      }
    } catch (e) {
      if (mounted) showToast(context, 'Couldn\'t generate a premise: $e', icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _addCompanion() async {
    final store = context.read<GameStore>();
    final options = store.characters.where((c) => c.id != _heroId && !_companions.any((x) => x.name == c.name)).toList();
    final picked = await showAppSheet<Character>(
      context,
      builder: (ctx) {
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const SheetTitle('Add companion', subtitle: 'Companions fight, heal and talk on their own.'),
            if (options.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SectionLabel('Your characters', padding: EdgeInsets.fromLTRB(4, 0, 4, 8)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: RowGroup(
                  children: [
                    for (final c in options)
                      ListRow(
                        leading: CharacterPortrait(character: c, size: 40),
                        title: c.name,
                        subtitle: 'Level ${c.level} ${c.classSummary}',
                        onTap: () => Navigator.pop(ctx, c.clone()),
                      ),
                  ],
                ),
              ),
            ],
            const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: SectionLabel('Presets')),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: RowGroup(
                children: [
                  for (final p in presets.where((p) => !_companions.any((c) => c.name == p.name) && _hero?.name != p.name))
                    ListRow(
                      leading: CharacterPortrait(character: p.create(), size: 40),
                      title: p.name,
                      subtitle: p.personality,
                      onTap: () => Navigator.pop(ctx, p.create()),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: AppButton(
                label: 'Create new companion',
                kind: ButtonKind.secondary,
                icon: Icons.add,
                onPressed: () async {
                  final c = await Navigator.of(ctx).push<Character>(MaterialPageRoute(builder: (_) => const CharacterCreator(companionMode: true)));
                  if (c != null && ctx.mounted) Navigator.pop(ctx, c.clone());
                },
              ),
            ),
          ],
        );
      },
    );
    if (picked == null) return;
    final hero = _hero;
    picked.id = newId();
    picked.isCompanion = true;
    while (hero != null && picked.level < hero.level) {
      picked.xp = hero.xp;
      picked.levelUp(picked.classLevels.keys.first);
      picked.autoProgress(picked.classLevels.keys.first);
    }
    setState(() => _companions.add(picked));
  }

  Future<void> _start() async {
    final heroSrc = _hero;
    if (heroSrc == null) return;
    final hero = heroSrc.clone();
    if (!hero.inventory.any((i) => i.name.toLowerCase().contains('ration'))) hero.inventory.add(InventoryItem.of('rations', qty: 3));
    final mod = _engine == StoryEngine.module ? moduleById(_moduleId) : null;
    if (mod != null) {
      _titleCtrl.text = mod.title;
      _premiseCtrl.text = mod.tagline;
      _setting = mod.setting[0].toUpperCase() + mod.setting.substring(1);
      _tone = mod.tone;
    }
    final adv = Adventure(
      id: newId(),
      title: _titleCtrl.text.trim().isEmpty ? 'The Tale of ${hero.name.split(' ').first}' : _titleCtrl.text.trim(),
      premise: _premiseCtrl.text.trim().isEmpty ? 'Surprise the hero with a compelling hook.' : _premiseCtrl.text.trim(),
      hero: hero,
      engine: _engine,
      setting: _setting,
      tone: _tone,
      difficulty: _difficulty,
      textMode: _textMode,
      companions: _companions,
      coverSeed: _seed,
      scene: SceneInfo(title: 'The Beginning', location: mod?.coverLoc ?? _settings[_setting] ?? 'forest', time: mod?.coverTime ?? 'dusk', mood: 'mystery', seed: _seed),
      offline: mod == null ? null : ModuleEngine.createState(mod.id),
      hardcore: _hardcore,
      showDcs: _showDcs,
      chaos: _chaos,
    );
    await context.read<GameStore>().saveAdventure(adv, syncHero: false);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => _textMode ? TextAdventureScreen(adventure: adv) : AdventureScreen(adventure: adv),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<GameStore>();
    final settings = context.watch<SettingsController>();
    final hero = _hero;
    return Scaffold(
      appBar: AppBar(title: const Text('New adventure')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            const SectionLabel('Character', padding: EdgeInsets.fromLTRB(4, 8, 4, 10)),
            SizedBox(
              height: 108,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final c in store.characters)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 84,
                        child: SelectCard(
                          selected: c.id == _heroId,
                          showCheck: false,
                          padding: const EdgeInsets.all(8),
                          onTap: () => setState(() {
                            _heroId = c.id;
                            _companions.removeWhere((x) => x.name == c.name);
                          }),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Column(
                            children: [
                              CharacterPortrait(character: c, size: 46),
                              const SizedBox(height: 4),
                              Text(
                                c.name.split(' ').first,
                                style: T.caption(color: AppColors.text),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text('Lv ${c.level}', style: T.caption()),
                            ],
                          ),
                          ),
                        ),
                      ),
                    ),
                  SizedBox(
                    width: 84,
                    child: AppCard(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CharacterCreator())),
                      padding: EdgeInsets.zero,
                      child: const Center(child: Icon(Icons.add, color: AppColors.textMuted)),
                    ),
                  ),
                ],
              ),
            ),
            const SectionLabel('Story'),
            SegmentedButton<StoryEngine>(
              showSelectedIcon: false,
              segments: [
                const ButtonSegment(value: StoryEngine.module, label: Text('Stories', maxLines: 1), icon: Icon(Icons.auto_stories_outlined, size: 16)),
                ButtonSegment(value: StoryEngine.ai, label: const Text('AI'), icon: Icon(settings.useAiText ? Icons.auto_awesome_outlined : Icons.lock_outline, size: 16)),
                const ButtonSegment(value: StoryEngine.offline, label: Text('Endless'), icon: Icon(Icons.all_inclusive, size: 16)),
              ],
              selected: {_engine},
              onSelectionChanged: (v) {
                if (v.first == StoryEngine.ai && !settings.useAiText) {
                  showAiUnavailable(context, feature: 'AI adventures');
                  return;
                }
                setState(() => _engine = v.first);
              },
            ),
            const SizedBox(height: 6),
            Text(
              switch (_engine) {
                    StoryEngine.module => 'Handcrafted stories with branching choices and multiple endings. Works offline.',
                    StoryEngine.ai => 'An AI Dungeon Master improvises the story with ${settings.textModel}.',
                    StoryEngine.offline => 'Generated quests that never run out. Works offline.',
                  } +
                  (settings.useAiText ? '' : ' Tap AI to see how to turn on the AI Dungeon Master.'),
              style: T.caption(),
            ),
            if (_engine == StoryEngine.module) ...[
              const SizedBox(height: 14),
              for (final m in adventureModules)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ModuleCard(module: m, selected: m.id == _moduleId, onTap: () => setState(() => _moduleId = m.id)),
                ),
            ],
            const SectionLabel('Layout'),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('Standard'), icon: Icon(Icons.view_agenda_outlined, size: 16)),
                ButtonSegment(value: true, label: Text('Text only'), icon: Icon(Icons.notes, size: 16)),
              ],
              selected: {_textMode},
              onSelectionChanged: (v) => setState(() => _textMode = v.first),
            ),
            if (_engine != StoryEngine.module) ...[
              const SectionLabel('Setting'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [for (final s in _settings.keys) ChoiceChip(label: Text(s), selected: _setting == s, onSelected: (_) => setState(() => _setting = s))],
              ),
              const SectionLabel('Tone'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [for (final t in _tones) ChoiceChip(label: Text(t), selected: _tone == t, onSelected: (_) => setState(() => _tone = t))],
              ),
            ],
            const SectionLabel('Difficulty'),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [for (final d in _difficulties) ButtonSegment(value: d, label: Text(d))],
              selected: {_difficulty},
              onSelectionChanged: (s) => setState(() => _difficulty = s.first),
            ),
            const SizedBox(height: 10),
            RowGroup(children: [
              ListRow(
                leading: Icon(Icons.local_fire_department_outlined, size: 20, color: _hardcore ? AppColors.danger : null),
                title: 'Hardcore',
                subtitle: 'Permadeath. No rewind. Rests are riskier.',
                trailing: Switch(value: _hardcore, onChanged: (v) => setState(() => _hardcore = v)),
              ),
              ListRow(
                leading: const Icon(Icons.visibility_outlined, size: 20),
                title: 'Show DCs',
                subtitle: 'See how hard each check is before you roll',
                trailing: Switch(value: _showDcs, onChanged: (v) => setState(() => _showDcs = v)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                child: Row(children: [
                  const Icon(Icons.help_outline, size: 20, color: AppColors.textMuted),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Oracle chaos', style: T.body()),
                      Text(_chaos <= 3 ? 'Orderly: few surprises' : (_chaos <= 6 ? 'Balanced' : 'Chaotic: expect the unexpected'), style: T.small()),
                    ]),
                  ),
                  SizedBox(width: 140, child: Slider(value: _chaos.toDouble(), min: 1, max: 9, divisions: 8, label: '$_chaos', onChanged: (v) => setState(() => _chaos = v.round()))),
                ]),
              ),
            ]),
            SectionLabel('Companions', trailing: Text('${_companions.length}/3', style: T.caption())),
            RowGroup(
              children: [
                for (final c in _companions)
                  ListRow(
                    leading: CharacterPortrait(character: c, size: 36),
                    title: c.name,
                    subtitle: 'Level ${c.level} ${c.classSummary}',
                    trailing: IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _companions.remove(c))),
                  ),
                if (_companions.length < 3) ListRow(leading: const Icon(Icons.add, size: 20), title: 'Add companion', onTap: hero == null ? null : _addCompanion),
              ],
            ),
            if (_engine != StoryEngine.module) ...[
              SectionLabel(
                'Premise',
                trailing: TextButton.icon(
                  onPressed: hero == null || _generating ? null : _generatePremise,
                  icon: _generating ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome_outlined, size: 16),
                  label: Text('Generate', style: T.small(color: AppColors.text)),
                ),
              ),
              TextField(
                controller: _titleCtrl,
                style: T.body(),
                decoration: const InputDecoration(hintText: 'Title (optional)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _premiseCtrl,
                style: T.body(),
                minLines: 3,
                maxLines: 6,
                decoration: InputDecoration(
                  hintText: _engine == StoryEngine.ai ? 'An idea for the story, or leave blank to be surprised' : 'Optional. The offline storyteller generates its own quest.',
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: ContentWidth(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: AppButton(label: 'Start adventure', onPressed: hero == null ? null : _start),
          ),
        ),
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({required this.module, required this.selected, required this.onTap});
  final AdventureModule module;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = module;
    return SelectCard(
      selected: selected,
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
            child: SizedBox(
              height: selected ? 150 : 110,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  BrightArt(child: SceneView(location: m.coverLoc, time: m.coverTime, mood: 'calm', seed: stableModSeed(m.id))),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: [0.45, 1], colors: [Colors.transparent, Color(0xB3000000)]),
                    ),
                  ),
                  Positioned(
                    left: 14,
                    bottom: 10,
                    right: 40,
                    child: Text(m.title, style: T.h3(color: Colors.white)),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.tagline, style: T.small(color: AppColors.text)),
                if (selected) ...[const SizedBox(height: 8), Text(m.description, style: T.small())],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    Tag('Level ${m.levels}'),
                    Tag('~${m.minutes} min'),
                    Tag(m.endings == 1 ? '1 ending' : '${m.endings} endings'),
                    if (m.seriesId != null) Tag('Part ${m.part}', icon: Icons.auto_stories_outlined, color: AppColors.warning),
                    if (m.classes.isNotEmpty) Tag('Best for ${m.classes.map((c) => c[0].toUpperCase() + c.substring(1)).join(' & ')}', icon: Icons.star_outline),
                    Tag(m.tone),
                    if (selected)
                      for (final t in m.tags) Tag(t, color: AppColors.accent, filled: true),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

int stableModSeed(String id) => id.codeUnits.fold(7, (a, c) => (a * 31 + c) & 0x3FFFFFFF);
