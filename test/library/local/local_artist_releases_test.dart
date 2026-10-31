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
      }) async {
        await db.insert('library', {
          'id': name,
          'track_name': name,
          'artist_name': 'Test Artist',
          'album_artist': 'Test Artist',
          'album_name': name,
          'album_key': name.toLowerCase(),
          'track_name_norm': name.toLowerCase(),
          'artist_name_norm': 'test artist',
          'album_artist_norm': 'test artist',
          'album_name_norm': name.toLowerCase(),
          'file_path': '/music/$name.flac',
          'scanned_at': scanned,
          'release_date': date,
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
