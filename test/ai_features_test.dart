import 'dart:convert';

import 'package:dnd/data/presets.dart';
import 'package:dnd/game/story.dart';
import 'package:dnd/models/adventure.dart';
import 'package:dnd/models/tale.dart';
import 'package:dnd/models/world.dart';
import 'package:dnd/services/ai/gateway_client.dart';
import 'package:dnd/services/ai/model_catalog.dart';
import 'package:dnd/services/ai/tale_narrator.dart';
import 'package:dnd/services/export.dart';
import 'package:dnd/services/settings.dart';
import 'package:dnd/services/usage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Adventure adventure() => Adventure(id: 'a', title: 'Story', premise: '', hero: presets.first.create(), engine: StoryEngine.ai);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
    GatewayClient.onUsage = null;
    GatewayClient.usageTarget = null;
    GatewayClient.beforeRequest = null;
    GatewayClient.priceOf = null;
    GatewayClient.openRouterKey = '';
  });

  group('JSON repair', () {
    test('raw line breaks, bad escapes and trailing commas are repaired', () {
      const raw = '{"narration": "The door creaks.\nNyx says: \\\'Wait.\\\'", "choices": ["Go in", "Run",], "scene": {"title": "Oakhaven",},}';
      final turn = DmTurn.parse(raw);
      expect(turn.narration, "The door creaks.\nNyx says: 'Wait.'");
      expect(turn.choices.map((c) => c.text), ['Go in', 'Run']);
      expect(turn.scene?.title, 'Oakhaven');
    });

    test('a reply cut off mid-object keeps its fields', () {
      final j = extractJsonObject('{"name": "Kaelen", "class": "warlock", "skills": ["Arcana", "Decep');
      expect(j?['name'], 'Kaelen');
      expect(j?['class'], 'warlock');
      expect((j?['skills'] as List).first, 'Arcana');
    });

    test('unescaped quotes inside a story string survive', () {
      final j = extractJsonObject('{"narration": "She whispers "run" and vanishes.", "choices": []}');
      expect(j?['narration'], 'She whispers "run" and vanishes.');
    });

    test('code fences without a closing fence still parse', () {
      expect(extractJsonObject('```json\n{"narration": "Hi"}')?['narration'], 'Hi');
    });
  });

  group('two routers', () {
    test('catalog merges Vercel and OpenRouter with free, video and voice prices', () {
      final vercel = jsonEncode({
        'data': [
          {'id': 'anthropic/claude-haiku-5.5', 'type': 'language', 'pricing': {'input': '0.000001', 'output': '0.000005'}},
          {'id': 'bytedance/seedance-v1.0-pro-fast', 'type': 'video', 'pricing': {'video_duration_pricing': [{'resolution': '480p', 'cost_per_second': '0.0097'}, {'resolution': '720p', 'cost_per_second': '0.0206'}]}, 'video_capabilities': {'supported_operations': ['text-to-video'], 'supported_durations_seconds': [2, 4, 6]}},
          {'id': 'alibaba/wan-v2.6-i2v', 'type': 'video', 'pricing': {}, 'video_capabilities': {'supported_operations': ['image-to-video']}},
          {'id': 'openai/tts-1', 'type': 'speech', 'pricing': {'speech_input_character_cost': '0.000015'}},
        ],
      });
      final or = jsonEncode({
        'data': [
          {'id': 'meta-llama/llama-4:free', 'name': 'Meta: Llama 4 (free)', 'architecture': {'input_modalities': ['text'], 'output_modalities': ['text']}, 'pricing': {'prompt': '0', 'completion': '0'}, 'context_length': 128000},
          {'id': 'x-ai/grok-imagine-video-1.5-lite', 'architecture': {'output_modalities': ['video']}, 'pricing': {'prompt': '0', 'completion': '0'}},
          {'id': 'heygen/heygen-voice-1', 'architecture': {'output_modalities': ['speech']}, 'pricing': {'prompt': '0.000015'}, 'supported_voices': ['nadine', 'bram']},
          {'id': 'qwen/qwen-image-2.1-turbo', 'architecture': {'output_modalities': ['image']}, 'pricing': {'image_output': '0.0000044'}},
          {'id': 'openai/text-embedding', 'architecture': {'output_modalities': ['embeddings']}, 'pricing': {}},
        ],
      });
      final orVideo = jsonEncode({
        'data': [
          {'id': 'x-ai/grok-imagine-video-1.5-lite', 'supported_durations': [1, 5, 10], 'pricing_skus': {'cents_per_video_output_second_480p': '2', 'cents_per_video_output_second_720p': '3', 'cents_per_image_input': '1'}},
        ],
      });
      final models = mergeCatalogs(CatalogInput(vercel, null, or, orVideo));
      final byId = {for (final m in models) m.id: m};
      expect(byId['or:meta-llama/llama-4:free']!.isFree, isTrue);
      expect(byId['or:meta-llama/llama-4:free']!.name, 'Llama 4 (free)');
      expect(byId['anthropic/claude-haiku-5.5']!.isFree, isFalse);
      expect(byId['bytedance/seedance-v1.0-pro-fast']!.videoPrice, closeTo(0.0097, 1e-9));
      expect(byId['bytedance/seedance-v1.0-pro-fast']!.durations, [2, 4, 6]);
      expect(byId['or:x-ai/grok-imagine-video-1.5-lite']!.videoPrice, closeTo(0.02, 1e-9));
      expect(byId['openai/tts-1']!.speechPrice, closeTo(0.000015, 1e-12));
      expect(byId['or:heygen/heygen-voice-1']!.voices, ['nadine', 'bram']);
      expect(byId['or:qwen/qwen-image-2.1-turbo']!.canMakeImages, isTrue);
      expect(byId.containsKey('or:openai/text-embedding'), isFalse);
      final catalog = ModelCatalog(_prefs)..models = models;
      expect(catalog.videoModels.map((m) => m.id), isNot(contains('alibaba/wan-v2.6-i2v')), reason: 'Image-to-video models cannot film from a prompt alone.');
      final cheapest = catalog.videoModels.toList()..sort((a, b) => a.sortPrice.compareTo(b.sortPrice));
      expect(cheapest.first.id, 'bytedance/seedance-v1.0-pro-fast');
    });

    test('OpenRouter models go to OpenRouter with its key and the bare id', () async {
      late http.Request sent;
      final client = GatewayClient(apiKey: 'vercel-key', openRouterKey: 'or-key', client: MockClient((r) async {
        sent = r;
        return http.Response(jsonEncode({'choices': [{'message': {'content': 'Hi'}}], 'usage': {'prompt_tokens': 3, 'completion_tokens': 1, 'cost': 0.0001}}), 200);
      }));
      expect(await client.complete(model: 'or:meta-llama/llama-4:free', messages: const [ChatMessage('user', 'x')]), 'Hi');
      expect(sent.url.toString(), 'https://openrouter.ai/api/v1/chat/completions');
      expect(sent.headers['Authorization'], 'Bearer or-key');
      expect(jsonDecode(sent.body)['model'], 'meta-llama/llama-4:free');
      expect(client.spentCost, closeTo(0.0001, 1e-12), reason: 'OpenRouter reports the exact cost.');
      client.close();
    });

    test('a missing router key explains which key to add', () async {
      final client = GatewayClient(apiKey: 'vercel-key', client: MockClient((_) async => http.Response('{}', 200)));
      await expectLater(client.complete(model: 'or:x/y', messages: const []), throwsA(isA<GatewayException>().having((e) => e.message, 'message', contains('OpenRouter key'))));
      client.close();
    });

    test('speech: Vercel returns base64 audio, OpenRouter raw bytes; characters are billed', () async {
      final events = <UsageEvent>[];
      GatewayClient.onUsage = events.add;
      final mp3 = [0x49, 0x44, 0x33, 1, 2, 3];
      final vercel = GatewayClient(apiKey: 'k', category: 'voice', client: MockClient((r) async {
        expect(r.url.toString(), 'https://ai-gateway.vercel.sh/v4/ai/speech-model');
        expect(r.headers['ai-model-id'], 'openai/tts-1');
        expect(jsonDecode(r.body)['voice'], 'alloy');
        return http.Response(jsonEncode({'audio': base64Encode(mp3)}), 200);
      }));
      final a = await vercel.speak(model: 'openai/tts-1', text: 'Hello there', voice: 'alloy');
      expect(a.bytes, mp3);
      expect(a.mime, 'audio/mpeg');
      final wav = [0x52, 0x49, 0x46, 0x46, 0, 0];
      final or = GatewayClient(apiKey: '', openRouterKey: 'or', category: 'voice', client: MockClient((r) async {
        expect(r.url.path, '/api/v1/audio/speech');
        expect(jsonDecode(r.body)['input'], 'Hi');
        return http.Response.bytes(wav, 200);
      }));
      expect((await or.speak(model: 'or:google/gemini-3.8-flash-lite-tts', text: 'Hi')).mime, 'audio/wav');
      expect(events.map((e) => (e.kind, e.characters, e.category)), [('speech', 11, 'voice'), ('speech', 2, 'voice')]);
      vercel.close();
      or.close();
    });

    test('an image model that answers in words gets one firm retry', () async {
      var calls = 0;
      final png = base64Encode([137, 80, 78, 71]);
      final client = GatewayClient(apiKey: 'k', client: MockClient((r) async {
        calls++;
        final images = calls == 1 ? [] : [{'image_url': {'url': 'data:image/png;base64,$png'}}];
        return http.Response(jsonEncode({'choices': [{'message': {'content': 'Here you go!', 'images': images}}]}), 200);
      }));
      final bytes = await client.generateImage(model: 'google/gemini-3.1-flash-image', prompt: 'A castle');
      expect(bytes, [137, 80, 78, 71]);
      expect(calls, 2);
      client.close();
    });

    test('OpenRouter defaults are adopted when only its key is set', () {
      final s = SettingsController(_prefs)..openRouterKey = 'k';
      adoptOpenRouterModels(s, null);
      for (final id in [s.textModel, s.fastModel, s.imageModel, s.videoModel, s.speechModel]) {
        expect(id, startsWith('or:'));
        expect(s.canUse(id), isTrue);
      }
    });
  });

  group('usage', () {
    test('video seconds, speech characters and media caps', () async {
      final settings = SettingsController(_prefs)..adventureImageLimit = 2;
      final catalog = ModelCatalog(_prefs)
        ..models = [
          ModelInfo(id: 'v', name: 'V', provider: 'p', type: 'video', videoPrice: 0.01),
          ModelInfo(id: 's', name: 'S', provider: 'p', type: 'speech', speechPrice: 0.00002),
          ModelInfo(id: 'i', name: 'I', provider: 'p', type: 'image', imagePrice: 0.04),
        ];
      final usage = UsageTracker(_prefs, catalog, settings: settings);
      expect(usage.costOf(UsageEvent(model: 'v', videos: 1, seconds: 4)), closeTo(0.04, 1e-9));
      expect(usage.costOf(UsageEvent(model: 's', characters: 1000)), closeTo(0.02, 1e-9));
      final story = <String, num>{'images': 2};
      expect(() => usage.reserve('i', 10, 0, 1, story), throwsA(isA<GatewayException>()));
      usage.record(UsageEvent(model: 'v', videos: 1, seconds: 4, kind: 'video', category: 'video', target: story));
      expect(story['videos'], 1);
      expect(usageBreakdown(story, 'category')['video']!.seconds, 4);
      expect(usageBreakdown(story, 'category')['video']!.detail, contains('1 video (4s)'));
    });
  });

  group('relationships and world data', () {
    test('friendship and romance move separately and are remembered', () {
      final a = adventure();
      final npc = Npc(id: 'n', name: 'Nyx', portrait: a.hero.portrait);
      a.npcs.add(npc);
      expect(applyBondChange(a, npc, friendship: 6, romance: 12, reason: 'You kissed her'), contains('Nyx'));
      final b = a.bondFor(npc);
      expect((b.friendship, b.romance, b.romanceLabel, b.label), (6, 12, 'Curious', 'Acquaintance'));
      applyBondChange(a, npc, romance: 25, status: 'Courting');
      expect(b.label, 'Courting');
      expect(b.romance, 37, reason: 'A single change is capped at 25.');
      applyBondChange(a, npc, romanceClosed: true, romance: 10, reason: 'She said no');
      expect(b.romance, 37, reason: 'A closed romance does not grow.');
      expect(b.moments, hasLength(3));
      expect(a.bondsPrompt(a.people), contains('Nyx — friendship 6/100'));
      expect(npc.disposition, 6);
    });

    test('bonds, chats, gallery and voices survive saving', () {
      final a = adventure();
      final npc = Npc(id: 'n', name: 'Nyx', portrait: a.hero.portrait);
      a.npcs.add(npc);
      applyBondChange(a, npc, friendship: 10);
      a.chatWith('n').addAll([ChatLine(fromPlayer: true, text: 'Hi'), ChatLine(fromPlayer: false, text: 'Hello', tokens: 50, cost: 0.001)]);
      a.addMedia(MediaItem(path: '/x.png', kind: 'scene', caption: 'Inn', cost: 0.04));
      a.voices['n'] = 'nova';
      final back = Adventure.fromJson(jsonDecode(jsonEncode(a.toJson())));
      expect(back.bonds['n']!.friendship, 10);
      expect(back.chats['n']!.last.cost, 0.001);
      expect(back.gallery.single.caption, 'Inn');
      expect(back.mediaCosts['/x.png'], 0.04);
      expect(back.voices['n'], 'nova');

      final t = Tale.create(title: 'T', genre: 'noir', engine: TaleEngine.ai)..scene = SceneInfo(title: 'The Office');
      final rose = t.meet('Rose Calloway', role: 'client', description: 'Red coat, cold eyes.');
      applyBondChange(t, rose, romance: 8);
      t.remember('clue', 'The ledger', 'Missing page 12.');
      t.goals.add(Quest(id: 'g', title: 'Find the ledger'));
      final tb = Tale.fromJson(jsonDecode(jsonEncode(t.toJson())));
      expect(tb.personNamed('rose')?.role, 'client');
      expect(tb.bonds[rose.id]!.romance, 8);
      expect(tb.canon.single.name, 'The ledger');
      expect(tb.goals.single.title, 'Find the ledger');
      expect(tb.scene.title, 'The Office');
    });

    test('text adventure turns carry people, dialogue, relationships, goals and scene', () {
      final turn = TaleTurn.parse(jsonEncode({
        'title': 'The Docks',
        'narration': 'Fog rolls in.',
        'speaker': 'Rose',
        'dialogue': [{'name': 'Mack', 'line': 'Boss wants you.'}],
        'people': [{'name': 'Mack', 'role': 'dock boss', 'description': 'Huge.'}],
        'relationships': [{'name': 'Rose', 'friendship': 3, 'romance': 5, 'reason': 'You kept her secret'}],
        'goals': [{'title': 'Find the ledger', 'status': 'new'}],
        'scene': {'location_type': 'coast', 'time': 'night', 'mood': 'tense', 'image_prompt': 'Fog over the docks'},
        'moment': 'A gunshot splits the fog.',
        'choices': ['Run'],
      }));
      expect(turn.title, 'The Docks');
      expect(turn.speaker, 'Rose');
      expect(turn.dialogue.single, ('Mack', 'Boss wants you.'));
      expect(turn.people.single['role'], 'dock boss');
      expect(turn.relationships.single['romance'], 5);
      expect(turn.goals.single['title'], 'Find the ledger');
      expect((turn.location, turn.time, turn.mood), ('coast', 'night', 'tense'));
      expect(turn.moment, 'A gunshot splits the fog.');
    });
  });

  group('export', () {
    test('Markdown and the interactive page include the cast and relationships', () async {
      final t = Tale.create(title: 'Rain Ledger', genre: 'noir', engine: TaleEngine.ai, premise: 'A dead man owes you money.');
      final rose = t.meet('Rose', role: 'client');
      applyBondChange(t, rose, friendship: 20, romance: 30, status: 'Partners');
      t.log.addAll([
        LogEntry(kind: LogKind.narration, text: 'Rain on the window.'),
        LogEntry(kind: LogKind.dialogue, text: 'You came.', speaker: 'Rose'),
        LogEntry(kind: LogKind.player, text: 'I always do.'),
      ]);
      final doc = exportDocFromTale(t);
      final md = storyMarkdown(doc);
      expect(md, contains('# Rain Ledger'));
      expect(md, contains('**Rose:** You came.'));
      expect(md, contains('Rose**, client — Partners'));
      final html = await storyHtml(doc);
      expect(html, contains('<title>Rain Ledger</title>'));
      expect(html, contains('id="theme"'));
      expect(html, contains('class="cast"'));
      expect(html, contains('Partners'));
    });

    testWidgets('PDF export produces a document', (tester) async {
      final a = adventure()..log.add(LogEntry(kind: LogKind.narration, text: 'The road is long — and dark.'));
      final bytes = await tester.runAsync(() => storyPdf(exportDocFromAdventure(a)));
      expect(utf8.decode(bytes!.sublist(0, 5)), '%PDF-');
    });
  });
}

late SharedPreferences _prefs;
