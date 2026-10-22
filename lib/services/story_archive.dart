import 'dart:convert';
import 'dart:typed_data';

import '../data/tale_genres.dart';
import '../data/tales/tales.dart';
import '../game/module_engine.dart' show moduleById;
import '../models/adventure.dart';
import '../models/character.dart' show newId;
import '../models/tale.dart';
import '../models/world.dart';

/// Versioned playable saves, independent of the reading-only export formats.
Map<String, dynamic> storyArchive(StoryRecord record) {
  final Map<String, dynamic> state;
  if (record is Adventure) {
    state = record.toJson()
      ..['log'] = record.log.map((e) => e.toJson()).toList()
      ..['aiHistory'] = record.aiHistory.toList();
  } else if (record is Tale) {
    state = record.toJson();
  } else {
    throw const FormatException('Unsupported story type.');
  }
  final world = record as WorldData;
  state['chats'] = world.chats.map((k, v) => MapEntry(k, v.map((line) => line.toJson()).toList()));
  state['bonds'] = world.bonds.map((k, v) => MapEntry(k, {...v.toJson(), 'm': v.moments.map((moment) => moment.toJson()).toList()}));
  return jsonDecode(
    jsonEncode({
      'app': 'DnD',
      'format': 'story',
      'version': 1,
      'kind': record is Adventure ? 'adventure' : 'tale',
      'exported': DateTime.now().toIso8601String(),
      'state': state,
    }),
  ) as Map<String, dynamic>;
}

Map<String, dynamic> decodeStoryArchive(String raw) {
  final data = jsonDecode(raw);
  if (data is! Map<String, dynamic> || data['app'] != 'DnD' || data['format'] != 'story') {
    throw const FormatException('Choose a playable adventure JSON export. Books and library backups are imported separately.');
  }
  if (data['version'] != 1) throw const FormatException('This save version is not supported.');
  if (data['state'] is! Map<String, dynamic> || !['tale', 'adventure'].contains(data['kind'])) {
    throw const FormatException('The adventure save is incomplete.');
  }
  final state = data['state'] as Map<String, dynamic>;
  if (state['id'] is! String || state['title'] is! String || state['engine'] is! String || state['log'] is! List || state['choices'] is! List) {
    throw const FormatException('The adventure is missing required story data.');
  }
  // Parse before any storage writes, including nested model data.
  if (data['kind'] == 'tale') {
    if (!TaleEngine.values.any((e) => e.name == state['engine'])) throw const FormatException('Unknown story engine.');
    final tale = Tale.fromJson(state);
    if (tale.engine == TaleEngine.preset) {
      final preset = taleById(tale.presetId);
      if (preset == null || (tale.node.isNotEmpty && !preset.nodes.containsKey(tale.node))) {
        throw const FormatException('This offline story is not installed in this version.');
      }
      if (tale.node.isNotEmpty) {
        for (final choice in tale.choices) {
          final index = choice.data['i'];
          if (index is! int || index < 0 || index >= preset.nodes[tale.node]!.options.length) {
            throw const FormatException('The saved choices do not match this story version.');
          }
        }
      }
    }
  } else {
    if (!StoryEngine.values.any((e) => e.name == state['engine'])) throw const FormatException('Unknown adventure engine.');
    final adventure = Adventure.fromJson(state);
    if (adventure.engine == StoryEngine.module && moduleById(adventure.offline['module']) == null) {
      throw const FormatException('This adventure module is not installed.');
    }
  }
  return data;
}

/// Replace both media references and media-cost map keys.
dynamic remapArchive(dynamic value, Map<String, String> paths) {
  if (value is String) return paths[value] ?? value;
  if (value is List) return value.map((v) => remapArchive(v, paths)).toList();
  if (value is Map) {
    return <String, dynamic>{for (final e in value.entries) paths[e.key] ?? e.key as String: remapArchive(e.value, paths)};
  }
  return value;
}

