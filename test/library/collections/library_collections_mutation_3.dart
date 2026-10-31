part of 'library_collections_mutation_test.dart';

void _registerLibraryCollectionsMutation3() {
  for (final kind in ['loved', 'artists']) {
    test('two overlapping $kind toggles persist insert then delete', () async {
      final db = _CollectionsDatabase();
      final container = _container(db);
      final notifier = container.read(libraryCollectionsProvider.notifier);
      await Future<void>.value();
      Future<bool> toggle() => switch (kind) {
        'loved' => notifier.toggleLoved(_track('song')),
        _ => notifier.toggleFavoriteArtist(
          artistId: 'artist',
          providerId: 'example',
          name: 'Artist',
        ),
      };
      final key = kind == 'artists' ? 'example:artist' : 'example:song';
      final first = toggle();
      await db.writeStarted.future;
      final second = toggle();
      await Future<void>.delayed(Duration.zero);
      expect(db.events, ['insert:$kind:$key']);
      final pending = container.read(libraryCollectionsProvider);
      expect(pending.loved, isEmpty);
      expect(pending.favoriteArtists, isEmpty);
      db.releaseWrite.complete();
      expect(await Future.wait([first, second]), [true, false]);
      expect(db.events, ['insert:$kind:$key', 'delete:$kind:$key']);
      expect(db.loved, isEmpty);
      expect(db.artists, isEmpty);
      final state = container.read(libraryCollectionsProvider);
      expect(state.loved, isEmpty);
      expect(state.favoriteArtists, isEmpty);
    });
  }

  test(
    'playlist deletion cannot remove a concurrently created playlist',
    () async {
      final db = _CollectionsDatabase();
      for (final id in ['target', 'keep']) {
        db.playlists[id] = {
          'id': id,
          'name': id,
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        };
      }
      final container = _container(db);
      final notifier = container.read(libraryCollectionsProvider.notifier);
      await Future<void>.value();
      final deletion = notifier.deletePlaylists(['target']);
      await db.writeStarted.future;
      final creation = notifier.createPlaylist('New');
      await Future<void>.delayed(Duration.zero);
      expect(db.events, ['bulk-playlists:remove']);
      expect(
        container.read(libraryCollectionsProvider).playlists.map((p) => p.id),
        ['target', 'keep'],
      );
      db.releaseWrite.complete();
      await deletion;
      final createdId = await creation;
      expect(db.events, [
        'bulk-playlists:remove',
        'insert:playlist:$createdId',
      ]);
      expect(db.playlists.keys.toSet(), {'keep', createdId});
      expect(
        container.read(libraryCollectionsProvider).playlists.map((p) => p.id),
        [createdId, 'keep'],
      );
    },
  );

  test(
    'failed writes retain published state and release the next mutation',
    () async {
      final db = _CollectionsDatabase()..failNextWrite = true;
      final container = _container(db);
      final notifier = container.read(libraryCollectionsProvider.notifier);
      await Future<void>.value();
      final failed = notifier.toggleLoved(_track('failed'));
      final failure = expectLater(failed, throwsStateError);
      await db.writeStarted.future;
      final successful = notifier.toggleLoved(_track('successful'));
      await Future<void>.delayed(Duration.zero);
      expect(db.events, ['insert:loved:example:failed']);
      expect(container.read(libraryCollectionsProvider).loved, isEmpty);
      db.releaseWrite.complete();
      await failure;
      expect(await successful, isTrue);
      expect(db.loved.keys, ['example:successful']);
      expect(
        container.read(libraryCollectionsProvider).loved.map((e) => e.key),
        ['example:successful'],
      );
    },
  );
}
