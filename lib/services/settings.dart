import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';
import 'ai/gateway_client.dart';

enum ImageMode { procedural, ai }

enum Verbosity { brief, balanced, lavish }

/// Which features use the AI Gateway.
enum AiMode { none, text, images, both }

class SettingsController extends ChangeNotifier {
  SettingsController(this._prefs) {
    _load();
  }

  final SharedPreferences _prefs;
  static const _key = 'settings.v1';

  bool onboarded = false;
  String apiKey = '';
  String textModel = 'anthropic/claude-sonnet-5.5';
  String fastModel = 'anthropic/claude-haiku-5.5';
  String imageModel = 'google/gemini-3.1-flash-image';

  /// OpenRouter key; models from it are stored with an `or:` prefix.
  String openRouterKey = '';

  /// LM Studio server on this computer or network, e.g. http://192.168.1.20:1234.
  String lmStudioUrl = '';

  // Video (short clips instead of, or alongside, images)
  bool videoEnabled = false;
  String videoModel = 'bytedance/seedance-v1.0-pro-fast';
  bool videoScenes = true;
  bool videoEffects = false;
  int videoDuration = 4;
  String videoResolution = '480p';
  bool videoAudio = false;

  // AI voices
  /// 'device' (free, offline TTS) or 'ai' (a speech model).
  String voiceEngine = 'device';
  String speechModel = 'openai/tts-1';
  String aiVoice = '';
  String voiceStyle = 'A warm, dramatic storyteller with clear diction.';
  bool speakChatReplies = true;

  // ElevenLabs voices (voiceEngine == 'elevenlabs')
  String elevenLabsKey = '';
  String elevenModel = 'eleven_flash_v2_5';
  String elevenVoice = '';
  String elevenVoiceName = '';

  // Special-effect images for big moments
  bool aiEffects = false;
  Set<String> effectMoments = {'crit', 'boss', 'levelup', 'victory', 'romance', 'moment'};

  /// "Previously on…" recap when returning to a story after a while.
  bool aiRecaps = true;

  /// The AI retells each round of combat as a short dramatic passage.
  bool aiCombatNarration = false;

  // Per-item cost labels
  bool costPerMessage = false;
  bool costPerImage = false;
  bool costPerVideo = false;
  int adventureImageLimit = 0;
  int adventureVideoLimit = 0;
  ImageMode imageMode = ImageMode.procedural;
  bool aiText = true;
  bool aiPortraits = true;
  bool aiScenes = true;
  bool aiMaps = false;
  bool aiAutoImages = true;
  int dailyTokenLimit = 0;
  double dailyCostLimit = 0;
  int adventureTokenLimit = 0;
  double adventureCostLimit = 0;

  // Fine-grained AI features
  bool aiNpcChat = true;
  bool aiSummaries = true;
  bool aiCreator = true;
  bool aiPremises = true;
  bool aiNpcPortraits = true;
  bool aiCompanionPortraits = true;
  bool sfxEnabled = true;
  bool musicEnabled = true;
  double sfxVolume = 0.8;
  double musicVolume = 0.45;
  bool ambienceEnabled = true;

  /// What the home screen shows: 'dnd' or 'tales'.
  String homeMode = 'dnd';

  /// Monospace "typewriter" font in text adventures.
  bool taleTypewriterFont = false;

  /// New text adventures open in the terminal layout.
  bool taleTerminal = false;
  double ambienceVolume = 0.35;

  /// Saved dice formulas: name -> expression.
  List<(String, String)> diceFormulas = [('Attack', '1d20+5'), ('Fireball', '8d6'), ('Advantage', '2d20kh1'), ('Stats', '4d6kh3')];
  bool haptics = true;
  bool typewriter = true;

  /// Story text: 'serif', 'sans' or 'mono', and a size multiplier.
  String readingFont = 'serif';
  double readingScale = 1.0;
  double typeSpeed = 1.0;
  Verbosity verbosity = Verbosity.balanced;
  double temperature = 0.9;
  bool matureContent = false;
  bool streaming = true;
  bool autoRollEnemies = true;
  String playerName = '';
  String playerBio = '';

