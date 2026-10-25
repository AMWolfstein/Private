import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:spotiflac_android/services/library_database_models.dart';
import 'package:spotiflac_android/services/library_queue_store.dart';
import 'package:spotiflac_android/services/library_row_mapper.dart';
import 'package:spotiflac_android/services/library_schema.dart';

import 'support/sqlite_process_database.dart';

List<String> _tracks(QueueLibraryDbPage page) => [
  for (final row in page.rows) '${row['source']}:${(row['item'] as Map)['id']}',
];

class _AlbumQueryDatabase implements Database {
  _AlbumQueryDatabase(this.db);

  final Database db;
  late String sql;
  List<Object?>? args;

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) {
    this.sql = sql;
    args = arguments;
    return db.rawQuery(sql, arguments);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SqliteProcessDatabase db;
  late LibraryQueueStore store;

  Future<void> addHistory(
    String id,
    String album,
    int number, {
    String artist = 'Artist',
    String title = 'Song',
    String? path,
  }) async {
    final file = path ?? '/$id.flac';
    await db.insert('history_db.history', {
      'id': id,
      'track_name': title,
      'artist_name': artist,
      'album_name': album,
      'album_artist': artist,
      'file_path': file,
      'downloaded_at': '2026-01-01',
      'service': 'example-provider',
      'album_key': '${album.toLowerCase()}|${artist.toLowerCase()}',
      'track_number': number,
      'total_tracks': 2,
      'disc_number': 1,
      'total_discs': 1,
      'bit_depth': 16,
      'genre': 'Pop',
      'release_date': '2026',
      'sort_track': title.toLowerCase(),
      'sort_artist': artist.toLowerCase(),
      'sort_album': album.toLowerCase(),
      'sort_album_artist': artist.toLowerCase(),
      'sort_genre': 'pop',
      'sort_release': '2026',
      'sort_added': 1,
      'search_text': '$title $artist $album'.toLowerCase(),
      'has_replaygain': number == 1 ? 1 : 0,
    });
    await db.insert('history_db.history_path_keys', {
      'item_id': id,
      'path_key': file,
    });
  }

  Future<void> addLocal(
    String id,
    int number, {
    String? path,
    String source = 'legacy',
    String album = 'Local',
    String artist = 'Artist',
    String title = 'Song',
    int? totalTracks = 2,
    bool explicit = false,
    String releaseDate = '2026',
  }) async {
    final file = path ?? '/$id.flac';
    final track = LocalLibraryItem(
      id: id,
      sourceId: source,
      trackName: title,
      artistName: artist,
      albumName: album,
      filePath: file,
      scannedAt: DateTime.utc(2026),
      fileModTime: 1,
      trackNumber: number,
      totalTracks: totalTracks,
      explicit: explicit,
      discNumber: 1,
      totalDiscs: 1,
      bitDepth: 16,
      genre: 'Pop',
      releaseDate: releaseDate,
      hasReplayGain: number == 1,
    );
    await db.insert('library', LibraryRowMapper.encode(track.toJson()));
    await db.insert('library_path_keys', {'item_id': id, 'path_key': file});
  }

  setUp(() async {
    db = await SqliteProcessDatabase.open();
    await LibrarySchema.create(db, LibrarySchema.version);
    await db.execute("ATTACH DATABASE ':memory:' AS history_db");
    final definition = RegExp(r'CREATE TABLE history\s*\([\s\S]*?\n\s*\)')
        .firstMatch(
          File('lib/services/history_database.dart').readAsStringSync(),
        )!
        .group(0)!;
    await db.execute(
      definition.replaceFirst(
        'CREATE TABLE history',
        'CREATE TABLE history_db.history',
      ),
    );
    await db.execute(
      'CREATE TABLE history_db.history_path_keys (item_id TEXT, path_key TEXT)',
    );
    await addHistory('h1', 'Downloaded', 1);
    await addHistory('h2', 'Downloaded', 2);
    await addHistory('single', 'Single', 2, artist: 'Another Artist');
    await addLocal('l1', 1);
    await addLocal('l2', 2);
    await addLocal('mirror', 1, path: '/h1.flac');
    await db.insert('library_sources', {
      'id': 'offline',
      'path': '/offline',
      'display_name': 'Offline',
      'available': 0,
    });
    await addLocal('hidden', 1, source: 'offline');
    store = LibraryQueueStore(db, localFts: false);
  });
  tearDown(() => db.close());

  test(
    'album navigation resolves the normalized key with Unicode names',
    () async {
      await addLocal('unicode-2', 2, album: 'Été', artist: 'Björk');
      await addLocal('unicode-1', 1, album: 'Été', artist: 'Björk');
      await addLocal('other-edition', 1, album: 'Été', artist: 'Other');

      final rows = await store.localAlbumTracks('  ÉTÉ ', ' BJÖRK  ');
      expect(rows.map((row) => row['id']), ['unicode-1', 'unicode-2']);
      expect(await store.localAlbumTracks('Été', 'Missing'), isEmpty);
      expect(await store.localAlbumTracksByKey('été|björk'), rows);
    },
  );

  test(
    'queue tracks retain source ownership and explicit tags on round trip',
    () async {
      await db.insert('library_sources', {
        'id': 'music',
        'path': '/music',
        'display_name': 'Music',
      });
      await addLocal('explicit', 1, source: 'music', explicit: true);

      final page = await store.trackPage(const QueueLibraryDbQuery());
      final item = LocalLibraryItem.fromJson(
        Map<String, dynamic>.from(
          page.rows.singleWhere(
                (row) => (row['item'] as Map)['id'] == 'explicit',
              )['item']
              as Map,
        ),
      );
      expect(item.sourceId, 'music');
      expect(item.explicit, isTrue);
      final saved = LibraryRowMapper.encode(item.toJson());
      expect(saved['source_id'], 'music');
      expect(saved['explicit'], 1);
    },
  );

  test('singles use total-track tags across pages and badge counts', () async {
    await addLocal('single-copy-1', 1, album: 'Tagged Single', totalTracks: 1);
    await addLocal('single-copy-2', 1, album: 'Tagged Single', totalTracks: 1);
    await addLocal('partial', 1, album: 'Partial Album', totalTracks: 10);
    await addLocal('unknown', 1, album: 'Unknown Album', totalTracks: null);
    await addLocal('conflict-1', 1, album: 'Conflicting Album', totalTracks: 1);
    await addLocal(
      'conflict-2',
      2,
      album: 'Conflicting Album',
      totalTracks: 10,
    );

    for (final quality in [null, 'unrecognized']) {
      final query = QueueLibraryDbQuery(quality: quality);
      final counts = await store.counts(query);
      expect(
        [counts.allTrackCount, counts.albumCount, counts.singleTrackCount],
        [9, 4, 2],
      );
      final albums = await store.albumPage(query);
      expect(albums.rows.map((row) => row['album_name']).toSet(), {
        'Local',
        'Partial Album',
        'Unknown Album',
        'Conflicting Album',
      });
      final singles = await store.trackPage(
        QueueLibraryDbQuery(filterMode: 'singles', quality: quality),
      );
      expect(_tracks(singles).toSet(), {
        'local:single-copy-1',
        'local:single-copy-2',
      });
    }
    final filtered = await store.counts(
      const QueueLibraryDbQuery(searchQuery: 'Song', quality: 'unrecognized'),
    );
    expect(filtered.albumCount, 4);
    expect(filtered.singleTrackCount, 2);
    final allReleases = await store.albumPage(
      const QueueLibraryDbQuery(includeSingleTrackAlbums: true),
    );
    expect(allReleases.rows, hasLength(5));
  });

  test('artist releases order compact and ISO tags chronologically', () async {
    await addLocal(
      'compact',
      1,
      album: 'Compact',
      artist: 'Chronology',
      releaseDate: '20250101',
    );
    await addLocal(
      'iso',
      1,
      album: 'ISO',
      artist: 'Chronology',
      releaseDate: '2026-01-01',
    );
    await addLocal(
      'year',
      1,
      album: 'Year',
      artist: 'Chronology',
      releaseDate: '2024',
    );
    await addLocal(
      'invalid',
      1,
      album: 'Invalid',
      artist: 'Chronology',
      releaseDate: '2026-99-99',
    );

    final query = const QueueLibraryDbQuery(
      albumArtist: 'Chronology',
      sortMode: 'artist-releases-newest',
      includeSingleTrackAlbums: true,
      limit: 2,
    );
    final first = await store.albumPage(query);
    expect(first.rows.map((row) => row['album_name']), ['ISO', 'Compact']);
    final second = await store.albumPage(
      QueueLibraryDbQuery(
        albumArtist: 'Chronology',
        sortMode: 'artist-releases-newest',
        includeSingleTrackAlbums: true,
        cursor: first.nextCursor,
        limit: 2,
      ),
    );
    expect(second.rows.map((row) => row['album_name']), ['Year', 'Invalid']);
  });

  test(
    'track cursors match offset ordering across source ties for every sort',
    () async {
      for (final sort in [
        'latest',
        'oldest',
        'a-z',
        'z-a',
        'artist-asc',
        'artist-desc',
        'album-asc',
        'album-desc',
        'release-oldest',
        'release-newest',
        'genre-asc',
        'genre-desc',
      ]) {
        final expected = _tracks(
          await store.trackPage(QueueLibraryDbQuery(sortMode: sort)),
        );
        final actual = <String>[];
        QueueLibraryDbCursor? cursor;
        do {
          final page = await store.trackPage(
            QueueLibraryDbQuery(sortMode: sort, limit: 2, cursor: cursor),
          );
          actual.addAll(_tracks(page));
          cursor = page.nextCursor;
        } while (cursor != null);
        expect(actual, expected, reason: sort);
        expect(actual, hasLength(3), reason: sort);
        expect(actual, isNot(contains('local:hidden')));
      }
    },
  );

  test(
    'album cursors and invalid-cursor offset fallback preserve results',
    () async {
      for (final sort in [
        'latest',
        'album-asc',
        'album-desc',
        'artist-asc',
        'release-newest',
      ]) {
        final expected = (await store.albumPage(
          QueueLibraryDbQuery(sortMode: sort),
        )).rows;
        final first = await store.albumPage(
          QueueLibraryDbQuery(sortMode: sort, limit: 1),
        );
        final second = await store.albumPage(
          QueueLibraryDbQuery(
            sortMode: sort,
            limit: 1,
            cursor: first.nextCursor,
          ),
        );
        expect([...first.rows, ...second.rows], expected, reason: sort);
        final fallback = await store.albumPage(
          QueueLibraryDbQuery(
            sortMode: sort,
            offset: 0,
            limit: 1,
            cursor: const QueueLibraryDbCursor(['wrong length']),
          ),
        );
        expect(fallback.rows, [expected.first], reason: sort);
      }
    },
  );

  test(
    'unfiltered albums match the original aggregation across sources and pages',
    () async {
      await db.update('library', {'sort_added': 900}, where: "id = 'l1'");
      await addHistory('edition1', 'Downloaded', 1, artist: 'Other Artist');
      await addHistory('edition2', 'Downloaded', 2, artist: 'Other Artist');
      await addHistory('null-key', 'Invalid', 1);
      await db.update('history_db.history', {
        'album_key': null,
      }, where: "id = 'null-key'");
      await addLocal('local-edition1', 1, artist: 'Other Artist');
      await addLocal('local-edition2', 2, artist: 'Other Artist');
      await addLocal('local-single', 1, album: 'Local Single');
      await db.insert('library_sources', {
        'id': 'disabled',
        'path': '/disabled',
        'display_name': 'Disabled',
        'enabled': 0,
      });
      await addLocal('disabled1', 1, source: 'disabled');
      await addLocal('disabled2', 2, source: 'disabled');
      for (final source in [null, 'downloaded', 'local']) {
        for (final includeLocal in [false, true]) {
          for (final singles in [false, true]) {
            for (final sort in [
              'latest',
              'oldest',
              'album-asc',
              'album-desc',
              'artist-asc',
              'release-newest',
            ]) {
              for (final offset in [0, 1]) {
                Future<QueueLibraryDbPage> page(String? quality) =>
                    store.albumPage(
                      QueueLibraryDbQuery(
                        source: source,
                        includeLocal: includeLocal,
                        includeSingleTrackAlbums: singles,
                        sortMode: sort,
                        offset: offset,
                        limit: 1,
                        searchQuery: '  ',
                        quality: quality,
                      ),
                    );
                // Unknown quality adds no predicate but uses the original join.
                final original = await page('unrecognized');
                final fast = await page(null);
                expect(fast.rows, original.rows);
                expect(fast.nextCursor, original.nextCursor);
              }
            }
          }
        }
      }
      final albums = (await store.albumPage(const QueueLibraryDbQuery())).rows;
      expect(albums, hasLength(3));
      expect(
        albums.singleWhere(
          (row) => row['album_name'] == 'Local Single',
        )['track_count'],
        1,
        reason: 'a partial two-track release remains an album',
      );
      expect(
        (await store.albumPage(
          const QueueLibraryDbQuery(includeSingleTrackAlbums: true),
        )).rows,
        hasLength(3),
      );
      final filtered = (await store.albumPage(
        const QueueLibraryDbQuery(
          source: 'local',
          metadata: 'missing-replaygain',
        ),
      )).rows;
      final local = filtered.singleWhere(
        (row) => row['album_key'] == 'local|artist',
      );
      expect(local['track_count'], 1);
      expect(local['sort_added'], 900);
    },
  );

  test(
    'unfiltered local album query removes the second inventory pass',
    () async {
      await db.execute('''
      WITH RECURSIVE numbered(value) AS (
        SELECT 1 UNION ALL SELECT value + 1 FROM numbered WHERE value < 20000
      )
      INSERT INTO library (id, source_id, file_path, track_name, artist_name,
        album_name, album_key, track_name_norm, album_name_norm, album_artist_norm, sort_added, scanned_at)
      SELECT 'bulk-' || value, 'legacy', '/bulk-' || value || '.flac',
        'Song', 'Artist', 'Album ' || (value / 10), 'bulk-album-' || (value / 10),
        'song', 'album ' || (value / 10), 'artist', value, '2026-01-01' FROM numbered
    ''');
      await db.execute('''
      INSERT INTO library_path_keys (item_id, path_key)
      SELECT id, file_path FROM library WHERE id LIKE 'bulk-%'
    ''');
      final recorded = _AlbumQueryDatabase(db);
      final albums = LibraryQueueStore(recorded, localFts: false);
      final fast = await albums.albumPage(
        const QueueLibraryDbQuery(source: 'local', limit: 40),
      );
      final fastSql = recorded.sql;
      final fastArgs = recorded.args;
      final original = await albums.albumPage(
        const QueueLibraryDbQuery(
          source: 'local',
          limit: 40,
          quality: 'unrecognized',
        ),
      );
      final originalSql = recorded.sql;
      final originalArgs = recorded.args;
      expect(fast.rows, original.rows);
      final fastPlan = await db.rawQuery(
        'EXPLAIN QUERY PLAN $fastSql',
        fastArgs,
      );
      final originalPlan = await db.rawQuery(
        'EXPLAIN QUERY PLAN $originalSql',
        originalArgs,
      );
      int duplicateChecks(List<Map<String, Object?>> plan) => plan
          .where(
            (step) => (step['detail'] as String).contains(
              'CORRELATED SCALAR SUBQUERY',
            ),
          )
          .length;
      expect(
        duplicateChecks(fastPlan),
        lessThanOrEqualTo(duplicateChecks(originalPlan)),
      );
    },
  );

  test(
    'fast counts agree with filtered counts and deduplicate visible paths',
    () async {
      final fast = await store.counts(const QueueLibraryDbQuery());
      final filtered = await store.counts(
        const QueueLibraryDbQuery(quality: 'cd'),
      );
      expect(
        [fast.allTrackCount, fast.albumCount, fast.singleTrackCount],
        [3, 1, 0],
      );
      expect(
        [
          filtered.allTrackCount,
          filtered.albumCount,
          filtered.singleTrackCount,
        ],
        [3, 1, 0],
      );
      final local = await store.counts(
        const QueueLibraryDbQuery(source: 'local'),
      );
      expect(local.allTrackCount, 3);
      final gain = await store.trackPage(
        const QueueLibraryDbQuery(metadata: 'missing-replaygain'),
      );
      expect(_tracks(gain).toSet(), {'local:l2'});
    },
  );

  test('artist counts use the same filter as the track query', () async {
    for (final artist in ['Artist', 'Another Artist', 'Missing Artist']) {
      final query = QueueLibraryDbQuery(albumArtist: artist);
      final counts = await store.counts(query);
      final tracks = await store.trackPage(query);
      expect(counts.allTrackCount, tracks.rows.length, reason: artist);
      expect(
        [counts.allTrackCount, counts.albumCount, counts.singleTrackCount],
        switch (artist) {
          'Artist' => [3, 1, 0],
          _ => [0, 0, 0],
        },
      );
    }
  });

  test(
    'format aliases find indexed and filename-only tracks in both sources',
    () async {
      for (final sample in [
        (filter: 'm4a', format: 'MP4', extension: 'MP4'),
        (filter: 'aac', format: 'mp4a', extension: 'AAC'),
        (filter: 'alac', format: 'alac', extension: 'ALAC'),
        (filter: 'opus', format: 'opus', extension: 'OPUS'),
        (filter: 'ogg', format: 'vorbis', extension: 'OGG'),
        (filter: 'wav', format: 'wave', extension: 'WAVE'),
        (filter: 'aiff', format: 'aifc', extension: 'AIF'),
        (filter: 'ape', format: 'ape', extension: 'APE'),
        (filter: 'wv', format: 'wavpack', extension: 'WV'),
        (filter: 'dsf', format: 'dsf', extension: 'DSF'),
        (filter: 'dff', format: 'dff', extension: 'DFF'),
        (filter: 'mpc', format: 'musepack', extension: 'MPC'),
        (filter: 'eac3', format: 'ec-3', extension: 'EAC3'),
        (filter: 'ac3', format: 'ac_3', extension: 'AC3'),
        (filter: 'ac4', format: 'ac-4', extension: 'AC4'),
      ]) {
        // SAF may expose an opaque URI, so the indexed format must also work.
        for (final table in ['history_db.history', 'library']) {
          await db.update(table, {
            'format': ' ${sample.format} ',
            'file_path': 'content://example/document/123',
          }, where: table == 'library' ? "id = 'l1'" : "id = 'h1'");
          await db.update(table, {
            'format': null,
            'file_path': '/track.${sample.extension}',
          }, where: table == 'library' ? "id = 'l2'" : "id = 'h2'");
        }
        final request = QueueLibraryDbQuery(format: sample.filter);
        expect(_tracks(await store.trackPage(request)).toSet(), {
          'local:l1',
          'local:l2',
        }, reason: sample.filter);
        expect((await store.counts(request)).allTrackCount, 2);
        expect((await store.albumPage(request)).rows, hasLength(1));
        final tagged = QueueLibraryDbQuery(
          format: sample.filter,
          metadata: 'has-replaygain',
          source: 'local',
          quality: 'cd',
          searchQuery: 'Artist',
        );
        expect(_tracks(await store.trackPage(tagged)), ['local:l1']);
        expect((await store.counts(tagged)).allTrackCount, 1);
      }
    },
  );

  test(
    'ReplayGain presence follows tag updates, paging and source deduplication',
    () async {
      const request = QueueLibraryDbQuery(metadata: 'has-replaygain', limit: 1);
      final first = await store.trackPage(request);
      final second = await store.trackPage(
        QueueLibraryDbQuery(
          metadata: 'has-replaygain',
          limit: 1,
          cursor: first.nextCursor,
        ),
      );
      expect(
        {..._tracks(first), ..._tracks(second)},
        {'local:l1', 'local:mirror'},
      );
      expect((await store.counts(request)).allTrackCount, 2);
      expect((await store.albumPage(request)).rows.single['track_count'], 2);

      await db.update('library', {'has_replaygain': 0}, where: "id = 'l1'");
      await db.update('library', {'has_replaygain': 1}, where: "id = 'l2'");
      final updated = await store.trackPage(
        const QueueLibraryDbQuery(metadata: 'has-replaygain'),
      );
      expect(_tracks(updated).toSet(), {'local:l2', 'local:mirror'});
      expect((await store.counts(request)).allTrackCount, 2);
      final missing = await store.trackPage(
        const QueueLibraryDbQuery(metadata: 'missing-replaygain'),
      );
      expect(_tracks(missing).toSet(), {'local:l1'});
    },
  );

  test(
    'local FTS input matches LIKE fallback and escapes literal search',
    () async {
      final expected = _tracks(
        await store.trackPage(const QueueLibraryDbQuery(searchQuery: 'Artist')),
      );
      const search = QueueLibraryDbQuery(searchQuery: 'Artist');
      final expectedAlbums = (await store.albumPage(search)).rows;
      final expectedCounts = await store.counts(search);
      final expectedArtists = await store.artistPage(search);
      for (final localFts in [false, true]) {
        final indexed = LibraryQueueStore(db, localFts: localFts);
        expect(
          _tracks(
            await indexed.trackPage(
              const QueueLibraryDbQuery(searchQuery: 'Artist'),
            ),
          ),
          expected,
        );
        expect((await indexed.albumPage(search)).rows, expectedAlbums);
        final counts = await indexed.counts(search);
        expect(
          [counts.allTrackCount, counts.albumCount, counts.singleTrackCount],
          [
            expectedCounts.allTrackCount,
            expectedCounts.albumCount,
            expectedCounts.singleTrackCount,
          ],
        );
        expect(await indexed.artistPage(search), expectedArtists);
      }
      await addLocal(
        'literal',
        1,
        album: 'Special',
        artist: 'Literal',
        title: 'Percent % Track',
      );
      expect(
        _tracks(
          await store.trackPage(const QueueLibraryDbQuery(searchQuery: '%')),
        ),
        ['local:literal'],
      );
    },
  );

  test(
    'artist pages aggregate visible inventory without loading track models',
    () async {
      final artists = await store.artistPage(const QueueLibraryDbQuery());
      expect(artists.map((row) => row['artist_name']), ['Artist']);
      expect(artists.map((row) => row['track_count']), [3]);
      final downloaded = await store.artistPage(
        const QueueLibraryDbQuery(includeLocal: false),
      );
      expect(downloaded.map((row) => row['track_count']), isEmpty);
    },
  );
}
