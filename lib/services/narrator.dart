import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';

import 'ai/elevenlabs.dart';
import 'ai/gateway_client.dart';
import 'ai/model_catalog.dart';
import 'settings.dart';

/// Reads the story aloud, with the device's text-to-speech or an AI voice model.
///
/// Every character gets their own voice: an assigned AI voice, or a stable
/// pitch and rate shift of the device voice.
class Narrator extends ChangeNotifier {
  Narrator(this.settings, {this.catalog});

  final SettingsController settings;
  final ModelCatalog? catalog;
  FlutterTts? _tts;
  bool _ready = false;
  bool speaking = false;
  List<Map<String, String>> voices = [];
  final List<(String, String?)> _queue = [];
  AudioPlayer? _player;
  int _gen = 0;
  Completer<void>? _cut;

  /// Set by the story on screen: the voice assigned to a speaker, if any.
  String? Function(String speaker)? voiceResolver;

  /// Usage bucket of the story on screen.
  Map<String, num>? usageTarget;

  /// Last AI voice error; the line falls back to the device voice.
  String? lastError;

  /// Text of the line being read, for "now playing" indicators.
  String? current;

  Future<FlutterTts?> _init() async {
    if (_ready) return _tts;
    try {
      final t = FlutterTts();
      await t.awaitSpeakCompletion(true);
      t.setStartHandler(() {
        speaking = true;
        notifyListeners();
      });
      t.setCompletionHandler(() {
        speaking = false;
        notifyListeners();
      });
      t.setCancelHandler(() {
        speaking = false;
        notifyListeners();
      });
      t.setErrorHandler((_) {
        speaking = false;
        notifyListeners();
      });
      _tts = t;
      _ready = true;
    } catch (e) {
      debugPrint('TTS unavailable: $e');
    }
    return _tts;
  }

  Future<List<Map<String, String>>> loadVoices() async {
    final t = await _init();
    if (t == null) return [];
    try {
      final raw = await t.getVoices;
      if (raw is List) {
        voices = [
          for (final v in raw)
            if (v is Map) {'name': '${v['name']}', 'locale': '${v['locale'] ?? ''}'},
        ]..sort((a, b) => (a['locale'] ?? '').compareTo(b['locale'] ?? ''));
      }
    } catch (_) {}
    notifyListeners();
    return voices;
  }

  /// ElevenLabs voices in the user's library (loaded on demand).
  List<ElevenVoice> elevenVoices = [];
  bool elevenLoading = false;
  String? elevenError;

  Future<List<ElevenVoice>> loadElevenVoices({bool force = false}) async {
    if (!force && elevenVoices.isNotEmpty) return elevenVoices;
    if (settings.elevenLabsKey.trim().isEmpty) return const [];
    elevenLoading = true;
    elevenError = null;
    notifyListeners();
    final c = ElevenLabsClient(settings.elevenLabsKey);
    try {
      elevenVoices = await c.voices();
    } catch (e) {
      elevenError = e.toString();
    } finally {
      c.close();
      elevenLoading = false;
      notifyListeners();
    }
    return elevenVoices;
  }

  /// Plays a voice's free sample clip.
  Future<void> playSample(String url) async {
    await stop();
    try {
      final p = _player ??= AudioPlayer()..setReleaseMode(ReleaseMode.stop);
      await p.play(UrlSource(url));
    } catch (e) {
      lastError = e.toString();
      notifyListeners();
    }
  }

  /// Voices for character pickers: (id, label, sample url).
  List<(String, String, String?)> get voiceOptions {
    if (settings.useElevenLabs) return [for (final v in elevenVoices) (v.id, v.name, v.previewUrl)];
    return [for (final v in aiVoices) (v, v, null)];
  }

