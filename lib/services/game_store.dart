import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/adventure.dart';
import '../models/campaign.dart';
import '../models/character.dart';
import 'db/database.dart';

/// Persists the character roster, adventures and campaigns in SQLite.
///
/// Heroes, summaries and campaigns are kept in memory; full adventures are
/// loaded on demand. Without a database (tests) everything stays in memory.
class GameStore extends ChangeNotifier {
  GameStore._(this._db);

  final AppDatabase? _db;

  // Legacy SharedPreferences keys, migrated once into the database.
  static const _charsKey = 'characters.v1';
  static const _advIndexKey = 'adventures.index.v1';
  static const _advPrefix = 'adventure.v1.';
  static const _campaignsKey = 'campaigns.v1';

  final List<Campaign> campaigns = [];
  final List<Character> characters = [];

  /// Lightweight summaries; full adventures are loaded on demand.
  final List<AdventureSummary> adventures = [];

  /// Recently opened adventures (and the only copy when running without a database).
  final Map<String, Adventure> _cache = {};

  static GameStore memory() => GameStore._(null);

  static Future<GameStore> open(SharedPreferences prefs, AppDatabase db) async {
    final store = GameStore._(db);
    await store._migrateFromPrefs(prefs);
    await store._load();
    return store;
  }

  Future<void> _migrateFromPrefs(SharedPreferences prefs) async {
    final db = _db;
    if (db == null || await db.get('migrated.v1') != null) return;
    try {
      final chars = prefs.getString(_charsKey);
      if (chars != null) await db.putCharacters([for (final c in jsonDecode(chars) as List) Map<String, dynamic>.from(c)]);
      final camps = prefs.getString(_campaignsKey);
      if (camps != null) await db.putCampaigns([for (final c in jsonDecode(camps) as List) Map<String, dynamic>.from(c)]);
      final advKeys = prefs.getKeys().where((k) => k.startsWith(_advPrefix)).toList();
      for (final key in advKeys) {
        final raw = prefs.getString(key);
        if (raw == null) continue;
        try {
          final a = Adventure.fromJson(jsonDecode(raw) as Map<String, dynamic>);
          await db.putAdventure(a.id, a.toJson(), AdventureSummary.of(a).toJson(), a.updatedAt);
        } catch (e) {
          debugPrint('Skipping unreadable adventure $key: $e');
        }
      }
      await db.put('migrated.v1', DateTime.now().toIso8601String());
      // Free the old copies only after everything is safely in SQLite.
      for (final key in [_charsKey, _advIndexKey, _campaignsKey, ...advKeys]) {
        await prefs.remove(key);
      }
    } catch (e) {
      debugPrint('Migration failed (old data kept): $e');
    }
  }

  Future<void> _load() async {
    final db = _db;
    if (db == null) return;
    try {
      characters.addAll((await db.characters()).map(Character.fromJson));
      adventures.addAll((await db.adventureSummaries()).map(AdventureSummary.fromJson));
      adventures.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      campaigns.addAll((await db.campaigns()).map(Campaign.fromJson));
    } catch (e) {
      debugPrint('GameStore load failed: $e');
    }
  }

  Future<void> _saveChars() async => _db?.putCharacters(characters.map((c) => c.toJson()).toList());

