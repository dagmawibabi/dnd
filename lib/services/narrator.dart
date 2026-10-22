import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'ai/elevenlabs.dart';
import 'ai/gateway_client.dart';
import 'ai/model_catalog.dart';
import 'settings.dart';

/// A saved clip: its file, and what it says (when known).
class SavedClip {
  SavedClip({required this.file, required this.bytes, this.text = '', this.speaker = '', this.voice = '', this.story = '', this.storyId = '', this.at});
  final File file;
  final int bytes;
  final String text;
  final String speaker;
  final String voice;

  /// The story it was made for (empty: a sample, a preview, or made before
  /// clips were labelled).
  final String story;
  final String storyId;
  final DateTime? at;

  bool get isSample => file.path.split(Platform.pathSeparator).last.startsWith('sample_');
}

/// One piece of a passage being read: passages are split at sentences so the
/// first words play sooner and rewind/forward can step between them.
class _Line {
  _Line(this.text, this.speaker, this.passage, {this.voice, this.file});
  final String text;
  final String? speaker;

  /// A specific voice (previews), instead of the speaker's.
  final String? voice;

  /// A saved clip to play as is (replays of imported stories).
  final String? file;

  /// Lines from the same passage share this, for "restart".
  final int passage;
}

/// Reads the story aloud, with the device's text-to-speech or an AI voice model.
///
/// Every character gets their own voice: an assigned AI voice (matched to their
/// gender and kept for the whole story), or a stable pitch and rate shift of
/// the device voice. AI audio is cached on the device, so replays are free.
class Narrator extends ChangeNotifier {
  Narrator(this.settings, {this.catalog});

  final SettingsController settings;
  final ModelCatalog? catalog;
  FlutterTts? _tts;
  Completer<void>? _ttsDone;
  String? _ttsFailure;
  bool _ready = false;
  bool speaking = false;
  List<Map<String, String>> voices = [];
  AudioPlayer? _player;
  int _gen = 0;
  int _passages = 0;
  Completer<void>? _cut;

  /// Everything queued since the last stop, and which line is playing.
  final List<_Line> _items = [];
  int _pos = 0;
  bool _draining = false;

  /// Set by a jump (rewind, forward, restart) so the loop doesn't advance.
  bool _jumped = false;

  /// Paused by the player; [_resumeSignal] completes on resume.
  bool paused = false;
  Completer<void>? _resumeSignal;

  /// The current line was cut short by a pause (device voice) and replays.
  bool _interrupted = false;

  /// Whether the current line is AI audio (seekable) or the device voice.
  bool playingAudio = false;

  /// Set by the story on screen: the voice assigned to a speaker, if any.
  String? Function(String speaker)? voiceResolver;

  /// Set by the story on screen: a speaker's gender (female, male or empty).
  String Function(String speaker)? genderResolver;

  /// Set by the story on screen: remembers an automatic pick so a character
  /// keeps the same voice for the rest of the story.
  void Function(String speaker, String voice)? onAutoAssign;

  /// Set by the story on screen: voices other characters already use.
  Set<String> Function()? usedVoices;

  /// Usage bucket of the story on screen.
  Map<String, num>? usageTarget;

  /// The story on screen, so saved clips can say where they came from.
  String? storyTitle;
  String? storyId;

  /// Last AI voice error; the line falls back to the device voice.
  String? lastError;

  /// How many lines failed to play with the chosen voice (for a hint in the player).
  int errorCount = 0;

  /// The AI voice for the current line is being generated (not playing yet).
  bool loadingVoice = false;

  /// Text of the line being read, for "now playing" indicators.
  String? current;

  /// Who is speaking the current line (null for the narrator).
  String? currentSpeaker;

  /// Position in the queue, for "2 of 5".
  int get index => _pos;
  int get length => _items.length;

  double get speed => settings.narrationSpeed;

  /// Play narration on the media stream (the same volume as music). Samsung
  /// assistant/notification TTS streams are often muted while media is up.
  static final _voiceContext = AudioContext(
    android: const AudioContextAndroid(
      contentType: AndroidContentType.speech,
      usageType: AndroidUsageType.media,
      audioFocus: AndroidAudioFocus.gainTransientMayDuck,
    ),
  );

