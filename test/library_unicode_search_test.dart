import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/library/library_row_mapper.dart';
import 'package:sistrum/services/library/library_database_models.dart';
import 'package:sistrum/services/library/library_browse_store.dart';
import 'package:sistrum/services/library/library_genres.dart';
import 'package:sistrum/services/library/library_tag_credits.dart';
import 'package:sistrum/services/library/library_schema.dart';
import 'package:sistrum/services/library/library_search.dart';
import 'package:sistrum/services/library/sqlite_helpers.dart';

import 'support/sqlite_process_database.dart';

Map<String, dynamic> _unicodeTrack() => {
  'id': 'unicode',
  'trackName': 'Cafe\u0301',
  'artistName': 'E\u0301LISE',
  'albumName': 'E\u0301te\u0301',
  'filePath': '/music/unicode.flac',
  'scannedAt': '2026-10-25T00:00:00.000Z',
  'genre': '\r\n \u00a0E\u0301LECTRO\u00a0 ;\r\n  Rock  \r\n',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('combining marks remain in whole search tokens', () {
    expect(LibrarySearchQuery('كِتاب किताब ภาษาไทย').terms, [
      'كِتاب',
      'किताब',
      'ภาษาไทย',
    ]);
    expect(LibrarySearchQuery('كِتاب').matches('كتاب'), isFalse);
    expect(LibrarySearchQuery('Cafe\u0301').matches('CAFÉ'), isTrue);
    expect(LibrarySearchQuery('CAFÉ').rank('Cafe\u0301'), 0);
    expect(normalizeSearchText(' E\u0301LECTRO '), 'électro');
    // Library identity normalization is deliberately not a migration target.
    expect(normalizeLookupText(' E\u0301LECTRO '), 'e\u0301lectro');
  });

  {
    test(
      'canonical search works after new writes with stable identities',
      () async {
        final db = await SqliteProcessDatabase.open();
        addTearDown(db.close);
        final localFts = await LibrarySchema.create(db, LibrarySchema.version);
        final encoded = LibraryRowMapper.encode(_unicodeTrack());
        final albumKey = encoded['album_key'];
        final matchKey = encoded['match_key'];
        await db.insert('library', encoded);

        final stored = (await db.query('library')).single;
        expect(stored['id'], 'unicode');
        expect(stored['source_id'], encoded['source_id']);
        expect(stored['album_key'], albumKey);
        expect(stored['match_key'], matchKey);
        expect(stored['search_text'], 'café élise été élise');
        expect(stored['sort_genre'], ';;électro;;;rock;;');
        final genres = LibraryGenres(db, credits: LibraryTagCreditsCache());
        expect(
          (await genres.page(genre: 'ÉLECTRO', libraryVersion: 1)).single['id'],
          'unicode',
        );
        expect(
          (await genres.page(genre: 'rock', libraryVersion: 1)).single['id'],
          'unicode',
        );

        for (final fts in [false, if (localFts) true]) {
          final search = LibrarySearchStore(db, localFts: fts);
          for (final query in ['CAFÉ', 'Cafe\u0301']) {
            final hits = await search.search(
              query: query,
              kind: LibrarySearchKind.songs,
            );
            expect(hits.single.id, 'unicode');
            final queue = LibraryBrowseStore(db, localFts: fts);
            final request = LibraryBrowseDbQuery(searchQuery: query);
            final tracks = await queue.trackPage(request);
            expect((tracks.rows.single['item'] as Map)['id'], 'unicode');
            expect((await queue.counts(request)).allTrackCount, 1);
            expect((await queue.albumPage(request)).rows, hasLength(1));
          }
          final albums = await search.search(
            query: 'ÉTÉ',
            kind: LibrarySearchKind.albums,
          );
          expect(albums.single.id, albumKey);
          final artists = await search.search(
            query: 'ÉLISE',
            kind: LibrarySearchKind.artists,
          );
          expect(artists.single.id, 'e\u0301lise');
        }
      },
    );
  }
}
