import 'package:flutter/foundation.dart';

import '../models/tale.dart';
import 'db/database.dart';

/// Saved text adventures. Summaries stay in memory; full stories load on demand.
class TaleStore extends ChangeNotifier {
  TaleStore._(this._db);
  final AppDatabase? _db;

  final List<TaleSummary> tales = [];
  final Map<String, Tale> _cache = {};

  static TaleStore memory() => TaleStore._(null);

  static Future<TaleStore> open(AppDatabase db) async {
    final s = TaleStore._(db);
    try {
      s.tales.addAll((await db.taleSummaries()).map(TaleSummary.new));
    } catch (e) {
      debugPrint('TaleStore load failed: $e');
    }
    return s;
  }

  Future<Tale?> load(String id) async {
    final hit = _cache[id];
    if (hit != null) return hit;
    final j = await _db?.tale(id);
    if (j == null) return null;
    final t = Tale.fromJson(j);
    _cache[id] = t;
    return t;
  }

  Future<void> save(Tale t) async {
    t.updatedAt = DateTime.now();
    _cache[t.id] = t;
    if (_cache.length > 4 && _db != null) _cache.remove(_cache.keys.first);
    await _db?.putTale(t.id, t.toJson(), t.summary(), t.updatedAt);
    tales.removeWhere((x) => x.id == t.id);
    tales.insert(0, TaleSummary(t.summary()));
    notifyListeners();
  }

  Future<void> delete(String id) async {
    tales.removeWhere((x) => x.id == id);
    _cache.remove(id);
    await _db?.deleteTale(id);
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> backup() async {
    final out = <Map<String, dynamic>>[];
    for (final s in tales) {
      final t = await load(s.id);
      if (t != null) out.add(t.toJson());
    }
    return out;
  }

  Future<int> restore(List list) async {
    var n = 0;
    for (final j in list) {
      await save(Tale.fromJson(Map<String, dynamic>.from(j)));
      n++;
    }
    return n;
  }
}
