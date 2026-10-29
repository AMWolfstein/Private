
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
import 'package:sistrum/services/library/sqlite_helpers.dart' as sqlite;

export 'library_database_models.dart';

export 'library_browse_store.dart'
    show confirmedMissingLyricsSqlPredicate, missingReplayGainSqlPredicate;

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

  bool get searchFtsAvailable => _searchFtsAvailable ?? false;

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

  Future<List<LibrarySearchHit>> searchLibrary({
    required String query,
    required LibrarySearchKind kind,
    int limit = 40,
    int offset = 0,
  }) async {
    final db = await database;
    return LibrarySearchStore(
      db,
      localFts: searchFtsAvailable,
    ).search(query: query, kind: kind, limit: limit, offset: offset);
  }

  void _putPathKeysInBatch(Batch batch, String id, String? filePath) =>
      sqlite.putPathKeysInBatch(batch, 'library_path_keys', id, filePath);

  static String normalizeLookupText(String? value) =>
      sqlite.normalizeLookupText(value);

  static String matchKeyFor(String trackName, String artistName) {
    return '${normalizeLookupText(trackName)}|${normalizeLookupText(artistName)}';
  }

  Future<void> upsert(Map<String, dynamic> json, {String? sourceId}) async {
    final db = await database;
    await sqlite.transactionWithBusyRetry(db, (txn) async {
      final row = await sqlite.preserveLibraryRowId(
        txn,
        LibraryRowMapper.encode(json, sourceId: sourceId),
      );
      await txn.insert(
        'library',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      final batch = txn.batch();
      _putPathKeysInBatch(
        batch,
        row['id'] as String,
        json['filePath'] as String?,
      );
      await batch.commit(noResult: true);
    });
  }

  Future<void> upsertBatch(
    List<Map<String, dynamic>> items, {
    String? sourceId,
  }) async {
    if (items.isEmpty) return;
    final db = await database;
    await sqlite.transactionWithBusyRetry(db, (txn) async {
      final batch = txn.batch();
      for (final json in items) {
        final row = await sqlite.preserveLibraryRowId(
          txn,
          LibraryRowMapper.encode(json, sourceId: sourceId),
        );
        batch.insert(
          'library',
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        _putPathKeysInBatch(
          batch,
          row['id'] as String,
          json['filePath'] as String?,
        );
      }
      await batch.commit(noResult: true);
    });
    _log.i('Batch inserted ${items.length} items');
  }

  Future<void> replaceAll(List<Map<String, dynamic>> items) async {
    final db = await database;
    await sqlite.transactionWithBusyRetry(db, (txn) async {
      await txn.delete('library_path_keys');
      await txn.delete('library');
      if (items.isEmpty) {
        return;
      }

      final batch = txn.batch();
      for (final json in items) {
        batch.insert(
          'library',
          LibraryRowMapper.encode(json),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        _putPathKeysInBatch(
          batch,
          json['id'] as String,
          json['filePath'] as String?,
        );
      }
      await batch.commit(noResult: true);
    });
    _log.i('Replaced library with ${items.length} items');
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

  Future<void> upsertSource(LocalLibrarySource source) async {
    final db = await database;
    final values = <String, Object?>{
      'path': source.path,
      'display_name': source.displayName,
      'volume_id': source.volumeId,
      'is_removable': source.isRemovable ? 1 : 0,
      'enabled': source.enabled ? 1 : 0,
      'available': source.available ? 1 : 0,
      'last_scanned_at': source.lastScannedAt?.toIso8601String(),
      'last_seen_at': source.lastSeenAt?.toIso8601String(),
      'last_scan_error': source.lastScanError,
    };
    final updated = await db.update(
      'library_sources',
      values,
      where: 'id = ?',
      whereArgs: [source.id],
    );
    if (updated == 0) {
      await db.insert('library_sources', {'id': source.id, ...values});
    }
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

  Future<LibraryBrowseStore> _queueStore([
    LibraryBrowseDbQuery? request,
  ]) async {
    final db = await database;
    if (request != null && isLibrarySizeSort(request.sortMode)) {
      await (_fileSizes ??= LibraryFileSizes(db)).refresh();
    }
    return LibraryBrowseStore(db, localFts: searchFtsAvailable);
  }

  Future<LibraryBrowseDbPage> getBrowseTrackPage(
    LibraryBrowseDbQuery request,
  ) async => (await _queueStore(request)).trackPage(request);

  Future<LibraryBrowseCounts> getQueueCounts(
    LibraryBrowseDbQuery request,
  ) async => (await _queueStore()).counts(request);

  Future<LibraryBrowseDbPage> getBrowseAlbumPage(
    LibraryBrowseDbQuery request,
  ) async => (await _queueStore(request)).albumPage(request);

  /// Album artists across scanned music, excluding duplicate paths.
  Future<List<Map<String, dynamic>>> getBrowseArtistRows(
    LibraryBrowseDbQuery request,
  ) async => (await _queueStore()).artistPage(request);

  Future<List<Map<String, dynamic>>> getBrowseLocalAlbumRows(
    String albumName,
    String artistName,
  ) async => (await _queueStore()).localAlbumTracks(albumName, artistName);

  Future<List<Map<String, dynamic>>> getBrowseLocalAlbumRowsByKey(
    String albumKey,
  ) async => (await _queueStore()).localAlbumTracksByKey(albumKey);

  Future<Map<String, dynamic>?> getById(String id) async {
    final db = await database;
    final rows = await db.query(
      visibleLibraryView,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return LibraryRowMapper.decode(rows.first);
  }

  Future<Map<String, dynamic>?> getByIsrc(String isrc) async {
    final db = await database;
    final rows = await db.query(
      visibleLibraryView,
      where: 'isrc = ?',
      whereArgs: [isrc],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return LibraryRowMapper.decode(rows.first);
  }

  Future<List<Map<String, dynamic>>> findByTrackAndArtist(
    String trackName,
    String artistName,
  ) async {
    final db = await database;
    final rows = await db.query(
      visibleLibraryView,
      where: 'match_key = ?',
      whereArgs: [matchKeyFor(trackName, artistName)],
    );
    return rows.map(LibraryRowMapper.decode).toList();
  }

  Future<Map<String, dynamic>?> findExisting({
    String? isrc,
    String? trackName,
    String? artistName,
  }) async {
    if (isrc != null && isrc.isNotEmpty) {
      final byIsrc = await getByIsrc(isrc);
      if (byIsrc != null) return byIsrc;
    }

    if (trackName != null && artistName != null) {
      final matches = await findByTrackAndArtist(trackName, artistName);
      if (matches.isNotEmpty) return matches.first;
    }

    return null;
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

  /// Physical copies sharing one ISRC, excluding inactive NAS sources and
  /// alternate index/URI references to the same file. Best quality comes first.
  Future<List<IsrcDuplicateGroup>> findIsrcDuplicateGroups() async {
    final db = await database;

    return readIsrcDuplicateGroups(db);
  }

  Future<List<String>> getPhysicalFileIds(Iterable<String> filePaths) async =>
      sqlite.findPhysicalFileRowIds(await database, 'library', filePaths);

  /// Removes one row; shares the batched delete so both paths stay identical.
  Future<int> deleteByPath(String filePath) => deleteByPaths([filePath]);

  Future<void> updateAudioMetadata(
    String id, {
    int? duration,
    int? bitDepth,
    int? sampleRate,
    int? bitrate,
    bool? explicit,
    bool? hasLyrics,
    bool? hasReplayGain,
    String? format,
  }) async {
    final values = <String, dynamic>{};
    if (duration != null && duration > 0) {
      values['duration'] = duration;
    }
    if (bitDepth != null && bitDepth > 0) {
      values['bit_depth'] = bitDepth;
    }
    if (sampleRate != null && sampleRate > 0) {
      values['sample_rate'] = sampleRate;
    }
    if (bitrate != null && bitrate > 0) {
      values['bitrate'] = bitrate;
    }
    if (explicit != null) {
      values['explicit'] = explicit ? 1 : 0;
    }
    if (hasLyrics != null) {
      values['has_lyrics'] = hasLyrics ? 1 : 0;
    }
    if (hasReplayGain != null) {
      values['has_replaygain'] = hasReplayGain ? 1 : 0;
    }
    final normalizedFormat = normalizeAudioFormatValue(format);
    if (normalizedFormat != null) {
      values['format'] = normalizedFormat;
    }
    if (values.isEmpty) return;

    final db = await database;
    if (hasReplayGain == null && hasLyrics == null) {
      await db.update('library', values, where: 'id = ?', whereArgs: [id]);
      return;
    }
    // A quality-only update must not confirm absent tags. ReplayGain-only
    // writes can advance lyrics-aware rows, while older rows still rescan.
    final replayGainOnly = hasReplayGain != null && hasLyrics == null;
    final scanVersion = hasReplayGain != null
        ? audioMetadataScanVersion
        : lyricsMetadataScanVersion;
    final versionSql = replayGainOnly
        ? 'CASE WHEN COALESCE(audio_metadata_scan_version, 0) >= ? '
              'THEN MAX(COALESCE(audio_metadata_scan_version, 0), ?) '
              'ELSE COALESCE(audio_metadata_scan_version, 0) END'
        : 'MAX(COALESCE(audio_metadata_scan_version, 0), ?)';
    final columns = values.keys.toList(growable: false);
    await db.rawUpdate(
      'UPDATE library SET ${columns.map((column) => '$column = ?').join(', ')}, '
      'audio_metadata_scan_version = $versionSql WHERE id = ?',
      [
        ...columns.map((column) => values[column]),
        if (replayGainOnly) lyricsMetadataScanVersion,
        scanVersion,
        id,
      ],
    );
  }

  Future<void> delete(String id) async {
    await deleteByIds([id]);
  }

  Future<void> deleteByIds(Iterable<String> ids) async {
    if (ids.isEmpty) return;
    await deleteLibraryItemsByIds(await database, ids);
  }

  Future<int> cleanupMissingFiles({
    String? sourceId,
    Future<bool> Function()? canDelete,
  }) async {
    final db = await database;
    final removed = await cleanupMissingLibraryRows(
      db,
      sourceId: sourceId,
      canDelete: canDelete,
    );

    if (removed > 0) {
      _log.i('Cleaned up $removed missing files from library');
    }
    return removed;
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

  Future<void> close() async {
    final db = await database;
    await db.close();
    _database.reset();
    _fileSizes = null;
    _searchFtsAvailable = null;
  }

  Future<int> deleteByPaths(List<String> filePaths) async {
    if (filePaths.isEmpty) return 0;
    final db = await database;
    var totalDeleted = 0;
    const chunkSize = 500;
    // One commit for the whole removal; a rescan that dropped a folder can
    // otherwise pay several WAL commits per chunk.
    await sqlite.transactionWithBusyRetry(db, (txn) async {
      for (var i = 0; i < filePaths.length; i += chunkSize) {
        final end = (i + chunkSize < filePaths.length)
            ? i + chunkSize
            : filePaths.length;
        final chunk = filePaths.sublist(i, end);
        final placeholders = List.filled(chunk.length, '?').join(',');
        await txn.rawDelete(
          'DELETE FROM library_path_keys WHERE item_id IN '
          '(SELECT id FROM library WHERE file_path IN ($placeholders))',
          chunk,
        );
        totalDeleted += await txn.rawDelete(
          'DELETE FROM library WHERE file_path IN ($placeholders)',
          chunk,
        );
      }
    });
    if (totalDeleted > 0) {
      _log.i('Deleted $totalDeleted items from library');
    }
    return totalDeleted;
  }
}
