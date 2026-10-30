import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sistrum/services/library/browse/library_genres.dart';
import 'package:sistrum/services/library/browse/library_tag_credits.dart';
import 'package:sistrum/services/library/database/sqlite_helpers.dart';
import '../../../support/sqlite_process_database.dart';

/// The genre queries with one shared credits cache, for a fixed library version.
class _Genres {
  _Genres(Database db)
    : _store = LibraryGenres(db, credits: LibraryTagCreditsCache());

  final LibraryGenres _store;

  Future<List<Map<String, dynamic>>> page({
    TagCreditField field = TagCreditField.genre,
    String? genre,
    int offset = 0,
    int limit = 40,
  }) => _store.page(
    field: field,
    genre: genre,
    offset: offset,
    limit: limit,
    libraryVersion: 1,
  );
}

void main() {
  late SqliteProcessDatabase db;
  setUp(() async {
    db = await SqliteProcessDatabase.open();
    await db.execute('''CREATE TABLE library_visible (
      id TEXT PRIMARY KEY, track_name TEXT, artist_name TEXT, album_name TEXT,
      file_path TEXT, scanned_at TEXT, genre TEXT, track_name_norm TEXT, artist_name_norm TEXT,
      sort_genre TEXT, album_artist TEXT, composer TEXT
    )''');
    for (final row in [
      ['a', 'Alpha', ' Rock ; Rap;rock '],
      ['b', 'Beta', 'rock'],
      ['c', 'Gamma', 'Hip-Hop/Rap'],
      ['d', 'Delta', 'Trap'],
      ['e', 'Blank', ' \n '],
    ]) {
      await db.rawInsert(
        'INSERT INTO library_visible (id, track_name, artist_name, album_name, '
        'file_path, scanned_at, genre, track_name_norm, artist_name_norm, '
        'sort_genre) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          row[0],
          row[1],
          'Artist',
          'Album',
          '/music/${row[0]}.flac',
          '2026-10-19',
          row[2],
          row[1].toLowerCase(),
          'artist',
          normalizeGenreTags(row[2]),
        ],
      );
    }
  });
  tearDown(() => db.close());
  test(
    'genres trim and merge case, split multiple tags and count each song once',
    () async {
      final rows = await _Genres(db).page();
      expect(rows.map((row) => row['genre_key']), [
        'hip-hop/rap',
        'rap',
        'rock',
        'trap',
      ]);
      expect(
        rows.singleWhere((row) => row['genre_key'] == 'rock')['track_count'],
        2,
      );
      expect(
        rows.singleWhere((row) => row['genre_key'] == 'rap')['track_count'],
        1,
      );
    },
  );
  test(
    'genre tracks match exact tags, preserve metadata and page stably',
    () async {
      final store = _Genres(db);
      expect((await store.page(genre: 'rap')).map((row) => row['id']), ['a']);
      final first = await store.page(genre: 'rock', limit: 1);
      final second = await store.page(genre: 'rock', limit: 1, offset: 1);
      expect([...first, ...second].map((row) => row['id']), ['a', 'b']);
      expect(first.single['filePath'], '/music/a.flac');
      expect(
        (await store.page(limit: 2, offset: 2)).map((row) => row['genre_key']),
        ['rock', 'trap'],
      );
    },
  );
  test(
    'Unicode case and canonical equivalents merge with exact tag membership',
    () async {
      for (final row in [
        ['f', 'Électro; ÉLECTRO'],
        ['g', 'e\u0301lectro; Rock'],
        ['h', 'Électronic'],
      ]) {
        await db.insert('library_visible', {
          'id': row[0],
          'track_name': row[0],
          'genre': row[1],
          'sort_genre': normalizeGenreTags(row[1]),
          'track_name_norm': row[0],
          'artist_name_norm': 'artist',
        });
      }
      final store = _Genres(db);
      final genres = await store.page();
      final electro = genres.singleWhere(
        (row) => row['genre_key'] == 'électro',
      );
      expect(electro['track_count'], 2);
      expect(
        genres.where((row) => row['genre_key'] == 'électro'),
        hasLength(1),
      );
      expect((await store.page(genre: 'ÉLECTRO')).map((row) => row['id']), [
        'f',
        'g',
      ]);
      expect(
        (await store.page(genre: 'e\u0301lectro')).map((row) => row['id']),
        ['f', 'g'],
      );
    },
  );
  test(
    'leading separators and padded Unicode tags keep display and keys aligned',
    () async {
      const raw = '\r\n \u00a0E\u0301LECTRO\u00a0 ;\r\n  Rock  \r\n';
      expect(normalizeGenreTags(raw), ';;électro;;;rock;;');
      await db.insert('library_visible', {
        'id': 'leading',
        'track_name': 'Leading',
        'genre': raw,
        'sort_genre': normalizeGenreTags(raw),
        'track_name_norm': 'leading',
        'artist_name_norm': 'artist',
      });
      final store = _Genres(db);
      final genres = await store.page();
      expect(
        genres.where((row) => row['genre_key'] == 'électro'),
        hasLength(1),
      );
      expect((await store.page(genre: 'Électro')).map((row) => row['id']), [
        'leading',
      ]);
      expect((await store.page(genre: 'rock')).map((row) => row['id']), [
        'a',
        'b',
        'leading',
      ]);
      final electro = genres.singleWhere(
        (row) => row['genre_key'] == 'électro',
      );
      expect((electro['name'] as String).trim(), 'E\u0301LECTRO');
    },
  );

  test(
    'cached tags match the CTE and refresh per library version (PERF-402)',
    () async {
      final cache = LibraryTagCreditsCache();
      Future<List<Map<String, dynamic>>> cachedPage({
        String? genre,
        int offset = 0,
        int version = 1,
      }) => LibraryGenres(
        db,
        credits: cache,
      ).page(genre: genre, offset: offset, libraryVersion: version);

      final list = await cachedPage();
      expect(list.map((row) => row['genre_key']), [
        'hip-hop/rap',
        'rap',
        'rock',
        'trap',
      ]);
      expect(
        (await cachedPage(
          genre: normalizeGenreTags('rock'),
          version: 1,
        )).map((row) => row['id']),
        ['a', 'b'],
      );

      // A same-version reread serves the cache and does not see new rows...
      await db.insert('library_visible', {
        'id': 'new',
        'track_name': 'New',
        'genre': 'Ska',
        'sort_genre': 'ska',
        'track_name_norm': 'new',
        'artist_name_norm': 'artist',
      });
      expect(
        (await cachedPage()).map((row) => row['genre_key']),
        list.map((row) => row['genre_key']),
      );

      // ...while a version bump rebuilds the cached tags.
      final refreshed = await cachedPage(version: 2);
      expect(refreshed.map((row) => row['genre_key']), contains('ska'));
      expect(
        (await cachedPage(
          genre: normalizeGenreTags('ska'),
          version: 2,
        )).map((row) => row['id']),
        ['new'],
      );
    },
  );

  test(
    'a selected slash splits Hip-Hop/Rap; the default keeps it whole',
    () async {
      Future<List<String>> keys(TagCreditRules rules) async {
        final store = LibraryGenres(
          db,
          credits: LibraryTagCreditsCache(),
          rules: rules,
        );
        return (await store.page(
          libraryVersion: 1,
        )).map((row) => row['genre_key'] as String).toList();
      }

      expect(await keys(const TagCreditRules()), contains('hip-hop/rap'));
      final split = await keys(
        const TagCreditRules(genreDelimiters: [';', '/']),
      );
      expect(split, containsAll(['hip-hop', 'rap']));
      expect(split, isNot(contains('hip-hop/rap')));
    },
  );

  test('composers split on the same delimiters and list their songs', () async {
    await db.execute(
      "UPDATE library_visible SET composer = 'Bach, Liszt' WHERE id = 'a'",
    );
    await db.execute(
      "UPDATE library_visible SET composer = 'Liszt' WHERE id = 'c'",
    );
    final genres = _Genres(db);

    final composers = await genres.page(field: TagCreditField.composer);
    expect(composers.map((row) => row['genre_key']), ['bach', 'liszt']);

    final lisztSongs = await genres.page(
      field: TagCreditField.composer,
      genre: 'Liszt',
    );
    expect(lisztSongs.map((row) => row['id']), ['a', 'c']);
  });
}
