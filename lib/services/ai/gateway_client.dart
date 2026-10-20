import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class GatewayException implements Exception {
  GatewayException(this.message, {this.status});
  final String message;
  final int? status;

  @override
  String toString() => status == null ? message : 'AI error $status: $message';
}

class ChatMessage {
  const ChatMessage(this.role, this.content, {this.cache = false});
  final String role;
  final String content;

  /// Marks the end of a stable prefix the provider may cache.
  final bool cache;
  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

/// Providers on OpenRouter that need explicit cache markers (others cache automatically).
bool _needsCacheMarkers(String model) {
  final id = AiRoute.bare(model);
  return id.startsWith('anthropic/') || id.startsWith('qwen/');
}

/// A model on an LM Studio server.
class LmModel {
  const LmModel({required this.id, this.loaded = false, this.context, this.maxContext});
  final String id;
  final bool loaded;

  /// Context length it is loaded with (null when not loaded or unknown).
  final int? context;
  final int? maxContext;
}

/// Which service a model id is served by. OpenRouter ids carry an `or:` prefix
/// and LM Studio (local) ids an `lm:` prefix, so every model setting stays a
/// single string.
enum AiRouter { vercel, openRouter, lmStudio }

class AiRoute {
  static const prefix = 'or:';
  static const lmPrefix = 'lm:';
  static AiRouter of(String model) => model.startsWith(prefix) ? AiRouter.openRouter : (model.startsWith(lmPrefix) ? AiRouter.lmStudio : AiRouter.vercel);
  static bool isOpenRouter(String model) => model.startsWith(prefix);
  static bool isLmStudio(String model) => model.startsWith(lmPrefix);
  static String bare(String model) => isOpenRouter(model) ? model.substring(prefix.length) : (isLmStudio(model) ? model.substring(lmPrefix.length) : model);
  static String routerName(String model) => isOpenRouter(model) ? 'OpenRouter' : (isLmStudio(model) ? 'LM Studio' : 'Vercel AI Gateway');
}

/// One billed call, reported to [GatewayClient.onUsage].
class UsageEvent {
  UsageEvent({
    required this.model,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.images = 0,
    this.videos = 0,
    this.seconds = 0,
    this.characters = 0,
    this.kind = 'text',
    this.category = 'story',
    this.target,
    this.reportedCost,
    this.cachedTokens = 0,
  });
  final String model;

  /// Input tokens served from the provider's prompt cache (billed at a discount).
  final int cachedTokens;
  final String category;
  final Map<String, num>? target;
  final double? reportedCost;
  final int inputTokens;
  final int outputTokens;
  final int images;
  final int videos;

  /// Seconds of generated video.
  final int seconds;

  /// Characters sent to a speech model.
  final int characters;

  /// text | image | video | speech
  final String kind;
}

/// A generated media file: bytes and their MIME type.
class MediaBytes {
  const MediaBytes(this.bytes, this.mime);
  final Uint8List bytes;
  final String mime;

  String get extension => switch (mime) {
        'audio/wav' => 'wav',
        'audio/mpeg' => 'mp3',
        'video/webm' => 'webm',
        'video/mp4' => 'mp4',
        _ => mime.split('/').last,
      };
}

/// Client for the Vercel AI Gateway and OpenRouter (both OpenAI-compatible for
/// chat and images; each has its own speech and video APIs).
class GatewayClient {
  /// Global hook for token and cost tracking.
  static void Function(UsageEvent e)? onUsage;

  /// Estimated price of an event, for the per-request tallies below.
  static double Function(UsageEvent e)? priceOf;

  static Map<String, num>? Function()? usageTarget;
  static void Function()? Function(String model, int input, int output, int images, Map<String, num>? target, {int characters, int seconds})? beforeRequest;

  /// OpenRouter key, kept in sync with Settings.
  static String openRouterKey = '';

  /// LM Studio server address (e.g. http://192.168.1.20:1234), kept in sync with Settings.
  static String lmStudioUrl = '';

