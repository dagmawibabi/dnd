import 'package:flutter/material.dart';

import '../../../art/class_icon.dart';
import '../../../data/progression.dart';
import '../../../data/srd.dart';
import '../../../models/character.dart';
import '../../../theme/ui.dart';

class LevelUpResult {
  const LevelUpResult({required this.classId, this.rollHp = false, this.subclassId, this.asi, this.feat});
  final String classId;
  final bool rollHp;
  final String? subclassId;
  final Map<Ability, int>? asi;
  final String? feat;
}

Future<LevelUpResult?> showLevelUpSheet(BuildContext context, Character c) {
  return showAppSheet<LevelUpResult>(context, builder: (ctx) => _LevelUpSheet(character: c));
}

enum _AsiMode { plus2, plus11, feat }

class _LevelUpSheet extends StatefulWidget {
  const _LevelUpSheet({required this.character});
  final Character character;

  @override
  State<_LevelUpSheet> createState() => _LevelUpSheetState();
}

class _LevelUpSheetState extends State<_LevelUpSheet> {
  late String _classId = widget.character.classLevels.keys.first;
  bool _roll = false;
  String? _subclass;
  _AsiMode _mode = _AsiMode.plus2;
  Ability? _a1;
  Ability? _a2;
  String? _feat;

  Character get c => widget.character;

  /// 5e multiclassing: 13+ in the key ability of the new class and of your current classes.
  bool _canTake(String classId) {
    if (c.classLevels.containsKey(classId)) return true;
    return meetsMulticlass(classId, c.score) && c.classLevels.keys.every((k) => meetsMulticlass(k, c.score));
  }
  int get _nextClassLevel => (c.classLevels[_classId] ?? 0) + 1;
  bool get _needsSub => _nextClassLevel >= subclassLevel(_classId) && !c.subclasses.containsKey(_classId) && subclassesFor(_classId).isNotEmpty;
  bool get _gainsAsi => asiLevels.contains(c.level + 1);

  bool get _valid {
    if (_needsSub && _subclass == null) return false;
    if (!_gainsAsi) return true;
    return switch (_mode) {
      _AsiMode.plus2 => _a1 != null,
      _AsiMode.plus11 => _a1 != null && _a2 != null && _a1 != _a2,
      _AsiMode.feat => _feat != null,
    };
  }

  void _submit() {
    Map<Ability, int>? asi;
    String? feat;
    if (_gainsAsi) {
      switch (_mode) {
        case _AsiMode.plus2:
          asi = {_a1!: 2};
        case _AsiMode.plus11:
          asi = {_a1!: 1, _a2!: 1};
        case _AsiMode.feat:
          feat = _feat;
          final ab = featById(_feat!)?.ability;
          if (ab != null) asi = {ab: 1};
      }
    }
    Navigator.pop(context, LevelUpResult(classId: _classId, rollHp: _roll, subclassId: _needsSub ? _subclass : null, asi: asi, feat: feat));
  }

  Widget _abilityPicker({required Ability? value, required ValueChanged<Ability> onPick, required int bonus, Ability? exclude}) {
    return CompactChips(child: Wrap(spacing: 6, runSpacing: 6, children: [
      for (final a in Ability.values)
        ChoiceChip(
          label: Text('${a.short} ${c.score(a)}${value == a ? ' → ${(c.score(a) + bonus).clamp(0, 20)}' : ''}'),
          selected: value == a,
          onSelected: (c.score(a) + bonus > 20 || a == exclude) ? null : (_) => setState(() => onPick(a)),
        ),
    ]));
  }

