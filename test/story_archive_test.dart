import 'dart:convert';
import 'dart:typed_data';

import 'package:dnd/data/presets.dart';
import 'package:dnd/game/tale_controller.dart';
import 'package:dnd/game/combat.dart';
import 'package:dnd/models/adventure.dart';
import 'package:dnd/models/tale.dart';
import 'package:dnd/models/world.dart';
import 'package:dnd/services/story_archive.dart';
import 'package:dnd/services/settings.dart';
import 'package:dnd/services/tale_store.dart';
import 'package:dnd/services/audio/audio_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Tale savedTale() => Tale.create(title: 'In progress', genre: 'scifi', engine: TaleEngine.preset, presetId: 'silent_ship')
    ..node = 'cryo'
    ..choices = [
      const TaleChoice('Trace the blue line by hand', data: {'i': 0}),
    ]
    ..flags = {'scanned'}
    ..inventory = ['Cutting torch']
    ..health = 75
    ..turns = 9
    ..usage = {'in': 234, 'cost': 0.12}
    ..notes.add(StoryNote(title: 'Remember', body: 'Do not trust the intercom.'));

  test('text adventure restores playable state as an independent copy', () {
    final original = savedTale();
    final archive = decodeStoryArchive(jsonEncode(storyArchive(original)));
    final restored = restoreStoryArchive(archive) as Tale;
    expect(restored.id, isNot(original.id));
    expect(restored.node, original.node);
    expect(restored.choices.single.data['i'], 0);
    expect(restored.flags, original.flags);
    expect(restored.inventory, original.inventory);
    expect(restored.health, 75);
    expect(restored.turns, 9);
    expect(restored.notes.single.body, original.notes.single.body);
    expect(restored.usage, original.usage);
    expect(original.id, archive['state']['id']);
  });

  test('D&D archive preserves complete log and hero without campaign collision', () {
    final original = Adventure(id: 'original', title: 'Keep going', premise: 'Explore', hero: presets.first.create(), engine: StoryEngine.offline)
      ..campaignId = 'local-campaign'
      ..offline = {'seed': 42, 'stage': 3}
      ..log.addAll(List.generate(405, (i) => LogEntry(kind: LogKind.narration, text: 'Scene $i')));
    original.combat = CombatState(
      combatants: [
        Combatant(
          id: 'player',
          name: original.hero.name,
          hp: 8,
          maxHp: 12,
          ac: 14,
          attackBonus: 3,
          damage: '1d6',
          isPlayer: true,
          characterId: original.hero.id,
        ),
      ],
    );
    final restored = restoreStoryArchive(decodeStoryArchive(jsonEncode(storyArchive(original)))) as Adventure;
    expect(restored.log.length, 405);
    expect(restored.hero.name, original.hero.name);
    expect(restored.hero.id, isNot(original.hero.id));
    expect(restored.id, isNot(original.id));
    expect(restored.campaignId, isNull);
    expect(restored.offline, original.offline);
    expect(CombatEngine(restored).characterFor(restored.combat!.combatants.single), same(restored.hero));
  });

  test('an imported offline story continues from its exact saved choice', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsController(await SharedPreferences.getInstance())
      ..musicEnabled = false
      ..ambienceEnabled = false
      ..sfxEnabled = false;
    final audio = AudioService(settings);
    final store = TaleStore.memory();
    final restored = restoreStoryArchive(decodeStoryArchive(jsonEncode(storyArchive(savedTale())))) as Tale;
    final controller = TaleController(tale: restored, settings: settings, store: store, audio: audio);
    await controller.choose(restored.choices.single);
    expect(restored.node, 'cryo_rescue');
    expect(restored.turns, 10);
    expect(restored.health, 65);
    expect(restored.inventory, contains('Bypass key'));
    expect(restored.flags, contains('iona_saved'));
    await controller.flush();
    expect((await store.load(restored.id))!.node, 'cryo_rescue');
    controller.dispose();
    audio.dispose();
    store.dispose();
    settings.dispose();
  });

  test('portable assets deduplicate and remap gallery, scenes and cost keys', () async {
    final tale = savedTale()
      ..sceneImagePath = '/old/scene.png'
      ..sceneImages['Bridge'] = '/old/scene.png'
      ..gallery.add(MediaItem(path: '/old/scene.png'))
      ..mediaCosts['/old/scene.png'] = 0.04;
    var reads = 0;
    final archive = await portableStoryArchive(tale, (_) async {
      reads++;
      return Uint8List.fromList([1, 2, 3]);
    });
    expect(reads, 1);
    final decoded = decodeStoryArchive(jsonEncode(archive));
    final assets = archiveAssets(decoded);
    expect(assets['asset:0']!.$1, 'png');
    expect(assets['asset:0']!.$2, [1, 2, 3]);
    final restored = restoreStoryArchive(decoded, media: {'asset:0': '/new/scene.png'}) as Tale;
    expect(restored.sceneImagePath, '/new/scene.png');
    expect(restored.sceneImages['Bridge'], '/new/scene.png');
    expect(restored.gallery.single.path, '/new/scene.png');
    expect(restored.mediaCosts['/new/scene.png'], 0.04);
    expect(tale.sceneImagePath, '/old/scene.png');
  });

  test('malformed, incompatible and unavailable stories are rejected', () {
    expect(() => decodeStoryArchive('{}'), throwsFormatException);
    final archive = storyArchive(savedTale());
    archive['version'] = 99;
    expect(() => decodeStoryArchive(jsonEncode(archive)), throwsFormatException);
    archive['version'] = 1;
    archive['state']['node'] = 'missing';
    expect(() => decodeStoryArchive(jsonEncode(archive)), throwsFormatException);
    archive['state']['node'] = 'cryo';
    archive['state']['choices'][0]['d']['i'] = 99;
    expect(() => decodeStoryArchive(jsonEncode(archive)), throwsFormatException);
    expect(
      () => archiveAssets({
        'assets': {
          'asset:0': {'ext': '../exe', 'bytes': 'AQID'},
        },
      }),
      throwsFormatException,
    );
    expect(
      () => archiveAssets({
        'assets': {
          'asset:0': {'ext': 'png', 'bytes': '???'},
        },
      }),
      throwsFormatException,
    );
  });
}
