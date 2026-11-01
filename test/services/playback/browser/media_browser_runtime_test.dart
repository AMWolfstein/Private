import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/core/models/settings.dart';
import 'package:sistrum/services/playback/browser/background_playback.dart';
import 'package:sistrum/services/playback/browser/media_library_browser.dart';
import 'package:sistrum/services/playback/browser/media_library_catalog.dart';
import 'package:sistrum/services/playback/music_player/music_player_runtime.dart';
import '../../../support/media_library_catalog_harness.dart';
import '../../../support/music_player_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('an unnamed audio voice request resumes the existing queue', () async {
    final catalog = FakeMediaLibraryCatalog(count: 4);
    final runtime = musicPlayerRuntimeFor(
      mediaLibraryCatalog: catalog,
      restoreSession: (_) async => PlaybackRestoreOutcome.nothingSaved,
    );
    final handler = await runtime.initialize();
    await handler.setQueueAndPlay([catalog.songs[3]]);
    await handler.pause();
    await handler.playFromSearch('', {
      'android.intent.extra.focus': 'vnd.android.cursor.item/audio',
    });
    expect(handler.queue.value.length, 1);
    expect(handler.mediaItem.value!.id, 'song-3');
    expect(handler.playbackState.value.playing, true);
  });
  test(
    'headless bootstrap needs no Activity, is single-flight, and uses the selected locale',
    () async {
      var restores = 0;
      final decks = <FakeDeck>[];
      final runtime = musicPlayerRuntimeFor(
        settings: const AppSettings(locale: 'ar', pauseOnMute: false),
        decks: decks,
        mediaLibraryCatalog: FakeMediaLibraryCatalog(),
        restoreSession: (_) async {
          restores++;
          return PlaybackRestoreOutcome.nothingSaved;
        },
      );
      await Future.wait([
        initializeMediaBrowser(runtime),
        initializeMediaBrowser(runtime),
      ]);
      expect(restores, 1);
      expect(decks.length, 1);
      final roots = await runtime.handler!.getChildren(
        AudioService.browsableRootId,
      );
      expect(roots.length, 4);
      expect(roots.first.title, isNot('Songs'));
      expect(runtime.notification.sistrum, true);
      expect(runtime.handler!.mediaItem.value, isNull);
      expect(runtime.handler!.playbackState.value.playing, false);
    },
  );
  test(
    'browsing plays the selected library context and exposes search actions',
    () async {
      final catalog = FakeMediaLibraryCatalog(count: 20);
      final runtime = musicPlayerRuntimeFor(
        mediaLibraryCatalog: catalog,
        restoreSession: (_) async => PlaybackRestoreOutcome.nothingSaved,
      );
      final handler = await runtime.initialize();
      final listed = await handler.getChildren(MediaLibraryBrowser.songsId);
      await handler.playFromMediaId(listed[5].id);
      expect(handler.mediaItem.value!.title, 'Song 4');
      expect(handler.queue.value.length, 20);
      expect(
        handler.playbackState.value.systemActions,
        contains(MediaAction.playFromSearch),
      );
      final recent = await handler.getChildren(AudioService.recentRootId);
      expect(recent.single.id, handler.mediaItem.value!.id);
      // No provider on the host: private file paths are not disclosed as car art.
      expect(recent.single.artUri, isNull);
      await handler.playFromSearch('Song 12');
      expect(handler.mediaItem.value!.title, 'Song 12');
      expect(handler.queue.value.length, 1);
    },
  );
  for (final interrupt in [
    'second search',
    'stop',
    'seek',
    'pause',
    'dispose',
    'phone queue',
  ]) {
    test('a pending browser request cannot overwrite $interrupt', () async {
      final catalog = FakeMediaLibraryCatalog(count: 20);
      final runtime = musicPlayerRuntimeFor(
        mediaLibraryCatalog: catalog,
        restoreSession: (_) async => PlaybackRestoreOutcome.nothingSaved,
      );
      final handler = await runtime.initialize();
      await handler.setQueueAndPlay([catalog.songs.first]);
      final gate = Completer<BrowserTrackPage>();
      catalog.gate = gate;
      final request = handler.playFromSearch('Song 1');
      await settleMusicPlayer();
      switch (interrupt) {
        case 'second search':
          await handler.playFromSearch('Song 2');
        case 'stop':
          await handler.stop();
        case 'seek':
          await handler.seek(const Duration(seconds: 5));
        case 'pause':
          await handler.pause();
        case 'dispose':
          await handler.dispose();
        case 'phone queue':
          await handler.setQueueAndPlay([catalog.songs[9]]);
      }
      gate.complete((items: [catalog.songs[1]], hasMore: false));
      await request;
      if (interrupt == 'second search') {
        expect(handler.mediaItem.value!.title, 'Song 2');
      } else if (interrupt == 'phone queue') {
        expect(handler.mediaItem.value!.title, 'Song 9');
      } else {
        expect(handler.mediaItem.value?.title, isNot('Song 1'));
      }
    });
  }
}
