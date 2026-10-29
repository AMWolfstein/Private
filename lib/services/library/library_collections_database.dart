import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sistrum/models/library_collections.dart';
import 'package:sistrum/services/library/collection_restore_codec.dart';
import 'package:sistrum/services/library/collection_track_batch.dart';
import 'package:sistrum/services/library/library_collections_models.dart';
import 'package:sistrum/services/library/library_collections_read.dart';
import 'package:sistrum/services/library/library_collections_schema.dart';
import 'package:sistrum/services/library/sqlite_helpers.dart' as sqlite;
import 'package:sistrum/services/library/sqlite_native_snapshot.dart';
import 'package:sistrum/services/native/native_data_jobs.dart';
import 'package:sistrum/utils/logger.dart';

export 'library_collections_models.dart';

final _log = AppLogger('LibraryCollectionsDb');

class LibraryCollectionsDatabase {
  static int _restoreAttachmentSequence = 0;
  static final LibraryCollectionsDatabase instance =
      LibraryCollectionsDatabase._init();
  static final sqlite.SingleFlightInitializer<Database> _database =
      sqlite.SingleFlightInitializer<Database>();

  LibraryCollectionsDatabase._init();

  Future<Database> get database {
    return _database.getOrCreate(
      () => sqlite.openAppDatabase(
        dbFileName,
        version: dbVersion,
        foreignKeys: true,
        onCreate: createCollectionsSchema,
        onUpgrade: upgradeDatabaseSchema,
      ),
    );
  }

