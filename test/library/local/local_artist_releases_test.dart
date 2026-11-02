import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/providers/library/library_browse_provider.dart';
import 'package:sistrum/services/library/database/library_database.dart';
import '../../support/library_paging_fixture.dart';
import '../../support/sqlite_process_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'artist newest release follows tags; partial albums and EPs remain albums',
    () async {
      final db = await SqliteProcessDatabase.open();
      addTearDown(db.close);
      final store = await createLibraryPagingFixture(db, albumsPerSource: 0);
      Future<void> release(
        String name,
        String? date,
        int? total, {
        int discs = 1,
        String scanned = '2026-10-18T00:00:00Z',
        String? cover,
        String owner = 'Test Artist',
        String performer = 'Test Artist',
      }) async {
        await db.insert('library', {
          'id': name,
          'track_name': name,
          'artist_name': performer,
          'album_artist': owner,
          'album_name': name,
          'album_key': name.toLowerCase(),
          'track_name_norm': name.toLowerCase(),
          'artist_name_norm': performer.toLowerCase(),
          'album_artist_norm': owner.toLowerCase(),
          'album_name_norm': name.toLowerCase(),
          'file_path': '/music/$name.flac',
          'scanned_at': scanned,
          'release_date': date,
          'cover_path': cover,
          'total_tracks': total,
          'total_discs': discs,
          'track_number': 1,
        });
      }

      await release('Old album added today', '2020-01-01', 12);
      await release(
        'New album',
        '2026-09-01',
        12,
        scanned: '2026-09-05T00:00:00Z',
        cover: '/new.jpg',
      );
      await release('Newest single', '2026-10-01', 1);
      await release('EP', '2025-01-01', 4);
      await release('Unknown total', null, null);
      await release('One track per disc', '2024-01-01', 1, discs: 2);
      const request = LibraryBrowseDbQuery(
        albumArtist: 'Test Artist',
        includeSingleTrackAlbums: true,
        sortMode: 'artist-releases-newest',
        limit: 2,
      );
      final all = <LibraryBrowseEntry>[];
      LibraryBrowseDbCursor? cursor;
      do {
        final page = await store.albumPage(
          LibraryBrowseDbQuery(
            albumArtist: request.albumArtist,
            includeSingleTrackAlbums: true,
            sortMode: request.sortMode,
            limit: request.limit,
            offset: all.length,
            cursor: cursor,
          ),
        );
        all.addAll(
          page.rows.map(
            (row) => LibraryBrowseEntry.fromRow(row, isArtist: false),
          ),
        );
        cursor = page.nextCursor;
        if (page.rows.length < request.limit) break;
      } while (all.length < 20);
      expect(all.map((entry) => entry.name), [
        'Newest single',
        'New album',
        'EP',
        'One track per disc',
        'Old album added today',
        'Unknown total',
      ]);
      expect(all.first.releaseDate, '2026-10-01');
      expect(
        all.where((entry) => entry.isSingleRelease).map((entry) => entry.name),
        ['Newest single'],
      );
      final partial = all.singleWhere((entry) => entry.name == 'New album');
      expect(
        partial.trackCount,
        1,
      ); // Only one downloaded/scanned track is present.
      expect(partial.totalTracks, 12);
      expect(partial.isSingleRelease, false);
      await release(
        'Solo newest single',
        '2028',
        1,
        owner: 'Solo',
        performer: 'Solo',
        cover: '/solo-new.jpg',
        scanned: '2025-01-01T00:00:00Z',
      );
      await release(
        'Solo old single added later',
        '2020',
        1,
        owner: 'Solo',
        performer: 'Solo',
        cover: '/solo-old.jpg',
        scanned: '2030-01-01T00:00:00Z',
      );
      final soloDirectory = await store.artistPage(
        const LibraryBrowseDbQuery(),
      );
      expect(
        soloDirectory.singleWhere(
          (r) => r['artist_name'] == 'Solo',
        )['cover_path'],
        '/solo-new.jpg',
      );
      await release(
        'Guest appearance',
        '2031',
        12,
        owner: 'Other Artist',
        cover: '/guest.jpg',
      );
      for (var i = 0; i < 45; i++) {
        await release('Newer single $i', '2030', 1, cover: '/single.jpg');
      }
      const featureRequest = LibraryBrowseDbQuery(
        albumArtist: 'Test Artist',
        artistCredit: LibraryArtistCredit.albumArtist,
        releaseKind: LibraryReleaseKind.albums,
        includeSingleTrackAlbums: true,
        sortMode: 'artist-releases-newest',
        limit: 1,
      );
      final feature = await store.albumPage(featureRequest);
      expect(feature.rows.single['album_name'], 'New album');
      final directory = await store.artistPage(const LibraryBrowseDbQuery());
      expect(
        directory.singleWhere(
          (r) => r['artist_name'] == 'Test Artist',
        )['cover_path'],
        '/new.jpg',
      );
      await release('Fresh album', '2027/01/01', 10, cover: '/fresh.jpg');
      expect(
        (await store.albumPage(featureRequest)).rows.single['album_name'],
        'Fresh album',
      );
      final refreshed = await store.artistPage(const LibraryBrowseDbQuery());
      expect(
        refreshed.singleWhere(
          (r) => r['artist_name'] == 'Test Artist',
        )['cover_path'],
        '/fresh.jpg',
      );
      await db.rawUpdate(
        "UPDATE library SET cover_path = NULL WHERE id = 'Fresh album'",
      );
      final missingCover = await store.artistPage(const LibraryBrowseDbQuery());
      expect(
        missingCover.singleWhere(
          (r) => r['artist_name'] == 'Test Artist',
        )['cover_path'],
        '',
      );

      expect(
        all.singleWhere((entry) => entry.name == 'EP').isSingleRelease,
        false,
      );
      expect(
        all
            .singleWhere((entry) => entry.name == 'Unknown total')
            .isSingleRelease,
        false,
      );
    },
  );
}