  /// Profile picture path (photo or AI); empty uses initials.
  String playerAvatar = '';

  // Usage & cost
  bool showUsage = false;

  // Voice narration (device text-to-speech)
  bool ttsEnabled = false;
  double ttsRate = 0.5;
  double ttsPitch = 1.0;
  String ttsVoice = '';
  bool npcVoices = true;

  // Accessibility
  double textScale = 1.0;
  bool reducedMotion = false;
  bool highContrast = false;

  // Difficulty defaults for new adventures
  bool defaultHardcore = false;
  bool defaultShowDcs = true;

  bool get hasVercelKey => apiKey.trim().isNotEmpty;
  bool get hasOpenRouterKey => openRouterKey.trim().isNotEmpty;
  bool get hasLmStudio => lmStudioUrl.trim().isNotEmpty;
  bool get hasApiKey => hasVercelKey || hasOpenRouterKey || hasLmStudio;

  /// Whether the key (or server address) for [model]'s router is present.
  bool canUse(String model) => switch (AiRoute.of(model)) {
        AiRouter.openRouter => hasOpenRouterKey,
        AiRouter.lmStudio => hasLmStudio,
        AiRouter.vercel => hasVercelKey,
      };
  bool get useAiVideo => videoEnabled && hasApiKey && canUse(videoModel);
  bool get useAiVoice => voiceEngine == 'ai' && hasApiKey && canUse(speechModel);
  bool get useElevenLabs => voiceEngine == 'elevenlabs' && elevenLabsKey.trim().isNotEmpty;

  /// Any cloud voice (AI router or ElevenLabs) instead of the device voice.
  bool get useCloudVoice => useAiVoice || useElevenLabs;
  bool get useAiEffects => useAiImages && aiEffects;
  bool effectOn(String moment) => (useAiEffects || (useAiVideo && videoEffects)) && effectMoments.contains(moment);
  bool get showAnyItemCost => costPerMessage || costPerImage || costPerVideo;
  bool get useAiImages => imageMode == ImageMode.ai && canUse(imageModel);
  bool get useAiText => aiText && canUse(textModel);
  bool get useAiNpcChat => useAiText && aiNpcChat;
  bool get useAiSummaries => useAiText && aiSummaries;
  bool get useAiCreator => useAiText && aiCreator;
  bool get useAiPremises => useAiText && aiPremises;
  bool get useAiPortraits => useAiImages && aiPortraits;
  bool get useAiNpcPortraits => useAiImages && aiNpcPortraits;
  bool get useAiCompanionPortraits => useAiImages && aiCompanionPortraits;
  bool get useAiScenes => useAiImages && aiScenes;

  AiMode get aiMode {
    if (!hasApiKey) return AiMode.none;
    final img = imageMode == ImageMode.ai;
    return aiText ? (img ? AiMode.both : AiMode.text) : (img ? AiMode.images : AiMode.none);
  }

  set aiMode(AiMode m) {
    aiText = m == AiMode.text || m == AiMode.both;
    imageMode = (m == AiMode.images || m == AiMode.both) ? ImageMode.ai : ImageMode.procedural;
  }

  void _load() {
    _loadJson();
    _apply();
  }

  void _apply() {
    GatewayClient.openRouterKey = openRouterKey;
    GatewayClient.lmStudioUrl = lmStudioUrl;
    T.readingFont = taleTypewriterFont && readingFont == 'serif' ? 'mono' : readingFont;
    T.readingScale = readingScale;
  }

