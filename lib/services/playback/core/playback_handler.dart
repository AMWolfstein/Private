import 'package:audio_service/audio_service.dart';
import 'package:sistrum/core/models/playable_media.dart';
import 'package:sistrum/core/models/settings.dart';

/// Gain and rate the player applies to the current track.
class PlaybackProcessing {
  const PlaybackProcessing({
    required this.normalizationGain,
    required this.direct,
    required this.autoMixRate,
  });

  /// Linear volume from ReplayGain normalization; 1 when none applies.
  final double normalizationGain;

  /// A direct USB or exclusive path that bypasses the system mixer and DSP.
  final bool direct;

  /// AutoMix tempo matching; 1 outside a transition.
  final double autoMixRate;
}

/// The handler surface that the playback runtime and the UI drive. The concrete handler
/// lives in music_player_service.dart and extends this class, so the runtime
/// depends on this file and never on the service that depends on it.
abstract class PlaybackHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  bool get isDisposed;

  /// Reconcile only the playback fields affected by the new settings snapshot.
  void applySettings(AppSettings previous);

  void refreshNotificationControls();

  Future<void> onSourceDeleted(String source);

  Future<void> refreshNormalizationSource(String source);

  DateTime? get sleepTimerEndsAt;

  PlaybackProcessing get processing;

  void setSleepTimer(Duration duration);

  void cancelSleepTimer();

  Future<void> setQueueAndPlay(
    List<PlayableMedia> items, {
    int initialIndex = 0,
  });

  Future<void> restoreSession({
    required List<PlayableMedia> items,
    required int index,
    required Duration position,
    required bool shuffle,
    List<int>? originalOrder,
    bool queueNeedsRewrite = false,
    AudioServiceRepeatMode repeatMode = AudioServiceRepeatMode.none,
  });

  Future<void> persistCurrentSession();

  Future<void> enqueue(PlayableMedia item, {bool playNext = false});

  Future<void> enqueueAll(List<PlayableMedia> items, {bool playNext = false});

  void moveQueueItem(int oldIndex, int newIndex);

  void removeQueuedItem(MediaItem item);

  Future<void> dispose();
}
