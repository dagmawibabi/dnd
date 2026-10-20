import 'dart:math';

/// Mythic-style yes/no oracle for solo play.
enum Likelihood {
  certain('Certain', 90),
  nearlyCertain('Nearly certain', 80),
  veryLikely('Very likely', 70),
  likely('Likely', 60),
  even('50/50', 50),
  unlikely('Unlikely', 40),
  veryUnlikely('Very unlikely', 30),
  nearlyImpossible('Nearly impossible', 20),
  impossible('Impossible', 10);

  const Likelihood(this.label, this.base);
  final String label;
  final int base;
}

class OracleResult {
  OracleResult({required this.roll, required this.chance, required this.answer, this.event, this.meaning});
  final int roll;
  final int chance;

  /// "Exceptional Yes" | "Yes" | "No" | "Exceptional No"
  final String answer;
  final String? event;
  final String? meaning;

  bool get yes => answer.contains('Yes');
  bool get exceptional => answer.startsWith('Exceptional');
}

const eventFocus = [
  'A remote event shifts the world',
  'An NPC takes sudden action',
  'A new NPC appears',
  'A thread moves toward resolution',
  'A thread moves away from resolution',
  'A thread closes unexpectedly',
  'The hero suffers a setback',
  'The hero gets a lucky break',
  'An ambiguous omen',
  'An NPC is harmed or helped',
  'A new thread begins',
  'The environment turns',
];

const meaningActions = [
  'attain', 'betray', 'reveal', 'abandon', 'protect', 'deceive', 'pursue', 'ruin', 'bargain', 'awaken',
  'imprison', 'heal', 'steal', 'summon', 'oppose', 'guide', 'seize', 'release', 'corrupt', 'restore',
  'hide', 'challenge', 'celebrate', 'mourn', 'transform', 'warn', 'trap', 'follow', 'break', 'bless',
];

const meaningSubjects = [
  'a secret', 'an ally', 'the past', 'power', 'a debt', 'a weapon', 'faith', 'the dead', 'a map', 'a stranger',
  'wealth', 'a promise', 'the law', 'magic', 'family', 'a beast', 'a door', 'the weather', 'a rival', 'a ritual',
  'hope', 'fear', 'a letter', 'the crown', 'nature', 'a ship', 'a song', 'a curse', 'trust', 'a home',
];

class Oracle {
  Oracle([Random? rng]) : _rng = rng ?? Random();
  final Random _rng;

  static int chanceFor(Likelihood l, int chaos) => (l.base + (chaos - 5) * 5).clamp(1, 99);

  String meaning() => '${meaningActions[_rng.nextInt(meaningActions.length)]} ${meaningSubjects[_rng.nextInt(meaningSubjects.length)]}';

  OracleResult ask(Likelihood l, int chaos) {
    final chance = chanceFor(l, chaos);
    final roll = _rng.nextInt(100) + 1;
    final String answer;
    if (roll <= (chance / 5).ceil()) {
      answer = 'Exceptional Yes';
    } else if (roll <= chance) {
      answer = 'Yes';
    } else if (roll > 100 - ((100 - chance) / 5).floor()) {
      answer = 'Exceptional No';
    } else {
      answer = 'No';
    }
    String? event;
    String? mean;
    final tens = roll ~/ 10;
    final ones = roll % 10;
    if (roll < 100 && tens == ones && tens <= chaos && tens > 0) {
      event = eventFocus[_rng.nextInt(eventFocus.length)];
      mean = meaning();
    }
    return OracleResult(roll: roll, chance: chance, answer: answer, event: event, meaning: mean);
  }
}