  /// Built-in router voices described for casting.
  static const _voiceTraits = {
    'alloy': 'neutral, balanced adult',
    'ash': 'male, clear and direct',
    'ballad': 'male, soft and lyrical',
    'coral': 'female, warm and friendly',
    'echo': 'male, resonant',
    'fable': 'male, British storyteller',
    'nova': 'female, bright and youthful',
    'onyx': 'male, deep and authoritative',
    'sage': 'female, calm and wise',
    'shimmer': 'female, soft and gentle',
    'Kore': 'female, firm',
    'Puck': 'male, upbeat and playful',
    'Charon': 'male, informative, low',
    'Zephyr': 'female, bright',
    'Fenrir': 'male, excitable, gruff',
    'Leda': 'female, youthful',
    'Orus': 'male, firm',
    'Aoede': 'female, breezy',
    'Callirrhoe': 'female, easy-going',
    'Enceladus': 'male, breathy, ominous',
    'en-US-Harper': 'female, American',
    'en-US-Ethan': 'male, American',
    'en-US-Ava': 'female, American, expressive',
    'en-US-Andrew': 'male, American, warm',
    'en-GB-Sonia': 'female, British',
    'en-GB-Ryan': 'male, British',
  };

  /// Voices with descriptions, for the AI to cast characters.
  List<(String, String)> get voiceChoices {
    if (settings.useElevenLabs) {
      return [for (final v in elevenVoices) (v.id, '${v.name}${v.traits.isEmpty ? '' : ' — ${v.traits}'}${v.description.isEmpty ? '' : '. ${v.description}'}')];
    }
    return [for (final v in aiVoices) (v, '$v — ${_voiceTraits[v] ?? 'unknown style'}')];
  }

  String labelOfVoice(String? id) {
    if (id == null) return 'Default';
    return elevenVoices.where((v) => v.id == id).firstOrNull?.name ?? id;
  }

  /// AI voices offered by the selected speech model.
  List<String> get aiVoices => settings.useElevenLabs ? [for (final v in elevenVoices) v.id] : (catalog?.voicesFor(settings.speechModel) ?? defaultVoicesFor(settings.speechModel));

  String? get narratorVoice {
    if (settings.useElevenLabs) {
      if (settings.elevenVoice.isNotEmpty) return settings.elevenVoice;
      return elevenVoices.isEmpty ? null : elevenVoices.first.id;
    }
    if (settings.aiVoice.isNotEmpty) return settings.aiVoice;
    final v = aiVoices;
    return v.isEmpty ? null : v.first;
  }

  static int _hash(String s) => s.toLowerCase().codeUnits.fold<int>(7, (a, c) => (a * 31 + c) & 0x7fffffff);

  /// A character's AI voice: assigned, or a stable pick that differs from the narrator.
  String? aiVoiceFor(String? speaker) {
    if (speaker == null || speaker.isEmpty) return narratorVoice;
    final assigned = voiceResolver?.call(speaker);
    if (assigned != null && assigned.isNotEmpty && aiVoices.contains(assigned)) return assigned;
    if (!settings.npcVoices) return narratorVoice;
    final pool = aiVoices.where((v) => v != narratorVoice).toList();
    if (pool.isEmpty) return narratorVoice;
    return pool[_hash(speaker) % pool.length];
  }

  /// Per-speaker device voice: stable pitch/rate offsets derived from the name.
  (double pitch, double rate) _voiceFor(String? speaker) {
    if (speaker == null || speaker.isEmpty || !settings.npcVoices) return (settings.ttsPitch, settings.ttsRate);
    final h = _hash(speaker);
    final pitchOff = ((h % 9) - 4) * 0.09; // -0.36..+0.36
    final rateOff = (((h >> 4) % 5) - 2) * 0.04;
    return ((settings.ttsPitch + pitchOff).clamp(0.5, 2.0), (settings.ttsRate + rateOff).clamp(0.1, 1.0));
  }

  static String clean(String text) => text
      .replaceAll(RegExp(r'[*_#`>]'), '')
      .replaceAll(RegExp(r'\[(.*?)\]\(.*?\)'), r'$1')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Queues text; narration and dialogue are read in order. [force] reads it
  /// even when automatic narration is off (tap-to-listen, previews).
  Future<void> say(String text, {String? speaker, bool force = false}) async {
    if (!settings.ttsEnabled && !force) return;
    final t = clean(text);
    if (t.isEmpty) return;
    _queue.add((t, speaker));
    if (_queue.length == 1) unawaited(_drain());
  }

  /// Stops whatever is playing and reads this line now.
  Future<void> speakNow(String text, {String? speaker}) async {
    await stop();
    await say(text, speaker: speaker, force: true);
  }

