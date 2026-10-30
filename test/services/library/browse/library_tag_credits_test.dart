import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/library/browse/library_tag_credits.dart';
import '../../../support/sqlite_process_database.dart';

const _rules = TagCreditRules();

List<String> _artist(String? raw, {TagCreditRules rules = _rules}) =>
    splitTagCredits(raw, TagCreditField.artist, rules);

void main() {
  group('artists', () {
    test('default delimiters split names and word delimiters stand alone', () {
      expect(_artist('Amr Diab, R3HAB'), ['Amr Diab', 'R3HAB']);
      expect(_artist('A; B، C'), ['A', 'B', 'C']);
      expect(_artist('Daft Punk feat. Pharrell Williams'), [
        'Daft Punk',
        'Pharrell Williams',
      ]);
      expect(_artist('Daft Punk'), ['Daft Punk']);
      expect(_artist('Featurette and Lift Up'), ['Featurette and Lift Up']);
    });

    test('every chip splits by default; Keep together protects a name', () {
      // All is the default, so symbols and words such as x and with split.
      expect(_artist('AC/DC'), ['AC', 'DC']);
      expect(_artist('Simon & Garfunkel'), ['Simon', 'Garfunkel']);
      expect(_artist('Lift with Me'), ['Lift', 'Me']);
      expect(_artist('Malcolm X'), ['Malcolm']);

      const kept = TagCreditRules(
        keepTogether: ['AC/DC', 'Lift with Me', 'Malcolm X'],
      );
      expect(_artist('AC/DC', rules: kept), ['AC/DC']);
      expect(_artist('Lift with Me', rules: kept), ['Lift with Me']);
      expect(_artist('Malcolm X, Amr Diab', rules: kept), [
        'Malcolm X',
        'Amr Diab',
      ]);
    });

    test('a symbol that is not selected stays inside a name', () {
      const commaOnly = TagCreditRules(artistDelimiters: [',']);
      expect(_artist('AC/DC', rules: commaOnly), ['AC/DC']);
      expect(_artist('Simon & Garfunkel', rules: commaOnly), [
        'Simon & Garfunkel',
      ]);
    });

    test('a selected word delimiter splits only as a whole word', () {
      const withWord = TagCreditRules(artistDelimiters: ['with']);
      expect(_artist('Lift Up with Me', rules: withWord), ['Lift Up', 'Me']);
      expect(_artist('Lift Up', rules: withWord), ['Lift Up']);
    });

    test('a newline always separates', () {
      const semicolonOnly = TagCreditRules(artistDelimiters: [';']);
      expect(_artist('A\nB', rules: semicolonOnly), ['A', 'B']);
    });

    test('brackets left by a feature are removed, balanced ones kept', () {
      expect(_artist('Artist A (feat. Artist B)'), ['Artist A', 'Artist B']);
      expect(_artist('Band (UK)'), ['Band (UK)']);
    });

    test('repeated names are listed once, keeping the first', () {
      expect(_artist('A; a; B'), ['A', 'B']);
    });

    test('blank and missing values have no names', () {
      expect(_artist(''), isEmpty);
      expect(_artist('  '), isEmpty);
      expect(_artist(null), isEmpty);
    });
  });

  group('keep together', () {
    const keep = TagCreditRules(keepTogether: ['Tyler, The Creator']);

    test('a protected name keeps its own separators', () {
      expect(_artist('Tyler, The Creator, Kali Uchis', rules: keep), [
        'Tyler, The Creator',
        'Kali Uchis',
      ]);
    });

    test('matching ignores case and returns the spelling from the tag', () {
      expect(_artist('tyler, the creator, Kali', rules: keep), [
        'tyler, the creator',
        'Kali',
      ]);
    });

    test('a name inside a longer word is not protected', () {
      const kali = TagCreditRules(keepTogether: ['Kali']);
      expect(_artist('Kalification, Kali', rules: kali), [
        'Kalification',
        'Kali',
      ]);
    });

    test('genres never keep names together', () {
      expect(
        splitTagCredits(
          'Tyler, The Creator',
          TagCreditField.genre,
          const TagCreditRules(keepTogether: ['Tyler, The Creator']),
        ),
        ['Tyler, The Creator'],
      );
    });
  });

  group('genres', () {
    test('default genre delimiters are semicolon and the Arabic comma', () {
      List<String> genre(String raw) =>
          splitTagCredits(raw, TagCreditField.genre, _rules);
      expect(genre('Soundtrack; Hip-Hop/Rap'), ['Soundtrack', 'Hip-Hop/Rap']);
      expect(genre('Pop، Rock'), ['Pop', 'Rock']);
      expect(genre('R&B/Soul'), ['R&B/Soul']);
      expect(genre('Rock\nPop'), ['Rock', 'Pop']);
    });

    test('a selected slash splits genres that contain one', () {
      const slash = TagCreditRules(genreDelimiters: [';', '/']);
      expect(splitTagCredits('Hip-Hop/Rap', TagCreditField.genre, slash), [
        'Hip-Hop',
        'Rap',
      ]);
    });
  });

  group('credits table', () {
    late SqliteProcessDatabase db;

    setUp(() async {
      db = await SqliteProcessDatabase.open();
      await db.execute('''CREATE TABLE library_visible (
        id TEXT PRIMARY KEY, artist_name TEXT, album_artist TEXT,
        composer TEXT, genre TEXT
      )''');
      await db.rawInsert('INSERT INTO library_visible VALUES (?, ?, ?, ?, ?)', [
        'a',
        'A, B',
        '',
        'C',
        'Rock; Pop',
      ]);
      await db.rawInsert('INSERT INTO library_visible VALUES (?, ?, ?, ?, ?)', [
        'b',
        'Song',
        'D',
        null,
        '',
      ]);
    });

    tearDown(() => db.close());

    Future<Map<String, int>> countsByField() async {
      final rows = await db.rawQuery(
        'SELECT field, COUNT(*) AS n FROM ${LibraryTagCreditsCache.tempTable} '
        'GROUP BY field',
      );
      return {for (final row in rows) row['field'] as String: row['n'] as int};
    }

    test(
      'one row per name, with an empty album artist taken from the track',
      () async {
        await LibraryTagCreditsCache().ensure(
          db,
          libraryVersion: 1,
          rules: _rules,
        );
        expect(await countsByField(), {
          'artist': 3,
          'album_artist': 3,
          'composer': 1,
          'genre': 2,
        });
        final keys = await db.rawQuery(
          'SELECT name_key FROM ${LibraryTagCreditsCache.tempTable} '
          "WHERE field = 'album_artist' AND item_id = 'a' ORDER BY position",
        );
        expect(keys.map((row) => row['name_key']), ['a', 'b']);
      },
    );

    test(
      'rebuilds for a new version or rules, not for the same ones',
      () async {
        final cache = LibraryTagCreditsCache();
        await cache.ensure(db, libraryVersion: 1, rules: _rules);
        await db.rawInsert(
          'INSERT INTO ${LibraryTagCreditsCache.tempTable} '
          "VALUES ('stray', 'artist', 'Stray', 'stray', 0)",
        );

        // The same version and rules keep the table as it is.
        await cache.ensure(db, libraryVersion: 1, rules: _rules);
        expect((await countsByField())['artist'], 4);

        // A new version rebuilds it.
        await cache.ensure(db, libraryVersion: 2, rules: _rules);
        expect((await countsByField())['artist'], 3);

        // New rules rebuild it too: `, ` no longer splits artists.
        const semicolonOnly = TagCreditRules(artistDelimiters: [';']);
        await cache.ensure(db, libraryVersion: 2, rules: semicolonOnly);
        expect((await countsByField())['artist'], 2);
      },
    );

    test(
      'invalidate forces a rebuild for the same version and rules',
      () async {
        final cache = LibraryTagCreditsCache();
        await cache.ensure(db, libraryVersion: 1, rules: _rules);
        await db.rawInsert(
          'INSERT INTO ${LibraryTagCreditsCache.tempTable} '
          "VALUES ('stray', 'artist', 'Stray', 'stray', 0)",
        );
        cache.invalidate();
        await cache.ensure(db, libraryVersion: 1, rules: _rules);
        expect((await countsByField())['artist'], 3);
      },
    );
  });
}
