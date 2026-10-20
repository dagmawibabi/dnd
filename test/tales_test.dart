import 'dart:convert';
import 'dart:math';

import 'package:dnd/data/tale_genres.dart';
import 'package:dnd/data/tales/tales.dart';
import 'package:dnd/game/tale_controller.dart';
import 'package:dnd/models/adventure.dart';
import 'package:dnd/models/tale.dart';
import 'package:dnd/services/ai/tale_narrator.dart';
import 'package:dnd/services/audio/audio_service.dart';
import 'package:dnd/services/settings.dart';
import 'package:dnd/services/tale_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('first launch publishes and saves the opening scene without a layout switch', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsController(await SharedPreferences.getInstance())
      ..musicEnabled = false
      ..ambienceEnabled = false
      ..sfxEnabled = false;
    final audio = AudioService(settings);
    final store = TaleStore.memory();
    final preset = talePresets.first;
    final tale = Tale.create(title: preset.title, genre: preset.genre, engine: TaleEngine.preset, presetId: preset.id);
    final controller = TaleController(tale: tale, settings: settings, store: store, audio: audio);
    addTearDown(() {
      controller.dispose();
      audio.dispose();
      store.dispose();
      settings.dispose();
    });

    var updates = 0;
    controller.addListener(() {
      updates++;
      expect(tale.log.where((e) => e.kind == LogKind.narration).single.text, preset.nodes[preset.start]!.text);
      expect(tale.choices, isNotEmpty);
    });

    await controller.start();
    expect(updates, 1, reason: 'The screen must rebuild after the opening scene is ready.');
    await tester.pump(const Duration(milliseconds: 600));
    expect(await store.load(tale.id), isNotNull);
    expect(store.tales, hasLength(1));

    final logLength = tale.log.length;
    await controller.start();
    expect(tale.log, hasLength(logLength), reason: 'Resuming must not duplicate the opening scene.');
    expect(updates, 1);
  });

  test('every text adventure link points at a real scene', () {
    for (final p in talePresets) {
      expect(p.nodes.containsKey(p.start), isTrue, reason: '${p.id} start');
      expect(taleGenres.any((g) => g.id == p.genre), isTrue, reason: '${p.id} genre');
      for (final e in p.nodes.entries) {
        final n = e.value;
        expect(n.end != null || n.options.isNotEmpty, isTrue, reason: '${p.id}/${e.key} is a dead end');
        for (final o in n.options) {
          expect(p.nodes.containsKey(o.go), isTrue, reason: '${p.id}/${e.key} -> ${o.go}');
          if (o.fail != null) expect(p.nodes.containsKey(o.fail), isTrue, reason: '${p.id}/${e.key} fail -> ${o.fail}');
        }
      }
      expect(p.endings, greaterThanOrEqualTo(3), reason: '${p.id} endings');
    }
  });

  test('random playthroughs reach several endings', () {
    final rng = Random(7);
    for (final p in talePresets) {
      final reached = <String>{};
      for (var run = 0; run < 60; run++) {
        final flags = <String>{};
        final inv = <String>{};
        var node = p.start;
        var hp = 100;
        var steps = 0;
        bool gate(String g) => g.startsWith('item:') ? inv.contains(g.substring(5)) : flags.contains(g);
        while (steps++ < 60) {
          final n = p.nodes[node]!;
          if (n.gives != null) inv.add(n.gives!);
          if (n.sets != null) flags.add(n.sets!);
          hp -= n.damage;
          if (n.end != null || hp <= 0) break;
          final opts = n.options.where((o) => (o.requires == null || gate(o.requires!)) && (o.unless == null || !gate(o.unless!))).toList();
          expect(opts, isNotEmpty, reason: '${p.id} stuck at $node');
          final o = opts[rng.nextInt(opts.length)];
          if (o.gives != null) inv.add(o.gives!);
          if (o.takes != null) inv.remove(o.takes!);
          if (o.sets != null) flags.add(o.sets!);
          hp -= o.damage;
          node = (o.chance != null && rng.nextDouble() > o.chance! && o.fail != null) ? o.fail! : o.go;
        }
        expect(steps, lessThan(60), reason: '${p.id} looped');
        reached.add(node);
      }
      expect(reached.length, greaterThanOrEqualTo(2), reason: '${p.id} reached only $reached');
    }
  });

  test('AI tale turns parse', () {
    final t = TaleTurn.parse(jsonEncode({
      'title': 'Airlock',
      'narration': 'Cold.',
      'choices': ['Open it', {'text': 'Wait'}],
      'inventory_add': ['Keycard'],
      'health_change': -250,
      'ending': 'GOOD',
    }));
    expect(t.choices, ['Open it', 'Wait']);
    expect(t.add, ['Keycard']);
    expect(t.health, -100);
    expect(t.ending, 'good');
  });

  test('tales round-trip and store in memory', () async {
    final t = Tale.create(title: 'X', genre: 'noir', engine: TaleEngine.ai)
      ..inventory.add('Gun')
      ..terminal = true;
    final back = Tale.fromJson(jsonDecode(jsonEncode(t.toJson())));
    expect(back.inventory, ['Gun']);
    expect(back.terminal, isTrue, reason: 'layout choice is remembered per story');
    expect(back.engine, TaleEngine.ai);
    final store = TaleStore.memory();
    await store.save(t);
    expect(store.tales.single.title, 'X');
    expect(await store.load(t.id), isNotNull);
  });
}
