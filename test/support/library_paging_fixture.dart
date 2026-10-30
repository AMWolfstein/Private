import 'package:sqflite/sqflite.dart';
import 'package:sistrum/providers/library_browse_provider.dart';
import 'package:sistrum/services/library/browse/library_browse_store.dart';
import 'package:sistrum/services/library/database/library_schema.dart';

/// Real schema17 local rows, album ties and an unavailable source. The history
/// read fixture keeps the same named columns and covering album index as the
/// app so the completeness join stays exercised; no network or production DB
/// is touched.
Future<LibraryBrowseStore> createLibraryPagingFixture(
  Database db, {
  int albumsPerSource = 1000,
  String cover = '',
}) async {
  await LibrarySchema.create(db, LibrarySchema.version);
  await db.insert('library_sources', {
    'id': 'offline',
    'path': '/fixture/offline',
    'display_name': 'Offline fixture',
    'available': 0,
  });
  final batch = db.batch();
  void add(int index, int number) {
    final suffix = index.toString().padLeft(4, '0');
    final album = 'Album $suffix';
    final artist = 'Artist $suffix';
    final id = 'local-$index-$number';
    final path = '/fixture/local-$index-$number.flac';
    final fields = <String, Object?>{
      'id': id,
      'track_name': 'Song $number',
      'artist_name': artist,
      'album_artist': artist,
      'album_name': album,
      'album_key': '${album.toLowerCase()}|${artist.toLowerCase()}',
      'file_path': path,
      'track_number': number,
      'disc_number': 1,
      'total_tracks': index % 3 == 2
          ? null
          : index % 3 == 1
          ? 4
          : 2,
      'total_discs': 1,
      'sort_added': index ~/ 4,
      'release_date': '2026',
      'search_text': '$album $artist song $number'.toLowerCase(),
      'sort_genre': '',
      'sort_release': '2026',
      'source_id': 'legacy',
      'scanned_at': '2026-10-07T00:00:00Z',
      'track_name_norm': 'song $number',
      'artist_name_norm': artist.toLowerCase(),
      'album_artist_norm': artist.toLowerCase(),
      'album_name_norm': album.toLowerCase(),
      'cover_path': cover,
    };
    batch.insert('library', fields);
    batch.insert('library_path_keys', {'item_id': id, 'path_key': path});
  }

  for (var index = 0; index < albumsPerSource; index++) {
    for (var number = 1; number <= 2; number++) {
      add(index, number);
    }
  }
  batch.insert('library', {
    'id': 'hidden',
    'source_id': 'offline',
    'track_name': 'Hidden track',
    'artist_name': 'Hidden artist',
    'album_name': 'Hidden album',
    'album_key': 'hidden|hidden',
    'file_path': '/fixture/hidden.flac',
    'scanned_at': '2026-10-07T00:00:00Z',
  });
  await batch.commit(noResult: true);
  return LibraryBrowseStore(db, localFts: false);
}

Future<LibraryBrowsePage> readLibraryPagingFixture(
  LibraryBrowseStore store,
  LibraryBrowsePageRequest request,
) async {
  final query = libraryBrowseQuery(request);
  if (request.browse.artists) {
    return LibraryBrowsePage.fromRows(
      await store.artistPage(query),
      artists: true,
    );
  }
  final page = await store.albumPage(query);
  return LibraryBrowsePage.fromRows(
    page.rows,
    artists: false,
    nextCursor: page.nextCursor,
  );
}

List<String> libraryPagingIdentities(Iterable<LibraryBrowseEntry> entries) => [
  for (final entry in entries)
    '${entry.source}:${entry.key}:${entry.trackCount}:${entry.completeness?.badge}',
];
