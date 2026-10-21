import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Device speech recognition shared by every text box with a microphone.
/// Only one box listens at a time; starting another stops the first.
class VoiceInput extends ChangeNotifier {
  VoiceInput._();
  static final instance = VoiceInput._();

  final _stt = SpeechToText();
  bool? _ready;
  Object? _owner;
  void Function(String words, bool done)? _onText;
  String _heard = '';

  bool get listening => _owner != null;

  /// Microphone loudness, 0..1, while listening.
  double level = 0;

  /// The last problem in words people understand, or null.
  String? error;

  bool isListening(Object owner) => _owner == owner;

  Future<bool> _init() async {
    if (_ready == true) return true;
    try {
      _ready = await _stt.initialize(onError: _onError, onStatus: _onStatus);
    } catch (e) {
      debugPrint('speech init failed: $e');
      _ready = false;
    }
    return _ready!;
  }

  /// Starts transcribing for [owner]. [onText] gets the words so far, then
  /// once more with done = true. Returns false if speech isn't available.
  Future<bool> start(Object owner, void Function(String words, bool done) onText) async {
    if (_owner != null) await stop();
    error = null;
    if (!await _init()) {
      error = 'Voice input isn’t available. Allow microphone and speech access for DnD, or check that this device has speech recognition.';
      notifyListeners();
      return false;
    }
    _owner = owner;
    _onText = onText;
    _heard = '';
    level = 0;
    notifyListeners();
    try {
      await _stt.listen(
        onResult: _onResult,
        onSoundLevelChange: _onLevel,
        listenOptions: SpeechListenOptions(
          partialResults: true,
          listenMode: ListenMode.dictation,
          cancelOnError: true,
          autoPunctuation: true,
          listenFor: const Duration(seconds: 60),
          pauseFor: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      error = 'Couldn’t start listening: $e';
      _finish();
      return false;
    }
    return true;
  }

  /// Stops listening; the words heard so far are delivered as final.
  Future<void> stop() async {
    if (_owner == null) return;
    try {
      await _stt.stop();
    } catch (_) {}
    _finish();
  }

  void _onResult(SpeechRecognitionResult r) {
    if (_owner == null) return;
    _heard = r.recognizedWords;
    _onText?.call(_heard, false);
    if (r.finalResult) _finish();
  }

  void _onLevel(double db) {
    // Platforms report roughly -2..10 dB (Android) or 0..1 (iOS); normalise both.
    final v = db > 1 ? (db + 2) / 12 : db;
    level = v.clamp(0, 1).toDouble();
    notifyListeners();
  }

  void _onStatus(String status) {
    if ((status == SpeechToText.doneStatus || status == SpeechToText.notListeningStatus) && _owner != null) _finish();
  }

  void _onError(SpeechRecognitionError e) {
    error = switch (e.errorMsg) {
      'error_no_match' || 'error_speech_timeout' => 'Didn’t catch that. Try again a little closer to the microphone.',
      'error_permission' || 'error_insufficient_permissions' => 'Microphone access is off for DnD. Turn it on in your device settings.',
      'error_network' || 'error_network_timeout' || 'error_server' => 'Speech recognition needs a connection on this device.',
      'error_busy' => 'The speech recognizer is busy. Try again in a moment.',
      _ => 'Voice input stopped: ${e.errorMsg}',
    };
    _finish();
  }

  void _finish() {
    final cb = _onText;
    final heard = _heard;
    _owner = null;
    _onText = null;
    level = 0;
    notifyListeners();
    cb?.call(heard, true);
  }
}

/// Puts dictated words after what was already typed.
String joinDictation(String typed, String spoken) {
  final a = typed.trimRight();
  final b = spoken.trim();
  if (a.isEmpty) return b;
  if (b.isEmpty) return a;
  return '$a $b';
}
