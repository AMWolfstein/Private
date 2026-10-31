part of 'library_collections_database.dart';

extension LibraryCollectionsDatabasePart3 on LibraryCollectionsDatabase {
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
}
