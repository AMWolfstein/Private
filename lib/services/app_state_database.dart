import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sistrum/services/sqlite_helpers.dart' as sqlite;
import 'package:sistrum/utils/logger.dart';

final _log = AppLogger('AppStateDb');

const _dbFileName = 'app_state.db';
const _dbVersion = 5;

const _queueTable = 'download_queue_items';
// Dropped in v5 with the Search tab's Recent list.
const _droppedRecentTables = [
  'recent_access_items',
  'hidden_recent_downloads',
  'recent_access_state',
];
const _playbackSessionTable = 'playback_session';

const _legacyQueueKey = 'download_queue';

const _queueMigrationKey = 'app_state_migrated_queue_to_sqlite_v1';

class AppStateDatabase {
  static final AppStateDatabase instance = AppStateDatabase._init();
  static final sqlite.SingleFlightInitializer<Database> _database =
      sqlite.SingleFlightInitializer<Database>();

  final Future<SharedPreferences> _prefs = SharedPreferences.getInstance();

  AppStateDatabase._init();

  Future<Database> get database => _database.getOrCreate(_initDb);

  Future<Database> _initDb() {
    return sqlite.openAppDatabase(
      _dbFileName,
      version: _dbVersion,
      incrementalAutoVacuum: false,
      onCreate: _createDb,
      onUpgrade: _upgradeDb,
    );
  }

  Future<void> _createDb(Database db, int version) async {
    _log.i('Creating app state database schema v$version');

    await db.execute('''
      CREATE TABLE $_queueTable (
        id TEXT PRIMARY KEY,
        item_json TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_${_queueTable}_status ON $_queueTable(status)',
    );
    await db.execute(
      'CREATE INDEX idx_${_queueTable}_created ON $_queueTable(created_at ASC)',
    );

    await _createPlaybackSessionTable(db);
  }

  Future<void> _upgradeDb(Database db, int oldVersion, int newVersion) async {
    _log.i('Upgrading app state database from v$oldVersion to v$newVersion');
    if (oldVersion < 4) {
      await _migratePlaybackSessionToV4(db);
    }
    if (oldVersion < 5) {
      for (final table in _droppedRecentTables) {
        await db.execute('DROP TABLE IF EXISTS $table');
      }
    }
  }

  static Future<void> _createPlaybackSessionTable(Database db) {
    return db.execute('''
      CREATE TABLE IF NOT EXISTS $_playbackSessionTable (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        media_json TEXT NOT NULL,
        current_index INTEGER NOT NULL DEFAULT 0,
        position_ms INTEGER NOT NULL DEFAULT 0,
        shuffle INTEGER NOT NULL DEFAULT 0,
        repeat_mode TEXT NOT NULL DEFAULT 'none',
        updated_at TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _migratePlaybackSessionToV4(Database db) async {
    final table = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [_playbackSessionTable],
    );
    if (table.isEmpty) {
      await _createPlaybackSessionTable(db);
      return;
    }

    final columns = await db.rawQuery(
      'PRAGMA table_info($_playbackSessionTable)',
    );
    if (columns.any((column) => column['name'] == 'media_json')) return;

    Map<String, dynamic>? legacySession;
    final rows = await db.query(_playbackSessionTable, limit: 1);
    final raw = rows.isEmpty ? null : rows.first['session_json'] as String?;
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          legacySession = Map<String, dynamic>.from(decoded);
        }
      } catch (e) {
        _log.w('Discarding unreadable legacy playback session: $e');
      }
    }

    const migratedTable = '${_playbackSessionTable}_v4';
    await db.execute('DROP TABLE IF EXISTS $migratedTable');
    await db.execute('''
      CREATE TABLE $migratedTable (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        media_json TEXT NOT NULL,
        current_index INTEGER NOT NULL DEFAULT 0,
        position_ms INTEGER NOT NULL DEFAULT 0,
        shuffle INTEGER NOT NULL DEFAULT 0,
        repeat_mode TEXT NOT NULL DEFAULT 'none',
        updated_at TEXT NOT NULL
      )
    ''');
    if (legacySession != null) {
      await db.insert(migratedTable, _playbackSessionRow(legacySession));
    }
    await db.execute('DROP TABLE $_playbackSessionTable');
    await db.execute(
      'ALTER TABLE $migratedTable RENAME TO $_playbackSessionTable',
    );
  }

  static Map<String, Object?> _playbackSessionRow(
    Map<String, dynamic> session,
  ) {
    final media = session['media'];
    final currentIndex = session['index'];
    final positionMs = session['positionMs'];
    final repeatMode = session['repeat'];
    return {
      'id': 1,
      'media_json': jsonEncode(media is List ? media : const []),
      'current_index': currentIndex is num ? currentIndex.toInt() : 0,
      'position_ms': positionMs is num ? positionMs.toInt() : 0,
      'shuffle': session['shuffle'] == true ? 1 : 0,
      'repeat_mode': repeatMode is String ? repeatMode : 'none',
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  /// Retire session URIs and legacy preferences tied to a previous installation.
  Future<void> clearRestoredPlaybackState() async {
    await clearPlaybackSession();
    final prefs = await _prefs;
    await prefs.remove(_legacyQueueKey);
    await prefs.setBool(_queueMigrationKey, true);
  }

  Future<Map<String, dynamic>?> getPlaybackSession() async {
    final db = await database;
    final rows = await db.query(_playbackSessionTable, limit: 1);
    if (rows.isEmpty) return null;
    final row = rows.first;
    final raw = row['media_json'] as String?;
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return {
        'version': 2,
        'media': decoded,
        'index': (row['current_index'] as num?)?.toInt() ?? 0,
        'positionMs': (row['position_ms'] as num?)?.toInt() ?? 0,
        'shuffle': (row['shuffle'] as num?)?.toInt() == 1,
        'repeat': row['repeat_mode'] as String? ?? 'none',
      };
    } catch (e) {
      _log.w('Discarding unreadable playback session: $e');
    }
    return null;
  }

  Future<void> savePlaybackSession(Map<String, dynamic> session) async {
    final db = await database;
    await db.insert(
      _playbackSessionTable,
      _playbackSessionRow(session),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<bool> updatePlaybackSessionState({
    required int index,
    required int positionMs,
    required bool shuffle,
    required String repeatMode,
  }) async {
    final db = await database;
    final changed = await db.update(_playbackSessionTable, {
      'current_index': index,
      'position_ms': positionMs,
      'shuffle': shuffle ? 1 : 0,
      'repeat_mode': repeatMode,
      'updated_at': DateTime.now().toIso8601String(),
    }, where: 'id = 1');
    return changed > 0;
  }

  Future<void> clearPlaybackSession() async {
    final db = await database;
    await db.delete(_playbackSessionTable);
  }
}