  Future<void> _drain() async {
    final gen = _gen;
    while (_queue.isNotEmpty && gen == _gen) {
      final (text, speaker) = _queue.first;
      current = text;
      speaking = true;
      notifyListeners();
      var done = false;
      if (settings.useCloudVoice) {
        try {
          await _aiSpeak(text, speaker);
          done = true;
          lastError = null;
        } catch (e) {
          lastError = e.toString();
          debugPrint('AI voice failed, using the device voice: $e');
        }
      }
      if (!done && gen == _gen) await _deviceSpeak(text, speaker);
      if (gen != _gen) return;
      if (_queue.isNotEmpty) _queue.removeAt(0);
    }
    current = null;
    speaking = false;
    notifyListeners();
  }

  Future<void> _deviceSpeak(String text, String? speaker) async {
    final tts = await _init();
    if (tts == null) return;
    try {
      final (pitch, rate) = _voiceFor(speaker);
      if (settings.ttsVoice.isNotEmpty) {
        final v = voices.where((v) => v['name'] == settings.ttsVoice).firstOrNull;
        if (v != null) await tts.setVoice(v);
      }
      await tts.setPitch(pitch);
      await tts.setSpeechRate(rate);
      await tts.setVolume(1.0);
      await tts.speak(text);
    } catch (e) {
      debugPrint('TTS speak failed: $e');
    }
  }

  Future<void> _aiSpeak(String text, String? speaker) async {
    if (settings.useElevenLabs && elevenVoices.isEmpty) await loadElevenVoices();
    final voice = aiVoiceFor(speaker);
    if (settings.useElevenLabs && (voice == null || voice.isEmpty)) throw StateError('No ElevenLabs voice available. Pick one in Settings → Voice.');
    final style = speaker == null ? settings.voiceStyle : 'Speak as $speaker, a character in the story: natural, in character, expressive.';
    final model = settings.useElevenLabs ? 'el:${settings.elevenModel}' : settings.speechModel;
    final key = _hash('$model|$voice|$style|$text').toRadixString(36);
    Uint8List? bytes;
    File? cached;
    if (!kIsWeb) {
      final dir = await getTemporaryDirectory();
      final d = Directory('${dir.path}${Platform.pathSeparator}voices');
      if (!d.existsSync()) d.createSync(recursive: true);
      for (final ext in const ['mp3', 'wav']) {
        final f = File('${d.path}${Platform.pathSeparator}$key.$ext');
        if (f.existsSync()) cached = f;
      }
      if (cached == null) {
        final media = await _fetch(text, voice, style);
        cached = File('${d.path}${Platform.pathSeparator}$key.${media.extension}');
        await cached.writeAsBytes(media.bytes, flush: true);
      }
    } else {
      bytes = (await _fetch(text, voice, style)).bytes;
    }
    final p = _player ??= AudioPlayer()..setReleaseMode(ReleaseMode.stop);
    final finished = p.onPlayerComplete.first;
    final cut = _cut = Completer<void>();
    await p.setVolume(1.0);
    await p.play(cached != null ? DeviceFileSource(cached.path) : BytesSource(bytes!));
    // Generous ceiling in case the completion event never arrives.
    await Future.any([finished, cut.future]).timeout(Duration(seconds: 20 + text.length ~/ 8), onTimeout: () {});
  }

  Future<MediaBytes> _fetch(String text, String? voice, String style) async {
    if (settings.useElevenLabs) {
      final el = ElevenLabsClient(settings.elevenLabsKey, target: usageTarget ?? GatewayClient.usageTarget?.call());
      try {
        return MediaBytes(await el.speak(voiceId: voice!, text: text, model: settings.elevenModel), 'audio/mpeg');
      } finally {
        el.close();
      }
    }
    final client = GatewayClient(apiKey: settings.apiKey, category: 'voice', target: usageTarget, captureTarget: usageTarget == null);
    try {
      return await client.speak(model: settings.speechModel, text: text, voice: voice, instructions: style);
    } finally {
      client.close();
    }
  }

  Future<void> stop() async {
    _gen++;
    _queue.clear();
    if (!(_cut?.isCompleted ?? true)) _cut!.complete();
    try {
      await _tts?.stop();
    } catch (_) {}
    try {
      await _player?.stop();
    } catch (_) {}
    speaking = false;
    current = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }
}
