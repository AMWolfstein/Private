import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/library/library_browse_order.dart';
import 'package:sistrum/services/library/library_database_models.dart';

void main() {
  group('queue track order terms', () {
    test('each sort mode orders by its key, then the stable tie-breakers', () {
      expect(
        queueOrderBy(queueTrackOrderTerms('size-asc')),
        'sort_size_unknown ASC, sort_size ASC, sort_track ASC, id ASC',
      );
      expect(
        queueOrderBy(queueTrackOrderTerms('size-desc')),
        'sort_size_unknown ASC, sort_size DESC, sort_track ASC, id ASC',
      );
      expect(
        queueOrderBy(queueTrackOrderTerms('oldest')),
        'sort_added ASC, sort_track ASC, id ASC',
      );
      expect(
        queueOrderBy(queueTrackOrderTerms('a-z')),
        'sort_track ASC, sort_artist ASC, id ASC',
      );
      expect(
        queueOrderBy(queueTrackOrderTerms('z-a')),
        'sort_track DESC, sort_artist DESC, id ASC',
      );
      expect(
        queueOrderBy(queueTrackOrderTerms('artist-asc')),
        'sort_artist ASC, sort_track ASC, id ASC',
      );
      expect(
        queueOrderBy(queueTrackOrderTerms('artist-desc')),
        'sort_artist DESC, sort_track ASC, id ASC',
      );
      expect(
        queueOrderBy(queueTrackOrderTerms('album-asc')),
        'sort_album ASC, sort_track ASC, id ASC',
      );
      expect(
        queueOrderBy(queueTrackOrderTerms('album-desc')),
        'sort_album DESC, sort_track ASC, id ASC',
      );
      expect(
        queueOrderBy(queueTrackOrderTerms('release-oldest')),
        'sort_release ASC, sort_track ASC, id ASC',
      );
      expect(
        queueOrderBy(queueTrackOrderTerms('release-newest')),
        'sort_release DESC, sort_track ASC, id ASC',
      );
      expect(
        queueOrderBy(queueTrackOrderTerms('genre-asc')),
        'sort_genre ASC, sort_track ASC, id ASC',
      );
      expect(
        queueOrderBy(queueTrackOrderTerms('genre-desc')),
        'sort_genre DESC, sort_track ASC, id ASC',
      );
    });

    test('an unknown mode falls back to newest-added first', () {
      expect(
        queueOrderBy(queueTrackOrderTerms('no-such-mode')),
        'sort_added DESC, sort_track ASC, id ASC',
      );
    });
  });

  group('queue album order terms', () {
    test('each sort mode orders albums by its key and album_key last', () {
      expect(
        queueOrderBy(queueAlbumOrderTerms('size-asc')),
        'sort_size_unknown ASC, sort_size ASC, sort_album ASC, album_key ASC',
      );
      expect(
        queueOrderBy(queueAlbumOrderTerms('size-desc')),
        'sort_size_unknown ASC, sort_size DESC, sort_album ASC, album_key ASC',
      );
      expect(
        queueOrderBy(queueAlbumOrderTerms('release-date-newest')),
        'sort_release DESC, album_key ASC',
      );
      expect(
        queueOrderBy(queueAlbumOrderTerms('artist-releases-newest')),
        'sort_release DESC, sort_added DESC, album_key ASC',
      );
      expect(
        queueOrderBy(queueAlbumOrderTerms('oldest')),
        'sort_added ASC, sort_album ASC, album_key ASC',
      );
      expect(
        queueOrderBy(queueAlbumOrderTerms('a-z')),
        'sort_album ASC, sort_artist ASC, album_key ASC',
      );
      expect(
        queueOrderBy(queueAlbumOrderTerms('album-asc')),
        queueOrderBy(queueAlbumOrderTerms('a-z')),
      );
      expect(
        queueOrderBy(queueAlbumOrderTerms('z-a')),
        'sort_album DESC, sort_artist DESC, album_key ASC',
      );
      expect(
        queueOrderBy(queueAlbumOrderTerms('album-desc')),
        queueOrderBy(queueAlbumOrderTerms('z-a')),
      );
      expect(
        queueOrderBy(queueAlbumOrderTerms('artist-asc')),
        'sort_artist ASC, sort_album ASC, album_key ASC',
      );
      expect(
        queueOrderBy(queueAlbumOrderTerms('artist-desc')),
        'sort_artist DESC, sort_album ASC, album_key ASC',
      );
      expect(
        queueOrderBy(queueAlbumOrderTerms('release-oldest')),
        'sort_release ASC, sort_album ASC, album_key ASC',
      );
      expect(
        queueOrderBy(queueAlbumOrderTerms('release-newest')),
        'sort_release DESC, sort_album ASC, album_key ASC',
      );
      expect(
        queueOrderBy(queueAlbumOrderTerms('genre-desc')),
        'sort_genre DESC, sort_album ASC, album_key ASC',
      );
      expect(
        queueOrderBy(queueAlbumOrderTerms('unknown')),
        'sort_added DESC, sort_album ASC, album_key ASC',
      );
    });
  });

  group('size sort helpers', () {
    test('only size modes join file sizes and select size columns', () {
      expect(
        sizeJoin('size-desc', 't'),
        'LEFT JOIN track_file_sizes file_sizes ON file_sizes.item_id = t.id',
      );
      expect(
        trackSizeColumns('size-asc'),
        ', file_sizes.size_bytes AS file_size_bytes, '
        '(file_sizes.size_bytes IS NULL) AS sort_size_unknown, '
        'COALESCE(file_sizes.size_bytes, 0) AS sort_size',
      );
      expect(
        albumSizeColumns('size-desc'),
        ', (COUNT(file_sizes.size_bytes) < COUNT(*)) AS sort_size_unknown, '
        'COALESCE(SUM(file_sizes.size_bytes), 0) AS sort_size',
      );
    });

    test('other modes add no join and no size columns', () {
      for (final mode in ['a-z', 'oldest', 'release-newest']) {
        expect(sizeJoin(mode, 't'), '');
        expect(trackSizeColumns(mode), '');
        expect(albumSizeColumns(mode), '');
      }
    });
  });

  group('cursor pagination', () {
    test('a cursor builds a keyset predicate over the ordered terms', () {
      final args = <Object?>[];
      final predicate = queueCursorPredicate(
        const LibraryBrowseDbCursor(['Song', 'Artist', 7]),
        queueTrackOrderTerms('a-z'),
        args,
      );

      expect(
        predicate,
        '(sort_track >= ?) AND ((sort_track > ?) OR '
        '(sort_track = ? AND sort_artist > ?) OR '
        '(sort_track = ? AND sort_artist = ? AND id > ?))',
      );
      expect(args, ['Song', 'Song', 'Song', 'Artist', 'Song', 'Artist', 7]);
    });

    test('descending first term flips the coarse and strict operators', () {
      final args = <Object?>[];
      final predicate = queueCursorPredicate(
        const LibraryBrowseDbCursor(['Song', 'Artist', 7]),
        queueTrackOrderTerms('z-a'),
        args,
      );

      expect(predicate, startsWith('(sort_track <= ?) AND ('));
      expect(predicate, contains('(sort_track < ?)'));
      expect(predicate, contains('(sort_track = ? AND sort_artist < ?)'));
      expect(
        predicate,
        contains('(sort_track = ? AND sort_artist = ? AND id > ?)'),
      );
    });

    test('no cursor, or a cursor with the wrong arity, adds nothing', () {
      final args = <Object?>[];
      final terms = queueTrackOrderTerms('a-z');

      expect(queueCursorPredicate(null, terms, args), '');
      expect(
        queueCursorPredicate(
          const LibraryBrowseDbCursor(['only-one']),
          terms,
          args,
        ),
        '',
      );
      expect(args, isEmpty);
    });

    test('a cursor is read from the matching row columns', () {
      final cursor = queueCursorFromRow({
        'sort_track': 'a',
        'sort_artist': 'b',
        'id': 3,
      }, queueTrackOrderTerms('a-z'));

      expect(cursor, const LibraryBrowseDbCursor(['a', 'b', 3]));
    });

    test('a missing row or a null column yields no cursor', () {
      final terms = queueTrackOrderTerms('a-z');

      expect(queueCursorFromRow(null, terms), isNull);
      expect(queueCursorFromRow({'sort_track': 'a', 'id': 3}, terms), isNull);
    });
  });
}
