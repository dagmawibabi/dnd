import 'package:dnd/data/presets.dart';
import 'package:dnd/game/adventure_controller.dart';
import 'package:dnd/game/campaign_world.dart';
import 'package:dnd/models/adventure.dart';
import 'package:dnd/models/chronicle.dart';
import 'package:dnd/models/world.dart';
import 'package:dnd/services/ai/model_catalog.dart';
import 'package:dnd/services/audio/audio_service.dart';
import 'package:dnd/services/game_store.dart';
import 'package:dnd/services/image_service.dart';
import 'package:dnd/services/settings.dart';
import 'package:dnd/services/studio.dart';
import 'package:dnd/services/usage.dart';
import 'package:dnd/theme/app_theme.dart';
import 'package:dnd/ui/screens/adventure/map_screen.dart';
import 'package:dnd/ui/screens/story/chapter_recap_screen.dart';
import 'package:dnd/ui/screens/story/story_tools.dart';
import 'package:dnd/ui/screens/studio/art_studio.dart';
import 'package:dnd/ui/screens/studio/music_studio.dart';
import 'package:dnd/ui/screens/studio/sfx_studio.dart';
import 'package:dnd/ui/widgets/voice_input_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SettingsController settings;
  late StudioStore studio;
  late AudioService audio;
  late ImageService images;
  late GameStore games;
  late AdventureController ctl;
  late ModelCatalog catalog;
  late UsageTracker usage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settings = SettingsController(prefs)
      ..musicEnabled = false
      ..ambienceEnabled = false
      ..sfxEnabled = false
      ..haptics = false
      ..typewriter = false;
    studio = StudioStore.memory();
    audio = AudioService(settings)..studio = studio;
    catalog = ModelCatalog(prefs);
    usage = UsageTracker(prefs, catalog, settings: settings);
    images = ImageService(settings, catalog);
    games = GameStore.memory();
    final a = Adventure(
      id: 'ch1',
      title: 'The Saved Village',
      premise: '',
      hero: presets.first.create(),
      engine: StoryEngine.offline,
      turns: 6,
    );
    final c = presets.last.create()
      ..name = 'Mira'
      ..isCompanion = true;
    a.companions.add(c);
    a.map = MapState(
      kind: MapKind.overworld,
      seed: 5,
      name: 'The Vale',
      current: 1,
      locations: [
        MapLocation(
          name: 'Redhollow',
          visited: true,
          note: 'The miller owes us',
        ),
        MapLocation(name: 'Old Keep', note: 'Scouts watch the gate'),
        MapLocation(name: 'Thorn Pass'),
      ],
    );
    rememberWorld(
      a,
      'place',
      'Redhollow',
      'Safe again',
      'You drove out the raiders.',
    );
    rememberWorld(
      a,
      'place',
      'Old Keep',
      'Held by bandits',
      'Their banner flies over the walls.',
    );
    a.chronicle.arcs[c.id] = CompanionArc(
      companionId: c.id,
      name: c.name,
      title: 'The Broken Banner',
      description: 'Recover the standard.',
      stage: 'pursuing',
      progress: 1,
    );
    a
        .chatWith(c.id)
        .add(
          ChatLine(
            fromPlayer: false,
            text: 'Walk with me a moment?',
            opener: 'How they feel about you',
          ),
        );
    a.unreadChats.add(c.id);
    ctl = AdventureController(
      adventure: a,
      settings: settings,
      store: games,
      audio: audio,
      images: images,
    );
  });

  tearDown(() async {
    await ctl.flush();
    ctl.dispose();
    audio.dispose();
    games.dispose();
  });

  Widget app(Widget home) => MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: settings),
      ChangeNotifierProvider.value(value: studio),
      ChangeNotifierProvider.value(value: images),
      ChangeNotifierProvider.value(value: games),
      ChangeNotifierProvider.value(value: catalog),
      ChangeNotifierProvider.value(value: usage),
      Provider.value(value: audio),
    ],
    child: MaterialApp(theme: buildAppTheme(), home: home),
  );

  Future<void> phone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('studios open on a phone and every tab lays out', (tester) async {
    await phone(tester);
    for (final (screen, tabs) in [
      (
        const ArtStudioScreen(),
        ['Portraits', 'Creatures', 'Maps', 'My images', 'Collection', 'Scenes'],
      ),
      (
        const MusicStudioScreen(),
        ['Compose', 'My tracks', 'Soundscapes', 'Themes'],
      ),
      (const SfxStudioScreen(), ['Designer', 'My sounds', 'Game sounds']),
    ]) {
      await tester.pumpWidget(app(screen));
      await tester.pump(const Duration(milliseconds: 300));
      for (final t in tabs) {
        await tester.ensureVisible(find.text(t).first);
        await tester.pump();
        await tester.tap(find.text(t).first);
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          tester.takeException(),
          isNull,
          reason: '${screen.runtimeType} $t',
        );
      }
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('what changed, the map and the approach banner render', (
    tester,
  ) async {
    await phone(tester);
    await tester.pumpWidget(
      app(ChapterRecapScreen(host: ctl, ended: true, onContinue: () {})),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Redhollow'), findsWidgets);
    await tester.scrollUntilVisible(find.textContaining('Broken Banner'), 300);
    expect(find.textContaining('Broken Banner'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(app(MapScreen(ctl: ctl)));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Places'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Thorn Pass'), findsWidgets);
    expect(tester.takeException(), isNull);
    Navigator.of(tester.element(find.text('Thorn Pass').first)).pop();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byTooltip('Current location'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Scouts watch the gate'), findsOneWidget);
    expect(find.text('THE WORLD REMEMBERS'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      app(
        Scaffold(
          body: Column(
            children: [
              const Spacer(),
              ApproachBanner(host: ctl),
              VoiceInputButton(controller: TextEditingController()),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('MIRA WANTS TO TALK'), findsOneWidget);
    expect(find.byTooltip('Speak'), findsOneWidget);
    await tester.tap(find.byTooltip('Later'));
    await tester.pump();
    expect(ctl.adventure.unreadChats, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('AI result actions wrap on a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(280, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    settings.costPerMessage = true;
    final note = AiNote(
      kind: 'recap',
      title: 'Previously on…',
      text: 'A short recap.',
      tokens: 120000,
      cost: 12.34,
    );
    await tester.pumpWidget(
      app(
        Scaffold(
          body: AiNoteActions(host: ctl, note: note),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
