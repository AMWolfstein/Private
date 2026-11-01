import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/providers/library/library_collections_provider.dart';
import 'package:sistrum/providers/playback/music_player_provider.dart';
import 'package:sistrum/services/playback/notification/playback_notification.dart';

/// Stable for the shell lifetime: per-track notification rebuilds must not
/// replace the subscription while a headless collection transaction commits.
final backgroundCollectionSyncProvider = Provider.autoDispose<void>((ref) {
  final subscription = ref
      .watch(musicPlayerRuntimeProvider)
      .backgroundCollectionChanges
      .listen((_) {
        if (ref.mounted) ref.invalidate(libraryCollectionsProvider);
      });
  ref.onDispose(() => unawaited(subscription.cancel()));
});

/// Kept alive by the app shell so notification favorites share the exact
/// Library identity and refresh when the same track is starred inside the app.
final playbackNotificationProvider = Provider.autoDispose
    .family<
      void,
      ({
        String favorite,
        String unfavorite,
        String shuffleOn,
        String shuffleOff,
      })
    >((ref, labels) {
      ref.watch(backgroundCollectionSyncProvider);
      const sistrum = true;
      final item = ref.watch(currentMediaItemProvider).value;
      final track = item == null
          ? null
          : ref.watch(playerCollectionTrackProvider(item)).value;
      final loved = ref.watch(
        libraryCollectionsProvider.select(
          (state) => track != null && state.isLoved(track),
        ),
      );
      // Publishing playback state inside a provider build would synchronously
      // modify the stream provider this binding is observing.
      var active = true;
      ref.onDispose(() => active = false);
      scheduleMicrotask(() {
        if (!active) return;
        final runtime = ref.read(musicPlayerRuntimeProvider);
        runtime.configureNotification(
          presentation: PlaybackNotification(
            sistrum: sistrum,
            mediaId: item?.id,
            source: item?.extras?['source']?.toString(),
            loved: loved,
            favoriteLabel: labels.favorite,
            unfavoriteLabel: labels.unfavorite,
            shuffleOnLabel: labels.shuffleOn,
            shuffleOffLabel: labels.shuffleOff,
          ),
          toggleFavorite: (selected) async {
            final collections = ref.read(libraryCollectionsProvider.notifier);
            final selectedTrack = await ref.read(
              playerCollectionTrackProvider(selected).future,
            );
            return collections.toggleLoved(selectedTrack);
          },
        );
      });
    });