  Future<FlutterTts?> _init() async {
    if (_ready) return _tts;
    try {
      final t = FlutterTts();
      await t.awaitSpeakCompletion(false);
      await t.awaitSynthCompletion(false);
      t.setCompletionHandler(() => _finishTts());
      t.setCancelHandler(() => _finishTts());
      t.setErrorHandler((message) {
        _ttsFailure = '$message';
        _finishTts();
      });
      try {
        final engines = await t.getEngines;
        debugPrint('NARRATOR engines: $engines');
        if (engines is List &&
            engines.map((e) => '$e').contains('com.google.android.tts')) {
          await t.setEngine('com.google.android.tts');
        }
      } catch (e) {
        debugPrint('NARRATOR setEngine: $e');
      }
      try {
        await t.setLanguage('en-US');
      } catch (_) {}
      try {
        await t.setAudioAttributesForNavigation();
      } catch (_) {}
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
            if (v is Map)
              {'name': '${v['name']}', 'locale': '${v['locale'] ?? ''}'},
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

  /// Plays a voice's free sample clip (downloaded once, then played from the cache).
  Future<void> playSample(String url) async {
    await stop();
    try {
      final p = await _freshPlayer();
      final file = await _cachedSample(url);
      speaking = true;
      playingAudio = true;
      current = 'Voice sample';
      lastError = null;
      notifyListeners();
      final gen = _gen;
      await p.setVolume(1.0);
      await p.play(
        file != null ? DeviceFileSource(file.path) : UrlSource(url),
        ctx: _voiceContext,
        mode: PlayerMode.mediaPlayer,
      );
      unawaited(p.onPlayerComplete.first.then((_) {
        if (gen != _gen) return;
        speaking = false;
        playingAudio = false;
        current = null;
        notifyListeners();
      }));
    } catch (e) {
      speaking = false;
      playingAudio = false;
      current = null;
      lastError = e.toString();
      errorCount++;
      notifyListeners();
    }
  }

  Future<File?> _cachedSample(String url) async {
    final d = await _cacheDir();
    if (d == null) return null;
    final f = File(
      '${d.path}${Platform.pathSeparator}sample_${_hash(url).toRadixString(36)}.mp3',
    );
    if (f.existsSync()) return f;
    try {
      final r = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) return null;
      await f.writeAsBytes(r.bodyBytes, flush: true);
      return f;
    } catch (_) {
      return null;
    }
  }

  /// Voices for character pickers: (id, label, sample url).
  List<(String, String, String?)> get voiceOptions {
    if (settings.useElevenLabs)
      return [for (final v in elevenVoices) (v.id, v.name, v.previewUrl)];
    return [for (final v in aiVoices) (v, v, null)];
  }

  /// Built-in router voices described for casting.
  static const voiceTraits = {
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
    'verse': 'male, expressive',
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

  /// A voice's description: traits for built-in voices, labels for ElevenLabs.
  String describeVoice(String id) {
    final el = elevenVoices.where((v) => v.id == id).firstOrNull;
    if (el != null)
      return [el.traits, el.description].where((s) => s.isNotEmpty).join('. ');
    return voiceTraits[id] ?? '';
  }

  /// female, male, or '' when a voice doesn't say.
  String voiceGender(String id) {
    final el = elevenVoices.where((v) => v.id == id).firstOrNull;
    final t =
        (el != null
                ? (el.labels['gender'] ?? el.traits)
                : (voiceTraits[id] ?? ''))
            .toLowerCase();
    if (t.contains('female') || t.contains('woman')) return 'female';
    if (RegExp(r'\bmale\b').hasMatch(t) || t.contains('man')) return 'male';
    return '';
  }

  /// Voices with descriptions, for the AI to cast characters.
  List<(String, String)> get voiceChoices {
    if (settings.useElevenLabs) {
      return [
        for (final v in elevenVoices)
          (
            v.id,
            '${v.name}${v.traits.isEmpty ? '' : ' — ${v.traits}'}${v.description.isEmpty ? '' : '. ${v.description}'}',
          ),
      ];
    }
    return [
      for (final v in aiVoices)
        (v, '$v — ${voiceTraits[v] ?? 'unknown style'}'),
    ];
  }

  String labelOfVoice(String? id) {
    if (id == null) return 'Default';
    return elevenVoices.where((v) => v.id == id).firstOrNull?.name ?? id;
  }

  /// Voices a speech model said it accepts, learned from its errors (the
  /// catalog sometimes lists voices a model refuses).
  final Map<String, Set<String>> _accepted = {};

  /// AI voices offered by the selected speech model.
  List<String> get aiVoices {
    if (settings.useElevenLabs) return [for (final v in elevenVoices) v.id];
    final listed = catalog?.voicesFor(settings.speechModel) ?? defaultVoicesFor(settings.speechModel);
    final ok = _accepted[settings.speechModel];
    if (ok == null) return listed;
    final kept = listed.where(ok.contains).toList();
    return kept.isEmpty ? ok.toList() : kept;
  }

  String? get narratorVoice {
    if (settings.useElevenLabs) {
      if (settings.elevenVoice.isNotEmpty) return settings.elevenVoice;
      return elevenVoices.isEmpty ? null : elevenVoices.first.id;
    }
    final v = aiVoices;
    if (settings.aiVoice.isNotEmpty && (v.isEmpty || v.contains(settings.aiVoice))) return settings.aiVoice;
    return v.isEmpty ? null : v.first;
  }

  /// Reads "Input should be 'nova', 'shimmer' …" from a refused voice and
  /// remembers the voices the model takes. True when something was learned.
  bool learnVoices(Object error) {
    final text = '$error';
    if (!text.contains('voice')) return false;
    final m = RegExp(r'''(?:should be|must be one of|expected)[^\[\]]*?((?:'[^']+'(?:,\s*|\s+or\s+)?)+)''').firstMatch(text);
    if (m == null) return false;
    final names = {for (final x in RegExp(r"'([^']+)'").allMatches(m.group(1)!)) x.group(1)!};
    if (names.length < 2) return false;
    final before = _accepted[settings.speechModel];
    if (before != null && before.containsAll(names) && names.containsAll(before)) return false;
    _accepted[settings.speechModel] = names;
    debugPrint('NARRATOR learned voices for ${settings.speechModel}: $names');
    return true;
  }

  static int _hash(String s) => s.toLowerCase().codeUnits.fold<int>(
    7,
    (a, c) => (a * 31 + c) & 0x7fffffff,
  );

  /// A stable voice for someone without one: their gender's voices first,
  /// avoiding the narrator and (where possible) voices others already use.
  String? pickVoiceFor(
    String name, {
    String gender = '',
    Set<String> avoid = const {},
  }) {
    var pool = aiVoices.where((v) => v != narratorVoice).toList();
    if (pool.isEmpty) return narratorVoice;
    if (gender.isNotEmpty) {
      final matched = pool.where((v) => voiceGender(v) == gender).toList();
      if (matched.isNotEmpty) pool = matched;
    }
    final fresh = pool.where((v) => !avoid.contains(v)).toList();
    if (fresh.isNotEmpty) pool = fresh;
    return pool[_hash(name) % pool.length];
  }

  /// A character's AI voice: assigned, or a gender-matched pick that is then
  /// kept, so they sound the same from their first line to their last.
  String? aiVoiceFor(String? speaker) {
    if (speaker == null || speaker.isEmpty) return narratorVoice;
    final assigned = voiceResolver?.call(speaker);
    if (assigned != null && assigned.isNotEmpty && aiVoices.contains(assigned))
      return assigned;
    if (!settings.npcVoices) return narratorVoice;
    final pick = pickVoiceFor(
      speaker,
      gender: genderResolver?.call(speaker) ?? '',
      avoid: usedVoices?.call() ?? const {},
    );
    if (pick != null && pick != narratorVoice)
      onAutoAssign?.call(speaker, pick);
    return pick;
  }

  /// Per-speaker device voice: stable pitch/rate offsets derived from the name,
  /// higher for women and lower for men.
  (double pitch, double rate) _voiceFor(String? speaker) {
    if (speaker == null || speaker.isEmpty || !settings.npcVoices) {
      return (settings.ttsPitch, settings.ttsRate);
    }
    final h = _hash(speaker);
    final gender = genderResolver?.call(speaker) ?? '';
    final base = gender == 'female' ? 0.22 : (gender == 'male' ? -0.18 : 0.0);
    final pitchOff = base + ((h % 5) - 2) * 0.06;
    final rateOff = (((h >> 4) % 5) - 2) * 0.04;
    return (
      (settings.ttsPitch + pitchOff).clamp(0.5, 2.0),
      (settings.ttsRate + rateOff).clamp(0.1, 1.0),
    );
  }

  static String clean(String text) => text
      .replaceAll(RegExp(r'[*_#`>]'), '')
      .replaceAllMapped(RegExp(r'\[(.*?)\]\(.*?\)'), (m) => m[1] ?? '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Splits a passage at sentence ends. The first piece is short so speech
  /// starts quickly; later ones are longer for natural flow.
  static List<String> chunk(String text, {int first = 180, int rest = 420}) {
    final sentences = text
        .split(RegExp(r'(?<=[.!?…])\s+(?=["“A-Z0-9*])'))
        .where((s) => s.trim().isNotEmpty)
        .toList();
    final out = <String>[];
    var buf = StringBuffer();
    for (final s in sentences) {
      final limit = out.isEmpty ? first : rest;
      if (buf.isNotEmpty && buf.length + s.length + 1 > limit) {
        out.add(buf.toString().trim());
        buf = StringBuffer();
      }
      buf.write(buf.isEmpty ? s : ' $s');
    }
    if (buf.isNotEmpty) out.add(buf.toString().trim());
    return out.isEmpty ? [text] : out;
  }

  /// Queues text; narration and dialogue are read in order. [force] reads it
  /// even when automatic narration is off (tap-to-listen, previews).
  Future<void> say(String text, {String? speaker, bool force = false}) async {
    if (!settings.ttsEnabled && !force) return;
    final t = clean(text);
    if (t.isEmpty) return;
    debugPrint(
      'NARRATOR say cloud=${settings.useCloudVoice} engine=${settings.voiceEngine} n=${t.length}',
    );
    final passage = ++_passages;
    for (final piece in chunk(t)) {
      _items.add(_Line(piece, speaker, passage));
    }
    unawaited(_drain());
  }

  /// Stops whatever is playing and reads this line now.
  Future<void> speakNow(String text, {String? speaker}) async {
    await stop();
    // The previous drain must unwind; otherwise say() is ignored.
    for (var i = 0; i < 20 && _draining; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    _draining = false;
    await say(text, speaker: speaker, force: true);
  }

  /// Plays saved clips in order (a replayed passage), shown as [label].
  Future<void> playFiles(
    List<String> files, {
    String label = '',
    String? speaker,
  }) async {
    await stop();
    final passage = ++_passages;
    for (final f in files) {
      _items.add(_Line(label, speaker, passage, file: f));
    }
    unawaited(_drain());
  }

  /// The cached clips of a passage as it would be read now (null unless every
  /// piece is saved), so exports can carry the narration.
  Future<List<File>?> cachedClips(String text, {String? speaker}) async {
    if (!settings.useCloudVoice) return null;
    final d = await _cacheDir();
    if (d == null) return null;
    final out = <File>[];
    for (final piece in chunk(clean(text))) {
      final key = _keyFor(_Line(piece, speaker, 0));
      File? hit;
      for (final ext in const ['mp3', 'wav']) {
        final f = File('${d.path}${Platform.pathSeparator}$key.$ext');
        if (f.existsSync() && f.lengthSync() > 0) hit = f;
      }
      if (hit == null) return null;
      out.add(hit);
    }
    return out;
  }

  /// Reads [text] in the voice [id] without assigning it to anyone.
  Future<void> previewVoice(String id, String text) async {
    await stop();
    final t = clean(text);
    if (t.isEmpty) return;
    _items.add(_Line(t, null, ++_passages, voice: id));
    unawaited(_drain());
  }

  /// Stops whatever is playing and reads these passages in order (a scene, or
  /// the story from a passage onward). Cached audio replays for free.
  Future<void> playAll(List<(String text, String? speaker)> passages) async {
    await stop();
    for (final (text, speaker) in passages) {
      await say(text, speaker: speaker, force: true);
    }
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    final gen = _gen;
    try {
      while (gen == _gen && _pos < _items.length) {
        final line = _items[_pos];
        _jumped = false;
        _interrupted = false;
        current = line.text;
        currentSpeaker = line.speaker;
        speaking = true;
        notifyListeners();
        // Fetch the next piece while this one plays, so there is no gap.
        final audio = settings.useCloudVoice || line.file != null;
        if (settings.useCloudVoice) _prefetch(_pos + 1);
        var done = false;
        if (audio) {
          try {
            await _aiSpeak(line, gen);
            done = true;
            lastError = null;
          } catch (e) {
            // A voice the model doesn't take: switch to one it does and retry.
            var err = e;
            if (line.file == null && line.voice == null && learnVoices(e) && gen == _gen && !_jumped) {
              try {
                await _aiSpeak(line, gen);
                done = true;
                lastError = null;
              } catch (e2) {
                err = e2;
              }
            }
            if (!done) {
              lastError = err.toString();
              errorCount++;
              notifyListeners();
              debugPrint('AI voice failed, using the device voice: $err');
            }
          }
        }
        if (!done && gen == _gen && !_jumped) await _deviceSpeak(line, gen);
        if (gen != _gen) return;
        if (paused) await _waitForResume();
        if (gen != _gen) return;
        if (_jumped || _interrupted) continue;
        _pos++;
      }
    } finally {
      _draining = false;
      if (gen == _gen) {
        current = null;
        currentSpeaker = null;
        speaking = false;
        paused = false;
        playingAudio = false;
        notifyListeners();
      } else if (_pos < _items.length) {
        // Something new was queued while the old loop was winding down.
        unawaited(_drain());
      }
    }
  }

  Future<void> _waitForResume() async {
    final c = _resumeSignal ??= Completer<void>();
    await c.future;
  }

  void _finishTts() {
    final done = _ttsDone;
    if (done != null && !done.isCompleted) done.complete();
  }

  Future<void> _deviceSpeak(_Line line, int gen) async {
    final tts = await _init();
    if (tts == null) {
      lastError = 'This device has no text-to-speech voice. Install one in the system settings, or use an AI voice.';
      errorCount++;
      notifyListeners();
      return;
    }
    if (gen != _gen) return;
    try {
      final (pitch, rate) = _voiceFor(line.speaker);
      if (settings.ttsVoice.isNotEmpty) {
        if (voices.isEmpty) await loadVoices();
        final v = voices
            .where((v) => v['name'] == settings.ttsVoice)
            .firstOrNull;
        if (v != null) await tts.setVoice(v);
      }
      await tts.setPitch(pitch);
      await tts.setSpeechRate(rate);
      await tts.setVolume(1.0);
      if (gen != _gen) return;
      // Write a wav and play it on the media stream. Live speak() on Samsung
      // often completes with no audible output.
      if (!kIsWeb && await _synthAndPlay(tts, line, gen)) {
        lastError = null;
        return;
      }
      if (gen != _gen || _jumped) return;
      playingAudio = false;
      notifyListeners();
      var result = await _utter(tts, line.text);
      debugPrint('NARRATOR speak result=$result');
      if (result == 0 && gen == _gen && !_jumped) {
        try {
          await tts.stop();
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 80));
        if (gen != _gen || _jumped) return;
        result = await _utter(tts, line.text);
        debugPrint('NARRATOR speak retry=$result');
      }
      if (gen != _gen || _jumped) return;
      final pending = _ttsDone;
      if (pending != null && !pending.isCompleted) {
        await pending.future.timeout(
          Duration(seconds: 20 + line.text.length ~/ 8),
          onTimeout: () {},
        );
      }
      if (gen != _gen || _jumped) return;
      final failure = _ttsFailure;
      if (failure != null) throw StateError(failure);
      lastError = null;
    } catch (e) {
      _ttsDone = null;
      lastError = 'Device voice: $e';
      errorCount++;
      notifyListeners();
      debugPrint('TTS speak failed: $e');
    }
  }

  Future<bool> _synthAndPlay(FlutterTts tts, _Line line, int gen) async {
    Directory dir;
    try {
      dir = await getTemporaryDirectory();
    } catch (_) {
      return false;
    }
    final path =
        '${dir.path}${Platform.pathSeparator}narrate_${gen}_${line.passage}.wav';
    _ttsFailure = null;
    _ttsDone = Completer<void>();
    try {
      final result = await tts.synthesizeToFile(line.text, path, true);
      debugPrint('NARRATOR synth result=$result');
    } catch (e) {
      debugPrint('NARRATOR synth threw: $e');
      return false;
    }
    final pending = _ttsDone;
    if (pending != null && !pending.isCompleted) {
      await pending.future.timeout(
        Duration(seconds: 20 + line.text.length ~/ 8),
        onTimeout: () {},
      );
    }
    if (gen != _gen || _jumped) return true;
    if (_ttsFailure != null) {
      debugPrint('NARRATOR synth error: $_ttsFailure');
      return false;
    }
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final f = File(path);
    if (!f.existsSync() || f.lengthSync() < 100) {
      debugPrint(
        'NARRATOR synth empty file exists=${f.existsSync()} bytes=${f.existsSync() ? f.lengthSync() : 0}',
      );
      return false;
    }
    debugPrint('NARRATOR synth bytes=${f.lengthSync()}');
    await _playClip(DeviceFileSource(f.path), gen, line.text);
    return true;
  }

  Future<dynamic> _utter(FlutterTts tts, String text) async {
    _ttsFailure = null;
    _ttsDone = Completer<void>();
    return tts.speak(text);
  }

  // ------------------------------------------------------------------ cache

  Directory? _dirCache;

  /// Kept with the app's data (not the temp folder) so it survives restarts.
  Future<Directory?> _cacheDir() async {
    if (kIsWeb) return null;
    if (_dirCache != null) return _dirCache;
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}${Platform.pathSeparator}voice_cache');
    if (!d.existsSync()) d.createSync(recursive: true);
    return _dirCache = d;
  }

  final _memory = <String, Uint8List>{};
  final _inflight = <String, Future<Source>>{};

  String _keyFor(_Line line) {
    final voice = line.voice ?? aiVoiceFor(line.speaker);
    final style = line.speaker == null
        ? settings.voiceStyle
        : 'Speak as ${line.speaker}, a character in the story: natural, in character, expressive.';
    final model = settings.useElevenLabs
        ? 'el:${settings.elevenModel}'
        : settings.speechModel;
    return _hash('$model|$voice|$style|${line.text}').toRadixString(36);
  }

  /// The audio for a line: from the cache, an in-flight request, or the AI.
  Future<Source> _audioFor(_Line line) {
    final file = line.file;
    if (file != null)
      return Future.value(kIsWeb ? UrlSource(file) : DeviceFileSource(file));
    final key = _keyFor(line);
    // A block body: whenComplete waits on a returned future, and remove()
    // returns this very future, so `=> _inflight.remove(key)` never finished.
    return _inflight[key] ??= _load(line, key).whenComplete(() {
      _inflight.remove(key);
    });
  }

  Future<Source> _load(_Line line, String key) async {
    if (settings.useElevenLabs && elevenVoices.isEmpty)
      await loadElevenVoices();
    final voice = line.voice ?? aiVoiceFor(line.speaker);
    if (settings.useElevenLabs && (voice == null || voice.isEmpty))
      throw StateError(
        'No ElevenLabs voice available. Pick one in Settings → Voice.',
      );
    final style = line.speaker == null
        ? settings.voiceStyle
        : 'Speak as ${line.speaker}, a character in the story: natural, in character, expressive.';
    final d = await _cacheDir();
    if (d == null) {
      final hit = _memory[key];
      if (hit != null) return BytesSource(hit);
      final bytes = (await _fetch(line.text, voice, style)).bytes;
      if (bytes.length < 512) {
        throw StateError('The voice model returned an empty clip.');
      }
      _memory[key] = bytes;
      return BytesSource(bytes);
    }
    for (final ext in const ['mp3', 'wav']) {
      final f = File('${d.path}${Platform.pathSeparator}$key.$ext');
      if (f.existsSync() && f.lengthSync() > 0) return DeviceFileSource(f.path);
    }
    final media = await _fetch(line.text, voice, style);
    if (media.bytes.length < 512) {
      throw StateError('The voice model returned an empty clip.');
    }
    final f = File('${d.path}${Platform.pathSeparator}$key.${media.extension}');
    await f.writeAsBytes(media.bytes, flush: true);
    await _label(f, line, voice);
    return DeviceFileSource(f.path);
  }

  void _prefetch(int i) {
    if (i < 0 || i >= _items.length) return;
    unawaited(_audioFor(_items[i]).then((_) {}, onError: (_) {}));
  }

  static const _indexName = 'index.json';

  /// What saved clips say: file name -> {text, speaker, voice, story, id, at}.
  Future<Map<String, dynamic>> _index() async {
    final d = await _cacheDir();
    if (d == null) return {};
    final f = File('${d.path}${Platform.pathSeparator}$_indexName');
    if (!f.existsSync()) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(await f.readAsString()) as Map);
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeIndex(Map<String, dynamic> index) async {
    final d = await _cacheDir();
    if (d == null) return;
    try {
      await File('${d.path}${Platform.pathSeparator}$_indexName').writeAsString(jsonEncode(index));
    } catch (e) {
      debugPrint('Voice index not saved: $e');
    }
  }

  Future<void> _label(File f, _Line line, String? voice) async {
    final index = await _index();
    index[f.path.split(Platform.pathSeparator).last] = {
      't': line.text,
      if (line.speaker != null) 's': line.speaker,
      if (voice != null) 'v': voice,
      if (line.voice == null && (storyTitle ?? '').isNotEmpty) 'st': storyTitle,
      if (line.voice == null && (storyId ?? '').isNotEmpty) 'id': storyId,
      'at': DateTime.now().millisecondsSinceEpoch,
    };
    await _writeIndex(index);
  }

  /// Every saved clip with what it says, newest first.
  Future<List<SavedClip>> savedClips() async {
    final d = await _cacheDir();
    if (d == null) return const [];
    final index = await _index();
    final out = <SavedClip>[];
    for (final f in d.listSync().whereType<File>()) {
      final name = f.path.split(Platform.pathSeparator).last;
      if (name == _indexName) continue;
      final j = index[name] is Map ? Map<String, dynamic>.from(index[name] as Map) : const <String, dynamic>{};
      final at = j['at'] is num ? DateTime.fromMillisecondsSinceEpoch((j['at'] as num).toInt()) : f.lastModifiedSync();
      out.add(SavedClip(file: f, bytes: f.lengthSync(), text: '${j['t'] ?? ''}', speaker: '${j['s'] ?? ''}', voice: '${j['v'] ?? ''}', story: '${j['st'] ?? ''}', storyId: '${j['id'] ?? ''}', at: at));
    }
    out.sort((a, b) => (b.at ?? DateTime(0)).compareTo(a.at ?? DateTime(0)));
    return out;
  }

  /// Deletes one saved clip (it is made again, and charged again, if read).
  Future<void> deleteClip(SavedClip c) async {
    try {
      c.file.deleteSync();
    } catch (_) {}
    final index = await _index();
    if (index.remove(c.file.path.split(Platform.pathSeparator).last) != null) await _writeIndex(index);
    notifyListeners();
  }

  /// Number of cached clips and their total size in bytes.
  Future<(int, int)> cacheStats() async {
    final d = await _cacheDir();
    if (d == null)
      return (
        _memory.length,
        _memory.values.fold<int>(0, (n, b) => n + b.length),
      );
    var files = 0, bytes = 0;
    for (final f in d.listSync().whereType<File>()) {
      if (f.path.endsWith(_indexName)) continue;
      files++;
      bytes += f.lengthSync();
    }
    return (files, bytes);
  }

  Future<void> clearCache() async {
    await stop();
    _memory.clear();
    final d = await _cacheDir();
    if (d == null) return;
    for (final f in d.listSync().whereType<File>()) {
      try {
        f.deleteSync();
      } catch (_) {}
    }
    notifyListeners();
  }

  // ------------------------------------------------------------------ play

  Future<AudioPlayer> _freshPlayer() async {
    try {
      await _player?.stop();
    } catch (_) {}
    try {
      await _player?.dispose();
    } catch (_) {}
    return _player = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
  }

  Future<void> _playClip(Source source, int gen, String text) async {
    final p = await _freshPlayer();
    final finished = p.onPlayerComplete.first;
    final cut = _cut = Completer<void>();
    playingAudio = true;
    notifyListeners();
    await p.setVolume(1.0);
    await p.play(
      source,
      ctx: _voiceContext,
      mode: PlayerMode.mediaPlayer,
    );
    if (gen != _gen) {
      await p.stop();
      return;
    }
    try {
      debugPrint('NARRATOR play duration=${await p.getDuration()}');
    } catch (_) {}
    await Future.any([finished, cut.future]).timeout(
      Duration(seconds: 20 + text.length ~/ 8),
      onTimeout: () {},
    );
  }

  Future<void> _aiSpeak(_Line line, int gen) async {
    debugPrint(
      'NARRATOR ai fetch model=${settings.speechModel} voice=${line.voice ?? aiVoiceFor(line.speaker)}',
    );
    loadingVoice = true;
    notifyListeners();
    final Source source;
    try {
      source = await _audioFor(line).timeout(
        const Duration(seconds: 20),
        onTimeout: () =>
            throw TimeoutException('The AI voice took too long to answer.'),
      );
    } finally {
      loadingVoice = false;
      notifyListeners();
    }
    debugPrint('NARRATOR ai fetch done');
    if (_jumped || gen != _gen) return;
    await _playClip(source, gen, line.text);
  }

  Future<MediaBytes> _fetch(String text, String? voice, String style) async {
    if (settings.useElevenLabs) {
      final el = ElevenLabsClient(
        settings.elevenLabsKey,
        target: usageTarget ?? GatewayClient.usageTarget?.call(),
      );
      try {
        return MediaBytes(
          await el.speak(
            voiceId: voice!,
            text: text,
            model: settings.elevenModel,
          ),
          'audio/mpeg',
        );
      } finally {
        el.close();
      }
    }
    final client = GatewayClient(
      apiKey: settings.apiKey,
      category: 'voice',
      target: usageTarget,
      captureTarget: usageTarget == null,
    );
    try {
      return await client.speak(
        model: settings.speechModel,
        text: text,
        voice: voice,
        instructions: style,
      );
    } finally {
      client.close();
    }
  }

  // -------------------------------------------------------------- controls

  /// Ends the current line now; the loop then moves to [_pos].
  Future<void> _breakLine() async {
    if (!(_cut?.isCompleted ?? true)) _cut!.complete();
    _finishTts();
    try {
      await _tts?.stop();
    } catch (_) {}
    try {
      await _player?.stop();
    } catch (_) {}
  }

  void _wake() {
    final r = _resumeSignal;
    _resumeSignal = null;
    if (r != null && !r.isCompleted) r.complete();
  }

  Future<void> _jumpTo(int i) async {
    if (_items.isEmpty) return;
    _pos = i.clamp(0, _items.length - 1);
    _jumped = true;
    paused = false;
    _wake();
    await _breakLine();
    notifyListeners();
    if (!_draining) unawaited(_drain());
  }

  Future<void> pause() async {
    if (!speaking || paused) return;
    paused = true;
    _resumeSignal ??= Completer<void>();
    if (playingAudio) {
      try {
        await _player?.pause();
      } catch (_) {}
    } else {
      // The device voice can't resume mid-sentence: the line replays.
      _interrupted = true;
      try {
        await _tts?.stop();
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> resume() async {
    if (!paused) return;
    paused = false;
    if (playingAudio && !_interrupted) {
      try {
        await _player?.resume();
      } catch (_) {}
    }
    _wake();
    notifyListeners();
  }

  Future<void> togglePause() => paused ? resume() : pause();

  /// Moves [seconds] back or forward. AI audio seeks within the line and steps
  /// into the previous or next line at the edges; the device voice steps lines.
  Future<void> seekBy(int seconds) async {
    if (!speaking) return;
    final p = _player;
    if (playingAudio && p != null) {
      final pos = await p.getCurrentPosition() ?? Duration.zero;
      final dur = await p.getDuration();
      final target = pos + Duration(seconds: seconds);
      if (seconds < 0 && pos.inMilliseconds < 1500 && _pos > 0)
        return _jumpTo(_pos - 1);
      if (seconds > 0 && dur != null && target >= dur)
        return _jumpTo(_pos + 1 < _items.length ? _pos + 1 : _pos);
      await p.seek(target < Duration.zero ? Duration.zero : target);
      return;
    }
    if (seconds < 0) return _jumpTo(_pos);
    if (_pos + 1 < _items.length) return _jumpTo(_pos + 1);
    await stop();
  }

  Future<void> previous() => _jumpTo(_pos - 1);
  Future<void> next() async {
    if (_pos + 1 < _items.length) return _jumpTo(_pos + 1);
    await stop();
  }

  /// Back to the start of the passage being read.
  Future<void> restart() async {
    if (_items.isEmpty) return;
    final passage = _items[_pos.clamp(0, _items.length - 1)].passage;
    final first = _items.indexWhere((l) => l.passage == passage);
    await _jumpTo(first < 0 ? 0 : first);
  }

  /// Changes the reading speed, applied to the line playing now too.
  Future<void> setSpeed(double v) async {
    settings.update((s) => s.narrationSpeed = v.clamp(0.5, 2.5));
    if (playingAudio) {
      try {
        await _player?.setPlaybackRate(speed);
      } catch (_) {}
    } else if (speaking) {
      await _jumpTo(_pos);
    }
    notifyListeners();
  }

  /// Steps through common speeds: 1 → 1.25 → 1.5 → 1.75 → 2 → 0.75 → 1.
  Future<void> cycleSpeed() {
    const steps = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
    final i = steps.indexWhere((s) => (s - speed).abs() < 0.01);
    return setSpeed(steps[(i + 1) % steps.length]);
  }

  Future<void> stop() async {
    _gen++;
    _items.clear();
    _pos = 0;
    paused = false;
    _interrupted = false;
    _wake();
    await _breakLine();
    speaking = false;
    playingAudio = false;
    loadingVoice = false;
    current = null;
    currentSpeaker = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }
}
