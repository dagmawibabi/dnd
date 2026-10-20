import 'dart:convert';

import 'package:dnd/data/presets.dart';
import 'package:dnd/data/srd.dart';
import 'package:dnd/game/combat.dart';
import 'package:dnd/game/dice.dart';
import 'package:dnd/game/offline_engine.dart';
import 'package:dnd/game/story.dart';
import 'package:dnd/models/adventure.dart';
import 'package:dnd/models/character.dart';
import 'package:dnd/services/audio/synth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dice expressions parse and roll within bounds', () {
    final e = DiceExpression.parse('2d6+3');
    expect(e.terms.single.count, 2);
    expect(e.modifier, 3);
    for (var i = 0; i < 200; i++) {
      final r = e.roll().total;
      expect(r, inInclusiveRange(5, 15));
    }
    final kh = DiceExpression.parse('4d6kh3').roll();
    expect(kh.rolls.where((r) => r.dropped).length, 1);
    expect(rollD20(modifier: 2, dc: 10, forcedNatural: 20).isCrit, isTrue);
    expect(rollD20(modifier: 50, dc: 10, forcedNatural: 1).success, isFalse);
  });

  test('presets build valid level-1 characters and round-trip JSON', () {
    for (final p in presets) {
      final c = p.create();
      expect(c.maxHp, greaterThan(0));
      expect(c.armorClass, greaterThanOrEqualTo(10));
      expect(c.inventory, isNotEmpty);
      final back = Character.fromJson(jsonDecode(jsonEncode(c.toJson())));
      expect(back.name, c.name);
      expect(back.score(Ability.cha), c.score(Ability.cha));
      expect(back.skills, c.skills);
    }
  });

  test('leveling and multiclassing', () {
    final c = presets.first.create();
    c.xp = 900;
    expect(c.canLevelUp, isTrue);
    c.levelUp('warlock');
    c.levelUp('sorcerer');
    expect(c.level, 3);
    expect(c.classLevels['sorcerer'], 1);
    expect(c.spellSlots, isNotEmpty);
  });

  test('DM JSON parsing tolerates fences and partial streams', () {
    const raw = 'Sure!\n```json\n{"narration": "You enter the \\"crypt\\".", "choices": [{"text": "Sneak", "type": "stealth", "check": {"ability": "DEX", "skill": "Stealth", "dc": 13}}], "events": [{"type": "gold", "amount": 5}]}\n```';
    final t = DmTurn.parse(raw);
    expect(t.narration, 'You enter the "crypt".');
    expect(t.choices.single.check!.skill, Skill.stealth);
    expect(t.events.single['amount'], 5);
    expect(partialJsonString('{"narration": "Hello wor', 'narration'), 'Hello wor');
  });

  test('offline adventure can be played start to finish', () {
    for (var seed = 1; seed <= 12; seed++) {
      final hero = presets[seed % presets.length].create();
      final adv = Adventure(id: 'a$seed', title: 'T', premise: '', hero: hero, engine: StoryEngine.offline, companions: [presets[(seed + 3) % presets.length].create()..isCompanion = true]);
      adv.offline = OfflineEngine.createState(seed * 7919, hero);
      var turn = OfflineEngine(adv).begin();
      var steps = 0;
      while (!adv.finished && steps < 200) {
        steps++;
        final combat = turn.events.where((e) => e['type'] == 'combat').firstOrNull;
        if (combat != null) {
          final specs = (combat['enemies'] as List).map((e) => EnemySpec.fromJson(Map<String, dynamic>.from(e))).toList();
          final engine = CombatEngine(adv);
          engine.begin(CombatEngine.buildEnemies(specs, partyLevel: hero.level));
          var rounds = 0;
          while (!engine.state.victory && !engine.state.defeat && rounds < 400) {
            rounds++;
            final cur = engine.state.current;
            if (!cur.down) {
              if (cur.isPlayer) {
                final foe = engine.state.enemies.firstWhere((e) => !e.down);
                engine.attack(cur, foe);
              } else {
                engine.autoTurn();
              }
            }
            engine.nextTurn();
          }
          final victory = engine.state.victory;
          final boss = combat['boss'] == true;
          engine.finish();
          if (hero.hp <= 0) hero.hp = 1;
          turn = OfflineEngine(adv).afterCombat(victory: victory, fled: false, xp: 0, wasBoss: boss);
          continue;
        }
        expect(turn.choices, isNotEmpty, reason: 'seed $seed step $steps: ${turn.narration}');
        // prefer moving forward, otherwise first option
        final c = turn.choices.firstWhere((c) => c.data['a'] == 'next' || c.type == ChoiceType.combat, orElse: () => turn.choices.first);
        final roll = c.check == null ? null : rollD20(modifier: hero.mod(c.check!.ability), dc: c.check!.dc);
        turn = OfflineEngine(adv).choose(c, roll);
      }
      expect(adv.finished, isTrue, reason: 'seed $seed did not finish in $steps steps');
    }
  });

  test('synth renders valid WAV data', () {
    final sfx = renderSfx('dice');
    expect(String.fromCharCodes(sfx.sublist(0, 4)), 'RIFF');
    final music = renderMusic('dungeon');
    expect(music.length, greaterThan(44 + kSampleRate));
  });
}
