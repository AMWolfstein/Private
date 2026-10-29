import 'package:sqflite/sqflite.dart';
import 'package:sistrum/services/library/library_database_models.dart';
import 'package:sistrum/services/library/sqlite_helpers.dart' as sqlite;
import 'package:sistrum/utils/logger.dart';

final _log = AppLogger('LibraryDatabase');

/// Schema lifecycle is independent of collection reads and scan transactions.
abstract final class LibrarySchema {
  static const version = 20;
  static const visibleView = 'library_visible';
  static const searchFtsTable = 'library_search_fts';
  static const _legacySourceId = LocalLibraryItem.legacySourceId;

  static Future<bool> create(Database db, int version) async {
    _log.i('Creating library database schema v$version');
    await db.execute('''
      CREATE TABLE library (
        id TEXT PRIMARY KEY,
        source_id TEXT NOT NULL DEFAULT '$_legacySourceId',
        track_name TEXT NOT NULL,
        artist_name TEXT NOT NULL,
        album_name TEXT NOT NULL,
        album_artist TEXT,
        file_path TEXT NOT NULL UNIQUE,
        cover_path TEXT,
        scanned_at TEXT NOT NULL,
        file_mod_time INTEGER,
        isrc TEXT,
        track_number INTEGER,
        total_tracks INTEGER,
        disc_number INTEGER,
        total_discs INTEGER,
        duration INTEGER,
        release_date TEXT,
        bit_depth INTEGER,
        sample_rate INTEGER,
        bitrate INTEGER,
        genre TEXT,
        composer TEXT,
        label TEXT,
        copyright TEXT,
        explicit INTEGER NOT NULL DEFAULT 0,
        has_lyrics INTEGER NOT NULL DEFAULT 0,
        has_replaygain INTEGER NOT NULL DEFAULT 0,
        format TEXT,
        audio_metadata_scan_version INTEGER NOT NULL DEFAULT 4,
        track_name_norm TEXT,
        artist_name_norm TEXT,
        album_name_norm TEXT,
        album_artist_norm TEXT,
        match_key TEXT,
        album_key TEXT,
        search_text TEXT,
        search_track TEXT,
        search_album TEXT,
        search_artist TEXT,
        sort_genre TEXT,
        sort_release TEXT,
        sort_added INTEGER
      )
    ''');
    for (final index in const {
      'isrc': 'isrc',
      'track_artist': 'track_name, artist_name',
      'album': 'album_name, album_artist',
      'file_path': 'file_path',
    }.entries) {
      await db.execute(
        'CREATE INDEX idx_library_${index.key} ON library(${index.value})',
      );
    }
    await _createNormalizedIndexes(db);
    await _createQueueIndexes(db);
    await sqlite.createPathKeyTable(db, 'library_path_keys');
    await _createSources(db);
    final ftsAvailable = await createSearchFts(db);
    _log.i('Library database schema created with indexes');
    return ftsAvailable;
  }

  /// Databases older than v20 are not upgraded: Rust pins the schema version,
  /// and an index from an older build is rebuilt by a fresh scan instead.
  static Future<void> upgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    _log.i('Library database v$oldVersion needs no upgrade to v$newVersion');
  }

  static Future<bool> createSearchFts(DatabaseExecutor db) =>
      sqlite.createTrigramFtsIndex(
        db,
        ftsTable: searchFtsTable,
        contentTable: 'library',
        triggerPrefix: 'library_search_fts',
      );

  static Future<void> _createSources(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS library_sources (
        id TEXT PRIMARY KEY,
        path TEXT NOT NULL UNIQUE,
        display_name TEXT NOT NULL,
        bookmark TEXT,
        volume_id TEXT,
        is_removable INTEGER NOT NULL DEFAULT 0,
        enabled INTEGER NOT NULL DEFAULT 1,
        available INTEGER NOT NULL DEFAULT 1,
        last_scanned_at TEXT,
        last_seen_at TEXT,
        last_scan_error TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_library_source_id ON library(source_id)',
    );
    await db.insert('library_sources', {
      'id': _legacySourceId,
      'path': 'legacy://local-library',
      'display_name': 'Music',
      'enabled': 1,
      'available': 1,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.execute('DROP VIEW IF EXISTS $visibleView');
    await db.execute('''
      CREATE VIEW $visibleView AS
      SELECT l.* FROM library l
      JOIN library_sources s ON s.id = l.source_id
      WHERE s.enabled = 1 AND s.available = 1
    ''');
  }

  static Future<void> _createNormalizedIndexes(DatabaseExecutor db) async {
    for (final column in const {
      'match_key': 'match_key',
      'album_key': 'album_key',
      'track_norm': 'track_name_norm',
      'artist_norm': 'artist_name_norm',
      'album_norm': 'album_name_norm',
      'album_artist_norm': 'album_artist_norm',
      'scanned_at': 'scanned_at',
    }.entries) {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_library_${column.key} ON library(${column.value})',
      );
    }
  }

  static Future<void> _createQueueIndexes(DatabaseExecutor db) async {
    for (final order in const {
      'added': 'sort_added DESC, track_name_norm, id',
      'track': 'track_name_norm, artist_name_norm, id',
      'artist': 'artist_name_norm, track_name_norm, id',
      'album': 'album_name_norm, track_name_norm, id',
      'genre': 'sort_genre, track_name_norm, id',
      'release': 'sort_release, track_name_norm, id',
    }.entries) {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_library_queue_${order.key} ON library(${order.value})',
      );
    }
  }
}
