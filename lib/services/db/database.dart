import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqlite_api.dart';

import 'factory_io.dart' if (dart.library.js_interop) 'factory_web.dart';

/// The app's SQLite database: heroes, adventures, campaigns and images.
///
/// Small preferences stay in SharedPreferences; anything that grows lives here.
class AppDatabase {
  AppDatabase._(this.db);
  final Database db;

  static AppDatabase? _instance;
  static AppDatabase get instance => _instance!;
  static bool get isOpen => _instance != null;

  static const _version = 2;

  static const _talesTable = 'CREATE TABLE tales (id TEXT PRIMARY KEY, json TEXT NOT NULL, summary TEXT NOT NULL, updated INTEGER NOT NULL)';

  static Future<AppDatabase> open({String name = 'dnd.db', DatabaseFactory? factory}) async {
    final f = factory ?? platformDatabaseFactory();
    final path = (kIsWeb || name == inMemoryDatabasePath) ? name : p.join(await f.getDatabasesPath(), name);
    final db = await f.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _version,
        onCreate: (db, v) async {
          final b = db.batch();
          b.execute('CREATE TABLE characters (id TEXT PRIMARY KEY, json TEXT NOT NULL, sort INTEGER NOT NULL)');
          b.execute('CREATE TABLE adventures (id TEXT PRIMARY KEY, json TEXT NOT NULL, summary TEXT NOT NULL, updated INTEGER NOT NULL)');
          b.execute('CREATE TABLE campaigns (id TEXT PRIMARY KEY, json TEXT NOT NULL, sort INTEGER NOT NULL)');
          b.execute('CREATE TABLE images (key TEXT PRIMARY KEY, bytes BLOB NOT NULL, created INTEGER NOT NULL)');
          b.execute('CREATE TABLE kv (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
          b.execute(_talesTable);
          await b.commit(noResult: true);
        },
        onUpgrade: (db, from, to) async {
          if (from < 2) await db.execute(_talesTable);
        },
      ),
    );
    return _instance = AppDatabase._(db);
  }

  // ------------------------------------------------------------- characters

  Future<List<Map<String, dynamic>>> characters() async {
    final rows = await db.query('characters', orderBy: 'sort ASC');
    return [for (final r in rows) jsonDecode(r['json'] as String) as Map<String, dynamic>];
  }

  Future<void> putCharacters(List<Map<String, dynamic>> list) async {
    final b = db.batch();
    b.delete('characters');
    for (final (i, c) in list.indexed) {
      b.insert('characters', {'id': c['id'], 'json': jsonEncode(c), 'sort': i});
    }
    await b.commit(noResult: true);
  }

  // ------------------------------------------------------------- adventures

  Future<List<Map<String, dynamic>>> adventureSummaries() async {
    final rows = await db.query('adventures', columns: ['summary'], orderBy: 'updated DESC');
    return [for (final r in rows) jsonDecode(r['summary'] as String) as Map<String, dynamic>];
  }

  Future<Map<String, dynamic>?> adventure(String id) async {
    final rows = await db.query('adventures', columns: ['json'], where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return jsonDecode(rows.first['json'] as String) as Map<String, dynamic>;
  }

  Future<void> putAdventure(String id, Map<String, dynamic> json, Map<String, dynamic> summary, DateTime updated) =>
      db.insert('adventures', {'id': id, 'json': jsonEncode(json), 'summary': jsonEncode(summary), 'updated': updated.millisecondsSinceEpoch}, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> deleteAdventure(String id) => db.delete('adventures', where: 'id = ?', whereArgs: [id]);

  // ------------------------------------------------------------------ tales

  Future<List<Map<String, dynamic>>> taleSummaries() async {
    final rows = await db.query('tales', columns: ['summary'], orderBy: 'updated DESC');
    return [for (final r in rows) jsonDecode(r['summary'] as String) as Map<String, dynamic>];
  }

  Future<Map<String, dynamic>?> tale(String id) async {
    final rows = await db.query('tales', columns: ['json'], where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return jsonDecode(rows.first['json'] as String) as Map<String, dynamic>;
  }

  Future<void> putTale(String id, Map<String, dynamic> json, Map<String, dynamic> summary, DateTime updated) =>
      db.insert('tales', {'id': id, 'json': jsonEncode(json), 'summary': jsonEncode(summary), 'updated': updated.millisecondsSinceEpoch}, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> deleteTale(String id) => db.delete('tales', where: 'id = ?', whereArgs: [id]);

  // -------------------------------------------------------------- campaigns

  Future<List<Map<String, dynamic>>> campaigns() async {
    final rows = await db.query('campaigns', orderBy: 'sort ASC');
    return [for (final r in rows) jsonDecode(r['json'] as String) as Map<String, dynamic>];
  }

  Future<void> putCampaigns(List<Map<String, dynamic>> list) async {
    final b = db.batch();
    b.delete('campaigns');
    for (final (i, c) in list.indexed) {
      b.insert('campaigns', {'id': c['id'], 'json': jsonEncode(c), 'sort': i});
    }
    await b.commit(noResult: true);
  }

  // ----------------------------------------------------------------- images

  Future<void> putImage(String key, Uint8List bytes) =>
      db.insert('images', {'key': key, 'bytes': bytes, 'created': DateTime.now().millisecondsSinceEpoch}, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<Uint8List?> image(String key) async {
    final rows = await db.query('images', columns: ['bytes'], where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    final v = rows.first['bytes'];
    return v is Uint8List ? v : Uint8List.fromList(List<int>.from(v as List));
  }

  // --------------------------------------------------------------------- kv

  Future<String?> get(String key) async {
    final rows = await db.query('kv', columns: ['value'], where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  /// Erases every table (used by "Erase all data").
  Future<void> clearAll() async {
    final b = db.batch();
    for (final t in const ['characters', 'adventures', 'campaigns', 'images', 'kv', 'tales']) {
      b.delete(t);
    }
    await b.commit(noResult: true);
  }

  Future<void> put(String key, String value) => db.insert('kv', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
}
