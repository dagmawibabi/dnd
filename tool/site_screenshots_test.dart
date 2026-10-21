import 'dart:io';
import 'dart:typed_data';

import 'package:dnd/data/presets.dart';
import 'package:dnd/data/modules.dart';
import 'package:dnd/game/module_engine.dart';
import 'package:dnd/game/adventure_controller.dart';
import 'package:dnd/game/campaign_world.dart';
import 'package:dnd/models/adventure.dart';
import 'package:dnd/models/world.dart';
import 'package:dnd/services/studio.dart';
import 'package:dnd/services/codex_art.dart';
import 'package:dnd/ui/screens/adventure/adventure_screen.dart';
import 'package:dnd/ui/screens/adventure/map_screen.dart';
import 'package:dnd/ui/screens/adventure/camp_screen.dart';
import 'package:dnd/ui/screens/character/character_sheet.dart';
import 'package:dnd/ui/screens/compendium_screen.dart';
import 'package:dnd/ui/screens/dice_tray_screen.dart';
import 'package:dnd/ui/screens/studio/art_studio.dart';
import 'package:dnd/ui/screens/studio/music_studio.dart';
import 'package:dnd/ui/screens/story/world_memory_screen.dart';

import 'dart:ui' as ui;

import 'package:dnd/services/achievements.dart';
import 'package:dnd/services/ai/model_catalog.dart';
import 'package:dnd/services/audio/audio_service.dart';
import 'package:dnd/services/game_store.dart';
import 'package:dnd/services/image_service.dart';
import 'package:dnd/services/narrator.dart';
import 'package:dnd/services/settings.dart';
import 'package:dnd/services/tale_store.dart';
import 'package:dnd/services/usage.dart';
import 'package:dnd/theme/app_theme.dart';
import 'package:dnd/ui/screens/home_screen.dart';
import 'package:dnd/ui/screens/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final boundary = GlobalKey();
  late SettingsController settings;
  late ModelCatalog catalog;
  late GameStore games;
  late TaleStore tales;
  late AudioService audio;
  late ImageService images;
  late Narrator narrator;
  late UsageTracker usage;
  late Achievements achievements;
  late StudioStore studio;
  late CodexArt codex;

  setUp(() async {
    // Widget tests do not load system fonts. Use the app's desktop serif
    // fallback explicitly; other hosts can provide their own serif font path.
    const serifPath = String.fromEnvironment('SITE_SERIF_FONT',
        defaultValue: 'C:/Windows/Fonts/georgia.ttf');
    await (FontLoader('serif')
          ..addFont(File(serifPath).readAsBytes().then(ByteData.sublistView)))
        .load();
    for (final font in {
      'Inter': 'assets/fonts/Inter.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
      'JetBrainsMono': 'assets/fonts/JetBrainsMono.ttf',

      'Roboto': 'assets/fonts/Inter.ttf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settings = SettingsController(prefs)
      ..musicEnabled = false
      ..ambienceEnabled = false
      ..sfxEnabled = false
      ..ttsEnabled = false
      ..typewriter = false
      ..showUsage = true;
    settings.readingFont = 'sans';
    T.readingFont = 'sans';
    catalog = ModelCatalog(prefs);
    games = GameStore.memory();
    tales = TaleStore.memory();
    audio = AudioService(settings);
    images = ImageService(settings, catalog);
    narrator = Narrator(settings, catalog: catalog);
    usage = UsageTracker(prefs, catalog, settings: settings);
    achievements = Achievements(prefs);
    studio = StudioStore.memory();
    audio.studio = studio;
    codex = CodexArt(prefs);
  });
  tearDown(() {
    narrator.dispose();
    audio.dispose();
    images.dispose();
    usage.dispose();
    achievements.dispose();
    tales.dispose();
    games.dispose();
    catalog.dispose();
    settings.dispose();
  });

  Widget app(Widget screen) => MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: settings),
      ChangeNotifierProvider.value(value: studio),
      ChangeNotifierProvider.value(value: codex),
      ChangeNotifierProvider.value(value: catalog),
      ChangeNotifierProvider.value(value: games),
      ChangeNotifierProvider.value(value: tales),
      ChangeNotifierProvider.value(value: images),
      ChangeNotifierProvider.value(value: narrator),
      ChangeNotifierProvider.value(value: usage),
      ChangeNotifierProvider.value(value: achievements),
      Provider.value(value: audio),
    ],
    child: RepaintBoundary(
      key: boundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: screen,
      ),
    ),
  );

  testWidgets('capture real app screens for the site', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final hero = presets[1].create();
    await games.saveCharacter(hero);
    final mod = adventureModules[1];
    final adventure = Adventure(
      id: 'site-demo',
      title: mod.title,
      premise: mod.tagline,
      hero: hero,
      engine: StoryEngine.module,
      setting: mod.setting,
      tone: mod.tone,
      coverSeed: 42,
      scene: SceneInfo(
        title: 'The Beginning',
        location: mod.coverLoc,
        time: mod.coverTime,
        mood: 'mystery',
        seed: 42,
      ),
      offline: ModuleEngine.createState(mod.id),
    );
    final companion = presets.last.create()..isCompanion = true;
    adventure.companions.add(companion);
    adventure.map = MapState(
      kind: MapKind.overworld,
      seed: 42,
      name: 'The Greenmarch',
      current: 1,
      locations: [
        MapLocation(name: 'Redhollow', visited: true),
        MapLocation(name: 'Old Keep', visited: true),
        MapLocation(name: 'Thorn Pass'),
        MapLocation(name: 'Silverwood'),
        MapLocation(name: 'The Crossing'),
      ],
    );
    rememberWorld(
      adventure,
      'place',
      'Redhollow',
      'Safe again',
      'You drove out the raiders.',
    );
    rememberWorld(
      adventure,
      'place',
      'Old Keep',
      'Held by bandits',
      'Their banner flies over the walls.',
    );
    rememberWorld(
      adventure,
      'faction',
      'The village watch',
      'Allied',
      'You stood with them at the bridge.',
    );
    await games.saveAdventure(adventure);
    final ctl = AdventureController(
      adventure: adventure,
      settings: settings,
      store: games,
      audio: audio,
      images: images,
    );
    Future<void> capture(String name, Widget screen) async {
      await tester.pumpWidget(app(screen));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull, reason: name);
      await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final dir = Directory('site/static/screens')
          ..createSync(recursive: true);
        await File('${dir.path}/$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    }

    await capture('home', const HomeScreen());
    await capture('hero', CharacterSheetScreen(character: hero));
    await capture('adventure', AdventureScreen(adventure: adventure));
    await capture('map', MapScreen(ctl: ctl));
    await capture('camp', CampScreen(controller: ctl));
    await capture(
      'memory',
      WorldMemoryScreen(world: () => adventure.chronicle),
    );
    await capture('codex', const CompendiumScreen());
    await capture('dice', const DiceTrayScreen());
    await capture('art', const ArtStudioScreen());
    await capture('music', const MusicStudioScreen());
    settings.homeMode = 'tales';
    await capture('tales', const HomeScreen());
    await capture('settings', const SettingsScreen());
    await ctl.flush();
    ctl.dispose();
  });
}
