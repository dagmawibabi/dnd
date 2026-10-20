import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/srd.dart';
import 'image_service.dart';

/// One codex entry that can have AI art.
class CodexSubject {
  const CodexSubject(this.kind, this.id, this.name, this.prompt);

  /// race | class | monster
  final String kind;
  final String id;
  final String name;
  final String prompt;
  String get key => '$kind:$id';
}

List<CodexSubject> codexSubjects() => [
      for (final r in races) CodexSubject('race', r.id, r.name, 'Fantasy character portrait of a typical ${r.name} adventurer, head and shoulders, showing the defining features of the race. ${r.description}'),
      for (final c in classes) CodexSubject('class', c.id, c.name, 'Iconic ${c.name} hero in a dramatic signature pose with their tools of the trade. ${c.description}'),
      for (final m in monsters) CodexSubject('monster', m.id, m.name, 'A fearsome ${m.name}, a ${m.type} creature from Dungeons & Dragons, shown full body in its lair (${m.environments.join(', ')}), bestiary illustration.'),
    ];

/// AI paintings for races, classes and monsters in the codex.
class CodexArt extends ChangeNotifier {
  CodexArt(this._prefs) {
    try {
      paths = Map<String, String>.from(jsonDecode(_prefs.getString(_key) ?? '{}') as Map);
    } catch (_) {}
  }

  final SharedPreferences _prefs;
  static const _key = 'codex_art.v1';

  Map<String, String> paths = {};
  bool running = false;
  int done = 0;
  int total = 0;
  String? error;
  bool _cancel = false;

  String? pathOf(String kind, String id) => paths['$kind:$id'];

  int missing() => codexSubjects().where((s) => !paths.containsKey(s.key)).length;

  void _persist() => _prefs.setString(_key, jsonEncode(paths));

  void set(String key, String path) {
    paths[key] = path;
    _persist();
    notifyListeners();
  }

  void cancel() => _cancel = true;

  /// Paints every subject (or only those without art), one at a time.
  Future<void> paint(ImageService images, {bool missingOnly = true}) async {
    if (running) return;
    final todo = codexSubjects().where((s) => !missingOnly || !paths.containsKey(s.key)).toList();
    if (todo.isEmpty) return;
    running = true;
    _cancel = false;
    error = null;
    done = 0;
    total = todo.length;
    images.resume();
    notifyListeners();
    for (final s in todo) {
      if (_cancel) break;
      final key = 'codex_${s.kind}_${s.id}';
      final path = await images.generate(key, s.prompt, category: 'images');
      if (path != null) {
        paths[s.key] = path;
        _persist();
      } else if (images.isSuspended('image') || images.errors[key] != null) {
        error = images.errors.remove(key) ?? 'Image generation stopped.';
        if (images.isSuspended('image')) break;
      }
      done++;
      notifyListeners();
    }
    running = false;
    notifyListeners();
  }

  void restore(Map<String, String> restored) {
    paths.addAll(restored);
    _persist();
    notifyListeners();
  }
}
