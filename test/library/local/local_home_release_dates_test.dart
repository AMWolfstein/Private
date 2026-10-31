import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/library/database/library_database.dart';
import 'package:sistrum/providers/library/library_browse_provider.dart';
import 'package:sistrum/services/library/browse/library_browse_filters.dart';

import '../../support/library_paging_fixture.dart';
import '../../support/sqlite_process_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Home latest releases uses valid song metadata dates across bounded pages',
    () async {
      final db = await SqliteProcessDatabase.open();
      addTearDown(db.close);
      final store = await createLibraryPagingFixture(db, albumsPerSource: 0);
      Future<void> song(
        String album,
        String? date,
        int added, {
        String suffix = '',
      }) => db
          .insert('library', {
            'id': '$album$suffix',
            'track_name': '$album$suffix',
            'artist_name': 'Artist',
            'album_artist': 'Artist',
            'album_name': album,
            'album_key': album.toLowerCase(),
            'track_name_norm': album.toLowerCase(),
            'artist_name_norm': 'artist',
            'album_artist_norm': 'artist',
            'album_name_norm': album.toLowerCase(),
            'file_path': '/music/$album$suffix.opus',
            'scanned_at': '2026-10-19',
            'release_date': date,
            'sort_added': added,
            'track_number': 1,
          })
          .then((_) {});
      await song('Old', '2010-01-01', 99999);
      await song('Full', '2026-10-01T12:00:00Z', 1);
      await song('Slash', ' 2026/10/02 ', 1);
      await song('Compact', '20261003', 1);
      await song('Year', '2026', 1);
      await song('Month', '2026-09', 1);
      await song('NewestGroup', '20261004', 1);
      await song('NewestGroup', '2020-01-01', 999, suffix: '-older-tag');
      await song('TieA', '2026-10-03', 1);
      await song('TieZ', '2026-10-03', 1000);
      await song('Unknown', null, 2000);
      await song('Invalid', '2026-02-30', 2000);
      await song('Garbage', 'zzzz', 2000);

      final names = <String>[];
      final dates = <String>[];
      final displayedDates = <String?>[];
      LibraryBrowseDbCursor? cursor;
      do {
        final page = await store.albumPage(
          LibraryBrowseDbQuery(
            sortMode: 'release-date-newest',
            includeSingleTrackAlbums: true,
            limit: 2,
            offset: names.length,
            cursor: cursor,
          ),
        );
        expect(page.rows.length, lessThanOrEqualTo(2));
        names.addAll(page.rows.map((row) => row['album_name'] as String));
        dates.addAll(page.rows.map((row) => row['sort_release'] as String));
        displayedDates.addAll(
          page.rows.map(
            (row) =>
                LibraryBrowseEntry.fromRow(row, isArtist: false).releaseDate,
          ),
        );
        cursor = page.nextCursor;
        if (page.rows.length < 2) break;
      } while (names.length < 30);
      expect(names, [
        'NewestGroup',
        'Compact',
        'TieA',
        'TieZ',
        'Slash',
        'Full',
        'Month',
        'Year',
        'Old',
      ]);
      expect(dates.first, '2026-10-04');
      expect(dates[6], '2026-09-01');
      expect(dates[7], '2026-01-01');
      expect(displayedDates.first, '20261004');
      expect(displayedDates[6], '2026-09');
      expect(displayedDates[7], '2026');
      final added = await store.trackPage(
        const LibraryBrowseDbQuery(sortMode: 'latest', limit: 1),
      );
      expect((added.rows.single['item'] as Map)['albumName'], 'Old');

      await db.execute(
        "UPDATE library SET release_date='2027-03-01' WHERE id='Old'",
      );
      final refreshed = await store.albumPage(
        const LibraryBrowseDbQuery(
          sortMode: 'release-date-newest',
          includeSingleTrackAlbums: true,
          limit: 1,
        ),
      );
      expect(refreshed.rows.single['album_name'], 'Old');
      expect(refreshed.rows.single['sort_release'], '2027-03-01');
    },
  );

  test('metadata dates reject invalid calendars and accept leap days', () async {
    final db = await SqliteProcessDatabase.open();
    addTearDown(db.close);
    for (final entry in {
      '2024-02-29': '2024-02-29',
      '2025-02-29': '',
      '2026-13-01': '',
      'not dated': '',
      '2026-10': '2026-10-01',
    }.entries) {
      final rows = await db.rawQuery(
        'SELECT ${metadataReleaseDateSql('value')} AS release FROM (SELECT ? AS value)',
        [entry.key],
      );
      expect(rows.single['release'], entry.value);
    }
  });
}