  void _loadJson() {
    final raw = _prefs.getString(_key);
    if (raw == null) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      onboarded = j['onboarded'] ?? false;
      apiKey = j['apiKey'] ?? '';
      textModel = j['textModel'] ?? textModel;
      fastModel = j['fastModel'] ?? fastModel;
      imageModel = j['imageModel'] ?? imageModel;
      openRouterKey = j['orKey'] ?? '';
      lmStudioUrl = j['lmUrl'] ?? '';
      videoEnabled = j['video'] ?? false;
      videoModel = j['videoModel'] ?? videoModel;
      videoScenes = j['videoScenes'] ?? true;
      videoEffects = j['videoFx'] ?? false;
      videoDuration = (j['videoDur'] as num?)?.toInt() ?? 4;
      videoResolution = j['videoRes'] ?? '480p';
      videoAudio = j['videoAudio'] ?? false;
      voiceEngine = j['voiceEngine'] ?? 'device';
      speechModel = j['speechModel'] ?? speechModel;
      aiVoice = j['aiVoice'] ?? '';
      voiceStyle = j['voiceStyle'] ?? voiceStyle;
      speakChatReplies = j['speakChat'] ?? true;
      elevenLabsKey = j['elKey'] ?? '';
      elevenModel = j['elModel'] ?? elevenModel;
      elevenVoice = j['elVoice'] ?? '';
      elevenVoiceName = j['elVoiceName'] ?? '';
      aiEffects = j['fx'] ?? false;
      aiRecaps = j['recaps'] ?? true;
      aiCombatNarration = j['combatNarration'] ?? false;
      if (j['fxMoments'] is List) effectMoments = Set<String>.from(j['fxMoments']);
      costPerMessage = j['costMsg'] ?? false;
      costPerImage = j['costImg'] ?? false;
      costPerVideo = j['costVid'] ?? false;
      adventureImageLimit = (j['advImgLimit'] as num?)?.toInt() ?? 0;
      adventureVideoLimit = (j['advVidLimit'] as num?)?.toInt() ?? 0;
      imageMode = ImageMode.values.firstWhere((m) => m.name == j['imageMode'], orElse: () => ImageMode.procedural);
      aiText = j['aiText'] ?? true;
      aiPortraits = j['aiPortraits'] ?? true;
      aiScenes = j['aiScenes'] ?? true;
      aiMaps = j['aiMaps'] ?? false;
      aiAutoImages = j['aiAutoImages'] ?? true;
      dailyTokenLimit = (j['dailyTokenLimit'] as num?)?.toInt() ?? 0;
      dailyCostLimit = (j['dailyCostLimit'] as num?)?.toDouble() ?? 0;
      adventureTokenLimit = (j['adventureTokenLimit'] as num?)?.toInt() ?? 0;
      adventureCostLimit = (j['adventureCostLimit'] as num?)?.toDouble() ?? 0;
      aiNpcChat = j['aiNpcChat'] ?? true;
      aiSummaries = j['aiSummaries'] ?? true;
      aiCreator = j['aiCreator'] ?? true;
      aiPremises = j['aiPremises'] ?? true;
      aiNpcPortraits = j['aiNpcPortraits'] ?? true;
      aiCompanionPortraits = j['aiCompanionPortraits'] ?? true;
      sfxEnabled = j['sfx'] ?? true;
      musicEnabled = j['music'] ?? true;
      sfxVolume = (j['sfxVol'] ?? 0.8).toDouble();
      musicVolume = (j['musicVol'] ?? 0.45).toDouble();
      ambienceEnabled = j['amb'] ?? true;
      homeMode = j['home'] ?? 'dnd';
      taleTypewriterFont = j['taleMono'] ?? false;
      taleTerminal = j['taleTerm'] ?? false;
      ambienceVolume = (j['ambVol'] ?? 0.35).toDouble();
      if (j['dice'] is List) diceFormulas = [for (final d in j['dice'] as List) ((d['n'] ?? '').toString(), (d['e'] ?? '').toString())];
      haptics = j['haptics'] ?? true;
      typewriter = j['typewriter'] ?? true;
      readingFont = j['readFont'] ?? 'serif';
      readingScale = (j['readScale'] as num?)?.toDouble() ?? 1.0;
      typeSpeed = (j['typeSpeed'] ?? 1.0).toDouble();
      verbosity = Verbosity.values.firstWhere((v) => v.name == j['verbosity'], orElse: () => Verbosity.balanced);
      temperature = (j['temp'] ?? 0.9).toDouble();
      matureContent = j['mature'] ?? false;
      streaming = j['stream'] ?? true;
      autoRollEnemies = j['autoRoll'] ?? true;
      playerName = j['playerName'] ?? '';
      playerBio = j['playerBio'] ?? '';
      playerAvatar = j['playerAvatar'] ?? '';
      showUsage = j['showUsage'] ?? false;
      ttsEnabled = j['tts'] ?? false;
      ttsRate = (j['ttsRate'] ?? 0.5).toDouble();
      ttsPitch = (j['ttsPitch'] ?? 1.0).toDouble();
      ttsVoice = j['ttsVoice'] ?? '';
      npcVoices = j['npcVoices'] ?? true;
      textScale = (j['textScale'] ?? 1.0).toDouble();
      reducedMotion = j['reducedMotion'] ?? false;
      highContrast = j['highContrast'] ?? false;
      defaultHardcore = j['hardcore'] ?? false;
      defaultShowDcs = j['showDcs'] ?? true;
    } catch (_) {}
  }

  Future<void> _save() async {
    await _prefs.setString(
      _key,
      jsonEncode({
        'onboarded': onboarded,
        'apiKey': apiKey,
        'textModel': textModel,
        'fastModel': fastModel,
        'imageModel': imageModel,
        'orKey': openRouterKey,
        'lmUrl': lmStudioUrl,
        'video': videoEnabled,
        'videoModel': videoModel,
        'videoScenes': videoScenes,
        'videoFx': videoEffects,
        'videoDur': videoDuration,
        'videoRes': videoResolution,
        'videoAudio': videoAudio,
        'voiceEngine': voiceEngine,
        'speechModel': speechModel,
        'aiVoice': aiVoice,
        'voiceStyle': voiceStyle,
        'speakChat': speakChatReplies,
        'elKey': elevenLabsKey,
        'elModel': elevenModel,
        'elVoice': elevenVoice,
        'elVoiceName': elevenVoiceName,
        'fx': aiEffects,
        'recaps': aiRecaps,
        'combatNarration': aiCombatNarration,
        'fxMoments': effectMoments.toList(),
        'costMsg': costPerMessage,
        'costImg': costPerImage,
        'costVid': costPerVideo,
        'advImgLimit': adventureImageLimit,
        'advVidLimit': adventureVideoLimit,
        'imageMode': imageMode.name,
        'aiText': aiText,
        'aiPortraits': aiPortraits,
        'aiScenes': aiScenes,
        'aiMaps': aiMaps,
        'aiAutoImages': aiAutoImages,
        'dailyTokenLimit': dailyTokenLimit,
        'dailyCostLimit': dailyCostLimit,
        'adventureTokenLimit': adventureTokenLimit,
        'adventureCostLimit': adventureCostLimit,
        'aiNpcChat': aiNpcChat,
        'aiSummaries': aiSummaries,
        'aiCreator': aiCreator,
        'aiPremises': aiPremises,
        'aiNpcPortraits': aiNpcPortraits,
        'aiCompanionPortraits': aiCompanionPortraits,
        'sfx': sfxEnabled,
        'music': musicEnabled,
        'sfxVol': sfxVolume,
        'musicVol': musicVolume,
        'amb': ambienceEnabled,
        'home': homeMode,
        'taleMono': taleTypewriterFont,
        'taleTerm': taleTerminal,
        'ambVol': ambienceVolume,
        'dice': [for (final (n, e) in diceFormulas) {'n': n, 'e': e}],
        'haptics': haptics,
        'typewriter': typewriter,
        'readFont': readingFont,
        'readScale': readingScale,
        'typeSpeed': typeSpeed,
        'verbosity': verbosity.name,
        'temp': temperature,
        'mature': matureContent,
        'stream': streaming,
        'autoRoll': autoRollEnemies,
        'playerName': playerName,
        'playerBio': playerBio,
        'playerAvatar': playerAvatar,
        'showUsage': showUsage,
        'tts': ttsEnabled,
        'ttsRate': ttsRate,
        'ttsPitch': ttsPitch,
        'ttsVoice': ttsVoice,
        'npcVoices': npcVoices,
        'textScale': textScale,
        'reducedMotion': reducedMotion,
        'highContrast': highContrast,
        'hardcore': defaultHardcore,
        'showDcs': defaultShowDcs,
      }),
    );
  }

  void update(void Function(SettingsController s) change) {
    change(this);
    _apply();
    notifyListeners();
    _save();
  }
}
