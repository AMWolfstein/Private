import 'package:sistrum/services/native/library_scan_bridge.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sistrum/models/local_library_item.dart';
import 'package:sistrum/utils/logger.dart';
import 'package:sistrum/utils/audio_format_utils.dart';
import 'package:sistrum/services/library/library_browse_store.dart';
import 'package:sistrum/services/library/library_file_sizes.dart';
import 'package:sistrum/services/library/library_cleanup.dart';
import 'package:sistrum/services/library/library_search.dart';
import 'package:sistrum/services/library/library_database_models.dart';
import 'package:sistrum/services/library/library_duplicates.dart';
import 'package:sistrum/services/library/library_native_adapter.dart';
import 'package:sistrum/services/library/library_row_mapper.dart';
import 'package:sistrum/services/library/library_schema.dart';
import 'package:sistrum/services/library/library_tag_credits.dart';
import 'package:sistrum/services/library/sqlite_helpers.dart' as sqlite;

export 'library_database_models.dart';

export 'library_browse_filters.dart'
    show confirmedMissingLyricsSqlPredicate, missingReplayGainSqlPredicate;

part 'library_database_queries.dart';

final _log = AppLogger('LibraryDatabase');

class LibraryDatabase {
  static final LibraryDatabase instance = LibraryDatabase._init();
  // The FTS table is a derived, optional index and is initialized lazily after
  // the existing schema migration, so it does not require a user_version bump.
  static const int schemaVersion = LibrarySchema.version;
  static const String legacySourceId = LocalLibraryItem.legacySourceId;
  static const String visibleLibraryView = LibrarySchema.visibleView;
  static const String searchFtsTable = LibrarySchema.searchFtsTable;
  // v4 records ReplayGain availability; older rows rescan once.
  static const int audioMetadataScanVersion = libraryAudioMetadataScanVersion;

  /// First scan version whose rows record lyrics availability (v3).
  static const int lyricsMetadataScanVersion = libraryLyricsMetadataScanVersion;
  static final sqlite.SingleFlightInitializer<Database> _database =
      sqlite.SingleFlightInitializer<Database>();
  // null means this database connection has not attempted FTS setup yet.
  // false is a completed capability/setup result and must not be retried.
  bool? _searchFtsAvailable;
  LibraryFileSizes? _fileSizes;

  LibraryDatabase._init();

  Future<Database> get database {
    return _database.getOrCreate(() async {
      final db = await sqlite.openAppDatabase(
        'local_library.db',
        version: schemaVersion,
        onCreate: (db, version) async {
          _searchFtsAvailable = await LibrarySchema.create(db, version);
        },
        onUpgrade: LibrarySchema.upgrade,
      );
      // Library upserts use INSERT OR REPLACE. Recursive triggers ensure the
      // implicit delete also fires the external-content FTS delete trigger.
      await db.execute('PRAGMA recursive_triggers = ON');
      // onCreate normally initializes this derived index. Retry once after
      // opening an existing database in case an earlier setup was
      // interrupted; unsupported SQLite builds remain on the LIKE fallback.
      _searchFtsAvailable ??= await LibrarySchema.createSearchFts(db);
      return db;
    });
  }

  /// Keeps native scan output native through parsing, indexing and the atomic
  /// source swap.
  Future<({int inserted})> replaceSourceScanFile(
    String sourceId,
    LibraryScanNDJSONFile scan, {
    required String requestId,
    required bool Function() isCancelled,
  }) async {
    if (isCancelled()) throw StateError('Library scan cancelled');
    final db = await database;

    final result = await LibraryNativeAdapter(db).importScanFile(
      sourceId,
      scan,
      requestId: requestId,
      isCancelled: isCancelled,
    );
    return (inserted: (result['inserted'] as num).toInt());
  }

  /// Exports timestamps directly from the DB on the worker. Android's adapter
  /// backfills zero SAF timestamps in bounded ContentResolver batches first.
  Future<String> exportNativeFileModTimesSnapshot(
    String sourceId, {
    required String requestId,
    required bool Function() isCancelled,
  }) async {
    return LibraryNativeAdapter(await database).writeFileModTimesSnapshot(
      sourceId,
      requestId: requestId,
      isCancelled: isCancelled,
    );
  }

  /// Native folder scanning and delta ingestion share one operation, so delta
  /// track maps never return to Flutter. SAF traversal stays in its OS adapter.
  Future<Map<String, dynamic>> scanIncrementalNative(
    String sourceId,
    String folderPath,
    String snapshotPath, {
    required bool isSaf,
    required String requestId,
    required bool Function() isCancelled,
  }) async {
    final db = await database;

    return LibraryNativeAdapter(db).scanIncremental(
      sourceId,
      folderPath,
      snapshotPath,
      isSaf: isSaf,
      requestId: requestId,
      isCancelled: isCancelled,
    );
  }

  static String normalizeLookupText(String? value) =>
      sqlite.normalizeLookupText(value);

  static String matchKeyFor(String trackName, String artistName) {
    return '${normalizeLookupText(trackName)}|${normalizeLookupText(artistName)}';
  }