  Character? character(String id) {
    for (final c in characters) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> saveCharacter(Character c) async {
    final i = characters.indexWhere((x) => x.id == c.id);
    if (i >= 0) {
      characters[i] = c;
    } else {
      characters.insert(0, c);
    }
    notifyListeners();
    await _saveChars();
  }

  Future<void> deleteCharacter(String id) async {
    characters.removeWhere((c) => c.id == id);
    notifyListeners();
    await _saveChars();
  }

  Future<Adventure?> loadAdventure(String id) async {
    final cached = _cache[id];
    if (cached != null) return cached;
    final db = _db;
    if (db == null) return null;
    try {
      final j = await db.adventure(id);
      if (j == null) return null;
      final a = Adventure.fromJson(j);
      _remember(a);
      return a;
    } catch (e) {
      debugPrint('Adventure load failed: $e');
      return null;
    }
  }

  void _remember(Adventure a) {
    _cache.remove(a.id);
    _cache[a.id] = a;
    if (_db != null && _cache.length > 3) _cache.remove(_cache.keys.first);
  }

  Future<void> saveAdventure(Adventure a, {bool syncHero = true}) async {
    a.updatedAt = DateTime.now();
    _remember(a);
    final s = AdventureSummary.of(a);
    await _db?.putAdventure(a.id, a.toJson(), s.toJson(), a.updatedAt);
    // Only the newest chapter owns the live campaign world. Viewing or saving
    // an older chapter must never roll it back.
    final camp = campaign(a.campaignId);
    if (camp != null && camp.chapters.isNotEmpty && camp.chapters.last == a.id) {
      camp.worldFromJson(jsonDecode(jsonEncode(a.worldToJson())) as Map<String, dynamic>);
      camp.canon = [for (final c in a.canon) CanonEntry.fromJson(c.toJson())];
      await _saveCampaigns();
    }
    final i = adventures.indexWhere((x) => x.id == a.id);
    if (i >= 0) {
      adventures[i] = s;
    } else {
      adventures.insert(0, s);
    }
    adventures.sort((x, y) => y.updatedAt.compareTo(x.updatedAt));
    if (syncHero && character(a.hero.id) != null) {
      final idx = characters.indexWhere((c) => c.id == a.hero.id);
      characters[idx] = a.hero.clone();
      await _saveChars();
    }
    notifyListeners();
  }

  Future<void> deleteAdventure(String id) async {
    adventures.removeWhere((a) => a.id == id);
    _cache.remove(id);
    await _db?.deleteAdventure(id);
    for (final c in campaigns) {
      c.chapters.remove(id);
    }
    notifyListeners();
    await _saveCampaigns();
  }

  // -------------------------------------------------------------- campaigns

  Future<void> _saveCampaigns() async => _db?.putCampaigns(campaigns.map((c) => c.toJson()).toList());

  Campaign? campaign(String? id) => id == null ? null : campaigns.where((c) => c.id == id).firstOrNull;

  Future<void> saveCampaign(Campaign c) async {
    final i = campaigns.indexWhere((x) => x.id == c.id);
    if (i >= 0) {
      campaigns[i] = c;
    } else {
      campaigns.insert(0, c);
    }
    notifyListeners();
    await _saveCampaigns();
  }

  Future<void> deleteCampaign(String id) async {
    campaigns.removeWhere((c) => c.id == id);
    notifyListeners();
    await _saveCampaigns();
  }

  // ----------------------------------------------------------------- backup

  /// Everything needed to restore heroes, adventures and campaigns.
  Future<Map<String, dynamic>> backup() async {
    final advs = <Map<String, dynamic>>[];
    for (final s in adventures) {
      final a = await loadAdventure(s.id);
      if (a != null) advs.add(a.toJson());
    }
    return {
      'app': 'DnD',
      'version': 2,
      'exported': DateTime.now().toIso8601String(),
      'characters': characters.map((c) => c.toJson()).toList(),
      'adventures': advs,
      'campaigns': campaigns.map((c) => c.toJson()).toList(),
    };
  }

  /// Merges a backup into the store. Returns (characters, adventures, campaigns) imported.
  Future<(int, int, int)> restore(Map<String, dynamic> j) async {
    var nc = 0, na = 0, ncp = 0;
    for (final c in (j['characters'] as List? ?? [])) {
      final ch = Character.fromJson(Map<String, dynamic>.from(c));
      final i = characters.indexWhere((x) => x.id == ch.id);
      if (i >= 0) {
        characters[i] = ch;
      } else {
        characters.add(ch);
      }
      nc++;
    }
    await _saveChars();
    for (final a in (j['adventures'] as List? ?? [])) {
      final adv = Adventure.fromJson(Map<String, dynamic>.from(a));
      await saveAdventure(adv, syncHero: false);
      na++;
    }
    for (final c in (j['campaigns'] as List? ?? [])) {
      final cp = Campaign.fromJson(Map<String, dynamic>.from(c));
      campaigns.removeWhere((x) => x.id == cp.id);
      campaigns.add(cp);
      ncp++;
    }
    await _saveCampaigns();
    notifyListeners();
    return (nc, na, ncp);
  }
}

class AdventureSummary {
  AdventureSummary({
    required this.id,
    required this.title,
    required this.heroName,
    required this.heroClass,
    required this.level,
    required this.engine,
    required this.textMode,
    required this.updatedAt,
    required this.turns,
    required this.location,
    required this.coverSeed,
    required this.hp,
    required this.maxHp,
    this.finished = false,
    this.heroPortrait,
    Map<String, num>? usage,
    this.engineLabel = '',
    this.playSeconds = 0,
  }) : usage = usage ?? const {};

