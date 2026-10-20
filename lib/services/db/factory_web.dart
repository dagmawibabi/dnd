import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// SQLite compiled to WebAssembly, persisted in the browser's IndexedDB.
DatabaseFactory platformDatabaseFactory() => databaseFactoryFfiWeb;
