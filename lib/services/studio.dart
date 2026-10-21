import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/character.dart' show newId;
import 'audio/synth.dart';

/// A music or ambience loop: composed in the studio, or an imported file.
class StudioTrack {
  StudioTrack({String? id, required this.name, this.spec, this.file}) : id = id ?? newId();
  final String id;
  String name;
  MusicSpec? spec;

  /// An audio file the player added from their device.
  final String? file;
  bool get isFile => file != null;

  /// Stable id for caching what plays.
  String get key => file != null ? 'f_$id' : (spec ?? const MusicSpec()).key;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, if (spec != null) 'spec': spec!.toJson(), if (file != null) 'file': file};
  factory StudioTrack.fromJson(Map<String, dynamic> j) => StudioTrack(
        id: j['id'],
        name: j['name'] ?? 'Track',
        spec: j['spec'] is Map ? MusicSpec.fromJson(Map<String, dynamic>.from(j['spec'])) : null,
        file: j['file'],
      );
}

/// A sound effect: designed in the studio, or an imported file.
class StudioSound {
  StudioSound({String? id, required this.name, this.spec, this.file}) : id = id ?? newId();
  final String id;
  String name;
  SfxSpec? spec;
  final String? file;
  bool get isFile => file != null;
  String get key => file != null ? 'f_$id' : (spec ?? const SfxSpec()).key;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, if (spec != null) 'spec': spec!.toJson(), if (file != null) 'file': file};
  factory StudioSound.fromJson(Map<String, dynamic> j) => StudioSound(
        id: j['id'],
        name: j['name'] ?? 'Sound',
        spec: j['spec'] is Map ? SfxSpec.fromJson(Map<String, dynamic>.from(j['spec'])) : null,
        file: j['file'],
      );
}

/// A picture the player added from their gallery or files.
class StudioImage {
  StudioImage({String? id, required this.name, required this.path}) : id = id ?? newId();
  final String id;
  String name;
  final String path;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'path': path};
  factory StudioImage.fromJson(Map<String, dynamic> j) => StudioImage(id: j['id'], name: j['name'] ?? 'Image', path: j['path'] ?? '');
}

/// Volume and pitch adjustments for one of the game's sounds.
class SfxTweak {
  const SfxTweak({this.volume = 1, this.pitch = 1});
  final double volume;

  /// Playback rate: 2 is an octave up.
  final double pitch;
  bool get isDefault => (volume - 1).abs() < 0.01 && (pitch - 1).abs() < 0.01;

  Map<String, dynamic> toJson() => {'v': volume, 'p': pitch};
  factory SfxTweak.fromJson(Map<String, dynamic> j) => SfxTweak(volume: ((j['v'] ?? 1) as num).toDouble(), pitch: ((j['p'] ?? 1) as num).toDouble());
}

/// A favourite piece from the art studio: the painter and its settings.
class ArtPiece {
  ArtPiece({String? id, required this.kind, required this.name, required this.params, DateTime? created})
      : id = id ?? newId(),
        created = created ?? DateTime.now();
  final String id;

  /// scene | portrait | creature | map
  final String kind;
  String name;
  final Map<String, dynamic> params;
  final DateTime created;

  Map<String, dynamic> toJson() => {'id': id, 'k': kind, 'n': name, 'p': params, 'c': created.millisecondsSinceEpoch};
  factory ArtPiece.fromJson(Map<String, dynamic> j) => ArtPiece(
        id: j['id'],
        kind: j['k'] ?? 'scene',
        name: j['n'] ?? '',
        params: Map<String, dynamic>.from(j['p'] ?? const {}),
        created: DateTime.fromMillisecondsSinceEpoch(j['c'] ?? 0),
      );
}

Map<String, List<String>> _slots(Object? raw) => {
      for (final e in (raw as Map? ?? const {}).entries)
        e.key as String: e.value is List ? [for (final v in e.value as List) v as String] : [e.value as String],
    };

/// Everything players make or bring into the art, music and sound-effects
/// studios, and where in the game it is used instead of the built-in media.
class StudioStore extends ChangeNotifier {
  StudioStore(this._prefs) {
    _load();
  }

  final SharedPreferences? _prefs;
  static const _key = 'studio.v1';

  List<StudioTrack> tracks = [];

  /// Game theme (combat, tavern…) -> tracks that play instead, as a playlist.
  Map<String, List<String>> musicSlots = {};

  /// Soundscape (rain, cave…) -> tracks that loop instead.
  Map<String, List<String>> ambienceSlots = {};
  List<StudioSound> sounds = [];

  /// Game sound (dice, hit…) -> sounds that play instead, picked at random.
  Map<String, List<String>> sfxSlots = {};
  Map<String, SfxTweak> tweaks = {};
  List<ArtPiece> art = [];
  List<StudioImage> images = [];

  /// Scene place (forest, tavern…) -> the player's pictures for it.
  Map<String, List<String>> sceneImages = {};

  /// Map kind (overworld, town, dungeon) -> the player's pictures for it.
  Map<String, List<String>> mapImages = {};

  /// In-memory store for tests.
  factory StudioStore.memory() => StudioStore(null);

  void _load() {
    final raw = _prefs?.getString(_key);
    if (raw == null) return;
    try {
      fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('studio load failed: $e');
    }
  }

