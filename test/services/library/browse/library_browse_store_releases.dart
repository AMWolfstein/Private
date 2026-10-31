part of 'library_browse_store_test.dart';

late SqliteProcessDatabase db;

late LibraryBrowseStore store;

Future<void> _addLocal(
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

void _registerLibraryBrowseStoreReleases() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    db = await SqliteProcessDatabase.open();
    await LibrarySchema.create(db, LibrarySchema.version);
    await _addLocal('l1', 1);
    await _addLocal('l2', 2);
    await _addLocal('mirror', 1, path: '/h1.flac');
    await db.insert('library_sources', {
      'id': 'offline',
      'path': '/offline',
      'display_name': 'Offline',
      'available': 0,
    });
    await _addLocal('hidden', 1, source: 'offline');
    store = LibraryBrowseStore(db, localFts: false);
  });
  tearDown(() => db.close());

  test(
    'album navigation resolves the normalized key with Unicode names',
    () async {
      await _addLocal('unicode-2', 2, album: 'Été', artist: 'Björk');
      await _addLocal('unicode-1', 1, album: 'Été', artist: 'Björk');
      await _addLocal('other-edition', 1, album: 'Été', artist: 'Other');

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
      await _addLocal('explicit', 1, source: 'music', explicit: true);

      final page = await store.trackPage(const LibraryBrowseDbQuery());
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
    await _addLocal('single-copy-1', 1, album: 'Tagged Single', totalTracks: 1);
    await _addLocal('single-copy-2', 1, album: 'Tagged Single', totalTracks: 1);
    await _addLocal('partial', 1, album: 'Partial Album', totalTracks: 10);
    await _addLocal('unknown', 1, album: 'Unknown Album', totalTracks: null);
    await _addLocal(
      'conflict-1',
      1,
      album: 'Conflicting Album',
      totalTracks: 1,
    );
    await _addLocal(
      'conflict-2',
      2,
      album: 'Conflicting Album',
      totalTracks: 10,
    );

    for (final quality in [null, 'unrecognized']) {
      final query = LibraryBrowseDbQuery(quality: quality);
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
        LibraryBrowseDbQuery(filterMode: 'singles', quality: quality),
      );
      expect(_tracks(singles).toSet(), {
        'local:single-copy-1',
        'local:single-copy-2',
      });
    }
    final filtered = await store.counts(
      const LibraryBrowseDbQuery(searchQuery: 'Song', quality: 'unrecognized'),
    );
    expect(filtered.albumCount, 4);
    expect(filtered.singleTrackCount, 2);
    final allReleases = await store.albumPage(
      const LibraryBrowseDbQuery(includeSingleTrackAlbums: true),
    );
    expect(allReleases.rows, hasLength(5));
  });

  test('artist releases order compact and ISO tags chronologically', () async {
    await _addLocal(
      'compact',
      1,
      album: 'Compact',
      artist: 'Chronology',
      releaseDate: '20250101',
    );
    await _addLocal(
      'iso',
      1,
      album: 'ISO',
      artist: 'Chronology',
      releaseDate: '2026-01-01',
    );
    await _addLocal(
      'year',
      1,
      album: 'Year',
      artist: 'Chronology',
      releaseDate: '2024',
    );
    await _addLocal(
      'invalid',
      1,
      album: 'Invalid',
      artist: 'Chronology',
      releaseDate: '2026-99-99',
    );

    final query = const LibraryBrowseDbQuery(
      albumArtist: 'Chronology',
      sortMode: 'artist-releases-newest',
      includeSingleTrackAlbums: true,
      limit: 2,
    );
    final first = await store.albumPage(query);
    expect(first.rows.map((row) => row['album_name']), ['ISO', 'Compact']);
    final second = await store.albumPage(
      LibraryBrowseDbQuery(
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
          await store.trackPage(LibraryBrowseDbQuery(sortMode: sort)),
        );
        final actual = <String>[];
        LibraryBrowseDbCursor? cursor;
        do {
          final page = await store.trackPage(
            LibraryBrowseDbQuery(sortMode: sort, limit: 2, cursor: cursor),
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
          LibraryBrowseDbQuery(sortMode: sort),
        )).rows;
        final first = await store.albumPage(
          LibraryBrowseDbQuery(sortMode: sort, limit: 1),
        );
        final second = await store.albumPage(
          LibraryBrowseDbQuery(
            sortMode: sort,
            limit: 1,
            cursor: first.nextCursor,
          ),
        );
        expect([...first.rows, ...second.rows], expected, reason: sort);
        final fallback = await store.albumPage(
          LibraryBrowseDbQuery(
            sortMode: sort,
            offset: 0,
            limit: 1,
            cursor: const LibraryBrowseDbCursor(['wrong length']),
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
      await _addLocal('local-edition1', 1, artist: 'Other Artist');
      await _addLocal('local-edition2', 2, artist: 'Other Artist');
      await _addLocal('local-single', 1, album: 'Local Single');
      await db.insert('library_sources', {
        'id': 'disabled',
        'path': '/disabled',
        'display_name': 'Disabled',
        'enabled': 0,
      });
      await _addLocal('disabled1', 1, source: 'disabled');
      await _addLocal('disabled2', 2, source: 'disabled');
      {
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
              Future<LibraryBrowseDbPage> page(String? quality) =>
                  store.albumPage(
                    LibraryBrowseDbQuery(
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
      final albums = (await store.albumPage(const LibraryBrowseDbQuery())).rows;
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
          const LibraryBrowseDbQuery(includeSingleTrackAlbums: true),
        )).rows,
        hasLength(3),
      );
      final filtered = (await store.albumPage(
        const LibraryBrowseDbQuery(metadata: 'missing-replaygain'),
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
      final albums = LibraryBrowseStore(recorded, localFts: false);
      final fast = await albums.albumPage(
        const LibraryBrowseDbQuery(limit: 40),
      );
      final fastSql = recorded.sql;
      final fastArgs = recorded.args;
      final original = await albums.albumPage(
        const LibraryBrowseDbQuery(limit: 40, quality: 'unrecognized'),
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
      final fast = await store.counts(const LibraryBrowseDbQuery());
      final filtered = await store.counts(
        const LibraryBrowseDbQuery(quality: 'cd'),
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
      final local = await store.counts(const LibraryBrowseDbQuery());
      expect(local.allTrackCount, 3);
      final gain = await store.trackPage(
        const LibraryBrowseDbQuery(metadata: 'missing-replaygain'),
      );
      expect(_tracks(gain).toSet(), {'local:l2'});
    },
  );
}
