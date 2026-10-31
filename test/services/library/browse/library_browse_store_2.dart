part of 'library_browse_store_test.dart';

void _registerLibraryBrowseStore2() {
  test('artist counts use the same filter as the track query', () async {
    for (final artist in ['Artist', 'Another Artist', 'Missing Artist']) {
      final query = LibraryBrowseDbQuery(albumArtist: artist);
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
        await db.update('library', {
          'format': ' ${sample.format} ',
          'file_path': 'content://example/document/123',
        }, where: "id = 'l1'");
        await db.update('library', {
          'format': null,
          'file_path': '/track.${sample.extension}',
        }, where: "id = 'l2'");
        final request = LibraryBrowseDbQuery(format: sample.filter);
        expect(_tracks(await store.trackPage(request)).toSet(), {
          'local:l1',
          'local:l2',
        }, reason: sample.filter);
        expect((await store.counts(request)).allTrackCount, 2);
        expect((await store.albumPage(request)).rows, hasLength(1));
        final tagged = LibraryBrowseDbQuery(
          format: sample.filter,
          metadata: 'has-replaygain',
          quality: 'cd',
          searchQuery: 'Artist',
        );
        expect(_tracks(await store.trackPage(tagged)), ['local:l1']);
        expect((await store.counts(tagged)).allTrackCount, 1);
      }
    },
  );

  test('ReplayGain presence follows tag updates and paging', () async {
    const request = LibraryBrowseDbQuery(metadata: 'has-replaygain', limit: 1);
    final first = await store.trackPage(request);
    final second = await store.trackPage(
      LibraryBrowseDbQuery(
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
      const LibraryBrowseDbQuery(metadata: 'has-replaygain'),
    );
    expect(_tracks(updated).toSet(), {'local:l2', 'local:mirror'});
    expect((await store.counts(request)).allTrackCount, 2);
    final missing = await store.trackPage(
      const LibraryBrowseDbQuery(metadata: 'missing-replaygain'),
    );
    expect(_tracks(missing).toSet(), {'local:l1'});
  });

  test('browse track rows carry the lyrics flag', () async {
    await db.update('library', {'has_lyrics': 1}, where: "id = 'l1'");
    final page = await store.trackPage(const LibraryBrowseDbQuery());
    final lyrics = {
      for (final row in page.rows)
        (row['item'] as Map)['id']: (row['item'] as Map)['hasLyrics'],
    };
    expect(lyrics['l1'], isTrue);
    expect(lyrics['l2'], isFalse);
  });

  test(
    'local FTS input matches LIKE fallback and escapes literal search',
    () async {
      final expected = _tracks(
        await store.trackPage(
          const LibraryBrowseDbQuery(searchQuery: 'Artist'),
        ),
      );
      const search = LibraryBrowseDbQuery(searchQuery: 'Artist');
      final expectedAlbums = (await store.albumPage(search)).rows;
      final expectedCounts = await store.counts(search);
      final expectedArtists = await store.artistPage(search);
      for (final localFts in [false, true]) {
        final indexed = LibraryBrowseStore(db, localFts: localFts);
        expect(
          _tracks(
            await indexed.trackPage(
              const LibraryBrowseDbQuery(searchQuery: 'Artist'),
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
      await _addLocal(
        'literal',
        1,
        album: 'Special',
        artist: 'Literal',
        title: 'Percent % Track',
      );
      expect(
        _tracks(
          await store.trackPage(const LibraryBrowseDbQuery(searchQuery: '%')),
        ),
        ['local:literal'],
      );
    },
  );

  test(
    'artist pages aggregate visible inventory without loading track models',
    () async {
      final artists = await store.artistPage(const LibraryBrowseDbQuery());
      expect(artists.map((row) => row['artist_name']), ['Artist']);
      expect(artists.map((row) => row['track_count']), [3]);
    },
  );
}
