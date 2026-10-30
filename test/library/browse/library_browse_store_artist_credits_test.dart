import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/core/models/local_library_item.dart';
import 'package:sistrum/services/library/browse/library_browse_store.dart';
import 'package:sistrum/services/library/database/library_database_models.dart';
import 'package:sistrum/services/library/database/library_row_mapper.dart';
import 'package:sistrum/services/library/database/library_schema.dart';

import '../../support/sqlite_process_database.dart';

Set<String> _ids(LibraryBrowseDbPage page) => {
  for (final row in page.rows) (row['item'] as Map)['id'] as String,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SqliteProcessDatabase db;
  late LibraryBrowseStore store;

  Future<void> addTrack(
    String id, {
    required String album,
    required String albumArtist,
    required String artist,
    required int number,
  }) async {
    final track = LocalLibraryItem(
      id: id,
      sourceId: 'legacy',
      trackName: 'Song $id',
      artistName: artist,
      albumArtist: albumArtist,
      albumName: album,
      filePath: '/$id.flac',
      scannedAt: DateTime.utc(2026),
      fileModTime: 1,
      trackNumber: number,
      totalTracks: 2,
      discNumber: 1,
      totalDiscs: 1,
      bitDepth: 16,
      genre: 'Pop',
      releaseDate: '2026',
    );
    await db.insert('library', LibraryRowMapper.encode(track.toJson()));
    await db.insert('library_path_keys', {
      'item_id': id,
      'path_key': '/$id.flac',
    });
  }

  Future<Set<String>> tracks(String artist, LibraryArtistCredit credit) async =>
      _ids(
        await store.trackPage(
          LibraryBrowseDbQuery(albumArtist: artist, artistCredit: credit),
        ),
      );

  setUp(() async {
    db = await SqliteProcessDatabase.open();
    await LibrarySchema.create(db, LibrarySchema.version);
    // Album X by A, with one track featuring B.
    await addTrack(
      'x1',
      album: 'Album X',
      albumArtist: 'A',
      artist: 'A, B',
      number: 1,
    );
    await addTrack(
      'x2',
      album: 'Album X',
      albumArtist: 'A',
      artist: 'A',
      number: 2,
    );
    // Album Y by D, with one track featuring C.
    await addTrack(
      'y1',
      album: 'Album Y',
      albumArtist: 'D',
      artist: 'D, C',
      number: 1,
    );
    store = LibraryBrowseStore(db, localFts: false);
  });

  tearDown(() => db.close());

  test('a track tagged "A, B" lists A and B as artists', () async {
    expect(await tracks('A', LibraryArtistCredit.anyCredit), {'x1', 'x2'});
    expect(await tracks('B', LibraryArtistCredit.anyCredit), {'x1'});
  });

  test(
    'a featured-only artist C appears on the release, not in Albums',
    () async {
      expect(await tracks('C', LibraryArtistCredit.anyCredit), {'y1'});
      expect(await tracks('C', LibraryArtistCredit.albumArtist), isEmpty);
      expect(await tracks('C', LibraryArtistCredit.appearsOn), {'y1'});
    },
  );

  test(
    'the Albums shelf of A holds the release with the album artist credit',
    () async {
      expect(await tracks('A', LibraryArtistCredit.albumArtist), {'x1', 'x2'});
      expect(await tracks('B', LibraryArtistCredit.appearsOn), {'x1'});
    },
  );

  test('a release that A owns is excluded from Appears On for A', () async {
    expect(await tracks('A', LibraryArtistCredit.appearsOn), isEmpty);
  });

  test(
    'the artists list includes featured-only artists with their page',
    () async {
      final page = await store.artistPage(
        const LibraryBrowseDbQuery(limit: 100),
      );
      final keys = [for (final row in page) row['artist_key'] as String];
      expect(keys, containsAll(['a', 'b', 'c', 'd']));
    },
  );

  test(
    'the Artists list reads track artists and Album Artists reads album artists',
    () async {
      await addTrack(
        'z1',
        album: 'Album Z',
        albumArtist: 'Z',
        artist: 'W',
        number: 1,
      );
      Future<List<Object?>> keysOf({required bool albumArtistsOnly}) async {
        final page = await store.artistPage(
          LibraryBrowseDbQuery(limit: 100, albumArtistsOnly: albumArtistsOnly),
        );
        return [for (final row in page) row['artist_key']];
      }

      final artists = await keysOf(albumArtistsOnly: false);
      final albumArtists = await keysOf(albumArtistsOnly: true);
      expect(artists, containsAll(['a', 'b', 'c', 'd', 'w']));
      expect(artists, isNot(contains('z')));
      expect(albumArtists, containsAll(['a', 'd', 'z']));
      expect(albumArtists, isNot(contains('w')));
      expect(albumArtists, isNot(contains('b')));
    },
  );
}
