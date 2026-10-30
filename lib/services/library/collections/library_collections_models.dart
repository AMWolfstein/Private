class LibraryCollectionsSnapshot {
  final List<Map<String, dynamic>> lovedRows;
  final List<Map<String, dynamic>> playlistRows;
  final List<Map<String, dynamic>> playlistTrackRows;
  final List<Map<String, dynamic>> favoriteArtistRows;
  final String? nativeRowsPath;
  final String? nativeRowsDirectory;
  final int? nativeRowCount;

  const LibraryCollectionsSnapshot({
    required this.lovedRows,
    required this.playlistRows,
    required this.playlistTrackRows,
    required this.favoriteArtistRows,
    this.nativeRowsPath,
    this.nativeRowsDirectory,
    this.nativeRowCount,
  });
}

class LibraryPlaylistTracksSnapshot {
  const LibraryPlaylistTracksSnapshot({
    this.rows = const [],
    this.nativeRowsPath,
    this.nativeRowsDirectory,
    this.nativeRowCount,
  });
  final List<Map<String, dynamic>> rows;
  final String? nativeRowsPath;
  final String? nativeRowsDirectory;
  final int? nativeRowCount;
}

typedef NativeCollectionsJobRunner =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> request);
