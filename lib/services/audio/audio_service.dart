import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../settings.dart';
import '../studio.dart';
import 'synth.dart';

Uint8List _renderMusicIsolate(String theme) => renderMusic(theme);
Uint8List _renderMusicSpecIsolate(MusicSpec spec) => renderMusicSpec(spec);
Uint8List _renderSfxIsolate(String name) => renderSfx(name);
Uint8List _renderSfxSpecIsolate(SfxSpec spec) => renderSfxSpec(spec);
Uint8List _repitchIsolate((Uint8List, double) a) => repitchWav(a.$1, a.$2);
Uint8List _renderAmbienceIsolate(String name) => renderAmbience(name);

/// Plays procedurally synthesized sound effects and ambient music.
class AudioService {
  AudioService(this.settings) {
    settings.addListener(_onSettings);
  }

  final SettingsController settings;

  // The app mixes its own beds and effects. They must not request Android
  // audio focus individually or they pause narration whenever a sound starts.
  static final _bedContext = AudioContext(
    android: const AudioContextAndroid(
      contentType: AndroidContentType.music,
      usageType: AndroidUsageType.game,
      audioFocus: AndroidAudioFocus.none,
    ),
  );
  static final _effectContext = AudioContext(
    android: const AudioContextAndroid(
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.game,
      audioFocus: AndroidAudioFocus.none,
    ),
  );

  /// Player-made music and sounds that replace the game's own.
  StudioStore? get studio => _studio;
  StudioStore? _studio;
  set studio(StudioStore? s) {
    _studio?.removeListener(_onStudio);
    _studio = s;
    s?.addListener(_onStudio);
  }

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

  /// A studio track: an imported file plays as is, a composed one is rendered.
  Future<Source?> _trackSource(StudioTrack t) {
    if (t.isFile) return Future.value(DeviceFileSource(t.file!));
    return _specMusicSource(t.spec ?? const MusicSpec());
  }

  Future<Source?> _specMusicSource(MusicSpec spec) {
    final key = 'mc_${spec.key}';
    final cached = _musicFiles[key];
    if (cached != null) return Future.value(cached);
    return _pending.putIfAbsent(key, () async {
      final ex = await _existing('music_$key');
      final src = ex ?? await _toSource('music_$key', await compute(_renderMusicSpecIsolate, spec));
      if (src != null) _musicFiles[key] = src;
      _pending.remove(key);
      return src;
    });
  }

  /// A game sound with the player's changes: their own sound, pitch and volume.
  /// Imported files can't be re-rendered, so their pitch is a playback rate.
  Future<(Source?, double)> _playSource(String name) async {
    final custom = _studio?.soundFor(name);
    final pitch = _studio?.tweakFor(name).pitch ?? 1;
    if (custom != null && custom.isFile) return (DeviceFileSource(custom.file!), pitch);
    return (await _renderedSource(name, custom?.spec, pitch), 1.0);
  }

