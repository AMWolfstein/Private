part of 'library_collections_mutation_test.dart';

void _registerLibraryCollectionsMutation2() {
  for (final kind in ['loved', 'playlist']) {
    for (final failFirst in [false, true]) {
      test(
        'bulk $kind removal is atomic and serializes repeated clicks (fail: $failFirst)',
        () async {
          final db = _CollectionsDatabase()..failNextWrite = failFirst;
          final tracks = [
            for (final id in ['a', 'b', 'keep']) _track(id),
          ];
          final rows = [
            for (final track in tracks)
              <String, dynamic>{
                'track_key': trackCollectionKey(track),
                'track_json': jsonEncode(track.toJson()),
                'added_at': '2026-01-01T00:00:00Z',
              },
          ];
          for (final row in rows) {
            db.loved[row['track_key'] as String] = {...row};
          }
          for (final id in ['p', 'other']) {
            db.playlists[id] = {
              'id': id,
              'name': id,
              'cover_image_path': 'cover',
              'created_at': '2026-01-01T00:00:00Z',
              'updated_at': '2026-01-01T00:00:00Z',
            };
            db.playlistTracks[id] = [
              for (final row in rows) {...row},
            ];
          }
          db.releasePlaylistRead.complete();
          final container = _container(db);
          final notifier = container.read(libraryCollectionsProvider.notifier);
          Future<int> remove(Iterable<String> keys) => switch (kind) {
            'loved' => notifier.removeLovedTracks(keys),
            _ => notifier.removeTracksFromPlaylist('p', keys),
          };
          final selected = ['example:a', 'example:b', 'example:a', 'missing'];
          final first = remove(selected);
          selected
            ..clear()
            ..add('example:keep');
          final failure = failFirst
              ? expectLater(first, throwsStateError)
              : null;
          await db.writeStarted.future;
          final before = container.read(libraryCollectionsProvider);
          var publications = 0;
          container.listen(
            libraryCollectionsProvider,
            (_, _) => publications++,
          );
          final second = remove(['example:a', 'example:b']);
          expect(db.events, ['bulk-$kind:remove']);
          expect(container.read(libraryCollectionsProvider), same(before));
          db.releaseWrite.complete();
          if (failure != null) {
            await failure;
          } else {
            expect(await first, 2);
          }
          expect(await second, failFirst ? 2 : 0);
          expect(publications, 1);
          final after = container.read(libraryCollectionsProvider);
          final remaining = switch (kind) {
            'loved' => after.loved,
            _ => after.playlistById('p')!.tracks,
          };
          expect(remaining.map((entry) => entry.track.id), ['keep']);
          expect(remaining.single.addedAt, DateTime.utc(2026));
          expect(
            after.playlistById('other'),
            same(before.playlistById('other')),
          );
          expect(db.playlistTracks['other'], rows);
          expect(db.loved.length, kind == 'loved' ? 1 : 3);
          expect(db.playlistTracks['p']!.length, kind == 'playlist' ? 1 : 3);
          expect(db.events.length, failFirst ? 2 : 1);
          expect(db.playlistReads, kind == 'playlist' ? 1 : 0);
          if (kind == 'playlist') {
            final playlist = after.playlistById('p')!;
            expect(playlist.coverImagePath, 'cover');
            expect(playlist.createdAt, DateTime.utc(2026));
            expect(playlist.trackKeys, {'example:keep'});
            expect(playlist.updatedAt.isAfter(DateTime.utc(2026)), isTrue);
            expect(
              db.playlists['p']!['updated_at'],
              playlist.updatedAt.toIso8601String(),
            );
          }
          expect(await remove(const []), 0);
          expect(await remove(['missing']), 0);
          expect(
            await notifier.removeTracksFromPlaylist('missing', [
              'example:keep',
            ]),
            0,
          );
          expect(container.read(libraryCollectionsProvider), same(after));
          expect(publications, 1);
        },
      );
    }
  }

  for (final failFirst in [false, true]) {
    test(
      'Love All is atomic and serializes repeated clicks (failure: $failFirst)',
      () async {
        final db = _CollectionsDatabase()..failNextWrite = failFirst;
        final container = _container(db);
        final notifier = container.read(libraryCollectionsProvider.notifier);
        var publications = 0;
        container.listen(libraryCollectionsProvider, (_, _) => publications++);
        final selected = [_track('1'), _track('1'), _track('2')];
        final first = notifier.toggleLovedTracks(selected);
        final failure = failFirst ? expectLater(first, throwsStateError) : null;
        await db.writeStarted.future;
        publications = 0;
        expect(container.read(libraryCollectionsProvider).loved, isEmpty);
        final second = notifier.toggleLovedTracks(selected);
        expect(db.events, ['bulk-loved:add']);
        db.releaseWrite.complete();
        if (failure != null) {
          await failure;
        } else {
          expect(await first, (removed: false, count: 2));
        }
        expect(await second, (removed: !failFirst, count: 2));
        expect(publications, failFirst ? 1 : 2);
        expect(
          container
              .read(libraryCollectionsProvider)
              .loved
              .map((entry) => entry.track.id),
          failFirst ? ['2', '1'] : isEmpty,
        );
        expect(db.loved.length, failFirst ? 2 : 0);
        expect(db.events, [
          'bulk-loved:add',
          failFirst ? 'bulk-loved:add' : 'bulk-loved:remove',
        ]);
      },
    );
  }

  test(
    'mixed Love All preserves existing metadata and unrelated loved tracks',
    () async {
      final db = _CollectionsDatabase();
      for (final id in ['existing', 'unrelated']) {
        db.loved[trackCollectionKey(_track(id))] = {
          'track_key': trackCollectionKey(_track(id)),
          'track_json': jsonEncode(_track(id).toJson()),
          'added_at': '2026-01-01T00:00:00Z',
        };
      }
      final container = _container(db);
      final notifier = container.read(libraryCollectionsProvider.notifier);
      final selected = [_track('existing'), _track('new'), _track('new')];
      final add = notifier.toggleLovedTracks(selected);
      await db.writeStarted.future;
      db.releaseWrite.complete();
      expect(await add, (removed: false, count: 1));
      expect(
        container
            .read(libraryCollectionsProvider)
            .loved
            .map((entry) => entry.track.id),
        ['new', 'existing', 'unrelated'],
      );
      expect(
        db.loved[trackCollectionKey(_track('existing'))]!['added_at'],
        '2026-01-01T00:00:00Z',
      );
      expect(await notifier.toggleLovedTracks(selected), (
        removed: true,
        count: 2,
      ));
      expect(
        container.read(libraryCollectionsProvider).loved.single.track.id,
        'unrelated',
      );
      final before = db.events.length;
      expect(await notifier.toggleLovedTracks(const []), (
        removed: false,
        count: 0,
      ));
      expect(db.events.length, before);
    },
  );

  for (final failFirst in [false, true]) {
    test(
      'bulk additions publish after persistence and serialize duplicates (failure: $failFirst)',
      () async {
        final db = _CollectionsDatabase();
        db.playlists['playlist'] = {
          'id': 'playlist',
          'name': 'Playlist',
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        };
        db.releasePlaylistRead.complete();
        db.failNextWrite = failFirst;
        final container = _container(db);
        final notifier = container.read(libraryCollectionsProvider.notifier);
        final first = notifier.addTracksToPlaylist('playlist', [
          _track('1'),
          _track('1'),
          _track('2'),
        ]);
        final failure = failFirst ? expectLater(first, throwsStateError) : null;
        await db.writeStarted.future;
        expect(
          container
              .read(libraryCollectionsProvider)
              .playlistById('playlist')!
              .trackCount,
          0,
        );
        final second = notifier.addTracksToPlaylist('playlist', [
          _track('2'),
          _track('3'),
        ]);
        expect(db.events, ['batch:playlist']);
        db.releaseWrite.complete();
        if (failure != null) {
          await failure;
        } else {
          final result = await first;
          expect(result.addedCount, 2);
          expect(result.alreadyInPlaylistCount, 1);
        }
        final result = await second;
        expect(result.addedCount, failFirst ? 2 : 1);
        expect(result.alreadyInPlaylistCount, failFirst ? 0 : 1);
        final playlist = container
            .read(libraryCollectionsProvider)
            .playlistById('playlist')!;
        expect(
          playlist.tracks.map((entry) => entry.track.id),
          failFirst ? ['2', '3'] : ['1', '2', '3'],
        );
        expect(playlist.trackCount, failFirst ? 2 : 3);
        expect(db.events, ['batch:playlist', 'batch:playlist']);
      },
    );
  }

  test('disposed snapshot read removes native rows before returning', () async {
    final directory = await Directory.systemTemp.createTemp(
      'collection-read-disposed-',
    );
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final path = '${directory.path}/rows.ndjson';
    await File(path).writeAsString('must never be parsed');
    final reply = Completer<LibraryCollectionsSnapshot>();
    final db = _CollectionsDatabase()..pendingSnapshot = reply.future;
    final container = _container(db);
    final notifier = container.read(libraryCollectionsProvider.notifier);
    final done = notifier.ensurePlaylistLoaded('missing');
    await db.snapshotReadStarted.future;
    container.dispose();
    reply.complete(
      LibraryCollectionsSnapshot(
        lovedRows: const [],
        playlistRows: const [],
        playlistTrackRows: const [],
        favoriteArtistRows: const [],
        nativeRowsPath: path,
        nativeRowsDirectory: directory.path,
        nativeRowCount: 1,
      ),
    );
    await done;
    expect(await directory.exists(), isFalse);
  });

  test(
    'playlist worker load is single-flight and retains intervening rename',
    () async {
      final db = _CollectionsDatabase();
      db.playlists['playlist'] = {
        'id': 'playlist',
        'name': 'Original',
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
      };
      db.playlistTracks['playlist'] = List.generate(
        100,
        (index) => {
          'track_key': 'example:$index',
          'track_json': jsonEncode(_track('$index')),
          'added_at': '2026-01-01T00:00:00Z',
        },
      );
      final container = _container(db);
      final notifier = container.read(libraryCollectionsProvider.notifier);
      await Future<void>.value();
      final first = notifier.ensurePlaylistLoaded('playlist');
      await db.playlistReadStarted.future;
      final second = notifier.ensurePlaylistLoaded('playlist');
      final rename = notifier.renamePlaylist('playlist', 'Renamed');
      await db.writeStarted.future;
      db.releaseWrite.complete();
      await rename;
      db.releasePlaylistRead.complete();
      await Future.wait([first, second]);
      final playlist = container
          .read(libraryCollectionsProvider)
          .playlistById('playlist')!;
      expect(db.playlistReads, 1);
      expect(playlist.name, 'Renamed');
      expect(playlist.tracksLoaded, isTrue);
      expect(playlist.trackCount, 100);
      expect(
        playlist.tracks.map((entry) => entry.track.id),
        List.generate(100, (index) => '$index'),
      );
    },
  );

  test('disposed playlist read cannot publish a worker result', () async {
    final db = _CollectionsDatabase();
    final directory = await Directory.systemTemp.createTemp(
      'collection-read-disposed-',
    );
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final path = '${directory.path}/rows.ndjson';
    await File(path).writeAsString('must never be parsed');
    db.stagedPlaylistRows = LibraryPlaylistTracksSnapshot(
      nativeRowsPath: path,
      nativeRowsDirectory: directory.path,
      nativeRowCount: 1,
    );
    db.playlists['playlist'] = {
      'id': 'playlist',
      'name': 'Playlist',
      'created_at': '2026-01-01T00:00:00Z',
    };
    final container = _container(db);
    final notifier = container.read(libraryCollectionsProvider.notifier);
    await Future<void>.value();
    final loading = notifier.ensurePlaylistLoaded('playlist');
    await db.playlistReadStarted.future;
    container.dispose();
    db.releasePlaylistRead.complete();
    await loading;
    expect(db.playlistReads, 1);
    expect(await directory.exists(), isFalse);
  });

  test(
    'late write completion does not publish or start a disposed mutation',
    () async {
      final db = _CollectionsDatabase();
      final container = _container(db);
      final notifier = container.read(libraryCollectionsProvider.notifier);
      await Future<void>.value();
      final active = notifier.toggleLoved(_track('active'));
      await db.writeStarted.future;
      final queued = notifier.toggleLoved(_track('queued'));
      final cancelled = expectLater(queued, throwsStateError);
      container.dispose();
      db.releaseWrite.complete();
      expect(await active, isTrue);
      await cancelled;
      expect(db.events, ['insert:loved:example:active']);
      expect(db.loved.keys, ['example:active']);
    },
  );
}