  /// "192.168.1.20:1234/v1/" → "http://192.168.1.20:1234".
  static String normalizeLmUrl(String url) {
    var u = url.trim();
    if (u.isEmpty) return '';
    if (!u.contains('://')) u = 'http://$u';
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    if (u.endsWith('/v1')) u = u.substring(0, u.length - 3);
    return u;
  }

  /// Fakes the LM Studio server in widget tests.
  static http.Client? lmTestClient;

  /// Model ids loaded or downloaded in LM Studio at [url] (without the `lm:` prefix).
  static Future<List<String>> lmStudioModels(String url, {http.Client? client}) async => [for (final m in await lmStudioDetails(url, client: client)) m.id];

  /// Models in LM Studio with whether they are loaded and their context size.
  /// Uses LM Studio's own API when available, else the OpenAI-style list.
  static Future<List<LmModel>> lmStudioDetails(String url, {http.Client? client}) async {
    client ??= lmTestClient;
    final base = normalizeLmUrl(url);
    if (base.isEmpty) throw GatewayException('Enter your LM Studio server address.');
    final c = client ?? http.Client();
    try {
      final rich = await c.get(Uri.parse('$base/api/v0/models')).timeout(const Duration(seconds: 8));
      if (rich.statusCode == 200) {
        final data = (jsonDecode(utf8.decode(rich.bodyBytes)) as Map)['data'];
        return [
          for (final m in (data is List ? data : const []))
            if (m is Map && m['id'] is String && m['type'] != 'embeddings' && !(m['id'] as String).contains('embed'))
              LmModel(id: m['id'], loaded: m['state'] == 'loaded', context: (m['loaded_context_length'] as num?)?.toInt(), maxContext: (m['max_context_length'] as num?)?.toInt()),
        ];
      }
      final r = await c.get(Uri.parse('$base/v1/models')).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) throw GatewayException('LM Studio answered ${r.statusCode}. Is the server running?', status: r.statusCode);
      final data = (jsonDecode(utf8.decode(r.bodyBytes)) as Map)['data'];
      return [
        for (final m in (data is List ? data : const []))
          // Embedding models can't write stories.
          if (m is Map && m['id'] is String && !(m['id'] as String).contains('embed')) LmModel(id: m['id']),
      ];
    } on GatewayException {
      rethrow;
    } catch (e) {
      throw GatewayException('Couldn\'t reach LM Studio at $base. Check that the server is running, "Serve on Local Network" is on, and this device is on the same Wi-Fi.');
    } finally {
      if (client == null) c.close();
    }
  }

  /// Whether LM Studio answers at [url] within a few seconds.
  static Future<bool> lmStudioReachable(String url) async {
    final base = normalizeLmUrl(url);
    if (base.isEmpty) return false;
    final c = lmTestClient ?? http.Client();
    try {
      final r = await c.get(Uri.parse('$base/v1/models')).timeout(const Duration(seconds: 4));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      if (lmTestClient == null) c.close();
    }
  }

  GatewayClient({required this.apiKey, http.Client? client, this.category = 'story', Map<String, num>? target, bool captureTarget = true, String? openRouterKey})
      : _http = client ?? http.Client(),
        _orKey = openRouterKey,
        target = target ?? (captureTarget ? usageTarget?.call() : null);
  final String category;
  final Map<String, num>? target;

  /// Vercel AI Gateway key.
  final String apiKey;
  final String? _orKey;
  final http.Client _http;

  bool _retriedLength = false;

  static bool _looksComplete(String text) {
    final t = text.trim();
    final end = t.lastIndexOf('}');
    return t.contains('{') && end > 0 && t.substring(end + 1).replaceAll('`', '').trim().isEmpty;
  }

  /// What this client has spent so far (shown per message, image or video).
  int spentTokens = 0;
  double spentCost = 0;

  static const baseUrl = 'https://ai-gateway.vercel.sh/v1';
  static const vercelAiUrl = 'https://ai-gateway.vercel.sh/v4/ai';
  static const openRouterUrl = 'https://openrouter.ai/api/v1';

