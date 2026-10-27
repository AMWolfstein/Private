import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sistrum/services/library_database_models.dart';
import 'package:sistrum/services/library_row_mapper.dart';
import 'package:sistrum/services/sqlite_helpers.dart' as sqlite;
import 'package:sistrum/utils/ios_container_paths.dart';
import 'package:sistrum/utils/logger.dart';

final _log = AppLogger('LibraryDatabase');

/// Schema lifecycle is independent of collection reads and scan transactions.
abstract final class LibrarySchema {
  static const version = 20;
  static const visibleView = 'library_visible';
  static const searchFtsTable = 'library_search_fts';

  /// Retired table name; only the v20 upgrade still refers to it.
  static const lookupSummaryTable = 'library_lookup_summary';
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

  static Future<void> upgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    _log.i('Upgrading library database from v$oldVersion to v$newVersion');
    // Keep historical defaults: older rows require a metadata rescan, while
    // freshly scanned rows are written with their actual scan version.
    for (final addition in const [
      (2, 'cover_path', 'TEXT'),
      (3, 'file_mod_time', 'INTEGER'),
      (4, 'bitrate', 'INTEGER'),
      (5, 'label', 'TEXT'),
      (5, 'copyright', 'TEXT'),
      (6, 'total_tracks', 'INTEGER'),
      (6, 'total_discs', 'INTEGER'),
      (6, 'composer', 'TEXT'),
    ]) {
      if (oldVersion < addition.$1) {
        await db.execute(
          'ALTER TABLE library ADD COLUMN ${addition.$2} ${addition.$3}',
        );
      }
    }
    if (oldVersion < 7) {
      for (final column in const [
        'track_name_norm',
        'artist_name_norm',
        'album_name_norm',
        'album_artist_norm',
        'match_key',
        'album_key',
      ]) {
        await sqlite.addColumnIfMissing(db, 'library', column, 'TEXT');
      }
      await _backfillNormalizedColumns(db);
      await _createNormalizedIndexes(db);
    }
    if (oldVersion < 8) {
      await sqlite.createPathKeyTable(db, 'library_path_keys');
    }
    if (oldVersion < 9) {
      await sqlite.addColumnIfMissing(
        db,
        'library',
        'audio_metadata_scan_version',
        'INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 10) {
      for (final column in const [
        'search_text',
        'search_track',
        'search_album',
        'search_artist',
        'sort_genre',
        'sort_release',
        'sort_added',
      ]) {
        await sqlite.addColumnIfMissing(
          db,
          'library',
          column,
          column == 'sort_added' ? 'INTEGER' : 'TEXT',
        );
      }
      await _backfillQueueColumns(db);
      await _createQueueIndexes(db);
    }
    if (oldVersion < 11) {
      await sqlite.addColumnIfMissing(
        db,
        'library',
        'source_id',
        "TEXT NOT NULL DEFAULT '$_legacySourceId'",
      );
      await _createSources(db);
    }
    for (final addition in const [(12, 'explicit'), (13, 'has_lyrics')]) {
      if (oldVersion < addition.$1) {
        await sqlite.addColumnIfMissing(
          db,
          'library',
          addition.$2,
          'INTEGER NOT NULL DEFAULT 0',
        );
      }
    }
    if (oldVersion < 15) {
      await sqlite.addColumnIfMissing(
        db,
        'library',
        'has_replaygain',
        'INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 16) {
      await sqlite.backfillPathKeys(db, 'library', 'library_path_keys');
    }
    if (oldVersion < 18) {
      for (final column in const [
        'search_track',
        'search_album',
        'search_artist',
      ]) {
        await sqlite.addColumnIfMissing(db, 'library', column, 'TEXT');
      }
      // Only derived search/genre fields change. Track IDs, album/match keys,
      // source ownership and collection references remain byte-for-byte stable.
      await _backfillQueueColumns(db);
    }
    if (oldVersion < 19) {
      // PERF-401: artist pages and the Artists shelf filter, group and order
      // by album_artist_norm; without the index every page scans the library.
      await _createNormalizedIndexes(db);
    }
    if (oldVersion < 20) {
      await _dropLegacyLookupSummary(db);
    }
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

  static Future<void> _backfillNormalizedColumns(Database db) async {
    final rows = await db.query(
      'library',
      columns: [
        'id',
        'track_name',
        'artist_name',
        'album_name',
        'album_artist',
      ],
    );
    final batch = db.batch();
    for (final row in rows) {
      batch.update(
        'library',
        LibraryRowMapper.normalized(
          trackName: row['track_name'] as String? ?? '',
          artistName: row['artist_name'] as String? ?? '',
          albumName: row['album_name'] as String? ?? '',
          albumArtist: row['album_artist'] as String?,
        ),
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
    await batch.commit(noResult: true);
  }

  static Future<void> _backfillQueueColumns(Database db) async {
    String? afterId;
    while (true) {
      final rows = await db.query(
        'library',
        columns: [
          'id',
          'track_name',
          'artist_name',
          'album_name',
          'album_artist',
          'genre',
          'release_date',
          'file_mod_time',
          'scanned_at',
        ],
        where: afterId == null ? null : 'id > ?',
        whereArgs: afterId == null ? null : [afterId],
        orderBy: 'id',
        limit: 300,
      );
      if (rows.isEmpty) return;
      final batch = db.batch();
      for (final row in rows) {
        batch.update(
          'library',
          LibraryRowMapper.queue(
            trackName: row['track_name'] as String?,
            artistName: row['artist_name'] as String?,
            albumName: row['album_name'] as String?,
            albumArtist: row['album_artist'] as String?,
            genre: row['genre'] as String?,
            releaseDate: row['release_date'] as String?,
            fileModTime: (row['file_mod_time'] as num?)?.toInt(),
            scannedAt: row['scanned_at'] as String?,
          ),
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
      await batch.commit(noResult: true);
      afterId = rows.last['id'] as String;
    }
  }

  /// The lookup summary had no production reader after T9. Triggers go first:
  /// dropping the table while they are attached to `library` would break writes.
  static Future<void> _dropLegacyLookupSummary(DatabaseExecutor db) async {
    for (final kind in const ['isrc', 'match']) {
      for (final operation in const ['insert', 'delete', 'update']) {
        await db.execute(
          'DROP TRIGGER IF EXISTS library_lookup_${operation}_$kind',
        );
      }
    }
    await db.execute('DROP TABLE IF EXISTS $lookupSummaryTable');
  }

  static Future<void> migrateIosContainerPaths(Database db) async {
    if (!Platform.isIOS) return;
    final documents = await getApplicationDocumentsDirectory();
    await db.transaction((txn) async {
      final sources = await txn.query(
        'library_sources',
        columns: ['id', 'path'],
        where: "bookmark IS NULL OR bookmark = ''",
      );
      final localSourceIds = sources.map((source) => source['id']).toSet();
      final rows = await txn.query(
        'library',
        columns: ['id', 'source_id', 'file_path', 'cover_path'],
      );
      final batch = txn.batch();
      for (final row in rows) {
        final updates = <String, Object?>{};
        for (final column in ['file_path', 'cover_path']) {
          // External audio paths remain bookmark-owned. Extracted covers
          // always belong to our sandbox, including bookmarked sources.
          if (column == 'file_path' &&
              !localSourceIds.contains(row['source_id'])) {
            continue;
          }
          final previous = row[column] as String?;
          if (previous == null) continue;
          final current = rebaseIosSandboxPath(previous, documents.path);
          if (current != previous) updates[column] = current;
        }
        if (updates.isEmpty) continue;
        final id = row['id'] as String;
        batch.update('library', updates, where: 'id = ?', whereArgs: [id]);
        if (updates.containsKey('file_path')) {
          sqlite.putPathKeysInBatch(
            batch,
            'library_path_keys',
            id,
            updates['file_path'] as String,
          );
        }
      }
      for (final source in sources) {
        final previous = source['path'] as String;
        final current = rebaseIosSandboxPath(previous, documents.path);
        if (current == previous) continue;
        batch.update(
          'library_sources',
          {'path': current},
          where: 'id = ?',
          whereArgs: [source['id']],
        );
      }
      await batch.commit(noResult: true);
    });
  }
}
