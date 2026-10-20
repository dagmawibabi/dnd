import 'dart:convert';
import 'dart:typed_data';

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

Future<Map<String, dynamic>> portableStoryArchive(StoryRecord record, Future<Uint8List?> Function(String) readMedia) async {
  final archive = storyArchive(record);
  final world = record as WorldData;
  final paths = <String>{
    if (record.sceneImagePath != null) record.sceneImagePath!,
    ...record.sceneImages.values,
    ...world.gallery.map((m) => m.path),
    ...world.mediaCosts.keys,
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
        RegExp(r'\.(png|jpg|jpeg|webp|gif|mp4|webm|mov)$', caseSensitive: false).firstMatch(path)?.group(1)?.toLowerCase() ??
        (world.gallery.any((m) => m.path == path && m.video) ? 'mp4' : 'png');
    assets[key] = {'ext': ext, 'bytes': base64Encode(bytes)};
    replacements[path] = key;
  }
  archive['state'] = remapArchive(archive['state'], replacements);
  archive['assets'] = assets;
  archive['missingMedia'] = missing.length;
  return archive;
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
        !['png', 'jpg', 'jpeg', 'webp', 'gif', 'mp4', 'webm', 'mov'].contains(value['ext']) ||
        value['bytes'] is! String) {
      throw const FormatException('Invalid archived media.');
    }
    result[e.key] = (value['ext'] as String, base64Decode(value['bytes']));
  }
  return result;
}

StoryRecord restoreStoryArchive(Map<String, dynamic> archive, {Map<String, String> media = const {}}) {
  final state = Map<String, dynamic>.from(remapArchive(archive['state'], media) as Map);
  state['id'] = newId();
  if (archive['kind'] == 'tale') return Tale.fromJson(state);
  // A standalone adventure must not attach to an unrelated local campaign/hero.
  state['campaign'] = null;
  final oldHeroId = state['hero']['id'] as String;
  return Adventure.fromJson(Map<String, dynamic>.from(remapArchive(state, {oldHeroId: newId()}) as Map));
}