  void fromJson(Map<String, dynamic> j) {
    tracks = [for (final t in (j['tracks'] as List? ?? const [])) StudioTrack.fromJson(Map<String, dynamic>.from(t))];
    musicSlots = _slots(j['musicSlots']);
    ambienceSlots = _slots(j['ambienceSlots']);
    sounds = [for (final s in (j['sounds'] as List? ?? const [])) StudioSound.fromJson(Map<String, dynamic>.from(s))];
    sfxSlots = _slots(j['sfxSlots']);
    tweaks = {for (final e in (j['tweaks'] as Map? ?? const {}).entries) e.key as String: SfxTweak.fromJson(Map<String, dynamic>.from(e.value))};
    art = [for (final a in (j['art'] as List? ?? const [])) ArtPiece.fromJson(Map<String, dynamic>.from(a))];
    images = [for (final i in (j['images'] as List? ?? const [])) StudioImage.fromJson(Map<String, dynamic>.from(i))];
    sceneImages = _slots(j['sceneImages']);
    mapImages = _slots(j['mapImages']);
  }

  Map<String, dynamic> toJson() => {
        'tracks': tracks.map((t) => t.toJson()).toList(),
        'musicSlots': musicSlots,
        'ambienceSlots': ambienceSlots,
        'sounds': sounds.map((s) => s.toJson()).toList(),
        'sfxSlots': sfxSlots,
        'tweaks': {for (final e in tweaks.entries) if (!e.value.isDefault) e.key: e.value.toJson()},
        'art': art.map((a) => a.toJson()).toList(),
        'images': images.map((i) => i.toJson()).toList(),
        'sceneImages': sceneImages,
        'mapImages': mapImages,
      };

  bool get isEmpty => tracks.isEmpty && sounds.isEmpty && art.isEmpty && images.isEmpty && tweaks.values.every((t) => t.isDefault);

  void update(void Function(StudioStore s) change) {
    change(this);
    // Slots pointing at deleted creations fall back to the game's own.
    void prune(Map<String, List<String>> slots, Set<String> ids) {
      for (final l in slots.values) {
        l.removeWhere((id) => !ids.contains(id));
      }
      slots.removeWhere((_, l) => l.isEmpty);
    }

    final trackIds = {for (final t in tracks) t.id};
    prune(musicSlots, trackIds);
    prune(ambienceSlots, trackIds);
    prune(sfxSlots, {for (final s in sounds) s.id});
    final imageIds = {for (final i in images) i.id};
    prune(sceneImages, imageIds);
    prune(mapImages, imageIds);
    notifyListeners();
    _prefs?.setString(_key, jsonEncode(toJson()));
  }

  /// Merges a backup's studio into this one.
  void restore(Map<String, dynamic> j) {
    final other = StudioStore.memory()..fromJson(j);
    void merge(Map<String, List<String>> into, Map<String, List<String>> from) {
      for (final e in from.entries) {
        into[e.key] = {...?into[e.key], ...e.value}.toList();
      }
    }

    update((s) {
      for (final t in other.tracks) {
        s.tracks.removeWhere((x) => x.id == t.id);
        s.tracks.add(t);
      }
      for (final x in other.sounds) {
        s.sounds.removeWhere((y) => y.id == x.id);
        s.sounds.add(x);
      }
      for (final a in other.art) {
        s.art.removeWhere((y) => y.id == a.id);
        s.art.add(a);
      }
      for (final i in other.images) {
        s.images.removeWhere((y) => y.id == i.id);
        s.images.add(i);
      }
      merge(s.musicSlots, other.musicSlots);
      merge(s.ambienceSlots, other.ambienceSlots);
      merge(s.sfxSlots, other.sfxSlots);
      merge(s.sceneImages, other.sceneImages);
      merge(s.mapImages, other.mapImages);
      s.tweaks.addAll(other.tweaks);
    });
  }

  StudioTrack? track(String id) => tracks.where((t) => t.id == id).firstOrNull;
  StudioSound? sound(String id) => sounds.where((s) => s.id == id).firstOrNull;
  StudioImage? image(String id) => images.where((s) => s.id == id).firstOrNull;

  /// The playlist for a game theme, or empty for the built-in music.
  List<StudioTrack> tracksFor(String theme) => [for (final id in musicSlots[theme] ?? const <String>[]) ?track(id)];

  /// One of the player's tracks for [theme] (null: the game's own).
  StudioTrack? trackFor(String theme, [math.Random? r]) {
    final list = tracksFor(theme);
    return list.isEmpty ? null : list[(r ?? math.Random()).nextInt(list.length)];
  }

  StudioTrack? ambienceFor(String kind, [math.Random? r]) {
    final list = [for (final id in ambienceSlots[kind] ?? const <String>[]) ?track(id)];
    return list.isEmpty ? null : list[(r ?? math.Random()).nextInt(list.length)];
  }

  /// One of the sounds replacing [name], picked at random for variety.
  StudioSound? soundFor(String name, [math.Random? r]) {
    final list = [for (final id in sfxSlots[name] ?? const <String>[]) ?sound(id)];
    return list.isEmpty ? null : list[(r ?? math.Random()).nextInt(list.length)];
  }

  SfxTweak tweakFor(String name) => tweaks[name] ?? const SfxTweak();

  /// The player's picture for a scene place, chosen steadily by [seed].
  String? sceneImageFor(String location, int seed) => _pick(sceneImages[location], seed);

  /// The player's picture for a kind of map, chosen steadily by [seed].
  String? mapImageFor(String kind, int seed) => _pick(mapImages[kind], seed);

  String? _pick(List<String>? ids, int seed) {
    final list = [for (final id in ids ?? const <String>[]) ?image(id)];
    return list.isEmpty ? null : list[seed.abs() % list.length].path;
  }

  /// Adds [id] to (or removes it from) the list under [key].
  static void toggle(Map<String, List<String>> slots, String key, String id, bool on) {
    final l = slots.putIfAbsent(key, () => []);
    l.remove(id);
    if (on) l.add(id);
  }
}