  void _report(String model, dynamic usage, {int images = 0, int videos = 0, int seconds = 0, int characters = 0, String? kind, double? cost}) {
    final u = usage is Map ? usage : const {};
    final input = (u['prompt_tokens'] ?? u['input_tokens'] ?? 0) as num;
    final output = (u['completion_tokens'] ?? u['output_tokens'] ?? 0) as num;
    if (input == 0 && output == 0 && images == 0 && videos == 0 && characters == 0) return;
    final details = u['prompt_tokens_details'];
    final cached = ((details is Map ? details['cached_tokens'] : null) ?? u['cache_read_input_tokens'] ?? 0) as num;
    final e = UsageEvent(
      cachedTokens: cached.toInt(),
      model: model,
      inputTokens: input.toInt(),
      outputTokens: output.toInt(),
      images: images,
      videos: videos,
      seconds: seconds,
      characters: characters,
      kind: kind ?? (videos > 0 ? 'video' : images > 0 ? 'image' : 'text'),
      category: category,
      target: target,
      reportedCost: cost ?? num.tryParse('${u['cost']}')?.toDouble(),
    );
    spentTokens += e.inputTokens + e.outputTokens;
    spentCost += e.reportedCost ?? priceOf?.call(e) ?? 0;
    onUsage?.call(e);
  }

  String _keyFor(String model) {
    if (AiRoute.isLmStudio(model)) {
      if (normalizeLmUrl(lmStudioUrl).isEmpty) throw GatewayException('Add your LM Studio server address in Settings → AI providers to use ${AiRoute.bare(model)}.');
      return 'lm-studio';
    }
    if (AiRoute.isOpenRouter(model)) {
      final k = (_orKey ?? openRouterKey).trim();
      if (k.isEmpty) throw GatewayException('Add an OpenRouter key in Settings → AI providers to use ${AiRoute.bare(model)}.');
      return k;
    }
    if (apiKey.trim().isEmpty) throw GatewayException('Add a Vercel AI Gateway key in Settings → AI providers to use $model.');
    return apiKey.trim();
  }

  String _chatBase(String model) => AiRoute.isOpenRouter(model) ? openRouterUrl : (AiRoute.isLmStudio(model) ? '${normalizeLmUrl(lmStudioUrl)}/v1' : baseUrl);

  /// Local models can be slow, especially on the first call while they load.
  Duration _wait(String model, int seconds) => Duration(seconds: AiRoute.isLmStudio(model) ? seconds * 3 : seconds);

  List<Map<String, dynamic>> _messagesJson(String model, List<ChatMessage> messages) => [
        for (final m in messages)
          if (m.cache && AiRoute.isOpenRouter(model) && _needsCacheMarkers(model))
            {
              'role': m.role,
              'content': [
                {'type': 'text', 'text': m.content, 'cache_control': {'type': 'ephemeral'}},
              ],
            }
          else
            m.toJson(),
      ];

  /// Vercel adds cache markers itself when asked; OpenRouter uses ours.
  /// LM Studio gets no caching hints, but thinking is switched off: small local
  /// models otherwise spend the whole reply budget reasoning and return nothing.
  Map<String, dynamic> _cacheOptions(String model) => AiRoute.isLmStudio(model)
      ? const {'reasoning_effort': 'none'}
      : AiRoute.isOpenRouter(model)
      ? const {}
      : const {
          'providerOptions': {
            'gateway': {'caching': 'auto'},
          },
        };

  Map<String, String> _headers(String model) => {
        'Authorization': 'Bearer ${_keyFor(model)}',
        'Content-Type': 'application/json',
        'HTTP-Referer': 'https://github.com/dnd-solo-app',
        'X-Title': 'DnD',
      };

  Map<String, String> _vercelAiHeaders(String model, String spec) => {
        'Authorization': 'Bearer ${_keyFor(model)}',
        'Content-Type': 'application/json',
        'ai-gateway-protocol-version': '0.0.1',
        'ai-gateway-auth-method': 'api-key',
        'ai-$spec-model-specification-version': '4',
        'ai-model-id': model,
      };

  Future<String> complete({required String model, required List<ChatMessage> messages, double temperature = 0.9, int maxTokens = 1800, bool json = false}) async {
    final release = beforeRequest?.call(model, _inputEstimate(messages), maxTokens, 0, target);
    try {
      return await _complete(model: model, messages: messages, temperature: temperature, maxTokens: maxTokens, json: json);
    } finally {
      release?.call();
    }
  }

