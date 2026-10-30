import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/models/track.dart';
import 'package:sistrum/providers/library_collections_provider.dart';
import 'package:sistrum/providers/music_player_provider.dart';
import 'package:sistrum/providers/playback_notification_provider.dart';
import 'package:sistrum/services/playback/music_player_runtime.dart';
import 'package:sistrum/services/playback/playback_notification.dart';

import 'support/library_section_harness.dart';

/// Records the notification the provider configures, instead of posting one.
class _RecordingRuntime implements MusicPlayerRuntime {
  PlaybackNotification? presentation;
  int configured = 0;

  @override
  void configureNotification({
    required PlaybackNotification presentation,
    required Future<bool> Function(MediaItem) toggleFavorite,
  }) {
    this.presentation = presentation;
    configured++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CurrentItem extends CurrentMediaItemNotifier {
  @override
  Stream<MediaItem?> build() => Stream.value(
    const MediaItem(id: 'track-1', title: 'Song', extras: {'source': 'local'}),
  );
}

const _labels = (
  favorite: 'Favorite',
  unfavorite: 'Unfavorite',
  shuffleOn: 'Shuffle on',
  shuffleOff: 'Shuffle off',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the notification shows the current track with its labels', () async {
    final runtime = _RecordingRuntime();
    final container = ProviderContainer(
      overrides: [
        musicPlayerRuntimeProvider.overrideWithValue(runtime),
        currentMediaItemProvider.overrideWith(_CurrentItem.new),
        playerCollectionTrackProvider.overrideWith(
          (ref, item) async => Track(
            id: item.id,
            name: 'Song',
            artistName: 'Artist',
            albumName: 'Album',
            duration: 180,
          ),
        ),
        libraryCollectionsProvider.overrideWith(LibrarySectionCollections.new),
      ],
    );
    addTearDown(container.dispose);

    // Keep the auto-dispose provider alive while its notification is posted.
    final subscription = container.listen(
      playbackNotificationProvider(_labels),
      (_, _) {},
    );
    addTearDown(subscription.close);
    // The item arrives through a stream and the notification is posted in a
    // microtask, so wait for it rather than for a fixed time.
    for (var turn = 0; turn < 500 && runtime.configured == 0; turn++) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(runtime.configured, 1);
    final notification = runtime.presentation!;
    expect(notification.mediaId, 'track-1');
    expect(notification.source, 'local');
    expect(notification.loved, isFalse);
    expect(notification.favoriteLabel, 'Favorite');
    expect(notification.unfavoriteLabel, 'Unfavorite');
    expect(notification.shuffleOnLabel, 'Shuffle on');
    expect(notification.shuffleOffLabel, 'Shuffle off');
  });
}
