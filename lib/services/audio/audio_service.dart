import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../settings.dart';
import 'synth.dart';

Uint8List _renderMusicIsolate(String theme) => renderMusic(theme);
Uint8List _renderSfxIsolate(String name) => renderSfx(name);
Uint8List _renderAmbienceIsolate(String name) => renderAmbience(name);

/// Plays procedurally synthesized sound effects and ambient music.
class AudioService {
  AudioService(this.settings) {
    settings.addListener(_onSettings);
  }

  final SettingsController settings;
  final _sfxFiles = <String, Source>{};
  final _musicFiles = <String, Source>{};
  final _pending = <String, Future<Source?>>{};
  final List<AudioPlayer> _sfxPool = [];
  int _sfxIdx = 0;
  AudioPlayer? _music;
  AudioPlayer? _fadingOut;
  String? currentTheme;
  String? _wantedTheme;
  Directory? _dir;
  final bool _broken = false;

  Future<Directory?> _cacheDir() async {
    if (kIsWeb) return null;
    if (_dir != null) return _dir;
    try {
      final base = await getTemporaryDirectory();
      _dir = Directory('${base.path}${Platform.pathSeparator}grimoire_audio');
      if (!_dir!.existsSync()) _dir!.createSync(recursive: true);
    } catch (_) {
      _dir = null;
    }
    return _dir;
  }

  Future<Source?> _toSource(String key, Uint8List bytes) async {
    final dir = await _cacheDir();
    if (dir == null) {
      return UrlSource('data:audio/wav;base64,${base64Encode(bytes)}');
    }
    final f = File('${dir.path}${Platform.pathSeparator}$key.wav');
    await f.writeAsBytes(bytes, flush: true);
    return DeviceFileSource(f.path);
  }

  Future<Source?> _existing(String key) async {
    final dir = await _cacheDir();
    if (dir == null) return null;
    final f = File('${dir.path}${Platform.pathSeparator}$key.wav');
    if (f.existsSync() && f.lengthSync() > 100) return DeviceFileSource(f.path);
    return null;
  }

  Future<Source?> _sfxSource(String name) {
    final cached = _sfxFiles[name];
    if (cached != null) return Future.value(cached);
    return _pending.putIfAbsent('sfx_$name', () async {
      final ex = await _existing('sfx_v2_$name');
      final src = ex ?? await _toSource('sfx_v2_$name', await compute(_renderSfxIsolate, name));
      if (src != null) _sfxFiles[name] = src;
      _pending.remove('sfx_$name');
      return src;
    });
  }

  Future<Source?> _musicSource(String theme) {
    final cached = _musicFiles[theme];
    if (cached != null) return Future.value(cached);
    return _pending.putIfAbsent('music_$theme', () async {
      final ex = await _existing('music_v1_$theme');
      final src = ex ?? await _toSource('music_v1_$theme', await compute(_renderMusicIsolate, theme));
      if (src != null) _musicFiles[theme] = src;
      _pending.remove('music_$theme');
      return src;
    });
  }

  // ---------------------------------------------------------------- ambience

  final _ambFiles = <String, Source>{};
  AudioPlayer? _amb;
  String? currentAmbience;
  String? _wantedAmbience;
  double _ambDuck = 1;

  Future<Source?> _ambienceSource(String kind) {
    final cached = _ambFiles[kind];
    if (cached != null) return Future.value(cached);
    return _pending.putIfAbsent('amb_$kind', () async {
      final ex = await _existing('amb_v1_$kind');
      final src = ex ?? await _toSource('amb_v1_$kind', await compute(_renderAmbienceIsolate, kind));
      if (src != null) _ambFiles[kind] = src;
      _pending.remove('amb_$kind');
      return src;
    });
  }

  /// Loops a weather/place soundscape under the music, crossfading changes.
  Future<void> ambience(String? kind, {bool ducked = false}) async {
    _wantedAmbience = kind;
    _ambDuck = ducked ? 0.45 : 1;
    if (kind == null || !settings.ambienceEnabled || _broken) {
      await stopAmbience();
      return;
    }
    if (currentAmbience == kind && _amb != null) {
      await _amb!.setVolume(settings.ambienceVolume * _ambDuck);
      return;
    }
    try {
      final src = await _ambienceSource(kind);
      if (src == null || _wantedAmbience != kind) return;
      final next = AudioPlayer();
      await next.setReleaseMode(ReleaseMode.loop);
      await next.play(src, volume: 0);
      final prev = _amb;
      _amb = next;
      currentAmbience = kind;
      const steps = 16;
      var i = 0;
      Timer.periodic(const Duration(milliseconds: 90), (t) {
        i++;
        if (_gone[next] == true) {
          t.cancel();
          _release(prev);
          return;
        }
        _vol(next, settings.ambienceVolume * _ambDuck * i / steps);
        _vol(prev, settings.ambienceVolume * (1 - i / steps));
        if (i >= steps) {
          t.cancel();
          _release(prev);
        }
      });
    } catch (e) {
      debugPrint('ambience failed: $e');
    }
  }

