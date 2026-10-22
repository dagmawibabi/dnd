import 'dart:io';
import 'dart:ui' as ui;

import 'package:dnd/game/money.dart';
import 'package:dnd/game/tale_controller.dart';
import 'package:dnd/models/character.dart';
import 'package:dnd/models/companion.dart';
import 'package:dnd/models/tale.dart';
import 'package:dnd/models/world.dart';
import 'package:dnd/services/companion_life.dart';
import 'package:dnd/services/companion_store.dart';
import 'package:dnd/ui/screens/companions/companion_chat.dart';
import 'package:dnd/ui/screens/companions/companion_editor.dart';
import 'package:dnd/ui/screens/companions/companion_profile.dart';
import 'package:dnd/ui/screens/companions/companions_screen.dart';
import 'package:dnd/ui/screens/story/finance_screen.dart';
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
import 'package:dnd/theme/ui.dart' show ListRow;
import 'package:dnd/ui/screens/adventure/adventure_extras.dart';
import 'package:dnd/ui/screens/home_screen.dart';
import 'package:dnd/ui/screens/tales/tale_screen.dart';
import 'package:dnd/ui/screens/tales/tale_terminal_screen.dart';
import 'package:dnd/ui/screens/onboarding_screen.dart';
import 'package:dnd/ui/screens/settings/settings_screen.dart';
import 'package:dnd/ui/widgets/ai_gate.dart';
import 'package:dnd/services/ai/gateway_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';
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

  setUp(() async {
    for (final font in {
      'Inter': 'assets/fonts/Inter.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
      'JetBrainsMono': 'assets/fonts/JetBrainsMono.ttf',
      'serif': 'assets/fonts/Inter.ttf',
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
    catalog = ModelCatalog(prefs);
    games = GameStore.memory();
    tales = TaleStore.memory();
    audio = AudioService(settings);
    images = ImageService(settings, catalog);
    narrator = Narrator(settings, catalog: catalog);
    usage = UsageTracker(prefs, catalog, settings: settings);
    achievements = Achievements(prefs);
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
      ChangeNotifierProvider.value(value: catalog),
      ChangeNotifierProvider.value(value: games),
      ChangeNotifierProvider.value(value: tales),
      ChangeNotifierProvider.value(value: images),
      ChangeNotifierProvider.value(value: narrator),
      ChangeNotifierProvider.value(value: usage),
      ChangeNotifierProvider.value(value: achievements),
      Provider.value(value: audio),
      ChangeNotifierProvider.value(value: CompanionStore.instance),
      Provider.value(value: CompanionLife(settings: settings, store: CompanionStore.instance, images: images, games: games, tales: tales)),
    ],
    child: RepaintBoundary(
      key: boundary,
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildAppTheme(), home: screen),
    ),
  );

  Future<void> preview(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('UI_PREVIEWS')) return;
    await tester.runAsync(() async {
      final render = boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await render.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory('build/ui-previews')..createSync(recursive: true);
      await File('${dir.path}/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets('LM Studio sheet fits a phone, warns about small context and saves story and character models', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    GatewayClient.lmTestClient = MockClient((r) async => http.Response(
        jsonEncode({
          'data': [
            {'id': 'qwen3.5-0.8b', 'type': 'vlm', 'state': 'loaded', 'loaded_context_length': 8192, 'max_context_length': 262144},
            {'id': 'qwen3.5-4b', 'type': 'vlm', 'state': 'not-loaded', 'max_context_length': 262144},
            {'id': 'text-embedding-nomic-embed-text-v1.5', 'type': 'embeddings', 'state': 'not-loaded'},
          ],
        }),
        200));
    addTearDown(() => GatewayClient.lmTestClient = null);
    await tester.pumpWidget(app(const SettingsScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AI providers'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('LM Studio (local)'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pump();
    await tester.enterText(find.byType(TextField), '10.116.127.179:1234');
    await tester.ensureVisible(find.text('Connect'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // The loaded model is picked for both jobs, and its 8K context is flagged.
    expect(find.text('qwen3.5-0.8b · 8K loaded'), findsNWidgets(2));
    expect(find.textContaining('only a 8K context'), findsOneWidget);
    // Use the bigger model for the story.
    await tester.ensureVisible(find.text('qwen3.5-0.8b · 8K loaded').first);
    await tester.tap(find.text('qwen3.5-0.8b · 8K loaded').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('qwen3.5-4b').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('only a 8K context'), findsNothing);
    expect(find.textContaining('isn\'t loaded yet'), findsOneWidget);
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect((settings.textModel, settings.fastModel, settings.lmStudioUrl), ('lm:qwen3.5-4b', 'lm:qwen3.5-0.8b', 'http://10.116.127.179:1234'));
  });

  testWidgets('opening a story warns when LM Studio does not answer', (tester) async {
    settings.update((s) => s
      ..lmStudioUrl = 'http://10.0.0.5:1234'
      ..textModel = 'lm:qwen3.5-4b'
      ..aiText = true);
    GatewayClient.lmTestClient = MockClient((r) async => throw http.ClientException('refused'));
    addTearDown(() => GatewayClient.lmTestClient = null);
    await tester.pumpWidget(app(Scaffold(body: Builder(builder: (ctx) => TextButton(onPressed: () => checkLocalAi(ctx), child: const Text('open'))))));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('LM Studio isn\'t answering at http://10.0.0.5:1234'), findsOneWidget);
    expect(find.text('Check again'), findsOneWidget);
    // Back online: checking again confirms it.
    GatewayClient.lmTestClient = MockClient((r) async => http.Response('{"data": []}', 200));
    await tester.tap(find.text('Check again'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('LM Studio is connected.'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 3));
  });

  testWidgets('companion screens and the wallet fit a phone', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    CompanionStore.instance = CompanionStore.memory();
    final c = Companion(id: 'mira', name: 'Mira Lightkeeper', kind: 'Robot', pronouns: 'she/her', gender: 'female', personality: 'Dry wit, fiercely loyal, secretly sentimental about old songs.', backstory: 'Built to tend a lighthouse on a coast that no longer has ships.', interests: 'tides, poetry, terrible puns', portrait: PortraitSpec.random('human', seed: 4))
      ..trips.add(CompanionTrip(storyId: 'x', title: 'The Silent Ship', kind: 'tale', origin: true, summary: 'They escaped the derelict together and swore never to go back.'))
      ..chat.addAll([
        ChatLine(fromPlayer: false, text: 'Morning! I dreamt about the derelict again. Want to go somewhere sunnier?', opener: 'Texted you', tokens: 812, cost: 0.0004, suggest: 'The Silent Ship'),
        ChatLine(fromPlayer: true, text: 'Somewhere sunny sounds perfect.'),
        ChatLine(fromPlayer: false, text: 'Then pack sunscreen. Robots rust, you know.', tokens: 640),
      ]);
    c.profile.remember('You promised to show me a real sunrise.', source: 'chat');
    c.profile.remember('The harbor master lied to us.', source: 'story:The Silent Ship');
    CompanionStore.instance.add(c);
    for (final (name, screen) in <(String, Widget)>[
      ('companions', const CompanionsScreen()),
      ('companion-chat', const CompanionChatScreen(companionId: 'mira')),
      ('companion-profile', const CompanionProfileScreen(companionId: 'mira')),
      ('companion-editor', const CompanionEditor(companionId: 'mira')),
      ('home-companions', const HomeScreen()),
    ]) {
      await tester.pumpWidget(app(screen));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull, reason: name);
      await preview(tester, name);
      await tester.pumpWidget(const SizedBox());
    }
    final tale = Tale.create(title: 'The Glass Harbor', genre: 'scifi', engine: TaleEngine.ai);
    final ctl = TaleController(tale: tale, settings: settings, store: tales, audio: audio);
    final ozzie = ctl.meet('Ozzie Marr', role: 'fixer');
    spend(ctl, 240, category: 'wage', who: 'Dock office', tellStory: false);
    spend(ctl, -35, category: 'food', note: 'Noodles', tellStory: false);
    bankTransfer(ctl, 100);
    payByCard(ctl, 20, category: 'purchase', note: 'Rain cloak');
    giveMoney(ctl, ozzie, 30, kind: 'loan', dueIn: 10, rate: 5);
    tale.wallet.bankRate = 1;
    await tester.pumpWidget(app(FinanceScreen(host: ctl)));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    await preview(tester, 'wallet');
    await tester.scrollUntilVisible(find.text('MONEY WITH PEOPLE'), 300, scrollable: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    await preview(tester, 'wallet-people');
    await tester.scrollUntilVisible(find.textContaining('HISTORY'), 300, scrollable: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first);
    await tester.pump(const Duration(milliseconds: 300));
    await preview(tester, 'wallet-history');
    await tester.pumpWidget(const SizedBox());
    ctl.dispose();
  });

  testWidgets('homes fit phone and desktop in both modes', (tester) async {
    final fonts = FontLoader('Inter')..addFont(rootBundle.load('assets/fonts/Inter.ttf'));
    await fonts.load();
    for (final size in [const Size(390, 844), const Size(1200, 900)]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      for (final mode in ['dnd', 'tales']) {
        settings.homeMode = mode;
        await tester.pumpWidget(app(const HomeScreen()));
        await tester.pump(const Duration(seconds: 1));
        expect(find.byTooltip('Import adventure'), findsNothing);
        expect(tester.takeException(), isNull);
        await preview(tester, 'home-$mode-${size.width.toInt()}');
        await tester.pumpWidget(const SizedBox());
      }
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('usage sits beside choices and opens distinct story and lifetime tabs', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final tale = Tale.create(title: 'The Silent Ship', genre: 'scifi', engine: TaleEngine.preset, presetId: 'silent_ship')
      ..usage = {'in': 2000, 'out': 400, 'cost': 0.1};
    await tester.pumpWidget(app(TaleScreen(tale: tale)));
    await tester.pump(const Duration(seconds: 1));
    final toggle = find.text('Hide choices');
    final chip = find.byType(UsageChip);
    expect(tester.getCenter(toggle).dx, lessThan(tester.getCenter(chip).dx));
    expect((tester.getCenter(toggle).dy - tester.getCenter(chip).dy).abs(), lessThan(3));
    expect(find.descendant(of: find.byType(AppBar), matching: chip), findsNothing);
    await preview(tester, 'story-390');
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(find.text('Current story'), findsOneWidget);
    expect(find.text('By adventure'), findsNothing);
    await tester.tap(find.text('All time'));
    await tester.pumpAndSettle();
    expect(find.text('This story'), findsNothing);
    expect(find.text('Today'), findsOneWidget);
    await preview(tester, 'usage-390');
    Navigator.of(tester.element(find.text('Today'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Story tools'));
    await tester.pumpAndSettle();
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('AI tools'), findsOneWidget);
    expect(find.text('Music'), findsOneWidget);
    expect(find.text('Ambient sound'), findsOneWidget);
    expect(find.text('Terminal layout'), findsOneWidget);
    expect(find.text('Start over'), findsOneWidget);
    expect(find.text('Fullscreen'), findsOneWidget);
    // Fullscreen sits right below the terminal switch.
    expect(tester.getTopLeft(find.text('Fullscreen')).dy, greaterThan(tester.getTopLeft(find.text('Terminal layout')).dy));
    await tester.tap(find.descendant(of: find.ancestor(of: find.text('Terminal layout'), matching: find.byType(ListRow)), matching: find.byType(Switch)));
    await tester.pumpAndSettle();
    expect(find.byType(TaleTerminalScreen), findsOneWidget);
    expect(tale.terminal, isTrue);
    await tester.tap(find.byTooltip('Story tools'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start over'));
    await tester.pumpAndSettle();
    expect(tales.tales, hasLength(2));
    expect(tester.widget<TaleTerminalScreen>(find.byType(TaleTerminalScreen)).tale.id, isNot(tale.id));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('both new-adventure app bars offer import without heroes or AI keys', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final mode in ['dnd', 'tales']) {
      settings.homeMode = mode;
      await tester.pumpWidget(app(const HomeScreen()));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text(mode == 'dnd' ? 'New adventure' : 'New story'));
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(AppBar), matching: find.byTooltip('Import adventure')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await preview(tester, 'new-$mode-390');
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('onboarding tool chips form a compact group', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(const OnboardingScreen()));
    await tester.tap(find.text('Begin'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Same tools, both modes'), findsOneWidget);
    final chips = find.byType(Chip);
    expect(chips, findsNWidgets(8));
    expect(tester.getRect(chips.at(1)).left - tester.getRect(chips.first).right, closeTo(6, 0.1));
    expect(tester.takeException(), isNull);
    await preview(tester, 'onboarding-tools-390');
    await tester.pumpWidget(const SizedBox());
  });
}
