import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/providers/library/library_preference_events_provider.dart';
import 'package:sistrum/providers/playback/music_player_provider.dart';
import 'package:sistrum/providers/settings/settings_provider.dart';
import 'package:sistrum/services/library/collections/library_preference_events.dart';
import 'package:sistrum/services/playback/autoplay/autoplay_personalization.dart';

/// App-shell binding. Library never depends on playback, and this observer
/// neither creates a handler nor owns the runtime's learning model.
final autoplayLearningProvider = Provider.autoDispose<void>((ref) {
  final learning = ref.watch(musicPlayerRuntimeProvider).personalization;
  final enabled = ref.watch(
    settingsProvider.select((s) => s.autoplayPersonalization),
  );
  learning.setEnabled(enabled);
  final unsubscribe = ref.watch(libraryPreferenceEventsProvider).subscribe((
    track,
    kind,
  ) {
    learning.endorse(
      AutoplayLearningTrack(
        source: track.id,
        title: track.name,
        artist: track.artistName,
        album: track.albumName,
        genre: track.genre ?? '',
        duration: Duration(seconds: track.duration),
      ),
      kind == LibraryPreferenceKind.loved
          ? AutoplayFeedbackKind.loved
          : AutoplayFeedbackKind.playlisted,
    );
  });
  ref.onDispose(unsubscribe);
});
