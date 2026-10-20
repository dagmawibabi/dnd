// How many spells a character knows or prepares (5e SRD tables, simplified).
import '../models/character.dart';
import 'srd.dart';

/// Classes that prepare spells each day instead of knowing a fixed list.
const preparedCasters = {'cleric', 'druid', 'wizard', 'paladin'};

int cantripsKnown(String classId, int level) {
  if (level <= 0) return 0;
  final base = switch (classId) {
    'sorcerer' => 4,
    'cleric' || 'wizard' => 3,
    'bard' || 'druid' || 'warlock' => 2,
    _ => 0,
  };
  if (base == 0) return 0;
  return base + (level >= 4 ? 1 : 0) + (level >= 10 ? 1 : 0);
}

/// Leveled spells known, for classes that learn a fixed list.
int spellsKnown(String classId, int level) {
  if (level <= 0) return 0;
  const bard = [4, 5, 6, 7, 8, 9, 10, 11, 12, 14, 15, 15, 16, 18, 19, 19, 20, 22, 22, 22];
  const sorcerer = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 12, 13, 13, 14, 14, 15, 15, 15, 15];
  const warlock = [2, 3, 4, 5, 6, 7, 8, 9, 10, 10, 11, 11, 12, 12, 13, 13, 14, 14, 15, 15];
  const ranger = [0, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11];
  final i = (level - 1).clamp(0, 19);
  return switch (classId) {
    'bard' => bard[i],
    'sorcerer' => sorcerer[i],
    'warlock' => warlock[i],
    'ranger' => ranger[i],
    _ => 0,
  };
}

/// Spells a wizard's spellbook can hold: 6 at first level, +2 per level.
int spellbookSize(int wizardLevel) => wizardLevel <= 0 ? 0 : 6 + 2 * (wizardLevel - 1);

extension Spellcasting on Character {
  String? get casterClass => classLevels.keys.where((k) => classById(k).spellAbility != null).firstOrNull;

  bool get prepares => preparedCasters.contains(casterClass);

  int get casterLevel => classLevels[casterClass] ?? 0;

  int get cantripMax => cantripsKnown(casterClass ?? '', casterLevel);

  /// Leveled spells the character may have ready at once.
  int get leveledMax {
    final cls = casterClass;
    if (cls == null) return 0;
    if (!prepares) return spellsKnown(cls, casterLevel);
    final m = mod(spellAbility ?? Ability.wis);
    final lvl = cls == 'paladin' ? casterLevel ~/ 2 : casterLevel;
    return (m + lvl).clamp(1, 30);
  }

  /// Leveled spells this character could learn or prepare right now.
  List<SpellDef> get leveledPool {
    final cls = casterClass;
    if (cls == null) return const [];
    if (cls == 'wizard') return spellbook.map(spellById).whereType<SpellDef>().where((s) => s.level > 0 && s.level <= maxSpellLevel).toList();
    return spellsFor(cls, maxLevel: maxSpellLevel).where((s) => s.level > 0).toList();
  }

  List<SpellDef> get cantripPool => casterClass == null ? const [] : spellsFor(casterClass!, maxLevel: 0);

  int get cantripsChosen => this.spells.where((id) => spellById(id)?.level == 0).length;
  int get leveledChosen => this.spells.where((id) => (spellById(id)?.level ?? 0) > 0).length;

  /// Whether there are spells left to pick (after creation or a level-up).
  bool get hasSpellChoices => casterClass != null && (cantripsChosen < cantripMax.clamp(0, cantripPool.length) || leveledChosen < leveledMax.clamp(0, leveledPool.length) || (casterClass == 'wizard' && spellbook.length < spellbookSize(casterLevel)));
}
