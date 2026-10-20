import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../settings.dart';
import 'gateway_client.dart';

/// What a model produces, as the app uses it.
enum ModelKind { text, image, video, speech }

/// A model from the Vercel AI Gateway or OpenRouter, enriched with models.dev metadata.
class ModelInfo {
  ModelInfo({
    required this.id,
    required this.name,
    required this.provider,
    required this.type,
    this.description = '',
    this.contextWindow,
    this.maxOutput,
    this.inputPrice,
    this.outputPrice,
    this.imagePrice,
    this.videoPrice,
    this.speechPrice,
    this.inputModalities = const ['text'],
    this.outputModalities = const ['text'],
    this.reasoning = false,
    this.toolCall = false,
    this.openWeights = false,
    this.releaseDate,
    this.knowledge,
    this.tags = const [],
    this.voices = const [],
    this.durations = const [],
    this.resolutions = const [],
    this.textToVideo = true,
  });

  /// OpenRouter models are prefixed with `or:`.
  final String id;
  final String name;
  final String provider;

  /// language | image | video | speech
  final String type;
  final String description;
  final int? contextWindow;
  final int? maxOutput;

  /// USD per 1M tokens
  final double? inputPrice;
  final double? outputPrice;

  /// USD per image
  final double? imagePrice;

  /// USD per second of video at the cheapest resolution.
  final double? videoPrice;

  /// USD per character of speech.
  final double? speechPrice;
  final List<String> inputModalities;
  final List<String> outputModalities;
  final bool reasoning;
  final bool toolCall;
  final bool openWeights;
  final String? releaseDate;
  final String? knowledge;
  final List<String> tags;

  /// Built-in voices (speech models).
  final List<String> voices;

  /// Supported clip lengths in seconds (video models).
  final List<int> durations;
  final List<String> resolutions;
  final bool textToVideo;

  AiRouter get router => AiRoute.of(id);
  String get bareId => AiRoute.bare(id);
  bool get isText => type == 'language' && outputModalities.contains('text');
  bool get canMakeImages => type == 'image' || outputModalities.contains('image');
  bool get isVideo => type == 'video';
  bool get isSpeech => type == 'speech';

  /// Image via chat completions `modalities` rather than an image-only endpoint.
  bool get multimodalImage => type == 'language' && outputModalities.contains('image');
  bool get isVariant => id.endsWith('-batch') || id.endsWith(':batch') || id.endsWith('-decisions') || (inputPrice ?? 0) < 0;

  bool get isFree {
    if (id.endsWith(':free')) return true;
    return switch (type) {
      'language' => inputPrice == 0 && outputPrice == 0,
      'image' => imagePrice == 0,
      'video' => videoPrice == 0,
      'speech' => speechPrice == 0,
      _ => false,
    };
  }

  /// A comparable price for sorting by cheapness within a kind.
  double get sortPrice => switch (type) {
        'video' => videoPrice ?? 999,
        'speech' => speechPrice ?? 999,
        'image' => imagePrice ?? ((outputPrice ?? 999000) / 1e6 * 1290),
        _ => canMakeImages && imagePrice != null ? imagePrice! : (inputPrice ?? 999) * 0.75 + (outputPrice ?? 999) * 0.25,
      };

  String get priceLabel {
    if (isFree) return 'Free';
    String usd(double v) => v >= 1 ? '\$${v.toStringAsFixed(2)}' : (v >= 0.01 ? '\$${v.toStringAsFixed(3)}' : '\$${v.toStringAsFixed(4)}');
    if (type == 'video') return videoPrice == null ? 'price varies' : '${usd(videoPrice!)}/sec';
    if (type == 'speech') return speechPrice == null ? (inputPrice == null ? '—' : '\$${(inputPrice! / 1000).toStringAsFixed(3)}/1K chars') : '${usd(speechPrice! * 1000)}/1K chars';
    if (type == 'image' && imagePrice != null) return '${usd(imagePrice!)}/img';
    if (inputPrice == null && outputPrice == null) return '—';
    String f(double v) => v >= 10 ? v.toStringAsFixed(0) : (v >= 1 ? v.toStringAsFixed(2) : v.toStringAsFixed(3));
    return '\$${f(inputPrice ?? 0)} / \$${f(outputPrice ?? 0)}';
  }

