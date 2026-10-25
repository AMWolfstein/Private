import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/services/library_row_mapper.dart';
import 'package:spotiflac_android/services/library_database_models.dart';
import 'package:spotiflac_android/services/library_queue_store.dart';
import 'package:spotiflac_android/services/library_genres.dart';
import 'package:spotiflac_android/services/library_schema.dart';
import 'package:spotiflac_android/services/library_search.dart';
import 'package:spotiflac_android/services/sqlite_helpers.dart';

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

  test(
    'v17 search backfill crosses bounded pages without dropping rows',
    () async {
      final db = await SqliteProcessDatabase.open();
      addTearDown(db.close);
      await LibrarySchema.create(db, LibrarySchema.version);
      for (final column in ['search_track', 'search_album', 'search_artist']) {
        await db.execute('ALTER TABLE library DROP COLUMN $column');
      }
      final batch = db.batch();
      for (var i = 0; i < 305; i++) {
        final encoded =
            LibraryRowMapper.encode({
              ..._unicodeTrack(),
              'id': 'unicode-$i',
              'filePath': '/music/unicode-$i.flac',
            })..removeWhere(
              (key, _) => const {
                'search_track',
                'search_album',
                'search_artist',
              }.contains(key),
            );
        encoded['search_text'] = 'cafe\u0301';
        batch.insert('library', encoded);
      }
      await batch.commit(noResult: true);
      await LibrarySchema.upgrade(db, 17, LibrarySchema.version);
      final rows = await db.query('library', columns: ['id', 'search_track']);
      expect(rows, hasLength(305));
      expect(rows.every((row) => row['search_track'] == 'café'), isTrue);
      expect(rows.map((row) => row['id']).toSet(), hasLength(305));
    },
  );

  for (final migrate in [false, true]) {
    test(
      'canonical search works after ${migrate ? 'v17 migration' : 'new writes'} with stable identities',
      () async {
        final db = await SqliteProcessDatabase.open();
        addTearDown(db.close);
        final localFts = await LibrarySchema.create(db, LibrarySchema.version);
        final encoded = LibraryRowMapper.encode(_unicodeTrack());
        final albumKey = encoded['album_key'];
        final matchKey = encoded['match_key'];
        if (migrate) {
          for (final column in [
            'search_track',
            'search_album',
            'search_artist',
          ]) {
            await db.execute('ALTER TABLE library DROP COLUMN $column');
            encoded.remove(column);
          }
          encoded['search_text'] =
              'cafe\u0301 e\u0301lise e\u0301te\u0301 e\u0301lise';
          encoded['sort_genre'] = 'e\u0301lectro; rock';
        }
        await db.insert('library', encoded);
        if (migrate) {
          await LibrarySchema.upgrade(db, 17, LibrarySchema.version);
        }

        final stored = (await db.query('library')).single;
        expect(stored['id'], 'unicode');
        expect(stored['source_id'], encoded['source_id']);
        expect(stored['album_key'], albumKey);
        expect(stored['match_key'], matchKey);
        expect(stored['search_text'], 'café élise été élise');
        expect(stored['sort_genre'], ';;électro;;;rock;;');
        final genres = LibraryGenres(db);
        expect((await genres.page(genre: 'ÉLECTRO')).single['id'], 'unicode');
        expect((await genres.page(genre: 'rock')).single['id'], 'unicode');

        for (final fts in [false, if (localFts) true]) {
          final search = LibrarySearchStore(db, localFts: fts);
          for (final query in ['CAFÉ', 'Cafe\u0301']) {
            final hits = await search.search(
              query: query,
              kind: LibrarySearchKind.songs,
              includeLocal: true,
            );
            expect(hits.single.id, 'unicode');
            final queue = LibraryQueueStore(db, localFts: fts);
            final request = QueueLibraryDbQuery(searchQuery: query);
            final tracks = await queue.trackPage(request);
            expect((tracks.rows.single['item'] as Map)['id'], 'unicode');
            expect((await queue.counts(request)).allTrackCount, 1);
            expect((await queue.albumPage(request)).rows, hasLength(1));
          }
          final albums = await search.search(
            query: 'ÉTÉ',
            kind: LibrarySearchKind.albums,
            includeLocal: true,
          );
          expect(albums.single.id, albumKey);
          final artists = await search.search(
            query: 'ÉLISE',
            kind: LibrarySearchKind.artists,
            includeLocal: true,
          );
          expect(artists.single.id, 'e\u0301lise');
        }
      },
    );
  }
}
