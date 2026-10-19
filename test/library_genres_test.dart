import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/services/library_genres.dart';
import 'support/sqlite_process_database.dart';

void main() {
  late SqliteProcessDatabase db;
  setUp(() async {
    db = await SqliteProcessDatabase.open();
    await db.execute('''CREATE TABLE library_visible (
      id TEXT PRIMARY KEY, track_name TEXT, artist_name TEXT, album_name TEXT,
      file_path TEXT, scanned_at TEXT, genre TEXT, track_name_norm TEXT, artist_name_norm TEXT
    )''');
    for (final row in [
      ['a', 'Alpha', ' Rock ; Rap;rock '],
      ['b', 'Beta', 'rock'],
      ['c', 'Gamma', 'Hip-Hop/Rap'],
      ['d', 'Delta', 'Trap'],
      ['e', 'Blank', ' \n '],
    ]) {
      await db.rawInsert(
        'INSERT INTO library_visible VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
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
        ],
      );
    }
  });
  tearDown(() => db.close());
  test(
    'genres trim and merge case, split multiple tags and count each song once',
    () async {
      final rows = await LibraryGenres(db).page();
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
      final store = LibraryGenres(db);
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
}
