import 'dart:convert';

import 'package:dnd/data/presets.dart';
import 'package:dnd/game/tale_controller.dart';
import 'package:dnd/models/adventure.dart';
import 'package:dnd/models/tale.dart';
import 'package:dnd/services/audio/audio_service.dart';
import 'package:dnd/services/settings.dart';
import 'package:dnd/services/tale_store.dart';
import 'package:dnd/ui/screens/story/story_extras.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('play time is saved with stories and summaries', () {
    final a = Adventure(id: 'a', title: 'T', premise: '', hero: presets.first.create(), engine: StoryEngine.offline)..playSeconds = 754;
    expect(Adventure.fromJson(jsonDecode(jsonEncode(a.toJson()))).playSeconds, 754);
    final t = Tale.create(title: 'X', genre: 'noir', engine: TaleEngine.ai)..playSeconds = 61;
    expect(TaleSummary(t.summary()).playSeconds, 61);
    expect(fmtDuration(45), '45s');
    expect(fmtDuration(754), '12m');
    expect(fmtDuration(3 * 3600 + 120), '3h 2m');
  });

  test('restoring a text adventure snapshot keeps spend, media and notes', () {
    final t = Tale.create(title: 'X', genre: 'noir', engine: TaleEngine.ai)
      ..health = 80
      ..inventory.add('Key');
    final snap = Tale.fromJson(jsonDecode(jsonEncode(t.toJson())));
    t
      ..health = 40
      ..inventory.add('Gun')
      ..log.add(LogEntry(kind: LogKind.narration, text: 'Bang.'))
      ..usage['cost'] = 0.02;
    t.restoreFrom(snap);
    expect(t.health, 80);
    expect(t.inventory, ['Key']);
    expect(t.log, isEmpty);
    expect(t.usage['cost'], 0.02, reason: 'Spend is never rewound.');
  });

  testWidgets('stats describe a story in play', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsController(await SharedPreferences.getInstance())
      ..musicEnabled = false
      ..ambienceEnabled = false
      ..sfxEnabled = false;
    final audio = AudioService(settings);
    final store = TaleStore.memory();
    final t = Tale.create(title: 'X', genre: 'noir', engine: TaleEngine.preset, presetId: 'rain_ledger')
      ..log.addAll([
        LogEntry(kind: LogKind.player, text: 'Open the door'),
        LogEntry(kind: LogKind.narration, text: 'Rain falls on the city tonight.'),
      ])
      ..playSeconds = 300;
    final ctl = TaleController(tale: t, settings: settings, store: store, audio: audio);
    addTearDown(() {
      ctl.dispose();
      audio.dispose();
      store.dispose();
    });
    final stats = {for (final (_, label, value) in storyStats(ctl)) label: value};
    expect(stats['Time played'], '5m');
    expect(stats['Actions'], '1');
    expect(stats['Words read'], '6');
    expect(ctl.canRegenerate, isFalse, reason: 'Handcrafted stories have nothing to regenerate.');
  });
}