  Future<Source?> _renderedSource(String name, SfxSpec? custom, double pitch) {
    if (custom == null && (pitch - 1).abs() < 0.01) return _sfxSource(name);
    final key = 'sx_${custom?.key ?? name}_${(pitch * 100).round()}';
    final cached = _sfxFiles[key];
    if (cached != null) return Future.value(cached);
    return _pending.putIfAbsent(key, () async {
      final ex = await _existing(key);
      Source? src = ex;
      if (src == null) {
        var bytes = custom == null ? await compute(_renderSfxIsolate, name) : await compute(_renderSfxSpecIsolate, custom);
        if ((pitch - 1).abs() >= 0.01) bytes = await compute(_repitchIsolate, (bytes, pitch));
        src = await _toSource(key, bytes);
      }
      if (src != null) _sfxFiles[key] = src;
      _pending.remove(key);
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
    if (currentAmbience == kind && _amb != null && _ambKey == _ambienceKey(kind)) {
      await _amb!.setVolume(settings.ambienceVolume * _ambDuck);
      return;
    }
    try {
      final custom = _studio?.ambienceFor(kind);
      _ambKey = custom?.id ?? kind;
      final src = custom != null ? await _trackSource(custom) : await _ambienceSource(kind);
      if (src == null || _wantedAmbience != kind) return;
      final next = AudioPlayer();
      await next.setReleaseMode(ReleaseMode.loop);
      await next.play(src, volume: 0, ctx: _bedContext);
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
    volume *= _studio?.tweakFor(name).volume ?? 1;
    try {
      final (src, rate) = await _playSource(name);
      if (src == null) return;
      if (_sfxPool.length < 5) {
        final p = AudioPlayer();
        await p.setReleaseMode(ReleaseMode.stop);
        _sfxPool.add(p);
      }
      final p = _sfxPool[_sfxIdx % _sfxPool.length];
      _sfxIdx++;
      await p.stop();
      await p.play(src, volume: (settings.sfxVolume * volume).clamp(0, 1), ctx: _effectContext);
      if (rate != 1 || _rated[p] == true) {
        _rated[p] = rate != 1;
        await p.setPlaybackRate(rate);
      }
    } catch (e) {
      debugPrint('sfx failed: $e');
    }
  }

  /// Plays [theme]'s music: the game's loop, or one of the player's tracks.
  /// With several tracks, a song that ends moves on to another.
  Future<void> music(String theme, {bool force = false}) async {
    _wantedTheme = theme;
    if (!settings.musicEnabled || _broken) return;
    final playlist = _studio?.tracksFor(theme) ?? const <StudioTrack>[];
    final still = _chosen == null ? playlist.isEmpty : playlist.any((t) => t.id == _chosen!.id);
    if (currentTheme == theme && _music != null && still && !force) return;
    try {
      final others = playlist.where((t) => t.id != _chosen?.id).toList();
      final pick = playlist.isEmpty ? null : (others.isEmpty ? playlist : others)[_rng.nextInt((others.isEmpty ? playlist : others).length)];
      final src = pick == null ? await _musicSource(theme) : await _trackSource(pick);
      _chosen = pick;
      if (src == null || _wantedTheme != theme) return;
      final next = AudioPlayer();
      final moveOn = pick != null && pick.isFile && playlist.length > 1;
      await next.setReleaseMode(moveOn ? ReleaseMode.release : ReleaseMode.loop);
      if (moveOn) {
        next.onPlayerComplete.first.then((_) {
          if (_music == next && _wantedTheme == theme) music(theme, force: true);
        }).catchError((Object _) {});
      }
      await next.play(src, volume: 0, ctx: _bedContext);
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

  StudioTrack? _chosen;
  final _rated = Expando<bool>();
  String? _ambKey;
  final _rng = math.Random();
  String _ambienceKey(String kind) {
    final list = _studio?.ambienceSlots[kind];
    return list == null || list.isEmpty ? kind : (list.contains(_ambKey) ? _ambKey! : list.first);
  }

  void _onStudio() {
    if (_preview != null) return;
    final t = _wantedTheme;
    if (t != null && _music != null) {
      final playlist = _studio?.tracksFor(t) ?? const <StudioTrack>[];
      final still = _chosen == null ? playlist.isEmpty : playlist.any((x) => x.id == _chosen!.id);
      if (!still) music(t, force: true);
    }
    final a = _wantedAmbience;
    if (a != null && _amb != null && _ambKey != _ambienceKey(a)) {
      currentAmbience = null;
      ambience(a);
    }
  }

  /// Plays an imported file once (sounds) or on loop (music and ambience).
  Future<void> previewFile(String path, {bool loop = false, double volume = 0.9}) async {
    if (loop) {
      await stopPreview(resume: false);
      if (_music != null) {
        _resumeMusic = true;
        await stopMusic();
      }
    }
    try {
      final p = AudioPlayer();
      await p.setReleaseMode(loop ? ReleaseMode.loop : ReleaseMode.release);
      if (loop) {
        _preview = p;
      } else {
        p.onPlayerComplete.first.then((_) => p.dispose()).catchError((Object _) {});
      }
      await p.play(DeviceFileSource(path), volume: volume, ctx: loop ? _bedContext : _effectContext);
    } catch (e) {
      debugPrint('preview failed: $e');
    }
  }

  // ------------------------------------------------------------- studio previews

  AudioPlayer? _preview;
  bool _resumeMusic = false;

  /// Renders a studio sound to WAV bytes (for previews, waveforms and saving).
  Future<Uint8List> renderSound({String? name, SfxSpec? spec, double pitch = 1}) async {
    var bytes = spec != null ? await compute(_renderSfxSpecIsolate, spec) : await compute(_renderSfxIsolate, name ?? 'click');
    if ((pitch - 1).abs() >= 0.01) bytes = await compute(_repitchIsolate, (bytes, pitch));
    return bytes;
  }

  Future<Uint8List> renderTrack(MusicSpec spec) => compute(_renderMusicSpecIsolate, spec);
  Future<Uint8List> renderSoundscape(String kind) => compute(_renderAmbienceIsolate, kind);

  /// Plays a sound once in the studio, even when game sounds are off.
  Future<void> previewSound(Uint8List wav, {double volume = 1}) async {
    try {
      final p = AudioPlayer();
      await p.setReleaseMode(ReleaseMode.release);
      p.onPlayerComplete.first.then((_) => p.dispose()).catchError((Object _) {});
      await p.play(await _toSource('preview_${wav.length}_${wav.hashCode}', wav) ?? BytesSource(wav), volume: (settings.sfxVolume.clamp(0.3, 1) * volume).clamp(0, 1).toDouble(), ctx: _effectContext);
    } catch (e) {
      debugPrint('preview failed: $e');
    }
  }

  /// Loops a track or soundscape in the studio; game music pauses meanwhile.
  Future<void> previewLoop(Uint8List wav, {double volume = 0.8}) async {
    await stopPreview(resume: false);
    if (_music != null) {
      _resumeMusic = true;
      await stopMusic();
    }
    try {
      final p = AudioPlayer();
      _preview = p;
      await p.setReleaseMode(ReleaseMode.loop);
      await p.play(await _toSource('preview_loop_${wav.length}_${wav.hashCode}', wav) ?? BytesSource(wav), volume: volume, ctx: _bedContext);
    } catch (e) {
      debugPrint('preview failed: $e');
    }
  }

  bool get previewing => _preview != null;

  Future<void> stopPreview({bool resume = true}) async {
    final p = _preview;
    _preview = null;
    if (p != null) _release(p);
    if (resume && _resumeMusic) {
      _resumeMusic = false;
      final t = _wantedTheme;
      if (t != null) await music(t);
    }
  }

  void dispose() {
    settings.removeListener(_onSettings);
    _studio?.removeListener(_onStudio);
    _preview?.dispose();
    for (final p in _sfxPool) {
      p.dispose();
    }
    _music?.dispose();
  }
}