  Future<List<LocalLibrarySource>> getSources() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT s.*, COUNT(l.id) AS track_count
      FROM library_sources s
      LEFT JOIN library l ON l.source_id = s.id
      GROUP BY s.id
      HAVING s.path != 'legacy://local-library' OR COUNT(l.id) > 0
      ORDER BY s.is_removable, LOWER(s.display_name), LOWER(s.path)
    ''');
    return rows.map(_sourceFromRow).toList(growable: false);
  }

  Future<LocalLibrarySource?> getSourceByPath(String path) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT s.*, COUNT(l.id) AS track_count
      FROM library_sources s
      LEFT JOIN library l ON l.source_id = s.id
      WHERE s.path = ?
      GROUP BY s.id
      LIMIT 1
      ''',
      [path],
    );
    return rows.isEmpty ? null : _sourceFromRow(rows.first);
  }

  LocalLibrarySource _sourceFromRow(Map<String, Object?> row) {
    DateTime? parseDate(Object? value) =>
        value is String ? DateTime.tryParse(value) : null;
    return LocalLibrarySource(
      id: row['id'] as String,
      path: row['path'] as String,
      displayName: row['display_name'] as String,
      volumeId: row['volume_id'] as String?,
      isRemovable: (row['is_removable'] as num?)?.toInt() == 1,
      enabled: (row['enabled'] as num?)?.toInt() != 0,
      available: (row['available'] as num?)?.toInt() != 0,
      trackCount: (row['track_count'] as num?)?.toInt() ?? 0,
      lastScannedAt: parseDate(row['last_scanned_at']),
      lastSeenAt: parseDate(row['last_seen_at']),
      lastScanError: row['last_scan_error'] as String?,
    );
  }

  Future<void> updateSourceState(
    String sourceId, {
    bool? enabled,
    bool? available,
    DateTime? lastScannedAt,
    DateTime? lastSeenAt,
    String? lastScanError,
    bool clearLastScanError = false,
  }) async {
    final values = <String, Object?>{};
    if (enabled != null) values['enabled'] = enabled ? 1 : 0;
    if (available != null) values['available'] = available ? 1 : 0;
    if (lastScannedAt != null) {
      values['last_scanned_at'] = lastScannedAt.toIso8601String();
    }
    if (lastSeenAt != null) {
      values['last_seen_at'] = lastSeenAt.toIso8601String();
    }
    if (lastScanError != null || clearLastScanError) {
      values['last_scan_error'] = clearLastScanError ? null : lastScanError;
    }
    if (values.isEmpty) return;
    final db = await database;
    await db.update(
      'library_sources',
      values,
      where: 'id = ?',
      whereArgs: [sourceId],
    );
  }

  Future<void> removeSource(String sourceId) async {
    final db = await database;
    await sqlite.transactionWithBusyRetry(db, (txn) async {
      await txn.rawDelete(
        'DELETE FROM library_path_keys WHERE item_id IN '
        '(SELECT id FROM library WHERE source_id = ?)',
        [sourceId],
      );
      await txn.delete(
        'library',
        where: 'source_id = ?',
        whereArgs: [sourceId],
      );
      if (sourceId == legacySourceId) {
        await txn.update(
          'library_sources',
          {
            'path': 'legacy://local-library',
            'display_name': 'Music',
            'bookmark': null,
            'volume_id': null,
            'is_removable': 0,
            'enabled': 1,
            'available': 1,
            'last_scanned_at': null,
            'last_seen_at': null,
            'last_scan_error': null,
          },
          where: 'id = ?',
          whereArgs: [sourceId],
        );
      } else {
        await txn.delete(
          'library_sources',
          where: 'id = ?',
          whereArgs: [sourceId],
        );
      }
    });
  }

  /// Resolves a track list with a bounded number of indexed queries instead
  /// of issuing up to three SQLite calls for every track.
  Future<List<Map<String, dynamic>?>> findExistingBatch(
    List<LocalLibraryBatchLookupRequest> requests,
  ) async {
    if (requests.isEmpty) return const [];
    final db = await database;
    final byId = <String, Map<String, dynamic>>{};
    final byIsrc = <String, Map<String, dynamic>>{};
    final byMatchKey = <String, Map<String, dynamic>>{};

    Future<void> loadColumn(
      String column,
      Iterable<String> rawValues,
      Map<String, Map<String, dynamic>> destination,
    ) {
      return sqlite.loadRowsByColumn(
        db,
        table: visibleLibraryView,
        column: column,
        rawValues: rawValues,
        destination: destination,
        mapRow: LibraryRowMapper.decode,
      );
    }

    await Future.wait([
      loadColumn('id', requests.map((request) => request.id ?? ''), byId),
      loadColumn('isrc', requests.map((request) => request.isrc ?? ''), byIsrc),
      loadColumn(
        'match_key',
        requests.map(
          (request) => matchKeyFor(request.trackName, request.artistName),
        ),
        byMatchKey,
      ),
    ]);

    return requests
        .map((request) {
          final id = request.id?.trim() ?? '';
          if (id.isNotEmpty && byId[id] != null) return byId[id];
          final isrc = request.isrc?.trim() ?? '';
          if (isrc.isNotEmpty && byIsrc[isrc] != null) return byIsrc[isrc];
          return byMatchKey[matchKeyFor(request.trackName, request.artistName)];
        })
        .toList(growable: false);
  }

  Future<List<String>> getPhysicalFileIds(Iterable<String> filePaths) async =>
      sqlite.findPhysicalFileRowIds(await database, 'library', filePaths);

  Future<void> deleteByIds(Iterable<String> ids) async {
    if (ids.isEmpty) return;
    await deleteLibraryItemsByIds(await database, ids);
  }

  Future<void> clearAll() async {
    final db = await database;
    await sqlite.transactionWithBusyRetry(db, (txn) async {
      await txn.delete('library_path_keys');
      await txn.delete('library');
      await txn.update('library_sources', {
        'last_scanned_at': null,
        'last_scan_error': null,
      });
    });
    _log.i('Cleared all library data');
  }

  Future<int> getCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $visibleLibraryView',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> getSourceCount(String sourceId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM library WHERE source_id = ?',
      [sourceId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
