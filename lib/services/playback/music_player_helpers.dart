import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:audioplayers/audioplayers.dart';

List<int> buildShuffledQueueOrder({
  required int mediaCount,
  required int currentIndex,
  required Random random,
}) {
  final rest = [
    for (var i = 0; i < mediaCount; i++)
      if (i != currentIndex) i,
  ]..shuffle(random);
  return [
    if (currentIndex >= 0 && currentIndex < mediaCount) currentIndex,
    ...rest,
  ];
}

/// Returns a safe source-start position for restored playback. A completed
/// snapshot starts over instead of immediately completing again on resume.
Duration normalizedPlaybackResumePosition(
  Duration position, {
  Duration? duration,
}) {
  if (position <= Duration.zero) return Duration.zero;
  if (duration != null && duration > Duration.zero && position >= duration) {
    return Duration.zero;
  }
  return position;
}

AudioProcessingState mapProcessingState(PlayerState state) {
  switch (state) {
    case PlayerState.playing:
    case PlayerState.paused:
      return AudioProcessingState.ready;
    case PlayerState.completed:
      return AudioProcessingState.completed;
    case PlayerState.stopped:
    case PlayerState.disposed:
      return AudioProcessingState.idle;
  }
}
