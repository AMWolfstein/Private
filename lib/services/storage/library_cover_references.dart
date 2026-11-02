import 'package:sistrum/services/library/collections/library_collections_database.dart';
import 'package:sistrum/services/storage/app_state_database.dart';
import 'package:sistrum/services/playback/stats/listening_statistics.dart';
import 'package:sistrum/services/library/covers/library_cover_snapshot.dart';

/// Existing local stores only; removed download/history tables stay removed.
Future<List<LibraryCoverReferenceColumn>>
appLibraryCoverReferenceColumns() async {
  final collections = await LibraryCollectionsDatabase.instance.database;
  final appState = await AppStateDatabase.instance.database;
  final statistics = await ListeningStatisticsStore.instance.read(
    (db) async => db,
  );
  return [
    for (final table in ['loved_tracks', 'playlist_tracks'])
      (database: collections, table: table, column: 'track_json'),
    (database: collections, table: 'playlists', column: 'cover_image_path'),
    (database: collections, table: 'favorite_artists', column: 'artist_json'),
    (database: appState, table: 'playback_session', column: 'media_json'),
    (database: statistics, table: 'listening', column: 'artwork'),
  ];
}