/// [clipsFor] adds each passage's saved narration so the story can be replayed
/// with its voices on another device.
Future<Map<String, dynamic>> portableStoryArchive(StoryRecord record, Future<Uint8List?> Function(String) readMedia, {Future<List<(String, Uint8List)>?> Function(LogEntry e)? clipsFor}) async {
  final archive = storyArchive(record);
  final world = record as WorldData;
  final paths = <String>{
    ...world.replayAudio.values.expand((x) => x),
    if (record.sceneImagePath != null) record.sceneImagePath!,
    ...record.sceneImages.values,
    ...world.gallery.map((m) => m.path),
    ...world.mediaCosts.keys,
    ...world.itemImages.values,
    // Pictures sent in private chats.
    for (final lines in world.chats.values)
      for (final l in lines) ...l.images,
  };
  if (record is Adventure) {
    paths.addAll([
      if (record.hero.portrait.aiImagePath != null) record.hero.portrait.aiImagePath!,
      for (final c in record.companions)
        if (c.portrait.aiImagePath != null) c.portrait.aiImagePath!,
      for (final n in record.people)
        if (n.portrait.aiImagePath != null) n.portrait.aiImagePath!,
      if (record.map?.aiImagePath != null) record.map!.aiImagePath!,
      for (final e in record.log)
        if (e.meta['media'] is String) e.meta['media'] as String,
    ]);
  } else if (record is Tale) {
    paths.addAll([
      for (final n in record.npcs)
        if (n.portrait.aiImagePath != null) n.portrait.aiImagePath!,
      if (record.map?.aiImagePath != null) record.map!.aiImagePath!,
      for (final e in record.log)
        if (e.meta['media'] is String) e.meta['media'] as String,
    ]);
  }
  final replacements = <String, String>{};
  final assets = <String, dynamic>{};
  final missing = <String>[];
  for (final path in paths.where((p) => p.isNotEmpty)) {
    final bytes = await readMedia(path);
    if (bytes == null) {
      missing.add(path);
      continue;
    }
    final key = 'asset:${assets.length}';
    final ext =
        RegExp(r'\.(png|jpg|jpeg|webp|gif|mp4|webm|mov|mp3|wav|m4a)$', caseSensitive: false).firstMatch(path)?.group(1)?.toLowerCase() ??
        (world.gallery.any((m) => m.path == path && m.video) ? 'mp4' : 'png');
    assets[key] = {'ext': ext, 'bytes': base64Encode(bytes)};
    replacements[path] = key;
  }
  archive['state'] = remapArchive(archive['state'], replacements);
  if (clipsFor != null) {
    final log = record is Adventure ? record.log : (record as Tale).log;
    final audio = Map<String, dynamic>.from((archive['state'] as Map)['replayAudio'] ?? const {});
    for (final e in log) {
      final at = '${e.at.millisecondsSinceEpoch}';
      if (audio.containsKey(at) || !(e.kind == LogKind.narration || e.kind == LogKind.dialogue || e.kind == LogKind.companion)) continue;
      final clips = await clipsFor(e);
      if (clips == null || clips.isEmpty) continue;
      final keys = <String>[];
      for (final (ext, bytes) in clips) {
        final key = 'asset:${assets.length}';
        assets[key] = {'ext': ext, 'bytes': base64Encode(bytes)};
        keys.add(key);
      }
      audio[at] = keys;
    }
    (archive['state'] as Map)['replayAudio'] = audio;
    archive['narration'] = audio.length;
  }
  archive['assets'] = assets;
  archive['missingMedia'] = missing.length;
  return archive;
}

