import 'dart:convert';

import 'package:dnd/services/ai/gateway_client.dart';
import 'package:dnd/services/ai/story_ai.dart';
import 'package:dnd/services/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  localReplyTests();
  test('server addresses are normalized', () {
    expect(GatewayClient.normalizeLmUrl('10.116.127.179:1234'), 'http://10.116.127.179:1234');
    expect(GatewayClient.normalizeLmUrl(' http://127.0.0.1:1234/v1/ '), 'http://127.0.0.1:1234');
    expect(GatewayClient.normalizeLmUrl(''), '');
  });

  test('lm: models route to LM Studio and need only the address', () async {
    expect(AiRoute.of('lm:qwen3.5-0.8b'), AiRouter.lmStudio);
    expect(AiRoute.bare('lm:qwen3.5-0.8b'), 'qwen3.5-0.8b');
    expect(AiRoute.routerName('lm:x'), 'LM Studio');
    SharedPreferences.setMockInitialValues({});
    final s = SettingsController(await SharedPreferences.getInstance());
    expect(s.canUse('lm:x'), isFalse);
    s.update((s) => s
      ..lmStudioUrl = 'http://10.0.0.5:1234'
      ..textModel = 'lm:x');
    expect((s.hasApiKey, s.canUse('lm:x'), s.useAiText), (true, true, true));
    expect(GatewayClient.lmStudioUrl, 'http://10.0.0.5:1234');
  });

  test('chat requests go to the local server without cloud-only options', () async {
    GatewayClient.lmStudioUrl = '10.0.0.5:1234';
    late http.Request sent;
    final client = GatewayClient(
      apiKey: '',
      captureTarget: false,
      client: MockClient((r) async {
        sent = r;
        return http.Response(jsonEncode({'choices': [{'message': {'content': '{"narration":"hi"}'}}], 'usage': {'prompt_tokens': 10, 'completion_tokens': 3}}), 200);
      }),
    );
    final out = await client.complete(model: 'lm:qwen3.5-0.8b', messages: const [ChatMessage('system', 'x', cache: true), ChatMessage('user', 'go')], json: true);
    expect(out, contains('hi'));
    expect(sent.url.toString(), 'http://10.0.0.5:1234/v1/chat/completions');
    final body = jsonDecode(sent.body) as Map;
    expect(body['model'], 'qwen3.5-0.8b');
    expect(body.containsKey('response_format'), isFalse);
    expect(body.containsKey('providerOptions'), isFalse);
    expect(body['reasoning_effort'], 'none');
  });

  test('model list skips embedding models', () async {
    // Older LM Studio without its own API: fall back to the OpenAI-style list.
    final ids = await GatewayClient.lmStudioModels('10.0.0.5:1234', client: MockClient((r) async {
      if (r.url.path != '/v1/models') return http.Response('not found', 404);
      return http.Response(jsonEncode({'data': [{'id': 'qwen3.5-0.8b'}, {'id': 'text-embedding-nomic-embed-text-v1.5'}]}), 200);
    }));
    expect(ids, ['qwen3.5-0.8b']);
  });
}

void localReplyTests() {
  test('local character replies are cleaned to plain speech', () {
    expect(StoryAi.cleanLocalReply('Ilya Venn: My name is Ilya.', 'Ilya Venn'), 'My name is Ilya.');
    expect(StoryAi.cleanLocalReply('**Ilya:** "Stay close."', 'Ilya Venn'), 'Stay close.');
    expect(StoryAi.cleanLocalReply('```json\n{"reply": "Fine, thanks."}\n```', 'Ilya Venn'), 'Fine, thanks.');
    expect(StoryAi.cleanLocalReply('*smiles* I am well.', 'Ilya Venn'), '*smiles* I am well.');
  });

  test('model details report loaded state and context', () async {
    final models = await GatewayClient.lmStudioDetails('10.0.0.5:1234', client: MockClient((r) async {
      expect(r.url.path, '/api/v0/models');
      return http.Response(jsonEncode({'data': [{'id': 'a', 'type': 'llm', 'state': 'loaded', 'loaded_context_length': 8192, 'max_context_length': 32768}, {'id': 'e', 'type': 'embeddings'}]}), 200);
    }));
    expect(models.map((m) => (m.id, m.loaded, m.context, m.maxContext)), [('a', true, 8192, 32768)]);
  });

  test('reachability check answers quickly either way', () async {
    GatewayClient.lmTestClient = MockClient((r) async => http.Response('{"data": []}', 200));
    expect(await GatewayClient.lmStudioReachable('10.0.0.5:1234'), isTrue);
    GatewayClient.lmTestClient = MockClient((r) async => throw http.ClientException('refused'));
    expect(await GatewayClient.lmStudioReachable('10.0.0.5:1234'), isFalse);
    expect(await GatewayClient.lmStudioReachable(''), isFalse);
    GatewayClient.lmTestClient = null;
  });
}