  final int playSeconds;

  /// Token and cost totals for this adventure: in, out, calls, images, cost.
  final Map<String, num> usage;
  final String engineLabel;
  int get tokens => ((usage['in'] ?? 0) + (usage['out'] ?? 0)).toInt();
  double get cost => (usage['cost'] ?? 0).toDouble();

  final String id;
  final String title;
  final String heroName;
  final String heroClass;
  final int level;
  final StoryEngine engine;
  final bool textMode;
  final DateTime updatedAt;
  final int turns;
  final String location;
  final int coverSeed;
  final int hp;
  final int maxHp;
  final bool finished;
  final Map<String, dynamic>? heroPortrait;

  factory AdventureSummary.of(Adventure a) => AdventureSummary(
        id: a.id,
        title: a.title,
        heroName: a.hero.name,
        heroClass: a.hero.classSummary,
        level: a.hero.level,
        engine: a.engine,
        textMode: a.textMode,
        updatedAt: a.updatedAt,
        turns: a.turns,
        location: a.scene.location,
        coverSeed: a.coverSeed,
        hp: a.hero.hp,
        maxHp: a.hero.maxHp,
        finished: a.finished,
        heroPortrait: a.hero.portrait.toJson(),
        usage: Map<String, num>.of(a.usage),
        playSeconds: a.playSeconds,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'hero': heroName,
        'cls': heroClass,
        'lvl': level,
        'engine': engine.name,
        'text': textMode,
        'updated': updatedAt.toIso8601String(),
        'turns': turns,
        'loc': location,
        'cover': coverSeed,
        'hp': hp,
        'max': maxHp,
        'fin': finished,
        'portrait': heroPortrait,
        'usage': usage,
        'play': playSeconds,
      };

  factory AdventureSummary.fromJson(Map<String, dynamic> j) => AdventureSummary(
        id: j['id'],
        title: j['title'] ?? 'Adventure',
        heroName: j['hero'] ?? '',
        heroClass: j['cls'] ?? '',
        level: j['lvl'] ?? 1,
        engine: StoryEngine.values.firstWhere((e) => e.name == j['engine'], orElse: () => StoryEngine.offline),
        textMode: j['text'] ?? false,
        updatedAt: DateTime.tryParse(j['updated'] ?? '') ?? DateTime.now(),
        turns: j['turns'] ?? 0,
        location: j['loc'] ?? 'forest',
        coverSeed: j['cover'] ?? 0,
        hp: j['hp'] ?? 1,
        maxHp: j['max'] ?? 1,
        finished: j['fin'] ?? false,
        heroPortrait: j['portrait'] == null ? null : Map<String, dynamic>.from(j['portrait']),
        usage: Map<String, num>.from(j['usage'] ?? const {}),
        playSeconds: (j['play'] as num?)?.toInt() ?? 0,
      );
}