/// A fresh start of a story for someone else: its premise, world, tone and
/// characters, with no progress. Importing it begins a new playthrough.
Future<Map<String, dynamic>> storyTemplate(StoryRecord record, Future<Uint8List?> Function(String) readMedia, {bool cast = true}) async {
  final world = record as WorldData;
  final assets = <String, dynamic>{};
  Future<String?> pack(String? path) async {
    if (path == null || path.isEmpty) return null;
    final bytes = await readMedia(path);
    if (bytes == null) return null;
    final key = 'asset:${assets.length}';
    assets[key] = {'ext': RegExp(r'\.(jpg|jpeg|webp)$', caseSensitive: false).firstMatch(path)?.group(1)?.toLowerCase() ?? 'png', 'bytes': base64Encode(bytes)};
    return key;
  }

  final people = record is Adventure ? record.npcs : (record as Tale).npcs;
  final cover = world.gallery.where((m) => m.kind == 'scene' && !m.video).firstOrNull?.path ?? record.sceneImagePath;
  final state = <String, dynamic>{
    'title': record is Adventure ? record.title : (record as Tale).title,
    'premise': record is Adventure ? record.premise : (record as Tale).premise,
    'tone': world.narratorTone,
    'world': world.worldNotes,
    if (record is Adventure) ...{'setting': record.setting, 'mood': record.tone, 'difficulty': record.difficulty, 'hardcore': record.hardcore},
    if (record is Tale) ...{
      'genre': record.genre,
      if (isCustomGenre(record.genre)) 'genreDef': {'id': record.genre, 'name': genreById(record.genre).name, 'tagline': genreById(record.genre).tagline, 'style': genreById(record.genre).style, 'health': genreById(record.genre).healthLabel, 'scene': genreById(record.genre).scene, 'time': genreById(record.genre).time},
      'protagonist': record.protagonist,
    },
    'cover': await pack(cover),
    if (cast)
      'cast': [
        for (final p in people.take(8))
          {'name': p.name, 'role': p.role, 'description': p.description, if (p.gender.isNotEmpty) 'gender': p.gender, 'portrait': await pack(p.portrait.aiImagePath), if ((world.profiles[p.id]?.backstory ?? '').isNotEmpty) 'backstory': world.profiles[p.id]!.backstory},
      ],
  };
  return {'app': 'DnD', 'format': 'template', 'version': 1, 'kind': record is Adventure ? 'adventure' : 'tale', 'exported': DateTime.now().toIso8601String(), 'state': state, 'assets': assets};
}

/// What the world notes of a new story from a template should say about its cast.
String templateWorldNotes(Map<String, dynamic> state) {
  final cast = [for (final c in (state['cast'] as List? ?? const [])) if (c is Map) c];
  return [
    if ((state['world'] ?? '').toString().isNotEmpty) state['world'].toString(),
    if (cast.isNotEmpty) 'Characters who belong in this world (introduce them naturally as the story needs them): ${cast.map((c) => '${c['name']}${(c['role'] ?? '').toString().isEmpty ? '' : ', ${c['role']}'}${(c['description'] ?? '').toString().isEmpty ? '' : ': ${c['description']}'}').join('; ')}',
  ].join('\n');
}

/// Validate every asset before persisting any of them.
Map<String, (String, Uint8List)> archiveAssets(Map<String, dynamic> archive) {
  final raw = archive['assets'] ?? <String, dynamic>{};
  if (raw is! Map) throw const FormatException('Invalid media archive.');
  final result = <String, (String, Uint8List)>{};
  for (final e in raw.entries) {
    final value = e.value;
    if (e.key is! String ||
        !RegExp(r'^asset:\d+$').hasMatch(e.key) ||
        value is! Map ||
        !['png', 'jpg', 'jpeg', 'webp', 'gif', 'mp4', 'webm', 'mov', 'mp3', 'wav', 'm4a'].contains(value['ext']) ||
        value['bytes'] is! String) {
      throw const FormatException('Invalid archived media.');
    }
    result[e.key] = (value['ext'] as String, base64Decode(value['bytes']));
  }
  return result;
}

StoryRecord restoreStoryArchive(Map<String, dynamic> archive, {Map<String, String> media = const {}}) {
  final state = Map<String, dynamic>.from(remapArchive(archive['state'], media) as Map);
  final sourceId = state['id'];
  state['id'] = newId();
  // Import creates a new identity, but must not grant another downtime action.
  final chronicle = state['chronicle'];
  if (chronicle is Map && chronicle['lastChapter'] == sourceId) chronicle['lastChapter'] = state['id'];
  if (archive['kind'] == 'tale') return Tale.fromJson(state);
  // A standalone adventure must not attach to an unrelated local campaign/hero.
  state['campaign'] = null;
  final oldHeroId = state['hero']['id'] as String;
  return Adventure.fromJson(Map<String, dynamic>.from(remapArchive(state, {oldHeroId: newId()}) as Map));
}
