part of 'library_collections_mutation_test.dart';

void _registerLibraryCollectionsMutation1() {
  test(
    'deleted local IDs purge lazy playlists and Loved without ISRC collateral',
    () async {
      final db = _CollectionsDatabase();
      db.releaseWrite.complete();
      db.releasePlaylistRead.complete();
      final removed = _track(
        'deleted',
      ).copyWith(source: 'local', isrc: 'USAAA2600001');
      final retained = _track(
        'retained-copy',
      ).copyWith(source: 'local', isrc: 'USAAA2600001');
      final remote = _track('deleted').copyWith(source: 'legacy-provider');
      Map<String, dynamic> row(String key, Track track) => {
        'track_key': key,
        'track_json': jsonEncode(track.toJson()),
        'added_at': '2026-10-25',
      };
      db.loved['isrc:USAAA2600001'] = row('isrc:USAAA2600001', removed);
      db.loved['local:retained-copy'] = row('local:retained-copy', retained);
      db.loved['legacy-provider:deleted'] = row(
        'legacy-provider:deleted',
        remote,
      );
      db.playlists['playlist'] = {
        'id': 'playlist',
        'name': 'Mix',
        'created_at': '2026-10-25',
        'updated_at': '2026-10-25',
      };
      db.playlistTracks['playlist'] = [
        row('isrc:USAAA2600001', removed),
        row('occurrence:2:isrc:USAAA2600001', removed),
        row('local:retained-copy', retained),
        row('legacy-provider:deleted', remote),
      ];
      final container = _container(db);
      final notifier = container.read(libraryCollectionsProvider.notifier);
      await notifier.removeLocalLibraryTracks(['deleted']);
      expect(
        db.loved.keys,
        unorderedEquals(['local:retained-copy', 'legacy-provider:deleted']),
      );
      expect(db.playlistTracks['playlist']!.map((row) => row['track_key']), [
        'local:retained-copy',
        'legacy-provider:deleted',
      ]);
      final current = container.read(libraryCollectionsProvider);
      expect(current.loved.map((entry) => entry.track.id), [
        'retained-copy',
        'deleted',
      ]);
      expect(current.playlists.single.trackCount, 2);
      expect(current.playlists.single.tracksLoaded, isTrue);
    },
  );

  test(
    'failed deletion cleanup preserves Loved membership for retry',
    () async {
      final db = _CollectionsDatabase();
      db.releaseWrite.complete();
      final removed = _track('deleted').copyWith(source: 'local');
      db.loved['local:deleted'] = {
        'track_key': 'local:deleted',
        'track_json': jsonEncode(removed.toJson()),
        'added_at': '2026-10-25',
      };
      final container = _container(db);
      final notifier = container.read(libraryCollectionsProvider.notifier);
      db.failNextWrite = true;
      await expectLater(
        notifier.removeLocalLibraryTracks(['deleted']),
        throwsStateError,
      );
      expect(db.loved.keys, ['local:deleted']);
      expect(
        container.read(libraryCollectionsProvider).loved.single.track.id,
        'deleted',
      );
      await notifier.removeLocalLibraryTracks(['deleted']);
      expect(db.loved, isEmpty);
      expect(container.read(libraryCollectionsProvider).loved, isEmpty);
    },
  );

  test(
    'unreadable collections are not treated as empty deletion cleanup',
    () async {
      final db = _CollectionsDatabase();
      db.releaseWrite.complete();
      final pending = Completer<LibraryCollectionsSnapshot>();
      db.pendingSnapshot = pending.future;
      db.loved['local:deleted'] = {
        'track_key': 'local:deleted',
        'track_json': jsonEncode(
          _track('deleted').copyWith(source: 'local').toJson(),
        ),
        'added_at': '2026-10-25',
      };
      final container = _container(db);
      final notifier = container.read(libraryCollectionsProvider.notifier);
      final cleanup = notifier.removeLocalLibraryTracks(['deleted']);
      final rejected = expectLater(cleanup, throwsStateError);
      await db.snapshotReadStarted.future;
      pending.completeError(StateError('snapshot temporarily unreadable'));
      await rejected;
      expect(db.loved.keys, ['local:deleted']);
      expect(db.events, isEmpty);
      db.pendingSnapshot = null;
      await notifier.removeLocalLibraryTracks(['deleted']);
      expect(db.loved, isEmpty);
    },
  );

  test(
    'disposal during cleanup cannot report complete collection removal',
    () async {
      final db = _CollectionsDatabase();
      db.loved['local:deleted'] = {
        'track_key': 'local:deleted',
        'track_json': jsonEncode(
          _track('deleted').copyWith(source: 'local').toJson(),
        ),
        'added_at': '2026-10-25',
      };
      final container = _container(db);
      final notifier = container.read(libraryCollectionsProvider.notifier);
      final cleanup = notifier.removeLocalLibraryTracks(['deleted']);
      final rejected = expectLater(cleanup, throwsStateError);
      await db.writeStarted.future;
      container.dispose();
      db.releaseWrite.complete();
      await rejected;
    },
  );

  test(
    'playlist import retains all 202 positions and re-import is idempotent',
    () async {
      final db = _CollectionsDatabase();
      db.playlists['playlist'] = {
        'id': 'playlist',
        'name': 'Playlist',
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
      };
      db.releasePlaylistRead.complete();
      db.releaseWrite.complete();
      final container = _container(db);
      final notifier = container.read(libraryCollectionsProvider.notifier);
      final tracks = [
        for (var i = 0; i < 202; i++)
          _track('$i').copyWith(isrc: 'RECORDING${i % 198}'),
      ];
      final first = await notifier.addTracksToPlaylist(
        'playlist',
        tracks,
        preserveOccurrences: true,
      );
      expect(first.addedCount, 202);
      final imported = container
          .read(libraryCollectionsProvider)
          .playlists
          .single;
      expect(imported.trackCount, 202);
      expect(
        imported.tracks.map((entry) => entry.track.id),
        tracks.map((track) => track.id),
      );
      expect(db.playlistTracks['playlist'], hasLength(202));
      final request = PlaylistPickerSummaryRequest.fromTracks(
        tracks,
        preserveOccurrences: true,
      );
      expect(request.trackKeys.toSet(), imported.trackKeys);
      final second = await notifier.addTracksToPlaylist(
        'playlist',
        tracks,
        preserveOccurrences: true,
      );
      expect(second.addedCount, 0);
      expect(second.alreadyInPlaylistCount, 202);
      // Legacy playlists with the original 198 keys receive the four missing entries.
      final legacyKeys = tracks.map(trackCollectionKey).toSet();
      expect(
        request.trackKeys.where((key) => !legacyKeys.contains(key)),
        hasLength(4),
      );
    },
  );

  for (final failFirst in [false, true]) {
    test(
      'playlist bulk deletion snapshots IDs and serializes retries (fail: $failFirst)',
      () async {
        final db = _CollectionsDatabase()..failNextWrite = failFirst;
        for (final id in ['a', 'b', 'keep']) {
          db.playlists[id] = {
            'id': id,
            'name': 'Playlist $id',
            'cover_image_path': 'cover-$id',
            'created_at': '2026-01-01T00:00:00Z',
            'updated_at': '2026-01-02T00:00:00Z',
          };
          db.playlistTracks[id] = [
            {
              'track_key': 'example:shared',
              'track_json': jsonEncode(_track('shared').toJson()),
              'added_at': '2026-01-01T00:00:00Z',
            },
          ];
        }
        final container = _container(db);
        final notifier = container.read(libraryCollectionsProvider.notifier);
        final ids = ['a', 'b', 'missing', 'a'];
        final first = notifier.deletePlaylists(ids);
        ids
          ..clear()
          ..add('keep');
        final failure = failFirst ? expectLater(first, throwsStateError) : null;
        await db.writeStarted.future;
        final before = container.read(libraryCollectionsProvider);
        expect(before.playlists.every((p) => !p.tracksLoaded), true);
        var publications = 0;
        container.listen(libraryCollectionsProvider, (_, _) => publications++);
        final second = notifier.deletePlaylists(['a', 'b']);
        expect(db.events, ['bulk-playlists:remove']);
        expect(container.read(libraryCollectionsProvider), same(before));
        db.releaseWrite.complete();
        if (failure != null) {
          await failure;
        } else {
          expect(await first, 2);
        }
        expect(await second, failFirst ? 2 : 0);
        final after = container.read(libraryCollectionsProvider);
        expect(after.playlists.single, same(before.playlistById('keep')));
        expect(after.playlists.single.coverImagePath, 'cover-keep');
        expect(after.playlists.single.trackKeys, {'example:shared'});
        expect(db.playlists.keys, ['keep']);
        expect(db.playlistTracks.keys, ['keep']);
        expect(db.playlistReads, 0);
        expect(publications, 1);
        expect(await notifier.deletePlaylists([]), 0);
        expect(await notifier.deletePlaylists(['missing', 'a']), 0);
        expect(db.events.length, failFirst ? 2 : 1);
        expect(publications, 1);
      },
    );
  }

  test('late hydration cannot resurrect a bulk-deleted playlist', () async {
    final db = _CollectionsDatabase();
    db.playlists['p'] = {
      'id': 'p',
      'name': 'Playlist',
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
    };
    final rows = [
      {
        'track_key': 'example:shared',
        'track_json': jsonEncode(_track('shared').toJson()),
        'added_at': '2026-01-01T00:00:00Z',
      },
    ];
    db.playlistTracks['p'] = rows;
    db.stagedPlaylistRows = LibraryPlaylistTracksSnapshot(rows: rows);
    final container = _container(db);
    final notifier = container.read(libraryCollectionsProvider.notifier);
    final load = notifier.ensurePlaylistLoaded('p');
    await db.playlistReadStarted.future;
    db.releaseWrite.complete();
    expect(await notifier.deletePlaylists(['p']), 1);
    expect(container.read(libraryCollectionsProvider).playlists, isEmpty);
    db.releasePlaylistRead.complete();
    await load;
    expect(container.read(libraryCollectionsProvider).playlists, isEmpty);
    expect(db.playlistReads, 1);
  });
}
