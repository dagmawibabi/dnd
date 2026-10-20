import 'dart:convert';

import 'package:dnd/data/presets.dart';
import 'package:dnd/data/progression.dart';
import 'package:dnd/data/srd.dart';
import 'package:dnd/data/tables.dart';
import 'package:dnd/game/combat.dart';
import 'package:dnd/game/dice.dart';
import 'package:dnd/game/oracle.dart';
import 'package:dnd/game/story.dart';
import 'package:dnd/models/adventure.dart';
import 'package:dnd/models/campaign.dart';
import 'package:dnd/models/character.dart';
import 'package:dnd/services/achievements.dart';
import 'package:dnd/services/ai/gateway_client.dart';
import 'package:dnd/services/ai/model_catalog.dart';
import 'package:dnd/services/usage.dart';
import 'package:dnd/data/inventory_rules.dart';
import 'package:dnd/data/spellcasting.dart';
import 'package:dnd/services/audio/synth.dart';
import 'package:dnd/services/db/database.dart';
import 'package:dnd/services/game_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

Adventure _adv(Character hero) => Adventure(id: 't', title: 'Test', premise: '', hero: hero, engine: StoryEngine.offline);

void main() {
  test('oracle chance follows likelihood and chaos', () {
    expect(Oracle.chanceFor(Likelihood.even, 5), 50);
    expect(Oracle.chanceFor(Likelihood.likely, 9), 80);
    expect(Oracle.chanceFor(Likelihood.impossible, 1), 1);
    final o = Oracle(Rng(7).let((_) => null));
    var yes = 0;
    for (var i = 0; i < 2000; i++) {
      if (o.ask(Likelihood.veryLikely, 5).yes) yes++;
    }
    expect(yes / 2000, closeTo(0.70, 0.05));
  });

  test('subclasses, ASIs and feats apply to the character', () {
    final c = presets.firstWhere((p) => p.classId == 'fighter').create();
    for (var l = 2; l <= 4; l++) {
      c.xp = xpThresholds[l - 1];
      c.levelUp('fighter');
    }
    expect(c.needsSubclass('fighter'), isTrue);
    c.chooseSubclass('fighter', 'champion');
    expect(c.critRange, 19);
    final str = c.score(Ability.str);
    c.applyAsi(scores: {Ability.str: 2});
    expect(c.score(Ability.str), str + 2);
    final hp = c.maxHp;
    c.applyAsi(feat: 'tough');
    expect(c.maxHp, hp + 2 * c.level);
    expect(c.features.any((f) => f.name.startsWith('Improved Critical')), isTrue);
    final back = Character.fromJson(jsonDecode(jsonEncode(c.toJson())));
    expect(back.subclasses['fighter'], 'champion');
    expect(back.feats, contains('tough'));
    expect(subclassesFor('wizard'), isNotEmpty);
    expect(asiLevels.first, 4);
  });

  test('companions auto-progress when they level', () {
    final c = presets.firstWhere((p) => p.classId == 'cleric').create();
    c.autoProgress('cleric');
    expect(c.subclasses.containsKey('cleric'), isTrue);
  });

  test('attunement only activates attuned magic items', () {
    final c = presets.first.create();
    final ring = InventoryItem.of('ring_protection');
    c.inventory.add(ring);
    final ac = c.armorClass;
    expect(ring.active, isFalse);
    ring.attuned = true;
    expect(c.attunedCount, 1);
    expect(c.armorClass, ac + 1);
  });

  test('canon memory merges by name and survives JSON', () {
    final a = _adv(presets.first.create());
    a.remember('npc', 'Marta', 'Innkeeper.');
    a.remember('npc', 'marta', 'Owes the hero a favor.');
    expect(a.canon.length, 1);
    expect(a.canon.single.text, contains('favor'));
    a.canon.single.pinned = true;
    final back = Adventure.fromJson(jsonDecode(jsonEncode(a.toJson())));
    expect(back.canon.single.pinned, isTrue);
    expect(back.chaos, 5);
  });

  test('AI turns parse memory and companion approval', () {
    final t = DmTurn.parse(jsonEncode({
      'narration': 'Hi',
      'choices': ['Go'],
      'memory': [
        {'kind': 'place', 'name': 'Old Mill', 'text': 'Haunted.'},
      ],
      'approval': [
        {'name': 'Ser Kell', 'change': 30, 'reason': 'Mercy'},
      ],
    }));
    expect(t.memory.single['name'], 'Old Mill');
    expect(t.approval.single.$2, 15, reason: 'clamped');
  });

  test('scaled spell dice keep every term', () {
    final e = DiceExpression.parse('1d10+2d6');
    expect(e.terms.length, 2);
  });

  test('combat with monster abilities runs to completion', () {
    final ids = ['young_dragon', 'troll', 'ghoul', 'wolf', 'wraith', 'giant_spider', 'dark_acolyte', 'hell_hound'];
    for (final id in ids) {
      for (final p in presets.take(6)) {
        final hero = p.create();
        for (var l = 2; l <= 6; l++) {
          hero.xp = xpThresholds[l - 1];
          hero.levelUp(hero.classLevels.keys.first);
          hero.autoProgress(hero.classLevels.keys.first);
        }
        final a = _adv(hero);
        final engine = CombatEngine(a);
        final enemies = CombatEngine.buildEnemies([EnemySpec(name: id, monsterId: id, count: id == 'wolf' ? 3 : 1)], partyLevel: hero.level);
        engine.begin(enemies);
        var guard = 0;
        while (a.combat != null && guard++ < 300) {
          final st = engine.state;
          if (st.victory || st.defeat) break;
          engine.startOfTurn();
          final cur = st.current;
          if (cur.down) {
            engine.nextTurn();
            continue;
          }
          if (cur.isPlayer) {
            final foe = st.enemies.where((e) => !e.down).firstOrNull;
            if (foe == null) break;
            final spell = hero.knownSpellDefs.where((s) => s.kind == SpellKind.save && (s.level == 0 || hero.availableSlot(s.level) != null)).firstOrNull;
            if (spell != null && guard.isEven) {
              engine.castSpell(cur, spell, [foe]);
            } else if (guard % 7 == 0) {
              engine.moveTo(cur, (cur.x + 1).clamp(0, CombatEngine.gridW - 1), cur.y);
            } else {
              engine.attack(cur, foe);
            }
          } else {
            engine.autoTurn();
          }
          engine.nextTurn();
        }
        expect(guard, lessThan(300), reason: '$id vs ${p.name} never ended');
        engine.finish();
        expect(hero.concentration, isNull);
      }
    }
  });

  test('random tables all have entries', () {
    for (final t in randomTables) {
      expect(t.entries.length, greaterThanOrEqualTo(8), reason: t.id);
      expect(t.roll(), isNotEmpty);
    }
  });

  test('achievements unlock from stats', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final ach = Achievements(prefs);
    final unlocked = <String>[];
    ach.onUnlock = (a) => unlocked.add(a.id);
    ach.add(Stat.kills);
    expect(unlocked, contains('first_blood'));
    ach.max(Stat.maxLevel, 5);
    expect(ach.isUnlocked('level_5'), isTrue);
  });

  test('usage tracker prices calls from the catalog', () async {
    SharedPreferences.setMockInitialValues({
      'model_catalog.v1': jsonEncode([
        ModelInfo(id: 'test/model', name: 'Test', provider: 'test', type: 'language', inputPrice: 1, outputPrice: 4).toJson(),
      ]),
    });
    final prefs = await SharedPreferences.getInstance();
    final catalog = ModelCatalog(prefs);
    final usage = UsageTracker(prefs, catalog);
    final a = _adv(presets.first.create())..turns = 2;
    usage.current = a;
    GatewayClient.onUsage?.call(UsageEvent(model: 'test/model', inputTokens: 1000000, outputTokens: 500000, target: a.usage));
    if (catalog.byId('test/model') != null) {
      expect(usage.total.cost, closeTo(3.0, 1e-9));
      expect((a.usage['cost'] ?? 0).toDouble(), closeTo(3.0, 1e-9));
    }
    expect(usage.total.tokens, 1500000);
    expect(usage.insights(story: a.usage, turns: a.turns), isNotEmpty);
  });

  test('campaigns round-trip', () {
    final c = Campaign(id: 'c', name: 'Saga', heroId: 'h', chapters: ['a', 'b'], canon: [CanonEntry(id: 'x', kind: 'npc', name: 'Odile')]);
    final back = Campaign.fromJson(jsonDecode(jsonEncode(c.toJson())));
    expect(back.chapters, ['a', 'b']);
    expect(back.canon.single.name, 'Odile');
  });
  test('full casters reach 9th-level slots and legendary foes act', () {
    expect(spellSlotsFor(CasterType.full, 17).length, 9);
    expect(spellById('meteor_swarm')?.level, 9);
    final hero = presets.firstWhere((p) => p.classId == 'wizard').create();
    for (var l = 2; l <= 17; l++) {
      hero.xp = xpThresholds[l - 1];
      hero.levelUp('wizard');
    }
    expect(hero.availableSlot(9), isNotNull);
    final a = _adv(hero);
    final engine = CombatEngine(a);
    engine.begin(CombatEngine.buildEnemies([EnemySpec(name: 'Vampire', monsterId: 'vampire')], partyLevel: 10));
    final boss = engine.state.enemies.single;
    expect(engine.ability(boss, 'legendary'), isNotNull);
    // Legendary actions happen on other creatures' turns.
    engine.state.turn = engine.state.combatants.indexWhere((c) => !c.isEnemy);
    var acted = false;
    for (var i = 0; i < 20 && !acted; i++) {
      boss.conditions.removeWhere((c) => c.startsWith('LegAct'));
      acted = engine.legendaryActions().isNotEmpty;
    }
    expect(acted, isTrue);
    boss.hp = 50;
    engine.castSpell(engine.state.allies.first, spellById('power_word_kill')!, [boss]);
    expect(boss.down, isTrue);
  });

  test('pending notes reach the AI and survive saves', () {
    final a = _adv(presets.first.create())..pendingNotes.add('Bought a sword.');
    final back = Adventure.fromJson(jsonDecode(jsonEncode(a.toJson())));
    expect(back.pendingNotes.single, 'Bought a sword.');
  });

  test('SQLite store migrates old saves and persists adventures', () async {
    sqfliteFfiInit();
    final hero = presets.first.create();
    final adv = _adv(hero);
    SharedPreferences.setMockInitialValues({
      'characters.v1': jsonEncode([hero.toJson()]),
      'adventure.v1.${adv.id}': jsonEncode(adv.toJson()),
    });
    final prefs = await SharedPreferences.getInstance();
    final db = await AppDatabase.open(name: inMemoryDatabasePath, factory: databaseFactoryFfiNoIsolate);
    final store = await GameStore.open(prefs, db);
    expect(store.characters.single.name, hero.name);
    expect(store.adventures.single.id, adv.id);
    expect(prefs.getString('characters.v1'), isNull, reason: 'old copy removed after migration');
    final loaded = await store.loadAdventure(adv.id);
    expect(loaded?.title, adv.title);
    await db.putImage('k', Uint8List.fromList([1, 2, 3]));
    expect(await db.image('k'), [1, 2, 3]);
  });

  test('battle grid: melee walks in, cover and movement budget', () {
    final hero = presets.firstWhere((p) => p.classId == 'fighter').create();
    final a = _adv(hero);
    final engine = CombatEngine(a);
    engine.begin(CombatEngine.buildEnemies([EnemySpec(name: 'Goblin', monsterId: 'goblin', count: 2)], partyLevel: 1));
    final me = engine.state.allies.single;
    final foe = engine.state.enemies.first;
    expect(engine.adjacent(me, foe), isFalse);
    final left = engine.movesLeft(me);
    expect(left, me.x >= 0 ? greaterThan(0) : 0);
    engine.attack(me, foe, natural: 15);
    expect(engine.adjacent(me, foe), isTrue, reason: 'fighter stepped in to attack');
    expect(engine.movesLeft(me), lessThan(left));
    expect(engine.reachable(me).every((p) => engine.occupant(p.x, p.y) == null), isTrue);
  });

  test('saving throws: choices use save modifiers and conditions expire', () {
    final spec = CheckSpec.fromJson({'ability': 'DEX', 'save': true, 'dc': 14});
    expect(spec.save, isTrue);
    expect(spec.label, 'DEX save');
    final c = presets.first.create();
    c.conditions.add('Poisoned');
    c.conditionUntil['Poisoned'] = 3;
    final back = Character.fromJson(jsonDecode(jsonEncode(c.toJson())));
    expect(back.conditionUntil['Poisoned'], 3);
  });

  test('spell limits follow class tables', () {
    final wiz = presets.firstWhere((p) => p.classId == 'wizard').create();
    expect(wiz.prepares, isTrue);
    expect(wiz.spellbook.length, greaterThanOrEqualTo(2));
    expect(wiz.leveledMax, greaterThanOrEqualTo(1));
    final sorc = presets.firstWhere((p) => p.classId == 'sorcerer').create();
    expect(sorc.prepares, isFalse);
    expect(sorc.cantripMax, 4);
    expect(sorc.leveledMax, 2);
  });

  test('inventory weight, ammo and multiclass prerequisites', () {
    final ranger = presets.firstWhere((p) => p.classId == 'ranger').create();
    expect(ranger.carriedWeight, greaterThan(0));
    expect(ranger.encumbrance, 0);
    final bow = ranger.inventory.where((i) => i.def?.ammo != null).firstOrNull;
    if (bow != null) expect(ranger.ammoFor(bow.def!), isNotNull);
    final weak = presets.firstWhere((p) => p.classId == 'wizard').create();
    expect(meetsMulticlass('paladin', weak.score), isFalse);
  });

  test('ambience loops render', () {
    for (final k in ambienceNames) {
      final wav = renderAmbience(k);
      expect(wav.length, greaterThan(100000), reason: k);
    }
  });

}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
