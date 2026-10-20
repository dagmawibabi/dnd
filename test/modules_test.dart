import 'package:dnd/data/modules.dart';
import 'package:dnd/data/presets.dart';
import 'package:dnd/game/dice.dart';
import 'package:dnd/game/module_engine.dart';
import 'package:dnd/models/adventure.dart';
import 'package:dnd/services/audio/synth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every module link points at a real scene', () {
    for (final m in adventureModules) {
      expect(m.nodes.containsKey(m.start), isTrue, reason: '${m.id} start');
      for (final e in m.nodes.entries) {
        final n = e.value;
        final targets = <String?>[
          for (final c in n.choices) ...[c.go, c.ok, c.fail, ...?c.random],
          n.combat?.win,
          n.combat?.lose,
        ].whereType<String>();
        for (final t in targets) {
          expect(m.nodes.containsKey(t), isTrue, reason: '${m.id}/${e.key} -> $t');
        }
        expect(n.end != null || n.combat != null || n.choices.isNotEmpty, isTrue, reason: '${m.id}/${e.key} is a dead end');
      }
      if (!m.tags.contains('Tutorial')) expect(m.endings, greaterThanOrEqualTo(3), reason: '${m.id} endings');
    }
  });

  test('random playthroughs of every module reach an ending', () {
    final rng = Rng(42);
    for (final m in adventureModules) {
      final reached = <String>{};
      for (var run = 0; run < 40; run++) {
        final hero = presets[run % presets.length].create();
        final adv = Adventure(id: 'm$run', title: m.title, premise: '', hero: hero, engine: StoryEngine.module, offline: ModuleEngine.createState(m.id));
        var turn = ModuleEngine(adv).begin();
        var steps = 0;
        while (!adv.finished && steps < 80) {
          steps++;
          if (turn.events.any((e) => e['type'] == 'combat')) {
            turn = ModuleEngine(adv).afterCombat(victory: rng.chance(0.75), fled: false);
            continue;
          }
          expect(turn.choices, isNotEmpty, reason: '${m.id} stuck at ${adv.offline['node']}');
          final c = rng.pick(turn.choices);
          final roll = c.check == null ? null : rollD20(modifier: 2, dc: c.check!.dc);
          turn = ModuleEngine(adv).choose(c, roll);
        }
        expect(adv.finished, isTrue, reason: '${m.id} run $run did not finish (at ${adv.offline['node']})');
        reached.add(adv.offline['node'] as String);
      }
      if (!m.tags.contains('Tutorial')) expect(reached.length, greaterThanOrEqualTo(2), reason: '${m.id} only ever reached $reached');
    }
  });

  test('all sound effects render without clipping or silence', () {
    for (final n in sfxNames) {
      final wav = renderSfx(n);
      expect(wav.length, greaterThan(1000), reason: n);
      var peak = 0;
      for (var i = 44; i + 1 < wav.length; i += 2) {
        final v = (wav[i] | (wav[i + 1] << 8)).toSigned(16).abs();
        if (v > peak) peak = v;
      }
      expect(peak, greaterThan(3000), reason: '$n is silent');
      expect(peak, lessThan(32767), reason: '$n clips');
    }
  });
}
