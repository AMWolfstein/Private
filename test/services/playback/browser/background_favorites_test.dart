import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/providers/library/library_collections_provider.dart';
import 'package:sistrum/providers/playback/music_player_provider.dart';
import 'package:sistrum/providers/playback/playback_notification_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sistrum/core/models/track.dart';
import 'package:sistrum/services/library/collections/library_collections_database.dart';
import 'package:sistrum/services/library/database/library_database.dart';
import 'package:sistrum/services/playback/browser/background_favorites.dart';
import 'package:sistrum/services/playback/music_player/music_player_runtime.dart';
import 'package:sistrum/services/playback/notification/playback_notification.dart';
import '../../../support/music_player_harness.dart';
import '../../../support/media_library_catalog_harness.dart';
import '../../../support/sqlite_process_database.dart';

class Collections implements LibraryCollectionsDatabase {
  Collections(this.db);
  final Database db;
  @override
  Future<Database> get database async => db;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ControlledFavorites extends BackgroundFavorites {
  ControlledFavorites()
    : super(
        library: LibraryDatabase.instance,
        collections: LibraryCollectionsDatabase.instance,
      );
  final checks = <String, List<Completer<bool>>>{};
  Completer<bool>? toggleGate;
  @override
  Future<bool> isLoved(MediaItem item) {
    final gate = Completer<bool>();
    checks.putIfAbsent(item.id, () => []).add(gate);
    return gate.future;
  }

  @override
  Future<bool> toggle(MediaItem item) async =>
      toggleGate == null ? true : toggleGate!.future;
}

class FavoritesView extends LibraryCollectionsNotifier {
  FavoritesView(this.onBuild);
  final void Function() onBuild;
  @override
  LibraryCollectionsState build() {
    onBuild();
    return LibraryCollectionsState(isLoaded: true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'a headless star committed after UI takeover refreshes the loaded collection',
    () async {
      final runtime = musicPlayerRuntimeFor(
        restoreSession: (_) async => PlaybackRestoreOutcome.nothingSaved,
      );
      final favorites = ControlledFavorites()..toggleGate = Completer<bool>();
      runtime.configureBackgroundNotification(
        presentation: const PlaybackNotification(sistrum: true),
        favorites: favorites,
      );
      final pending = runtime.toggleFavorite(
        MediaItem(id: 'song', title: 'Song'),
      );
      var builds = 0;
      final container = ProviderContainer(
        overrides: [
          musicPlayerRuntimeProvider.overrideWithValue(runtime),
          libraryCollectionsProvider.overrideWith(
            () => FavoritesView(() => builds++),
          ),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        playbackNotificationProvider((
          favorite: 'UI favorite',
          unfavorite: 'UI unfavorite',
          shuffleOn: 'On',
          shuffleOff: 'Off',
        )),
        (_, _) {},
      );
      addTearDown(subscription.close);
      await container.pump();
      expect(builds, 1);
      favorites.toggleGate!.complete(true);
      expect(await pending, true);
      await settleMusicPlayer();
      await container.pump();
      expect(builds, 2);
      expect(runtime.notification.favoriteLabel, 'UI favorite');
    },
  );
  test(
    'headless stars persist with the same ISRC identity the UI uses',
    () async {
      final root = await Directory.systemTemp.createTemp('headless-loved-');
      final db = await SqliteProcessDatabase.open(
        path: '${root.path}/loved.db',
      );
      addTearDown(() async {
        await db.close();
        await root.delete(recursive: true);
      });
      await db.execute(
        'CREATE TABLE loved_tracks(track_key TEXT PRIMARY KEY,track_json TEXT,added_at TEXT)',
      );
      const track = Track(
        id: 'song',
        name: 'Song',
        artistName: 'Artist',
        albumName: 'Album',
        duration: 120,
        source: 'local',
        isrc: 'abc123',
      );
      final favorites = BackgroundFavorites(
        library: LibraryDatabase.instance,
        collections: Collections(db),
        resolve: (_) async => track,
      );
      final item = MediaItem(id: 'old-queue-id', title: 'Song');
      expect(await favorites.isLoved(item), false);
      expect(await favorites.toggle(item), true);
      expect(await favorites.isLoved(item), true);
      expect(
        (await db.rawQuery(
          'SELECT track_key FROM loved_tracks',
        )).single['track_key'],
        'isrc:ABC123',
      );
      expect(await favorites.toggle(item), false);
      expect(await favorites.isLoved(item), false);
    },
  );
  test(
    'late headless favorite reads cannot overwrite foreground controls or disposed runtime',
    () async {
      final catalog = FakeMediaLibraryCatalog(count: 2);
      final runtime = musicPlayerRuntimeFor(
        mediaLibraryCatalog: catalog,
        restoreSession: (_) async => PlaybackRestoreOutcome.nothingSaved,
      );
      final favorites = ControlledFavorites();
      runtime.configureBackgroundNotification(
        presentation: const PlaybackNotification(sistrum: true),
        favorites: favorites,
      );
      final handler = await runtime.initialize();
      await handler.setQueueAndPlay([catalog.songs.first]);
      await settleMusicPlayer();
      final pending = favorites.checks['song-0']!.single;
      runtime.configureNotification(
        presentation: const PlaybackNotification(favoriteLabel: 'UI control'),
        toggleFavorite: (_) async => false,
      );
      pending.complete(true);
      await settleMusicPlayer();
      expect(runtime.notification.favoriteLabel, 'UI control');
      expect(runtime.notification.mediaId, isNull);
      await runtime.dispose();
    },
  );
  test('A-B-A track changes reject the first delayed read of A', () async {
    final catalog = FakeMediaLibraryCatalog(count: 2);
    final runtime = musicPlayerRuntimeFor(
      mediaLibraryCatalog: catalog,
      restoreSession: (_) async => PlaybackRestoreOutcome.nothingSaved,
    );
    final favorites = ControlledFavorites();
    runtime.configureBackgroundNotification(
      presentation: const PlaybackNotification(sistrum: true),
      favorites: favorites,
    );
    final handler = await runtime.initialize();
    await handler.setQueueAndPlay(catalog.songs);
    await settleMusicPlayer();
    await handler.skipToNext();
    await settleMusicPlayer();
    await handler.skipToPrevious();
    await settleMusicPlayer();
    final a = favorites.checks['song-0']!;
    expect(a.length, 2);
    a.last.complete(false);
    await settleMusicPlayer();
    a.first.complete(true);
    await settleMusicPlayer();
    favorites.checks['song-1']!.single.complete(true);
    await settleMusicPlayer();
    expect(runtime.notification.mediaId, 'song-0');
    expect(runtime.notification.loved, false);
  });
}