  String get contextLabel {
    final c = contextWindow;
    if (c == null) return '—';
    if (c >= 1000000) return '${(c / 1000000).toStringAsFixed(c % 1000000 == 0 ? 0 : 1)}M';
    return '${(c / 1000).round()}K';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'provider': provider,
        'type': type,
        'desc': description,
        'ctx': contextWindow,
        'out': maxOutput,
        'ip': inputPrice,
        'op': outputPrice,
        'imp': imagePrice,
        'vp': videoPrice,
        'sp': speechPrice,
        'im': inputModalities,
        'om': outputModalities,
        'r': reasoning,
        'tc': toolCall,
        'ow': openWeights,
        'rd': releaseDate,
        'kn': knowledge,
        'tags': tags,
        'voices': voices,
        'dur': durations,
        'res': resolutions,
        't2v': textToVideo,
      };

  factory ModelInfo.fromJson(Map<String, dynamic> j) => ModelInfo(
        id: j['id'],
        name: j['name'] ?? j['id'],
        provider: j['provider'] ?? '',
        type: j['type'] ?? 'language',
        description: j['desc'] ?? '',
        contextWindow: j['ctx'],
        maxOutput: j['out'],
        inputPrice: (j['ip'] as num?)?.toDouble(),
        outputPrice: (j['op'] as num?)?.toDouble(),
        imagePrice: (j['imp'] as num?)?.toDouble(),
        videoPrice: (j['vp'] as num?)?.toDouble(),
        speechPrice: (j['sp'] as num?)?.toDouble(),
        inputModalities: List<String>.from(j['im'] ?? const ['text']),
        outputModalities: List<String>.from(j['om'] ?? const ['text']),
        reasoning: j['r'] ?? false,
        toolCall: j['tc'] ?? false,
        openWeights: j['ow'] ?? false,
        releaseDate: j['rd'],
        knowledge: j['kn'],
        tags: List<String>.from(j['tags'] ?? const []),
        voices: List<String>.from(j['voices'] ?? const []),
        durations: [for (final d in (j['dur'] as List? ?? const [])) (d as num).toInt()],
        resolutions: List<String>.from(j['res'] ?? const []),
        textToVideo: j['t2v'] ?? true,
      );
}

/// Well-known voices for speech models whose catalog entry doesn't list them.
List<String> defaultVoicesFor(String modelId) {
  final id = AiRoute.bare(modelId);
  if (id.startsWith('openai/')) return const ['alloy', 'ash', 'ballad', 'coral', 'echo', 'fable', 'nova', 'onyx', 'sage', 'shimmer'];
  if (id.startsWith('google/')) return const ['Kore', 'Puck', 'Charon', 'Zephyr', 'Fenrir', 'Leda', 'Orus', 'Aoede', 'Callirrhoe', 'Enceladus'];
  if (id.startsWith('microsoft/')) return const ['en-US-Harper', 'en-US-Ethan', 'en-US-Ava', 'en-US-Andrew', 'en-GB-Sonia', 'en-GB-Ryan'];
  if (id.startsWith('spacexai/') || id.startsWith('x-ai/') || id.startsWith('xai/')) return const ['Ara', 'Eve', 'Leo', 'Rex', 'Sal'];
  return const [];
}

class ModelCatalog extends ChangeNotifier {
  ModelCatalog(this._prefs) {
    _loadCache();
  }

  final SharedPreferences _prefs;
  static const _cacheKey = 'model_catalog.v2';
  static const _cacheTimeKey = 'model_catalog.time.v2';
  static const gatewayModelsUrl = 'https://ai-gateway.vercel.sh/v1/models';
  static const modelsDevUrl = 'https://models.dev/api.json';
  static const openRouterModelsUrl = 'https://openrouter.ai/api/v1/models?output_modalities=all';
  static const openRouterVideoUrl = 'https://openrouter.ai/api/v1/videos/models';

  List<ModelInfo> models = [];
  bool loading = false;
  String? error;
  DateTime? fetchedAt;
  Map<String, ModelInfo> _byId = {};

  /// Models served by LM Studio (fetched live, never cached).
  List<ModelInfo> localModels = [];
  String? localError;

  List<ModelInfo> get textModels => [...localModels, ...models.where((m) => m.isText && !m.isVariant)];
  List<ModelInfo> get imageModels => models.where((m) => m.canMakeImages && !m.isVariant).toList();
  List<ModelInfo> get videoModels => models.where((m) => m.isVideo && m.textToVideo).toList();
  List<ModelInfo> get speechModels => models.where((m) => m.isSpeech).toList();

  List<ModelInfo> ofKind(ModelKind k) => switch (k) {
        ModelKind.text => textModels,
        ModelKind.image => imageModels,
        ModelKind.video => videoModels,
        ModelKind.speech => speechModels,
      };

