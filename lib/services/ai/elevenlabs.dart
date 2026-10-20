import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'gateway_client.dart';

/// A voice from the user's ElevenLabs library.
class ElevenVoice {
  const ElevenVoice({required this.id, required this.name, this.category = '', this.previewUrl, this.labels = const {}, this.description = ''});
  final String id;
  final String name;
  final String category;

  /// A free sample clip of the voice.
  final String? previewUrl;
  final Map<String, String> labels;
  final String description;

  /// "American · female · young · narration"
  String get traits => [labels['accent'], labels['gender'], labels['age'], labels['use_case'] ?? labels['use case']].whereType<String>().where((s) => s.isNotEmpty).join(' · ');

  factory ElevenVoice.fromJson(Map<String, dynamic> j) => ElevenVoice(
        id: (j['voice_id'] ?? '').toString(),
        name: (j['name'] ?? 'Voice').toString(),
        category: (j['category'] ?? '').toString(),
        previewUrl: j['preview_url']?.toString(),
        labels: {for (final e in ((j['labels'] as Map?) ?? const {}).entries) e.key.toString(): e.value.toString()},
        description: (j['description'] ?? '').toString(),
      );
}

/// ElevenLabs speech models the app offers, cheapest first.
const elevenModels = [
  ('eleven_flash_v2_5', 'Flash v2.5', 'Fastest and cheapest'),
  ('eleven_multilingual_v2', 'Multilingual v2', 'Rich and steady'),
  ('eleven_v3', 'Eleven v3', 'Most expressive'),
];

/// Estimated USD per character (credit-based plans vary; shown as an estimate).
double elevenPricePerChar(String model) => model.contains('flash') || model.contains('turbo') ? 0.00005 : 0.0001;

/// Minimal ElevenLabs client: voices and text to speech.
class ElevenLabsClient {
  ElevenLabsClient(this.apiKey, {http.Client? client, this.target, this.category = 'voice'}) : _http = client ?? http.Client();
  final String apiKey;
  final Map<String, num>? target;
  final String category;
  final http.Client _http;

  static const base = 'https://api.elevenlabs.io/v1';
  Map<String, String> get _headers => {'xi-api-key': apiKey.trim(), 'Content-Type': 'application/json'};

  String _error(http.Response r) {
    try {
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      final d = j is Map ? j['detail'] : null;
      if (d is Map) return (d['message'] ?? d['status'] ?? r.body).toString();
      if (d != null) return d.toString();
    } catch (_) {}
    return 'ElevenLabs error ${r.statusCode}';
  }

  Future<List<ElevenVoice>> voices() async {
    final r = await _http.get(Uri.parse('$base/voices'), headers: _headers).timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) throw GatewayException(_error(r), status: r.statusCode);
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
    return [for (final v in (j['voices'] as List? ?? const [])) ElevenVoice.fromJson(Map<String, dynamic>.from(v))]..sort((a, b) => a.name.compareTo(b.name));
  }

  /// MP3 audio for [text] in [voiceId].
  Future<Uint8List> speak({required String voiceId, required String text, String model = 'eleven_flash_v2_5'}) async {
    final r = await _http
        .post(
          Uri.parse('$base/text-to-speech/$voiceId?output_format=mp3_44100_128'),
          headers: {..._headers, 'Accept': 'audio/mpeg'},
          body: jsonEncode({'text': text, 'model_id': model}),
        )
        .timeout(const Duration(seconds: 90));
    if (r.statusCode != 200) throw GatewayException(_error(r), status: r.statusCode);
    GatewayClient.onUsage?.call(UsageEvent(
      model: 'elevenlabs/$model',
      characters: text.length,
      kind: 'speech',
      category: category,
      target: target,
      reportedCost: text.length * elevenPricePerChar(model),
    ));
    return r.bodyBytes;
  }

  Future<bool> verify() async {
    try {
      await voices();
      return true;
    } catch (_) {
      return false;
    }
  }

  void close() => _http.close();
}
