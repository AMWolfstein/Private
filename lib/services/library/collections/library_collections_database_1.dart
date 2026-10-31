part of 'library_collections_database.dart';

extension LibraryCollectionsDatabasePart1 on LibraryCollectionsDatabase {
  /// A stable paged row file for backup; it never loads playlist UI models.
  Future<LibraryCollectionsSnapshot> exportBackupSnapshot() async =>
      LibraryCollectionsDatabase.writeDatabaseBackupSnapshot(await database);
  Future<List<PlaylistPickerSummary>> loadPlaylistPickerSummaries(
    List<String> requestedTrackKeys,
  ) async => readPlaylistPickerSummaries(await database, requestedTrackKeys);
}