  ModelInfo? byId(String id) {
    if (_byId.length != models.length + localModels.length) _byId = {for (final m in [...models, ...localModels]) m.id: m};
    return _byId[id];
  }

  /// Voices for a speech model, from the catalog or well-known defaults.
  List<String> voicesFor(String modelId) {
    final v = byId(modelId)?.voices ?? const [];
    return v.isNotEmpty ? v : defaultVoicesFor(modelId);
  }

  void _loadCache() {
    final raw = _prefs.getString(_cacheKey);
    if (raw == null) return;
    try {
      models = [for (final m in jsonDecode(raw) as List) ModelInfo.fromJson(Map<String, dynamic>.from(m))];
      final t = _prefs.getString(_cacheTimeKey);
      fetchedAt = t == null ? null : DateTime.tryParse(t);
    } catch (_) {}
  }

  /// Reads the models LM Studio offers, if a server address is set.
  Future<void> loadLocal() async {
    if (GatewayClient.normalizeLmUrl(GatewayClient.lmStudioUrl).isEmpty) {
      localModels = [];
      localError = null;
      _byId = {};
      notifyListeners();
      return;
    }
    try {
      final ids = await GatewayClient.lmStudioModels(GatewayClient.lmStudioUrl);
      localModels = [for (final id in ids) localModel(id)];
      localError = null;
    } catch (e) {
      localError = e.toString();
    }
    _byId = {};
    notifyListeners();
  }

  /// A free, local LM Studio model.
  static ModelInfo localModel(String id) => ModelInfo(
        id: '${AiRoute.lmPrefix}$id',
        name: id.split('/').last,
        provider: 'lm-studio',
        type: 'language',
        description: 'Runs on your own computer through LM Studio. Free and private.',
        inputPrice: 0,
        outputPrice: 0,
        openWeights: true,
      );

  Future<void> ensureLoaded() async {
    if (localModels.isEmpty) unawaited(loadLocal());
    final stale = fetchedAt == null || DateTime.now().difference(fetchedAt!) > const Duration(days: 3);
    if (models.isEmpty || stale) await refresh();
  }