  Future<void> stopAmbience() async {
    final a = _amb;
    _amb = null;
    currentAmbience = null;
    if (a == null) return;
    try {
      for (var i = 8; i >= 0; i--) {
        await a.setVolume(settings.ambienceVolume * i / 8);
        await Future.delayed(const Duration(milliseconds: 40));
      }
    } catch (_) {}
    _release(a);
  }

  /// Pre-renders the most common sounds in the background.
  Future<void> warmUp() async {
    for (final s in ['click', 'dice', 'dice_land', 'hit', 'miss', 'success', 'fail']) {
      await _sfxSource(s);
    }
  }

  Future<void> play(String name, {double volume = 1}) async {
    if (!settings.sfxEnabled || _broken) return;
    try {
      final src = await _sfxSource(name);
      if (src == null) return;
      if (_sfxPool.length < 5) {
        final p = AudioPlayer();
        await p.setReleaseMode(ReleaseMode.stop);
        _sfxPool.add(p);
      }
      final p = _sfxPool[_sfxIdx % _sfxPool.length];
      _sfxIdx++;
      await p.stop();
      await p.play(src, volume: (settings.sfxVolume * volume).clamp(0, 1));
    } catch (e) {
      debugPrint('sfx failed: $e');
    }
  }

  Future<void> music(String theme) async {
    _wantedTheme = theme;
    if (!settings.musicEnabled || _broken) return;
    if (currentTheme == theme && _music != null) return;
    try {
      final src = await _musicSource(theme);
      if (src == null || _wantedTheme != theme) return;
      final next = AudioPlayer();
      await next.setReleaseMode(ReleaseMode.loop);
      await next.play(src, volume: 0);
      final prev = _music;
      _music = next;
      currentTheme = theme;
      _crossfade(prev, next);
    } catch (e) {
      debugPrint('music failed: $e');
    }
  }

  /// Players already stopped and disposed; fade timers must leave them alone.
  final _gone = Expando<bool>();

  void _vol(AudioPlayer? p, double v) {
    if (p == null || _gone[p] == true) return;
    p.setVolume(v.clamp(0, 1)).catchError((Object _) {});
  }

  void _release(AudioPlayer? p) {
    if (p == null || _gone[p] == true) return;
    _gone[p] = true;
    p.stop().catchError((Object _) {}).whenComplete(() => p.dispose().catchError((Object _) {}));
  }

  void _crossfade(AudioPlayer? from, AudioPlayer to) {
    _release(_fadingOut);
    _fadingOut = from;
    const steps = 20;
    var i = 0;
    Timer.periodic(const Duration(milliseconds: 80), (t) {
      i++;
      final f = i / steps;
      if (_gone[to] == true) {
        t.cancel();
        return;
      }
      _vol(to, settings.musicVolume * f);
      _vol(from, settings.musicVolume * (1 - f));
      if (i >= steps) {
        t.cancel();
        _release(from);
        if (_fadingOut == from) _fadingOut = null;
      }
    });
  }

  Future<void> stopMusic() async {
    final m = _music;
    _music = null;
    currentTheme = null;
    if (m != null) {
      try {
        for (var i = 10; i >= 0; i--) {
          await m.setVolume(settings.musicVolume * i / 10);
          await Future.delayed(const Duration(milliseconds: 40));
        }
      } catch (_) {}
      _release(m);
    }
  }

  void _onSettings() {
    if (!settings.ambienceEnabled && _amb != null) {
      stopAmbience();
    } else if (settings.ambienceEnabled && _amb == null && _wantedAmbience != null) {
      ambience(_wantedAmbience);
    } else {
      _amb?.setVolume(settings.ambienceVolume * _ambDuck);
    }
    if (!settings.musicEnabled && _music != null) {
      stopMusic();
    } else if (settings.musicEnabled && _music == null && _wantedTheme != null) {
      music(_wantedTheme!);
    } else {
      _music?.setVolume(settings.musicVolume);
    }
  }

  void dispose() {
    settings.removeListener(_onSettings);
    for (final p in _sfxPool) {
      p.dispose();
    }
    _music?.dispose();
  }
}