  @override
  Widget build(BuildContext context) {
    final cls = classById(_classId);
    final newFeatures = cls.features.where((f) => f.level == _nextClassLevel).toList();
    final ordered = [...c.classLevels.keys, ...classes.map((x) => x.id).where((id) => !c.classLevels.containsKey(id))];
    final currentSub = subclassById(c.subclasses[_classId]);
    final subFeatures = currentSub?.features.where((f) => f.level == _nextClassLevel).toList() ?? const <SubclassFeature>[];
    final availableFeats = feats.where((f) => !c.feats.contains(f.id) && (f.prereq != 'Spellcasting' || c.isCaster)).toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.85,
      child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        SheetTitle('Level ${c.level + 1}', subtitle: 'Advance a class${_needsSub ? ', choose a subclass' : ''}${_gainsAsi ? ' and improve yourself' : ''}.'),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: ordered.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (ctx, i) {
              final k = ordered[i];
              final allowed = _canTake(k);
              return SizedBox(
                width: 92,
                child: Opacity(
                  opacity: allowed ? 1 : 0.4,
                  child: SelectCard(
                  selected: _classId == k,
                  showCheck: false,
                  padding: const EdgeInsets.all(10),
                  onTap: () {
                    if (!allowed) {
                      showToast(context, 'Multiclassing into ${classById(k).name} needs ${multiclassText(k)}, and your current class needs ${c.classLevels.keys.map(multiclassText).join(', ')}.', icon: Icons.block);
                      return;
                    }
                    setState(() {
                      _classId = k;
                      _subclass = null;
                    });
                  },
                  child: Column(children: [
                    ClassIcon(classId: k, size: 30),
                    const SizedBox(height: 6),
                    Text(classById(k).name, style: T.caption(color: AppColors.text), overflow: TextOverflow.ellipsis),
                    Text(c.classLevels.containsKey(k) ? '${c.classLevels[k]} → ${c.classLevels[k]! + 1}' : (allowed ? 'New' : multiclassText(k)), style: T.caption(), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ]),
                ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SectionLabel('Hit points'),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: false, label: Text('Average (${cls.hitDie ~/ 2 + 1})')),
                ButtonSegment(value: true, label: Text('Roll d${cls.hitDie}')),
              ],
              selected: {_roll},
              onSelectionChanged: (v) => setState(() => _roll = v.first),
            ),
            if (newFeatures.isNotEmpty || subFeatures.isNotEmpty) ...[
              const SectionLabel('New features'),
              for (final f in newFeatures) _Feature(name: f.name, text: f.text),
              for (final f in subFeatures) _Feature(name: f.name, text: f.text, tag: currentSub!.name),
            ],
            if (_needsSub) ...[
              SectionLabel('Choose your ${cls.name} subclass'),
              for (final s in subclassesFor(_classId))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SelectCard(
                    selected: _subclass == s.id,
                    onTap: () => setState(() => _subclass = s.id),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.name, style: T.h3()),
                      const SizedBox(height: 2),
                      Text(s.description, style: T.small()),
                      const SizedBox(height: 8),
                      for (final f in s.features)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text('Lv ${f.level} · ${f.name}: ${f.text}', style: T.caption(color: f.level <= _nextClassLevel ? AppColors.text : AppColors.textFaint)),
                        ),
                    ]),
                  ),
                ),
            ],
            if (_gainsAsi) ...[
              const SectionLabel('Ability score improvement'),
              SegmentedButton<_AsiMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: _AsiMode.plus2, label: Text('+2 one')),
                  ButtonSegment(value: _AsiMode.plus11, label: Text('+1 two')),
                  ButtonSegment(value: _AsiMode.feat, label: Text('Feat')),
                ],
                selected: {_mode},
                onSelectionChanged: (v) => setState(() {
                  _mode = v.first;
                  _a1 = null;
                  _a2 = null;
                  _feat = null;
                }),
              ),
              const SizedBox(height: 12),
              if (_mode == _AsiMode.plus2) _abilityPicker(value: _a1, bonus: 2, onPick: (a) => _a1 = a),
              if (_mode == _AsiMode.plus11) ...[
                Text('First', style: T.caption()),
                const SizedBox(height: 6),
                _abilityPicker(value: _a1, bonus: 1, exclude: _a2, onPick: (a) => _a1 = a),
                const SizedBox(height: 10),
                Text('Second', style: T.caption()),
                const SizedBox(height: 6),
                _abilityPicker(value: _a2, bonus: 1, exclude: _a1, onPick: (a) => _a2 = a),
              ],
              if (_mode == _AsiMode.feat)
                for (final f in availableFeats)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: SelectCard(
                      selected: _feat == f.id,
                      padding: const EdgeInsets.all(12),
                      onTap: () => setState(() => _feat = f.id),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(f.name, style: T.h3())),
                          if (f.ability != null) Tag('+1 ${f.ability!.short}'),
                        ]),
                        const SizedBox(height: 2),
                        Text(f.description, style: T.small()),
                      ]),
                    ),
                  ),
            ],
            if (cls.caster != CasterType.none) Padding(padding: const EdgeInsets.only(top: 12), child: Text('You\'ll learn a new spell if one is available.', style: T.caption())),
            const SizedBox(height: 20),
            AppButton(label: 'Level up', icon: Icons.arrow_upward, onPressed: _valid ? _submit : null),
            if (!_valid) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_needsSub && _subclass == null ? 'Choose a subclass to continue.' : 'Choose your improvement to continue.', textAlign: TextAlign.center, style: T.caption())),
          ]),
        ),
      ]),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({required this.name, required this.text, this.tag});
  final String name;
  final String text;
  final String? tag;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(padding: EdgeInsets.only(top: 3), child: Icon(Icons.auto_awesome, size: 14, color: AppColors.accent)),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(TextSpan(children: [
            TextSpan(text: name, style: T.small(color: AppColors.text).copyWith(fontWeight: FontWeight.w600)),
            if (tag != null) TextSpan(text: ' · $tag', style: T.caption()),
            TextSpan(text: '  $text', style: T.small()),
          ])),
        ),
      ]),
    );
  }
}
