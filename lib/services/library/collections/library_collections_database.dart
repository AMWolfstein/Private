import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sistrum/core/models/library_collections.dart';
import 'package:sistrum/services/library/collections/collection_restore_codec.dart';
import 'package:sistrum/services/library/collections/collection_track_batch.dart';
import 'package:sistrum/services/library/collections/library_collections_models.dart';
import 'package:sistrum/services/library/collections/library_collections_read.dart';
import 'package:sistrum/services/library/collections/library_collections_schema.dart';
import 'package:sistrum/services/library/database/sqlite_helpers.dart'
    as sqlite;
import 'package:sistrum/services/library/database/sqlite_native_snapshot.dart';
import 'package:sistrum/services/native/native_data_jobs.dart';
import 'package:sistrum/utils/logging/logger.dart';

export 'library_collections_models.dart';

part 'library_collections_database_snapshots.dart';
part 'library_collections_database_rows.dart';
part 'library_collections_database_playlists.dart';
part 'library_collections_database_statics.dart';

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
  ) => _LibraryCollectionsDatabaseStatics1.upgradeDatabaseSchema(
    db,
    oldVersion,
    newVersion,
  );

  static Future<LibraryCollectionsSnapshot> writeDatabaseBackupSnapshot(
    Database db, {
    Directory? temporaryDirectory,
  }) => _LibraryCollectionsDatabaseStatics1.writeDatabaseBackupSnapshot(
    db,
    temporaryDirectory: temporaryDirectory,
  );

  Future<LibraryCollectionsSnapshot> loadSnapshot() async =>
      readDatabaseSnapshot(await database);

  static Future<LibraryCollectionsSnapshot> readDatabaseSnapshot(
    Database db, {
    NativeCollectionsJobRunner? nativeJobRunner,
    Directory? temporaryDirectory,
  }) => _LibraryCollectionsDatabaseStatics1.readDatabaseSnapshot(
    db,
    nativeJobRunner: nativeJobRunner,
    temporaryDirectory: temporaryDirectory,
  );

  /// Pins the Dart reader for tests; production uses it below the native row
  /// threshold in [readDatabaseSnapshot].
  @visibleForTesting
  static Future<LibraryCollectionsSnapshot> readDartSnapshotForTesting(
    Database db,
  ) => _LibraryCollectionsDatabaseStatics1.readDartSnapshotForTesting(db);

  Future<LibraryPlaylistTracksSnapshot> loadPlaylistTracksSnapshot(
    String playlistId,
  ) async => readDatabasePlaylistTracks(await database, playlistId);

  static Future<LibraryPlaylistTracksSnapshot> readDatabasePlaylistTracks(
    Database db,
    String playlistId, {
    NativeCollectionsJobRunner? nativeJobRunner,
    Directory? temporaryDirectory,
  }) => _LibraryCollectionsDatabaseStatics1.readDatabasePlaylistTracks(
    db,
    playlistId,
    nativeJobRunner: nativeJobRunner,
    temporaryDirectory: temporaryDirectory,
  );

  /// Pins the Dart playlist-track reader for tests (see
  /// [readDartSnapshotForTesting]).
  @visibleForTesting
  static Future<LibraryPlaylistTracksSnapshot> readDartPlaylistTracksForTesting(
    Database db,
    String playlistId,
  ) => _LibraryCollectionsDatabaseStatics1.readDartPlaylistTracksForTesting(
    db,
    playlistId,
  );

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
  ) => _LibraryCollectionsDatabaseStatics1.writeDatabaseLovedTracks(db, tracks);

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
  ) => _LibraryCollectionsDatabaseStatics1.deleteDatabaseLovedTracks(db, keys);

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

  Future<void> deletePlaylists(List<String> playlistIds) async {
    if (playlistIds.isEmpty) return;
    await deleteDatabasePlaylists(await database, playlistIds);
  }

  /// Delete selected parents together; the owner's foreign-key cascade removes
  /// their track memberships without loading track metadata into Dart.
  static Future<void> deleteDatabasePlaylists(
    Database db,
    List<String> playlistIds,
  ) => _LibraryCollectionsDatabaseStatics1.deleteDatabasePlaylists(
    db,
    playlistIds,
  );

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
  }) => _LibraryCollectionsDatabaseStatics1.writeDatabasePlaylistTracks(
    db,
    playlistId: playlistId,
    playlistUpdatedAt: playlistUpdatedAt,
    tracks: tracks,
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
  }) => _LibraryCollectionsDatabaseStatics1.deleteDatabasePlaylistTracks(
    db,
    playlistId: playlistId,
    trackKeys: trackKeys,
    playlistUpdatedAt: playlistUpdatedAt,
  );

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
  }) => _LibraryCollectionsDatabaseStatics1.replaceDatabaseFromBackup(
    db,
    collectionsJson,
    nowIso: nowIso,
  );
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