  Stream<String> stream({required String model, required List<ChatMessage> messages, double temperature = 0.9, int maxTokens = 1800}) async* {
    final release = beforeRequest?.call(model, _inputEstimate(messages), maxTokens, 0, target);
    try {
      yield* _stream(model: model, messages: messages, temperature: temperature, maxTokens: maxTokens);
    } finally {
      release?.call();
    }
  }

  /// [multimodal] models draw through chat completions; others through
  /// `/images/generations` (Vercel) or image-only chat output (OpenRouter).
  /// [references] are images (PNG/JPEG bytes) of characters to keep consistent;
  /// sent to chat image models that accept image input.
  Future<Uint8List> generateImage({required String model, required String prompt, bool multimodal = true, String size = '1024x1024', List<Uint8List> references = const []}) async {
    final release = beforeRequest?.call(model, utf8.encode(prompt).length + 32 + references.length * 1300, multimodal ? 8192 : 0, 1, target);
    try {
      try {
        return await _generateImage(model: model, prompt: prompt, multimodal: multimodal, size: size, references: references);
      } on _NoImage {
        // Chat image models occasionally answer in words; ask once more, firmly.
        try {
          return await _generateImage(model: model, prompt: 'Generate the image now. Respond with the image only, no text.\n\n$prompt', multimodal: multimodal, size: size, references: references);
        } on _NoImage {
          throw GatewayException('The model returned no image twice. Try again, or pick another image model in Settings → Images.');
        }
      }
    } finally {
      release?.call();
    }
  }

  int _inputEstimate(List<ChatMessage> messages) => messages.fold(32, (n, m) => n + utf8.encode(m.content).length + 16);

