import 'dart:async';
import 'dart:convert';

import 'package:dnd/data/presets.dart';
import 'package:dnd/game/story.dart';
import 'package:dnd/models/adventure.dart';
import 'package:dnd/services/ai/gateway_client.dart';
import 'package:dnd/services/ai/model_catalog.dart';
import 'package:dnd/services/ai/tale_narrator.dart';
import 'package:dnd/services/image_service.dart';
import 'package:dnd/services/settings.dart';
import 'package:dnd/services/usage.dart';
import 'package:dnd/ui/screens/adventure/log_view.dart';
import 'package:dnd/ui/widgets/portrait.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Adventure adventure() => Adventure(
  id: 'a',
  title: 'Story',
  premise: '',
  hero: presets.first.create(),
  engine: StoryEngine.ai,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GatewayClient.onUsage = null;
    GatewayClient.usageTarget = null;
    GatewayClient.beforeRequest = null;
  });
  tearDown(() {
    GatewayClient.onUsage = null;
    GatewayClient.usageTarget = null;
    GatewayClient.beforeRequest = null;
  });

  test('truncated structured narration never becomes visible JSON', () {
    const raw =
        '{"narration":"The village is silent.\\nNyx whispers \\"Wait.\\"", "scene":{"title":"Oak';
    final turn = DmTurn.parse(raw);
    expect(turn.narration, 'The village is silent.\nNyx whispers "Wait."');
    expect(turn.choices, isNotEmpty);
    expect(TaleTurn.parse(raw).narration, turn.narration);
    expect(
      readableNarration(raw),
      turn.narration,
      reason: 'Old saved responses are recoverable too.',
    );
    expect(() => DmTurn.parse('{"scene":'), throwsFormatException);
    expect(() => DmTurn.parse(''), throwsFormatException);
    expect(DmTurn.parse('A door opens.').narration, 'A door opens.');
  });

  test(
    'speaker matching supports unique short names without confusing people',
    () {
      final a = adventure();
      final c = presets[1].create()..name = 'Kaelen Brightwater';
      a.companions.add(c);
      expect(a.companionNamed('kaelen'), same(c));
      expect(a.personNamed('KAELEN')!.portrait, same(c.portrait));
      expect(a.people.single.id, c.id);
      a.companions.add(presets[2].create()..name = 'Kaelen Stone');
      expect(
        a.personNamed('Kaelen'),
        isNull,
        reason: 'Ambiguous names must not select the wrong character.',
      );
    },
  );

  test(
    'a delayed response is billed to its original adventure and category',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final catalog = ModelCatalog(prefs)
        ..models = [
          ModelInfo(
            id: 'test/model',
            name: 'Test',
            provider: 'test',
            type: 'language',
            inputPrice: 1,
            outputPrice: 4,
          ),
        ];
      final usage = UsageTracker(prefs, catalog);
      final first = adventure();
      final second = adventure();
      usage.current = first;
      final response = Completer<http.Response>();
      final client = GatewayClient(
        apiKey: 'test',
        category: 'npc',
        client: MockClient((_) => response.future),
      );
      final pending = client.complete(
        model: 'test/model',
        messages: const [ChatMessage('user', 'Hello')],
      );
      usage.current = second;
      response.complete(
        http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'Hello there.'},
              },
            ],
            'usage': {'prompt_tokens': 1000, 'completion_tokens': 500},
          }),
          200,
        ),
      );
      expect(await pending, 'Hello there.');
      expect(first.usage['cost'], closeTo(0.003, 1e-9));
      expect(second.usage, isEmpty);
      expect(usageBreakdown(first.usage, 'category')['npc']!.tokens, 1500);
      expect(usageBreakdown(first.usage, 'model')['test/model']!.calls, 1);
      expect(
        usageBreakdown(first.usage, 'categoryModel:npc')['test/model']!.cost,
        closeTo(0.003, 1e-9),
      );
      client.close();
    },
  );

  test(
    'budgets include concurrent reservations and release failed requests',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsController(prefs)..dailyTokenLimit = 100;
      final catalog = ModelCatalog(prefs)
        ..models = [
          ModelInfo(
            id: 'test/model',
            name: 'Test',
            provider: 'test',
            type: 'language',
            inputPrice: 1,
            outputPrice: 4,
          ),
        ];
      final usage = UsageTracker(prefs, catalog, settings: settings);
      final release = usage.reserve('test/model', 10, 60, 0, null);
      expect(
        () => usage.reserve('test/model', 10, 30, 0, null),
        throwsA(isA<GatewayException>()),
      );
      release();
      usage.reserve('test/model', 10, 30, 0, null)();
      settings.dailyTokenLimit = 0;
      settings.adventureCostLimit = 0.001;
      final target = <String, num>{'cost': 0.0009};
      expect(
        () => usage.reserve('test/model', 1000, 0, 0, target),
        throwsA(isA<GatewayException>()),
      );
      settings.adventureCostLimit = 0;
      settings.dailyTokenLimit = 100;
      var attempts = 0;
      final client = GatewayClient(
        apiKey: 'test',
        client: MockClient((_) async {
          attempts++;
          throw const FormatException('Network failed');
        }),
      );
      for (var i = 0; i < 2; i++) {
        await expectLater(
          client.complete(
            model: 'test/model',
            messages: const [ChatMessage('user', 'x')],
            maxTokens: 20,
          ),
          throwsFormatException,
        );
      }
      expect(attempts, 2);
      client.close();
    },
  );

  test(
    'unknown-price models are blocked under a cost limit before HTTP',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsController(prefs)..dailyCostLimit = 1;
      UsageTracker(prefs, ModelCatalog(prefs), settings: settings);
      var sent = false;
      final client = GatewayClient(
        apiKey: 'test',
        client: MockClient((_) async {
          sent = true;
          return http.Response('{}', 200);
        }),
      );
      await expectLater(
        client.complete(model: 'unknown', messages: const []),
        throwsA(isA<GatewayException>()),
      );
      expect(sent, isFalse);
      client.close();
    },
  );

  test('a request can leave the provider output uncapped', () async {
    Map<String, dynamic>? sent;
    final client = GatewayClient(
      apiKey: 'test',
      client: MockClient((request) async {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'A complete reply.'},
              },
            ],
          }),
          200,
        );
      }),
    );
    expect(
      await client.complete(
        model: 'test/model',
        messages: const [ChatMessage('user', 'Keep it short.')],
        maxTokens: null,
      ),
      'A complete reply.',
    );
    expect(sent, isNot(contains('max_tokens')));
    client.close();
  });

  test('truncated character JSON reports an actionable error and records usage', () async {
    final events = <UsageEvent>[];
    GatewayClient.onUsage = events.add;
    final client = GatewayClient(
      apiKey: 'test',
      category: 'character',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'choices': [
              {
                'finish_reason': 'length',
                'message': {'content': '{"name":"Nyx",'},
              },
            ],
            'usage': {'prompt_tokens': 100, 'completion_tokens': 200},
          }),
          200,
        ),
      ),
    );
    await expectLater(
      client.complete(model: 'test', messages: const [], json: true),
      throwsA(isA<GatewayException>()),
    );
    expect(
      events,
      hasLength(2),
      reason:
          'A reply cut off by the output limit is retried once with more room.',
    );
    expect(
      events.every((e) => e.category == 'character' && e.outputTokens == 200),
      isTrue,
    );
    client.close();
  });

  test(
    'stream usage-only frames are accepted and gateway errors propagate',
    () async {
      final events = <UsageEvent>[];
      GatewayClient.onUsage = events.add;
      final client = GatewayClient(
        apiKey: 'test',
        client: MockClient.streaming(
          (_, _) async => http.StreamedResponse(
            Stream.value(
              utf8.encode(
                'data: {"choices":[{"delta":{"content":"Hello"}}]}\n'
                'data: {"choices":[],"usage":{"prompt_tokens":5,"completion_tokens":2}}\n'
                'data: {"error":{"message":"Provider interrupted"}}\n',
              ),
            ),
            200,
          ),
        ),
      );
      final text = <String>[];
      await expectLater(
        client.stream(model: 'test', messages: const []).forEach(text.add),
        throwsA(isA<GatewayException>()),
      );
      expect(text, ['Hello']);
      expect(events.single.inputTokens, 5);
      client.close();
    },
  );

  testWidgets(
    'companion dialogue shows an avatar and opens conversation on tap',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final images = ImageService(
        SettingsController(prefs),
        ModelCatalog(prefs),
      );
      final a = adventure()
        ..companions.add(presets[1].create()..name = 'Kaelen Brightwater');
      Npc? selected;
      await tester.pumpWidget(
        ChangeNotifierProvider<ImageService>.value(
          value: images,
          child: MaterialApp(
            home: Scaffold(
              body: LogEntryView(
                entry: LogEntry(
                  kind: LogKind.companion,
                  text: 'The village is waiting.',
                  speaker: 'Kaelen',
                ),
                adventure: a,
                onTalk: (n) => selected = n,
              ),
            ),
          ),
        ),
      );
      expect(find.byType(CharacterPortrait), findsOneWidget);
      await tester.tap(find.text('The village is waiting.'));
      expect(selected?.name, 'Kaelen Brightwater');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'full portrait viewer contains the whole image instead of cropping',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final images = ImageService(
        SettingsController(prefs),
        ModelCatalog(prefs),
      );
      final c = presets.first.create();
      await tester.pumpWidget(
        ChangeNotifierProvider<ImageService>.value(
          value: images,
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: CharacterPortrait(character: c, viewable: true),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(CharacterPortrait));
      await tester.pumpAndSettle();
      final displayed = tester
          .widgetList<GeneratedImage>(find.byType(GeneratedImage))
          .toList();
      expect(
        displayed.any(
          (image) => image.fit == BoxFit.contain && image.cacheWidth == null,
        ),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
