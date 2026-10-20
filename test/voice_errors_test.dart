import 'dart:convert';

import 'package:dnd/services/ai/elevenlabs.dart';
import 'package:dnd/services/ai/gateway_client.dart';
import 'package:dnd/ui/widgets/error_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('provider errors read as plain language with a top-up link', () {
    final i = describeIssue('AI error 402: Video generation requires a minimum balance of \$10. Your current balance is insufficient. Visit https://vercel.com/d?to=top-up to top up your credits.');
    expect(i.title, 'Out of credits');
    expect(i.summary, contains('\$10'));
    expect(i.link, 'https://vercel.com/d?to=top-up');
    expect(i.settings, isTrue);
    expect(describeIssue('AI error 401: Invalid API key').title, 'Key rejected');
    expect(describeIssue('AI error 429: Too many requests').title, 'Too many requests');
    expect(describeIssue('Daily cost limit would be exceeded.').title, 'Usage limit reached');
    expect(describeIssue('SocketException: Failed host lookup').title, "Can't reach the AI");
  });

  test('ElevenLabs lists voices with samples and bills spoken characters', () async {
    final events = <UsageEvent>[];
    GatewayClient.onUsage = events.add;
    final client = ElevenLabsClient('k', client: MockClient((r) async {
      expect(r.headers['xi-api-key'], 'k');
      if (r.url.path == '/v1/voices') {
        return http.Response(jsonEncode({
          'voices': [
            {'voice_id': 'v2', 'name': 'Rachel', 'preview_url': 'https://x/r.mp3', 'labels': {'accent': 'american', 'gender': 'female'}},
            {'voice_id': 'v1', 'name': 'Adam', 'labels': {}},
          ],
        }), 200);
      }
      expect(r.url.path, '/v1/text-to-speech/v2');
      expect(jsonDecode(r.body)['model_id'], 'eleven_flash_v2_5');
      return http.Response.bytes([1, 2, 3], 200);
    }));
    final voices = await client.voices();
    expect(voices.map((v) => v.name), ['Adam', 'Rachel']);
    expect(voices.last.previewUrl, 'https://x/r.mp3');
    expect(voices.last.traits, 'american · female');
    expect(await client.speak(voiceId: 'v2', text: 'Hello'), [1, 2, 3]);
    expect(events.single.characters, 5);
    expect(events.single.model, 'elevenlabs/eleven_flash_v2_5');
    GatewayClient.onUsage = null;
    client.close();
  });
}