  String _errorText(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map && j['error'] is Map) return (j['error']['message'] ?? body).toString();
      if (j is Map && j['error'] != null) return j['error'].toString();
      if (j is Map && j['message'] != null) return j['message'].toString();
    } catch (_) {}
    return body.length > 300 ? '${body.substring(0, 300)}…' : body;
  }

  Future<String> _complete({
    required String model,
    required List<ChatMessage> messages,
    double temperature = 0.9,
    int maxTokens = 1800,
    bool json = false,
  }) async {
    final res = await _http
        .post(
          Uri.parse('${_chatBase(model)}/chat/completions'),
          headers: _headers(model),
          body: jsonEncode({
            'model': AiRoute.bare(model),
            'messages': _messagesJson(model, messages),
            'temperature': temperature,
            'max_tokens': maxTokens,
            // LM Studio only takes json_schema / text here.
            if (json && !AiRoute.isLmStudio(model)) 'response_format': {'type': 'json_object'},
            ..._cacheOptions(model),
          }),
        )
        .timeout(_wait(model, 120));
    if (res.statusCode != 200) {
      // Some models reject response_format; retry once without it.
      if (json && res.statusCode == 400) {
        return _complete(model: model, messages: messages, temperature: temperature, maxTokens: maxTokens);
      }
      throw GatewayException(_errorText(utf8.decode(res.bodyBytes)), status: res.statusCode);
    }
    final j = jsonDecode(utf8.decode(res.bodyBytes));
    _report(model, j['usage']);
    final choices = j['choices'];
    if (choices is! List || choices.isEmpty) throw GatewayException('The model returned no choices. Try another model.');
    final raw = choices.first['message']?['content'];
    final content = raw is String ? raw : (raw is List ? raw.map((p) => p is Map ? (p['text'] ?? '') : p.toString()).join() : '');
    if (choices.first['finish_reason'] == 'length') {
      // Reasoning models can spend the whole budget thinking. Keep a usable
      // answer; otherwise retry once with much more room.
      if (content.trim().isNotEmpty && (!json || _looksComplete(content))) return content;
      if (!_retriedLength && maxTokens < 8000) {
        _retriedLength = true;
        try {
          return await _complete(model: model, messages: messages, temperature: temperature, maxTokens: (maxTokens * 4).clamp(2000, 8000), json: json);
        } finally {
          _retriedLength = false;
        }
      }
      throw GatewayException('The AI ran out of room before finishing (often a reasoning model thinking at length). Try again, or pick a non-reasoning model in Settings → Text & story.');
    }
    if (content.trim().isNotEmpty) return content;
    throw GatewayException('Empty response from model');
  }

  /// Streams content deltas via server-sent events.
  Stream<String> _stream({
    required String model,
    required List<ChatMessage> messages,
    double temperature = 0.9,
    int maxTokens = 1800,
  }) async* {
    final req = http.Request('POST', Uri.parse('${_chatBase(model)}/chat/completions'))
      ..headers.addAll(_headers(model))
      ..body = jsonEncode({
        'model': AiRoute.bare(model),
        'messages': _messagesJson(model, messages),
        'temperature': temperature,
        'max_tokens': maxTokens,
        'stream': true,
        'stream_options': {'include_usage': true},
        ..._cacheOptions(model),
      });
    final res = await _http.send(req).timeout(_wait(model, 60));
    if (res.statusCode != 200) {
      final body = await res.stream.bytesToString();
      throw GatewayException(_errorText(body), status: res.statusCode);
    }
    var buffer = '';
    await for (final chunk in res.stream.timeout(_wait(model, 120)).transform(utf8.decoder)) {
      buffer += chunk;
      while (true) {
        final nl = buffer.indexOf('\n');
        if (nl < 0) break;
        final line = buffer.substring(0, nl).trim();
        buffer = buffer.substring(nl + 1);
        if (!line.startsWith('data:')) continue;
        final data = line.substring(5).trim();
        if (data == '[DONE]') return;
        try {
          final j = jsonDecode(data);
          if (j['error'] != null) throw GatewayException(_errorText(data));
          if (j['usage'] != null) _report(model, j['usage']);
          final choices = j['choices'];
          if (choices is! List || choices.isEmpty) continue;
          final delta = choices.first['delta']?['content'];
          if (delta is String && delta.isNotEmpty) yield delta;
        } on FormatException {
          // Ignore malformed SSE frames, not gateway errors.
        }
      }
    }
  }

  static String _aspect(String size) {
    final p = size.split('x');
    final w = int.tryParse(p.first) ?? 1, h = int.tryParse(p.last) ?? 1;
    if (w == h) return '1:1';
    return w > h ? (w / h > 1.6 ? '16:9' : '3:2') : (h / w > 1.6 ? '9:16' : '2:3');
  }

  Future<Uint8List> _generateImage({required String model, required String prompt, bool multimodal = true, String size = '1024x1024', List<Uint8List> references = const []}) async {
    final or = AiRoute.isOpenRouter(model);
    if (multimodal || or) {
      final content = references.isEmpty
          ? prompt
          : [
              {'type': 'text', 'text': prompt},
              for (final r in references) {'type': 'image_url', 'image_url': {'url': 'data:${_imageMime(r)};base64,${base64Encode(r)}'}},
            ];
      final res = await _http
          .post(
            Uri.parse('${_chatBase(model)}/chat/completions'),
            headers: _headers(model),
            body: jsonEncode({
              'model': AiRoute.bare(model),
              'messages': [
                {'role': 'user', 'content': content},
              ],
              'modalities': multimodal ? ['image', 'text'] : ['image'],
              if (or && size != '1024x1024') 'image_config': {'aspect_ratio': _aspect(size)},
              'stream': false,
            }),
          )
          .timeout(const Duration(seconds: 180));
      if (res.statusCode != 200) {
        final err = _errorText(utf8.decode(res.bodyBytes));
        if (res.statusCode == 400 && references.isNotEmpty) {
          // The model may not take image input; try again from the text alone.
          return _generateImage(model: model, prompt: prompt, multimodal: multimodal, size: size);
        }
        if (res.statusCode == 400 && multimodal && !or) {
          // Model may be image-only; fall back to the images endpoint.
          return _generateImage(model: model, prompt: prompt, multimodal: false, size: size);
        }
        throw GatewayException(err, status: res.statusCode);
      }
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      final choices = j['choices'];
      final message = choices is List && choices.isNotEmpty ? choices.first['message'] : null;
      final images = message is Map ? message['images'] : null;
      _report(model, j['usage'], images: images is List && images.isNotEmpty ? images.length : 0, kind: 'image');
      if (images is List && images.isNotEmpty) {
        final url = images.first['image_url']?['url'] as String?;
        if (url != null) return _download(url);
      }
      throw const _NoImage();
    }
    final res = await _http
        .post(
          Uri.parse('$baseUrl/images/generations'),
          headers: _headers(model),
          body: jsonEncode({'model': model, 'prompt': prompt, 'n': 1, 'size': size, 'response_format': 'b64_json'}),
        )
        .timeout(const Duration(seconds: 180));
    if (res.statusCode != 200) {
      throw GatewayException(_errorText(utf8.decode(res.bodyBytes)), status: res.statusCode);
    }
    final j = jsonDecode(utf8.decode(res.bodyBytes));
    final data = j['data'];
    _report(model, j['usage'], images: data is List ? data.length : 1, kind: 'image');
    if (data is List && data.isNotEmpty) {
      final b64 = data.first['b64_json'] as String?;
      if (b64 != null) return base64Decode(b64);
      final url = data.first['url'] as String?;
      if (url != null) return _download(url);
    }
    throw const _NoImage();
  }

  Future<Uint8List> _download(String url, {Map<String, String>? headers}) async {
    if (url.startsWith('data:')) {
      final comma = url.indexOf(',');
      return base64Decode(url.substring(comma + 1));
    }
    final r = await _http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 120));
    if (r.statusCode != 200) throw GatewayException('Could not download the generated file.', status: r.statusCode);
    return r.bodyBytes;
  }

  // ---------------------------------------------------------------- speech

  /// Text to speech. Returns audio bytes (MP3 or WAV, detected from the data).
  Future<MediaBytes> speak({required String model, required String text, String? voice, String? instructions, double speed = 1}) async {
    final release = beforeRequest?.call(model, 0, 0, 0, target, characters: text.length);
    try {
      late Uint8List bytes;
      if (AiRoute.isOpenRouter(model)) {
        final res = await _http
            .post(
              Uri.parse('$openRouterUrl/audio/speech'),
              headers: _headers(model),
              body: jsonEncode({
                'model': AiRoute.bare(model),
                'input': text,
                if (voice != null && voice.isNotEmpty) 'voice': voice,
                if (instructions != null && instructions.isNotEmpty) 'instructions': instructions,
                'response_format': 'mp3',
                if (speed != 1) 'speed': speed,
              }),
            )
            .timeout(const Duration(seconds: 90));
        if (res.statusCode != 200) throw GatewayException(_errorText(utf8.decode(res.bodyBytes)), status: res.statusCode);
        bytes = res.bodyBytes;
      } else {
        final res = await _http
            .post(
              Uri.parse('$vercelAiUrl/speech-model'),
              headers: _vercelAiHeaders(model, 'speech'),
              body: jsonEncode({
                'text': text,
                if (voice != null && voice.isNotEmpty) 'voice': voice,
                if (instructions != null && instructions.isNotEmpty) 'instructions': instructions,
                'outputFormat': 'mp3',
                if (speed != 1) 'speed': speed,
              }),
            )
            .timeout(const Duration(seconds: 90));
        if (res.statusCode != 200) throw GatewayException(_errorText(utf8.decode(res.bodyBytes)), status: res.statusCode);
        final j = jsonDecode(utf8.decode(res.bodyBytes));
        final audio = j is Map ? j['audio'] : null;
        if (audio is! String || audio.isEmpty) throw GatewayException('The voice model returned no audio.');
        bytes = base64Decode(audio);
      }
      if (bytes.isEmpty) throw GatewayException('The voice model returned no audio.');
      _report(model, null, characters: text.length, kind: 'speech');
      return MediaBytes(bytes, sniffAudio(bytes));
    } finally {
      release?.call();
    }
  }

  static String _imageMime(Uint8List b) => b.length > 3 && b[0] == 0xFF && b[1] == 0xD8 ? 'image/jpeg' : (b.length > 4 && b[0] == 0x52 && b[1] == 0x49 ? 'image/webp' : 'image/png');

  static String sniffAudio(Uint8List b) {
    if (b.length > 4 && b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46) return 'audio/wav';
    if (b.length > 4 && b[0] == 0x4F && b[1] == 0x67 && b[2] == 0x67) return 'audio/ogg';
    return 'audio/mpeg';
  }

  // ----------------------------------------------------------------- video

  static String resolutionSize(String label, String aspect) {
    final h = switch (label) { '1080p' => 1080, '720p' => 720, _ => 480 };
    final w = (h * 16 / 9 / 2).round() * 2;
    return switch (aspect) { '9:16' => '${h}x$w', '1:1' => '${h}x$h', _ => '${w}x$h' };
  }

  /// Text-to-video. Both routers run it as a background job that we poll.
  Future<MediaBytes> generateVideo({
    required String model,
    required String prompt,
    int duration = 4,
    String aspectRatio = '16:9',
    String resolution = '480p',
    bool audio = false,
    void Function(String status)? onStatus,
    Duration timeout = const Duration(minutes: 8),
  }) async {
    final release = beforeRequest?.call(model, 0, 0, 0, target, seconds: duration);
    try {
      final r = AiRoute.isOpenRouter(model)
          ? await _openRouterVideo(model, prompt, duration, aspectRatio, resolution, audio, onStatus, timeout)
          : await _vercelVideo(model, prompt, duration, aspectRatio, resolution, audio, onStatus, timeout);
      return r;
    } finally {
      release?.call();
    }
  }

  Future<MediaBytes> _openRouterVideo(String model, String prompt, int duration, String aspect, String resolution, bool audio, void Function(String)? onStatus, Duration timeout) async {
    final res = await _http
        .post(
          Uri.parse('$openRouterUrl/videos'),
          headers: _headers(model),
          body: jsonEncode({'model': AiRoute.bare(model), 'prompt': prompt, 'duration': duration, 'aspect_ratio': aspect, 'resolution': resolution, 'generate_audio': audio}),
        )
        .timeout(const Duration(seconds: 60));
    if (res.statusCode != 200 && res.statusCode != 201 && res.statusCode != 202) throw GatewayException(_errorText(utf8.decode(res.bodyBytes)), status: res.statusCode);
    final start = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
    final poll = (start['polling_url'] ?? '$openRouterUrl/videos/${start['id']}').toString();
    final deadline = DateTime.now().add(timeout);
    onStatus?.call('Queued');
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(seconds: 5));
      final s = await _http.get(Uri.parse(poll), headers: _headers(model)).timeout(const Duration(seconds: 30));
      if (s.statusCode != 200) throw GatewayException(_errorText(utf8.decode(s.bodyBytes)), status: s.statusCode);
      final j = jsonDecode(utf8.decode(s.bodyBytes)) as Map;
      final status = (j['status'] ?? '').toString();
      if (status == 'completed') {
        final urls = (j['urls'] ?? j['unsigned_urls']) as List? ?? const [];
        if (urls.isEmpty) throw GatewayException('The video finished but has no download link.');
        final signed = j['urls'] is List && (j['urls'] as List).isNotEmpty;
        final bytes = await _download(urls.first.toString(), headers: signed ? null : {'Authorization': 'Bearer ${_keyFor(model)}'});
        _report(model, null, videos: 1, seconds: duration, kind: 'video', cost: num.tryParse('${(j['usage'] as Map?)?['cost']}')?.toDouble());
        return MediaBytes(bytes, 'video/mp4');
      }
      if (status == 'failed' || status == 'cancelled') throw GatewayException('Video generation failed: ${j['error'] ?? status}');
      onStatus?.call(status == 'in_progress' ? 'Rendering' : 'Queued');
    }
    throw GatewayException('The video took too long. It may still finish on the provider; try again later.');
  }

  Future<MediaBytes> _vercelVideo(String model, String prompt, int duration, String aspect, String resolution, bool audio, void Function(String)? onStatus, Duration timeout) async {
    final body = {'prompt': prompt, 'n': 1, 'aspectRatio': aspect, 'duration': duration, 'resolution': resolutionSize(resolution, aspect), 'generateAudio': audio};
    final res = await _http.post(Uri.parse('$vercelAiUrl/video-model/start'), headers: _vercelAiHeaders(model, 'video'), body: jsonEncode(body)).timeout(const Duration(seconds: 60));
    if (res.statusCode == 404) return _vercelVideoSync(model, body);
    if (res.statusCode != 200 && res.statusCode != 201 && res.statusCode != 202) throw GatewayException(_errorText(utf8.decode(res.bodyBytes)), status: res.statusCode);
    final operation = (jsonDecode(utf8.decode(res.bodyBytes)) as Map)['operation'];
    final deadline = DateTime.now().add(timeout);
    onStatus?.call('Queued');
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(seconds: 5));
      final s = await _http.post(Uri.parse('$vercelAiUrl/video-model/status'), headers: _vercelAiHeaders(model, 'video'), body: jsonEncode({'operation': operation})).timeout(const Duration(seconds: 30));
      if (s.statusCode != 200) throw GatewayException(_errorText(utf8.decode(s.bodyBytes)), status: s.statusCode);
      final j = jsonDecode(utf8.decode(s.bodyBytes)) as Map;
      switch (j['status']) {
        case 'completed':
          return _vercelVideoResult(model, j['videos'], duration);
        case 'error' || 'cancelled':
          throw GatewayException('Video generation failed: ${j['error'] ?? j['status']}');
      }
      onStatus?.call('Rendering');
    }
    throw GatewayException('The video took too long. Try a shorter clip or a faster model.');
  }

  /// Older gateway deployments: one long request answered with an SSE event.
  Future<MediaBytes> _vercelVideoSync(String model, Map<String, dynamic> body) async {
    final res = await _http
        .post(Uri.parse('$vercelAiUrl/video-model'), headers: {..._vercelAiHeaders(model, 'video'), 'accept': 'text/event-stream'}, body: jsonEncode(body))
        .timeout(const Duration(minutes: 10));
    if (res.statusCode != 200) throw GatewayException(_errorText(utf8.decode(res.bodyBytes)), status: res.statusCode);
    for (final line in const LineSplitter().convert(utf8.decode(res.bodyBytes))) {
      if (!line.startsWith('data:')) continue;
      final j = jsonDecode(line.substring(5).trim());
      if (j is Map && j['type'] == 'error') throw GatewayException((j['message'] ?? 'Video generation failed').toString(), status: (j['statusCode'] as num?)?.toInt());
      if (j is Map && j['type'] == 'result') return _vercelVideoResult(model, j['videos'], (body['duration'] as int?) ?? 4);
    }
    throw GatewayException('The video model returned nothing.');
  }

  Future<MediaBytes> _vercelVideoResult(String model, dynamic videos, int duration) async {
    if (videos is! List || videos.isEmpty) throw GatewayException('The video model returned no video.');
    final v = videos.first as Map;
    final mime = (v['mediaType'] ?? 'video/mp4').toString();
    final bytes = v['type'] == 'base64' ? base64Decode(v['data'] as String) : await _download(v['url'] as String);
    _report(model, null, videos: 1, seconds: duration, kind: 'video');
    return MediaBytes(bytes, mime);
  }

  // ------------------------------------------------------------------ keys

  /// Checks a key against its router. [model] picks the router.
  Future<bool> verifyKey(String model) async {
    if (AiRoute.isOpenRouter(model)) {
      try {
        final r = await _http.get(Uri.parse('$openRouterUrl/key'), headers: _headers(model)).timeout(const Duration(seconds: 20));
        return r.statusCode == 200;
      } catch (_) {
        return false;
      }
    }
    try {
      await complete(model: model, messages: const [ChatMessage('user', 'Reply with OK')], maxTokens: 8, temperature: 0);
      return true;
    } on GatewayException catch (e) {
      if (e.status == 401 || e.status == 403) return false;
      // Model-specific error but key accepted.
      return e.status != null && e.status != 401;
    }
  }

  void close() => _http.close();
}

class _NoImage implements Exception {
  const _NoImage();
}
