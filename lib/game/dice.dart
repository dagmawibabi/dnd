import 'dart:math' as math;

final math.Random _secure = math.Random();

/// Seeded helpers used by procedural generators.
class Rng {
  Rng(int seed) : _r = math.Random(seed);
  Rng.unseeded() : _r = math.Random();
  final math.Random _r;

  int nextInt(int max) => max <= 0 ? 0 : _r.nextInt(max);
  double nextDouble() => _r.nextDouble();
  bool chance(double p) => _r.nextDouble() < p;
  int range(int min, int maxInclusive) => min + nextInt(maxInclusive - min + 1);
  double rangeD(double min, double max) => min + _r.nextDouble() * (max - min);
  T pick<T>(List<T> list) => list[nextInt(list.length)];
  List<T> shuffled<T>(List<T> list) => List<T>.of(list)..shuffle(_r);
  List<T> sample<T>(List<T> list, int n) => shuffled(list).take(n).toList();
}

int stableHash(String s) {
  var h = 0x811C9DC5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0x7FFFFFFF;
  }
  return h;
}

int rollDie(int sides) => _secure.nextInt(sides) + 1;

enum RollMode { normal, advantage, disadvantage }

class DiceTerm {
  const DiceTerm(this.count, this.sides);
  final int count;
  final int sides;
}

/// Parsed dice expression like "2d6+3", "1d20-1", "4d6kh3", "d8".
class DiceExpression {
  DiceExpression(this.terms, this.modifier, {this.keepHighest});
  final List<DiceTerm> terms;
  final int modifier;
  final int? keepHighest;

  static final _re = RegExp(r'([+-]?)\s*(\d*)d(\d+)(kh\d+)?|([+-]?)\s*(\d+)');

  static DiceExpression parse(String input) {
    final s = input.toLowerCase().replaceAll(' ', '');
    final terms = <DiceTerm>[];
    var mod = 0;
    int? kh;
    for (final m in _re.allMatches(s)) {
      if (m.group(3) != null) {
        final count = (m.group(2) ?? '').isEmpty ? 1 : int.parse(m.group(2)!);
        terms.add(DiceTerm(count.clamp(1, 100), int.parse(m.group(3)!).clamp(2, 1000)));
        if (m.group(4) != null) kh = int.tryParse(m.group(4)!.substring(2));
      } else if (m.group(6) != null) {
        final v = int.parse(m.group(6)!);
        mod += m.group(5) == '-' ? -v : v;
      }
    }
    if (terms.isEmpty && mod == 0) terms.add(const DiceTerm(1, 20));
    return DiceExpression(terms, mod, keepHighest: kh);
  }

  int get maxValue => terms.fold(0, (a, t) => a + t.count * t.sides) + modifier;
  double get average => terms.fold(0.0, (a, t) => a + t.count * (t.sides + 1) / 2) + modifier;

  DiceResult roll({bool critical = false}) {
    final rolls = <DieRoll>[];
    for (final t in terms) {
      final n = critical ? t.count * 2 : t.count;
      for (var i = 0; i < n; i++) {
        rolls.add(DieRoll(t.sides, rollDie(t.sides)));
      }
    }
    var kept = rolls;
    if (keepHighest != null && keepHighest! < rolls.length) {
      final sorted = [...rolls]..sort((a, b) => b.value.compareTo(a.value));
      final keep = sorted.take(keepHighest!).toSet();
      for (final r in rolls) {
        r.dropped = !keep.contains(r);
      }
      kept = rolls.where((r) => !r.dropped).toList();
    }
    final total = kept.fold<int>(0, (a, r) => a + r.value) + modifier;
    return DiceResult(toString(), rolls, modifier, total);
  }

  @override
  String toString() {
    final parts = terms.map((t) => '${t.count}d${t.sides}${keepHighest != null ? 'kh$keepHighest' : ''}').join('+');
    if (modifier == 0) return parts;
    return '$parts${modifier > 0 ? '+' : ''}$modifier';
  }
}

class DieRoll {
  DieRoll(this.sides, this.value);
  final int sides;
  final int value;
  bool dropped = false;
}

class DiceResult {
  DiceResult(this.expression, this.rolls, this.modifier, this.total);
  final String expression;
  final List<DieRoll> rolls;
  final int modifier;
  final int total;

  String get breakdown {
    final r = rolls.map((d) => d.dropped ? '~${d.value}~' : '${d.value}').join(' + ');
    if (modifier == 0) return r;
    return '$r ${modifier > 0 ? '+' : '-'} ${modifier.abs()}';
  }
}

/// A single d20 test (attack, check or save).
class D20Result {
  D20Result({required this.rolls, required this.mode, required this.modifier, this.dc, this.label = ''});
  final List<int> rolls;
  final RollMode mode;
  final int modifier;
  final int? dc;
  final String label;

  int get natural => switch (mode) {
        RollMode.normal => rolls.first,
        RollMode.advantage => math.max(rolls[0], rolls[1]),
        RollMode.disadvantage => math.min(rolls[0], rolls[1]),
      };
  int get total => natural + modifier;
  bool get isCrit => natural == 20;
  bool get isFumble => natural == 1;
  bool get success => dc == null ? true : (isCrit || (!isFumble && total >= dc!));

  String describe() {
    final m = modifier == 0 ? '' : (modifier > 0 ? ' + $modifier' : ' - ${modifier.abs()}');
    final adv = mode == RollMode.normal ? '' : ' (${mode == RollMode.advantage ? 'adv' : 'dis'}: ${rolls.join('/')})';
    final vs = dc == null ? '' : ' vs DC $dc — ${success ? 'SUCCESS' : 'FAILURE'}';
    return '$label: $natural$m = $total$adv$vs${isCrit ? ' (NATURAL 20!)' : isFumble ? ' (natural 1)' : ''}';
  }
}

D20Result rollD20({int modifier = 0, RollMode mode = RollMode.normal, int? dc, String label = '', int? forcedNatural}) {
  final rolls = mode == RollMode.normal ? [forcedNatural ?? rollDie(20)] : [forcedNatural ?? rollDie(20), rollDie(20)];
  if (forcedNatural != null && mode != RollMode.normal) {
    // forced value represents the final natural result from the dice widget
    rolls[1] = mode == RollMode.advantage ? math.min(rolls[1], forcedNatural) : math.max(rolls[1], forcedNatural);
  }
  return D20Result(rolls: rolls, mode: mode, modifier: modifier, dc: dc, label: label);
}

String signed(int v) => v >= 0 ? '+$v' : '$v';