  Future<String?> _get(String url, {Duration timeout = const Duration(seconds: 45)}) async {
    try {
      final r = await http.get(Uri.parse(url)).timeout(timeout);
      return r.statusCode == 200 ? utf8.decode(r.bodyBytes) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> refresh() async {
    if (loading) return;
    loading = true;
    error = null;
    notifyListeners();
    unawaited(loadLocal());
    try {
      final results = await Future.wait([_get(gatewayModelsUrl), _get(modelsDevUrl, timeout: const Duration(seconds: 60)), _get(openRouterModelsUrl), _get(openRouterVideoUrl)]);
      if (results[0] == null && results[2] == null) throw Exception('Could not reach the model lists. Check your connection.');
      final merged = await compute(mergeCatalogs, CatalogInput(results[0], results[1], results[2], results[3]));
      models = merged;
      _byId = {};
      fetchedAt = DateTime.now();
      await _prefs.setString(_cacheKey, jsonEncode(models.map((m) => m.toJson()).toList()));
      await _prefs.setString(_cacheTimeKey, fetchedAt!.toIso8601String());
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}

class CatalogInput {
  CatalogInput(this.gateway, this.modelsDev, this.openRouter, this.openRouterVideo);
  final String? gateway;
  final String? modelsDev;
  final String? openRouter;
  final String? openRouterVideo;
}

double? _num(dynamic v) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '');

double? _perMillion(dynamic v) {
  final d = _num(v);
  return d == null ? null : d * 1000000;
}

/// Some gateway image models publish prices by resolution instead of `image`.
double? catalogImagePrice(Map pricing) {
  final flat = double.tryParse('${pricing['image']}');
  if (flat != null) return flat;
  final sizes = pricing['image_dimension_quality_pricing'];
  if (sizes is! List) return null;
  final entries = sizes.whereType<Map>().toList();
  final selected = entries.where((e) => e['size'] == 'default').firstOrNull
      ?? entries.where((e) => e['size'] == '1K').firstOrNull;
  return selected == null ? null : double.tryParse('${selected['cost']}');
}

/// Cheapest silent price per second from Vercel's `video_duration_pricing`.
double? vercelVideoPrice(Map pricing) {
  final tiers = pricing['video_duration_pricing'];
  if (tiers is! List) return null;
  final prices = [
    for (final t in tiers.whereType<Map>())
      if (t['audio'] != true) ?_num(t['cost_per_second']),
  ];
  if (prices.isEmpty) return null;
  prices.sort();
  return prices.first;
}

/// Cheapest price per output second from OpenRouter's `pricing_skus`.
double? openRouterVideoPrice(Map skus) {
  final prices = <double>[];
  skus.forEach((k, v) {
    final key = k.toString();
    if (!key.contains('second') || key.contains('reference') || key.contains('input')) return;
    final n = _num(v);
    if (n == null) return;
    prices.add(key.startsWith('cents') ? n / 100 : n);
  });
  if (prices.isEmpty) return null;
  prices.sort();
  return prices.first;
}

List<ModelInfo> mergeCatalogs(CatalogInput input) {
  final out = <ModelInfo>[];
  if (input.gateway != null) out.addAll(_vercel(input.gateway!, input.modelsDev));
  if (input.openRouter != null) out.addAll(_openRouter(input.openRouter!, input.openRouterVideo));
  out.sort((a, b) {
    final r = a.router.index.compareTo(b.router.index);
    if (r != 0) return r;
    final p = a.provider.compareTo(b.provider);
    if (p != 0) return p;
    return (b.releaseDate ?? '').compareTo(a.releaseDate ?? '');
  });
  return out;
}

List<ModelInfo> _vercel(String gateway, String? modelsDev) {
  final gw = (jsonDecode(gateway)['data'] as List).cast<Map<String, dynamic>>();
  Map<String, dynamic> dev = {};
  if (modelsDev != null) {
    try {
      final all = jsonDecode(modelsDev) as Map<String, dynamic>;
      dev = Map<String, dynamic>.from(all['vercel']?['models'] ?? {});
    } catch (_) {}
  }
  final out = <ModelInfo>[];
  for (final m in gw) {
    final id = m['id'] as String;
    final type = (m['type'] ?? 'language') as String;
    if (!const {'language', 'image', 'video', 'speech'}.contains(type)) continue;
    final d = dev[id] as Map<String, dynamic>?;
    final pricing = (m['pricing'] as Map?) ?? {};
    final mod = (m['modalities'] as Map?) ?? d?['modalities'] as Map? ?? {};
    final tags = List<String>.from(m['tags'] ?? const []);
    final caps = (m['video_capabilities'] as Map?) ?? const {};
    final ops = List<String>.from(caps['supported_operations'] ?? const []);
    double? speech;
    if (type == 'speech') {
      speech = _num(pricing['speech_input_character_cost']);
      final outTok = _num(pricing['audio_output_token_cost'] ?? pricing['output']);
      // Token-priced voices: roughly two audio tokens per spoken character.
      speech ??= outTok == null ? null : outTok * 2 + (_num(pricing['input']) ?? 0) / 4;
    }
    out.add(ModelInfo(
      id: id,
      name: (d?['name'] ?? m['name'] ?? id).toString(),
      provider: (m['owned_by'] ?? id.split('/').first).toString(),
      type: type,
      description: (m['description'] ?? d?['description'] ?? '').toString(),
      contextWindow: (m['context_window'] as num?)?.toInt() ?? (d?['limit']?['context'] as num?)?.toInt(),
      maxOutput: (m['max_tokens'] as num?)?.toInt() ?? (d?['limit']?['output'] as num?)?.toInt(),
      inputPrice: type == 'speech' ? null : _perMillion(pricing['input']) ?? (d?['cost']?['input'] as num?)?.toDouble(),
      outputPrice: type == 'speech' ? null : _perMillion(pricing['output']) ?? (d?['cost']?['output'] as num?)?.toDouble(),
      imagePrice: catalogImagePrice(pricing),
      videoPrice: type == 'video' ? vercelVideoPrice(pricing) : null,
      speechPrice: speech,
      inputModalities: List<String>.from(mod['input'] ?? const ['text']),
      outputModalities: List<String>.from(mod['output'] ?? (type == 'image' ? const ['image'] : const ['text'])),
      reasoning: (d?['reasoning'] as bool?) ?? tags.contains('reasoning'),
      toolCall: (d?['tool_call'] as bool?) ?? tags.contains('tool-use'),
      openWeights: (d?['open_weights'] as bool?) ?? tags.contains('open-weights'),
      releaseDate: (d?['release_date'] ?? '').toString().isEmpty ? _released(m['released']) : d!['release_date'].toString(),
      knowledge: (d?['knowledge'] ?? m['knowledge'])?.toString(),
      tags: tags,
      durations: [for (final s in (caps['supported_durations_seconds'] as List? ?? const [])) (s as num).toInt()],
      resolutions: List<String>.from(caps['supported_resolutions'] ?? const []),
      textToVideo: type != 'video' || ops.isEmpty || ops.contains('text-to-video'),
    ));
  }
  return out;
}

String? _released(dynamic unix) {
  final n = _num(unix);
  if (n == null || n <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch((n * 1000).toInt(), isUtc: true).toIso8601String().substring(0, 10);
}

List<ModelInfo> _openRouter(String raw, String? videoRaw) {
  final list = (jsonDecode(raw)['data'] as List).cast<Map<String, dynamic>>();
  final video = <String, Map<String, dynamic>>{};
  if (videoRaw != null) {
    try {
      for (final v in (jsonDecode(videoRaw)['data'] as List).cast<Map<String, dynamic>>()) {
        video[v['id'] as String] = v;
      }
    } catch (_) {}
  }
  final out = <ModelInfo>[];
  for (final m in list) {
    final id = m['id'] as String;
    final arch = (m['architecture'] as Map?) ?? const {};
    final outMods = List<String>.from(arch['output_modalities'] ?? const ['text']);
    final inMods = List<String>.from(arch['input_modalities'] ?? const ['text']);
    final pricing = (m['pricing'] as Map?) ?? const {};
    final String type;
    if (outMods.contains('video')) {
      type = 'video';
    } else if (outMods.contains('speech')) {
      type = 'speech';
    } else if (outMods.contains('text')) {
      type = 'language';
    } else if (outMods.contains('image')) {
      type = 'image';
    } else {
      continue;
    }
    final prompt = _num(pricing['prompt']);
    final completion = _num(pricing['completion']);
    final imageOut = _num(pricing['image_output']);
    double? imagePrice;
    if (outMods.contains('image')) {
      final perToken = imageOut ?? completion;
      imagePrice = perToken == null ? null : perToken * 1290;
    }
    final v = video[id];
    final created = _num(m['created']);
    final name = (m['name'] ?? id).toString();
    out.add(ModelInfo(
      id: '${AiRoute.prefix}$id',
      name: name.contains(': ') ? name.substring(name.indexOf(': ') + 2) : name,
      provider: id.split('/').first,
      type: type,
      description: (m['description'] ?? '').toString(),
      contextWindow: (m['context_length'] as num?)?.toInt(),
      maxOutput: (m['top_provider']?['max_completion_tokens'] as num?)?.toInt(),
      inputPrice: type == 'language' || type == 'image' ? (prompt == null ? null : prompt * 1e6) : null,
      outputPrice: type == 'language' || type == 'image' ? (completion == null ? null : completion * 1e6) : null,
      imagePrice: imagePrice,
      videoPrice: v == null ? null : openRouterVideoPrice((v['pricing_skus'] as Map?) ?? const {}),
      speechPrice: type == 'speech' ? prompt : null,
      inputModalities: inMods,
      outputModalities: type == 'speech' ? const ['audio'] : outMods,
      reasoning: List.from(m['supported_parameters'] ?? const []).contains('reasoning'),
      toolCall: List.from(m['supported_parameters'] ?? const []).contains('tools'),
      openWeights: m['hugging_face_id'] != null && '${m['hugging_face_id']}'.isNotEmpty,
      releaseDate: created == null ? null : _released(created),
      voices: List<String>.from(m['supported_voices'] ?? const []),
      durations: [for (final s in (v?['supported_durations'] as List? ?? const [])) (s as num).toInt()],
      resolutions: List<String>.from(v?['supported_resolutions'] ?? const []),
    ));
  }
  return out;
}

/// With only an OpenRouter key, points every model setting at OpenRouter: the
/// same model when OpenRouter has it, otherwise a sensible default.
void adoptOpenRouterModels(SettingsController s, ModelCatalog? cat) {
  String map(String id, String fallback) {
    if (AiRoute.isOpenRouter(id)) return id;
    final same = '${AiRoute.prefix}$id';
    return cat?.byId(same) != null ? same : fallback;
  }

  s.textModel = map(s.textModel, '${AiRoute.prefix}anthropic/claude-sonnet-5.5');
  s.fastModel = map(s.fastModel, '${AiRoute.prefix}anthropic/claude-haiku-5.5');
  s.imageModel = map(s.imageModel, '${AiRoute.prefix}google/gemini-3.1-flash-lite-image');
  s.videoModel = map(s.videoModel, '${AiRoute.prefix}x-ai/grok-imagine-video-1.5-lite');
  s.speechModel = map(s.speechModel, '${AiRoute.prefix}google/gemini-3.8-flash-lite-tts');
  s.aiVoice = '';
}