  /// Rust pins the collections schema at v4. Databases older than that are not
  /// upgraded.
  static Future<void> upgradeDatabaseSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    _log.i(
      'Collections database v$oldVersion needs no upgrade to v$newVersion',
    );
  }

  /// A stable paged row file for backup; it never loads playlist UI models.
  Future<LibraryCollectionsSnapshot> exportBackupSnapshot() async =>
      writeDatabaseBackupSnapshot(await database);

  static Future<LibraryCollectionsSnapshot> writeDatabaseBackupSnapshot(
    Database db, {
    Directory? temporaryDirectory,
  }) async {
    final directory =
        await (temporaryDirectory ?? await getTemporaryDirectory()).createTemp(
          'collection-backup-',
        );
    final path = '${directory.path}/rows.ndjson';
    final output = File(path).openWrite();
    var count = 0;
    try {
      await db.transaction((txn) async {
        for (final (table, kind, date, ascending) in [
          (tableLoved, 'loved', 'added_at', false),
          (tablePlaylists, 'playlist', 'created_at', false),
          (tableFavoriteArtists, 'artist', 'added_at', false),
          (tablePlaylistTracks, 'backup_track', 'added_at', true),
        ]) {
          Object? lastDate;
          int? lastRow;
          final direction = ascending ? 'ASC' : 'DESC';
          final compare = ascending ? '>' : '<';
          while (true) {
            final rows = await txn.rawQuery(
              'SELECT rowid AS __row, * FROM $table '
              '${lastRow == null ? '' : 'WHERE $date$compare? OR ($date=? AND rowid$compare?)'} '
              'ORDER BY $date $direction,rowid $direction LIMIT 256',
              lastRow == null ? const [] : [lastDate, lastDate, lastRow],
            );
            if (rows.isEmpty) break;
            for (final row in rows) {
              final values = Map<String, dynamic>.from(row)..remove('__row');
              output.writeln(jsonEncode({'kind': kind, 'row': values}));
              count++;
            }
            await output.flush();
            lastDate = rows.last[date];
            lastRow = rows.last['__row'] as int;
            if (rows.length < 256) break;
          }
        }
      });
      await output.close();
      return LibraryCollectionsSnapshot(
        lovedRows: const [],
        playlistRows: const [],
        playlistTrackRows: const [],
        favoriteArtistRows: const [],
        nativeRowsPath: path,
        nativeRowsDirectory: directory.path,
        nativeRowCount: count,
      );
    } catch (_) {
      await output.close();
      await directory.delete(recursive: true);
      rethrow;
    }
  }

  Future<LibraryCollectionsSnapshot> loadSnapshot() async =>
      readDatabaseSnapshot(await database);

  static Future<LibraryCollectionsSnapshot> readDatabaseSnapshot(
    Database db, {
    NativeCollectionsJobRunner? nativeJobRunner,
    Directory? temporaryDirectory,
  }) async {
    final probe = await db.rawQuery('''
      SELECT 1 FROM $tableLoved
      UNION ALL SELECT 1 FROM $tablePlaylists
      UNION ALL SELECT 1 FROM $tablePlaylistTracks
      UNION ALL SELECT 1 FROM $tableFavoriteArtists LIMIT 64
    ''');
    if (probe.length == 64) {
      return readNativeRows(
        db,
        nativeJobRunner: nativeJobRunner,
        temporaryDirectory: temporaryDirectory,
      );
    }
    return readDartSnapshot(db);
  }

  /// Pins the Dart reader for tests; production uses it below the native row
  /// threshold in [readDatabaseSnapshot].
  @visibleForTesting
  static Future<LibraryCollectionsSnapshot> readDartSnapshotForTesting(
    Database db,
  ) => readDartSnapshot(db);

  Future<LibraryPlaylistTracksSnapshot> loadPlaylistTracksSnapshot(
    String playlistId,
  ) async => readDatabasePlaylistTracks(await database, playlistId);

  static Future<LibraryPlaylistTracksSnapshot> readDatabasePlaylistTracks(
    Database db,
    String playlistId, {
    NativeCollectionsJobRunner? nativeJobRunner,
    Directory? temporaryDirectory,
  }) async {
    final probe = await db.rawQuery(
      'SELECT 1 FROM $tablePlaylistTracks WHERE playlist_id=? LIMIT 64',
      [playlistId],
    );
    if (probe.length == 64) {
      final snapshot = await readNativeRows(
        db,
        playlistId: playlistId,
        nativeJobRunner: nativeJobRunner,
        temporaryDirectory: temporaryDirectory,
      );
      return LibraryPlaylistTracksSnapshot(
        nativeRowsPath: snapshot.nativeRowsPath,
        nativeRowsDirectory: snapshot.nativeRowsDirectory,
        nativeRowCount: snapshot.nativeRowCount,
      );
    }
    return readDartPlaylistTracks(db, playlistId);
  }

  /// Pins the Dart playlist-track reader for tests (see
  /// [readDartSnapshotForTesting]).
  @visibleForTesting
  static Future<LibraryPlaylistTracksSnapshot> readDartPlaylistTracksForTesting(
    Database db,
    String playlistId,
  ) => readDartPlaylistTracks(db, playlistId);

  Future<List<PlaylistPickerSummary>> loadPlaylistPickerSummaries(
    List<String> requestedTrackKeys,
  ) async => readPlaylistPickerSummaries(await database, requestedTrackKeys);

  Future<void> _upsertEntry(
    String table,
    String prefix, {
    required String key,
    required String json,
    required String addedAt,
  }) async {
    final db = await database;
    await db.insert(table, {
      '${prefix}_key': key,
      '${prefix}_json': json,
      'added_at': addedAt,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _deleteEntry(String table, String prefix, String key) async {
    final db = await database;
    await db.delete(table, where: '${prefix}_key = ?', whereArgs: [key]);
  }

  Future<void> upsertLovedEntry({
    required String trackKey,
    required String trackJson,
    required String addedAt,
  }) => _upsertEntry(
    tableLoved,
    'track',
    key: trackKey,
    json: trackJson,
    addedAt: addedAt,
  );

  Future<void> deleteLovedEntry(String trackKey) =>
      _deleteEntry(tableLoved, 'track', trackKey);

  Future<void> upsertLovedTracksBatch(List<Map<String, String>> tracks) async {
    if (tracks.isEmpty) return;
    await writeDatabaseLovedTracks(await database, tracks);
  }

  static Future<void> writeDatabaseLovedTracks(
    Database db,
    List<Map<String, String>> tracks,
  ) async {
    if (tracks.isEmpty) return;
    await sqlite.transactionWithBusyRetry(db, (txn) async {
      for (var start = 0; start < tracks.length; start += 128) {
        final batch = txn.batch();
        for (final row in tracks.skip(start).take(128)) {
          batch.insert(
            tableLoved,
            row,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      }
    });
  }

  Future<void> upsertLovedTracksFile({
    required String addedAt,
    required String rowsPath,
    required int expectedCount,
  }) async => publishLovedBatch(
    database: await database,
    addedAt: addedAt,
    rowsPath: rowsPath,
    expectedCount: expectedCount,
  );

  Future<void> deleteLovedTracks(List<String> keys) async {
    if (keys.isEmpty) return;
    await deleteDatabaseLovedTracks(await database, keys);
  }

  static Future<void> deleteDatabaseLovedTracks(
    Database db,
    List<String> keys,
  ) async {
    if (keys.isEmpty) return;
    await sqlite.transactionWithBusyRetry(
      db,
      (txn) => _deleteTrackKeys(txn, tableLoved, keys),
    );
  }

  static Future<void> _deleteTrackKeys(
    DatabaseExecutor db,
    String table,
    List<String> keys, {
    String? playlistId,
  }) async {
    for (var start = 0; start < keys.length; start += 128) {
      final end = start + 128 < keys.length ? start + 128 : keys.length;
      final chunk = keys.sublist(start, end);
      await db.delete(
        table,
        where:
            '${playlistId == null ? '' : 'playlist_id = ? AND '}track_key IN (${List.filled(chunk.length, '?').join(',')})',
        whereArgs: [?playlistId, ...chunk],
      );
    }
  }

  Future<void> upsertFavoriteArtistEntry({
    required String artistKey,
    required String artistJson,
    required String addedAt,
  }) => _upsertEntry(
    tableFavoriteArtists,
    'artist',
    key: artistKey,
    json: artistJson,
    addedAt: addedAt,
  );

  Future<void> deleteFavoriteArtistEntry(String artistKey) =>
      _deleteEntry(tableFavoriteArtists, 'artist', artistKey);

  Future<void> upsertPlaylist({
    required String id,
    required String name,
    required String createdAt,
    required String updatedAt,
    String? coverImagePath,
  }) async {
    final db = await database;
    await db.insert(tablePlaylists, {
      'id': id,
      'name': name,
      'cover_image_path': coverImagePath,
      'created_at': createdAt,
      'updated_at': updatedAt,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> renamePlaylist({
    required String playlistId,
    required String name,
    required String updatedAt,
  }) async {
    final db = await database;
    await db.update(
      tablePlaylists,
      {'name': name, 'updated_at': updatedAt},
      where: 'id = ?',
      whereArgs: [playlistId],
    );
  }

  Future<void> updatePlaylistCover({
    required String playlistId,
    required String updatedAt,
    String? coverImagePath,
  }) async {
    final db = await database;
    await db.update(
      tablePlaylists,
      {'cover_image_path': coverImagePath, 'updated_at': updatedAt},
      where: 'id = ?',
      whereArgs: [playlistId],
    );
  }

  Future<void> deletePlaylists(List<String> playlistIds) async {
    if (playlistIds.isEmpty) return;
    await deleteDatabasePlaylists(await database, playlistIds);
  }

  /// Delete selected parents together; the owner's foreign-key cascade removes
  /// their track memberships without loading track metadata into Dart.
  static Future<void> deleteDatabasePlaylists(
    Database db,
    List<String> playlistIds,
  ) async {
    if (playlistIds.isEmpty) return;
    await sqlite.transactionWithBusyRetry(db, (txn) async {
      for (var start = 0; start < playlistIds.length; start += 128) {
        final end = start + 128 < playlistIds.length
            ? start + 128
            : playlistIds.length;
        final ids = playlistIds.sublist(start, end);
        await txn.delete(
          tablePlaylists,
          where: 'id IN (${List.filled(ids.length, '?').join(',')})',
          whereArgs: ids,
        );
      }
    });
  }

  Future<void> upsertPlaylistTrack({
    required String playlistId,
    required String trackKey,
    required String trackJson,
    required String addedAt,
    required String playlistUpdatedAt,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert(tablePlaylistTracks, {
        'playlist_id': playlistId,
        'track_key': trackKey,
        'track_json': trackJson,
        'added_at': addedAt,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.update(
        tablePlaylists,
        {'updated_at': playlistUpdatedAt},
        where: 'id = ?',
        whereArgs: [playlistId],
      );
    });
  }

  Future<void> upsertPlaylistTracksBatch({
    required String playlistId,
    required String playlistUpdatedAt,
    required List<Map<String, String>> tracks,
  }) async {
    if (tracks.isEmpty) return;
    await writeDatabasePlaylistTracks(
      await database,
      playlistId: playlistId,
      playlistUpdatedAt: playlistUpdatedAt,
      tracks: tracks,
    );
  }

  static Future<void> writeDatabasePlaylistTracks(
    Database db, {
    required String playlistId,
    required String playlistUpdatedAt,
    required List<Map<String, String>> tracks,
  }) async {
    if (tracks.isEmpty) return;
    await sqlite.transactionWithBusyRetry(db, (txn) async {
      var batch = txn.batch();
      var pending = 0;
      for (final track in tracks) {
        batch.insert(tablePlaylistTracks, {
          'playlist_id': playlistId,
          'track_key': track['track_key'],
          'track_json': track['track_json'],
          'added_at': track['added_at'],
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        if (++pending == 128) {
          await batch.commit(noResult: true);
          batch = txn.batch();
          pending = 0;
        }
      }
      batch.update(
        tablePlaylists,
        {'updated_at': playlistUpdatedAt},
        where: 'id = ?',
        whereArgs: [playlistId],
      );
      await batch.commit(noResult: true);
    });
  }

  Future<void> upsertPlaylistTracksFile({
    required String playlistId,
    required String playlistUpdatedAt,
    required String rowsPath,
    required int expectedCount,
  }) async => publishPlaylistBatch(
    database: await database,
    playlistId: playlistId,
    updatedAt: playlistUpdatedAt,
    rowsPath: rowsPath,
    expectedCount: expectedCount,
  );

  Future<void> deletePlaylistTracks({
    required String playlistId,
    required List<String> trackKeys,
    required String playlistUpdatedAt,
  }) async {
    if (trackKeys.isEmpty) return;
    await deleteDatabasePlaylistTracks(
      await database,
      playlistId: playlistId,
      trackKeys: trackKeys,
      playlistUpdatedAt: playlistUpdatedAt,
    );
  }

  static Future<void> deleteDatabasePlaylistTracks(
    Database db, {
    required String playlistId,
    required List<String> trackKeys,
    required String playlistUpdatedAt,
  }) async {
    if (trackKeys.isEmpty) return;
    await sqlite.transactionWithBusyRetry(db, (txn) async {
      await _deleteTrackKeys(
        txn,
        tablePlaylistTracks,
        trackKeys,
        playlistId: playlistId,
      );
      await txn.update(
        tablePlaylists,
        {'updated_at': playlistUpdatedAt},
        where: 'id = ?',
        whereArgs: [playlistId],
      );
    });
  }

  /// Wipes every collection table and rewrites them from a restored backup.
  ///
  /// [collectionsJson] must use the same shape as
  /// `LibraryCollectionsState.toJson()` (loved/playlists/favoriteArtists).
  /// Track entries carry a nested `track` map (stored as `track_json`); favorite
  /// artist entries are stored whole as `artist_json`.
  Future<void> replaceAllFromBackup(
    Map<String, dynamic> collectionsJson,
  ) async {
    final nowIso = DateTime.now().toIso8601String();
    await replaceDatabaseFromBackup(
      await database,
      collectionsJson,
      nowIso: nowIso,
    );
  }

  /// Shares the production restore route with isolated database integration
  /// fixtures. The caller initializes the app-owned schema before native IO.
  static Future<void> replaceDatabaseFromBackup(
    Database db,
    Map<String, dynamic> collectionsJson, {
    String? nowIso,
  }) async {
    final restoreTime = nowIso ?? DateTime.now().toIso8601String();
    final temporary = await Directory(
      (await getTemporaryDirectory()).path,
    ).createTemp('collection-restore-');
    var detached = true;
    try {
      final path = '${temporary.path}/commands.ndjson';
      final count = await writeCollectionRestoreCommands(
        path,
        collectionsJson,
        restoreTime,
      );
      // The native backend bundles its own SQLite. Give it a private file
      // after sqflite closes that file; only the database owner publishes
      // into the live database, preserving its WAL and connection caches.
      final stagedPath = '${temporary.path}/$dbFileName';
      final stagedDatabase = await openDatabase(
        stagedPath,
        version: dbVersion,
        onConfigure: (staged) => staged.execute('PRAGMA foreign_keys=ON'),
        onCreate: createCollectionsSchema,
      );
      detached = false;
      await stagedDatabase.close();
      detached = true;
      final result = await NativeDataJobs.run({
        'operation': 'backup_collections_import',
        'collections_path': stagedPath,
        'ndjson_path': path,
        'expected_count': count,
      });
      if (result['committed'] != true) {
        throw const FormatException('Incomplete collection restore');
      }
      final alias = 'collection_restore_${_restoreAttachmentSequence++}';
      await db.execute('ATTACH DATABASE ? AS $alias', [stagedPath]);
      var committed = false;
      try {
        await db.transaction((txn) async {
          for (final table in [
            tablePlaylistTracks,
            tablePlaylists,
            tableLoved,
            tableFavoriteArtists,
          ]) {
            await txn.delete(table);
          }
          for (final (table, columns) in [
            (tableLoved, 'track_key,track_json,added_at'),
            (tableFavoriteArtists, 'artist_key,artist_json,added_at'),
            (tablePlaylists, 'id,name,cover_image_path,created_at,updated_at'),
            (tablePlaylistTracks, 'playlist_id,track_key,track_json,added_at'),
          ]) {
            await txn.execute(
              'INSERT INTO main.$table($columns) '
              'SELECT $columns FROM $alias.$table ORDER BY rowid',
            );
          }
        });
        committed = true;
      } finally {
        try {
          await detachNativeSqliteSnapshot(db, alias, stagedPath);
        } on NativeSqliteSnapshotDetachException {
          detached = false;
          if (!committed) rethrow;
          _log.w(
            'Collections restored; retaining staging after a failed database detach',
          );
        }
      }
    } on NativeSqliteSnapshotDetachException {
      detached = false;
      _log.w(
        'Retaining collection restore staging after a failed database detach',
      );
      rethrow;
    } finally {
      if (detached) {
        try {
          await temporary.delete(recursive: true);
        } on FileSystemException catch (error) {
          _log.w('Could not remove collection restore staging: $error');
        }
      }
    }
    _log.i('Restored collections from backup');
  }
}

/// Reads picker rows with bounded selection queries, preserving playlist order.
Future<List<PlaylistPickerSummary>> readPlaylistPickerSummaries(
  DatabaseExecutor db,
  List<String> requestedTrackKeys,
) async {
  final uniqueTrackKeys = requestedTrackKeys
      .where((key) => key.trim().isNotEmpty)
      .toSet()
      .toList(growable: false);

  final playlistRows = await db.rawQuery('''
      SELECT
        p.id,
        p.name,
        p.cover_image_path,
        p.created_at,
        p.updated_at,
        COUNT(pt.track_key) AS track_count,
        CASE WHEN p.cover_image_path IS NULL OR p.cover_image_path = '' THEN (
          SELECT preview.track_json
          FROM $tablePlaylistTracks preview
          WHERE preview.playlist_id = p.id
          ORDER BY preview.added_at ASC, preview.rowid ASC
          LIMIT 1
        ) END AS preview_track_json
      FROM $tablePlaylists p
      LEFT JOIN $tablePlaylistTracks pt ON pt.playlist_id = p.id
      GROUP BY p.id
      ORDER BY p.created_at DESC, p.rowid DESC
    ''');

  final matchedCountsByPlaylistId = <String, int>{};
  const chunkSize = 500;
  for (var offset = 0; offset < uniqueTrackKeys.length; offset += chunkSize) {
    final chunk = uniqueTrackKeys.sublist(
      offset,
      (offset + chunkSize).clamp(0, uniqueTrackKeys.length),
    );
    final placeholders = List.filled(chunk.length, '?').join(', ');
    final matchedRows = await db.rawQuery('''
          SELECT playlist_id, COUNT(*) AS matched_count
          FROM $tablePlaylistTracks
          WHERE track_key IN ($placeholders)
          GROUP BY playlist_id
        ''', chunk);
    for (final row in matchedRows) {
      final playlistId = row['playlist_id']?.toString();
      if (playlistId == null || playlistId.isEmpty) continue;
      matchedCountsByPlaylistId[playlistId] =
          (matchedCountsByPlaylistId[playlistId] ?? 0) +
          ((row['matched_count'] as num?)?.toInt() ?? 0);
    }
  }

  return playlistRows
      .map((row) {
        final id = row['id']?.toString() ?? '';
        final createdAt =
            DateTime.tryParse(row['created_at']?.toString() ?? '') ??
            DateTime.now();
        final updatedAt =
            DateTime.tryParse(row['updated_at']?.toString() ?? '') ?? createdAt;
        String? previewCover;
        final previewJson = row['preview_track_json'] as String?;
        if (previewJson != null && previewJson.isNotEmpty) {
          try {
            final decoded = jsonDecode(previewJson);
            if (decoded is Map) {
              final cover = decoded['coverUrl']?.toString();
              if (cover != null && cover.isNotEmpty) previewCover = cover;
            }
          } catch (_) {}
        }
        return PlaylistPickerSummary(
          id: id,
          name: row['name']?.toString() ?? '',
          coverImagePath: row['cover_image_path'] as String?,
          previewCover: previewCover,
          createdAt: createdAt,
          updatedAt: updatedAt,
          trackCount: (row['track_count'] as num?)?.toInt() ?? 0,
          containsAllRequestedTracks:
              uniqueTrackKeys.isNotEmpty &&
              matchedCountsByPlaylistId[id] == uniqueTrackKeys.length,
        );
      })
      .toList(growable: false);
}
