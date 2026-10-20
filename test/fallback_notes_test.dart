import 'dart:convert';

import 'package:dnd/art/render_png.dart';
import 'package:dnd/data/presets.dart';
import 'package:dnd/models/adventure.dart';
import 'package:dnd/models/world.dart';
import 'package:dnd/services/ai/gateway_client.dart';
import 'package:dnd/services/ai/model_catalog.dart';
import 'package:dnd/services/export.dart';
import 'package:dnd/services/image_service.dart';
import 'package:dnd/services/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a failure a retry cannot fix pauses that kind once, then falls back quietly', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsController(prefs)..apiKey = 'k';
    final images = ImageService(settings, ModelCatalog(prefs));
    expect(ImageService.isHardFailure(GatewayException('Video generation requires a minimum balance of \$10.', status: 402)), isTrue);
    expect(ImageService.isHardFailure(GatewayException('Timeout', status: 504)), isFalse);
    expect(images.isSuspended('video'), isFalse);
    // No OpenRouter key for this image model: the first call reports, later ones stay quiet.
    settings.imageModel = 'or:google/gemini-3.1-flash-lite-image';
    expect(await images.generate('scene_a_1', 'x'), isNull);
    expect(images.errors, hasLength(1));
    expect(images.isSuspended('image'), isTrue);
    images.errors.clear(); // the player dismissed it
    expect(await images.generate('scene_a_2', 'y'), isNull);
    expect(images.errors, isEmpty, reason: 'A dismissed failure does not keep coming back.');
    settings.imageModel = 'google/gemini-3.1-flash-image';
    expect(images.isSuspended('image'), isFalse, reason: 'Changing the model in Settings resumes.');
    images.resume();
  });

  test('notes are saved with the story and exported', () {
    final a = Adventure(id: 'a', title: 'Notes', premise: '', hero: presets.first.create(), engine: StoryEngine.offline);
    a.notes.addAll([StoryNote(title: 'Suspects', body: 'Bram lied about the bell.', pinned: true), StoryNote()]);
    final back = Adventure.fromJson(jsonDecode(jsonEncode(a.toJson())));
    expect(back.notes, hasLength(1), reason: 'Empty notes are not kept.');
    expect(back.notes.single.heading, 'Suspects');
    expect(back.notes.single.pinned, isTrue);
    expect(StoryNote(body: 'First line\nsecond').heading, 'First line');
    expect(storyMarkdown(exportDocFromAdventure(back)), contains('### Suspects\nBram lied about the bell.'));
  });

  testWidgets('drawn portraits, scenes and maps render to PNG for saving', (tester) async {
    final hero = presets.first.create();
    final map = MapState(kind: MapKind.overworld, seed: 3, name: 'Vale', locations: [MapLocation(name: 'Inn', visited: true), MapLocation(name: 'Tower')]);
    final pngs = await tester.runAsync(() async => [
          await portraitPng(hero.portrait, hero.raceId, size: 256),
          await scenePng(SceneInfo(title: 'Inn', location: 'tavern'), width: 320, height: 180),
          await mapPng(map, width: 600),
        ]);
    for (final p in pngs!) {
      expect(p, isNotNull);
      expect(p!.sublist(1, 4), utf8.encode('PNG'));
    }
  });
}
