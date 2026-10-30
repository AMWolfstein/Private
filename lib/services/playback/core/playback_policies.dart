import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:sistrum/services/playback/autoplay/playback_automation.dart';
import 'package:sistrum/utils/logging/logger.dart';

/// Pauses playback after a chosen duration. The owner decides what happens
/// when it elapses; this class owns only the timer and its end time.
class SleepTimer {
  Timer? _timer;
  DateTime? _endsAt;

  DateTime? get endsAt => _endsAt;

  /// Starts the timer, replacing any running one. Non-positive durations are
  /// ignored and leave the running timer untouched.
  void start(Duration duration, void Function() onElapsed) {
    if (duration <= Duration.zero) return;
    _timer?.cancel();
    _endsAt = DateTime.now().add(duration);
    _timer = Timer(duration, () {
      _timer = null;
      _endsAt = null;
      onElapsed();
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _endsAt = null;
  }
}

/// Queue indexes of recently played entries, oldest first and bounded to
/// [capacity]. Queue edits remap the entries so they keep naming the same
/// tracks.
class PlayHistory {
  PlayHistory({this.capacity = 200});

  final int capacity;
  final List<int> _entries = [];

  int get length => _entries.length;

  int get last => _entries.last;

  Iterable<int> get entries => _entries;

  void clear() => _entries.clear();

  void record(int index) {
    _entries.add(index);
    if (_entries.length > capacity) _entries.removeAt(0);
  }

  void removeLast() => _entries.removeLast();

  /// Shifts entries at or after [at] up by one, for an insertion at [at].
  void makeRoomAt(int at) {
    for (var i = 0; i < _entries.length; i++) {
      if (_entries[i] >= at) _entries[i]++;
    }
  }

  /// Forgets the removed queue position [at] and shifts later entries down.
  void dropQueueEntry(int at) {
    final remapped = [
      for (final index in _entries)
        if (index != at) index > at ? index - 1 : index,
    ];
    _entries
      ..clear()
      ..addAll(remapped);
  }
}

/// Audio focus state: pause when another app takes focus, and resume only
/// after a transient pause. The owner performs the pause and resume, so this
/// class is testable without a player.
class AudioInterruptionPolicy {
  bool _active = false;
  bool _pausedByInterruption = false;

  /// True while another app holds audio focus.
  bool get active => _active;

  /// True when the current pause came from an interruption, so regaining focus
  /// may resume playback.
  bool get pausedByInterruption => _pausedByInterruption;

  /// Another app took focus. Returns whether the owner should pause now. A duck
  /// keeps playing and changes nothing.
  bool begin({required bool isDuck, required bool wasPlaying}) {
    if (isDuck) return false;
    _active = true;
    _pausedByInterruption = wasPlaying;
    return true;
  }

  /// Focus returned. Returns whether the owner should resume now.
  bool end({
    required bool isDuck,
    required bool isPause,
    required bool blocksPlayback,
  }) {
    if (isDuck) return false;
    _active = false;
    final resume = _pausedByInterruption && isPause && !blocksPlayback;
    _pausedByInterruption = false;
    return resume;
  }

  /// Forgets a pending resume, for a pause the user asked for or a lost route.
  void clearPending() => _pausedByInterruption = false;

  /// Playback is starting or stopping, so no interruption is in effect.
  void reset() {
    _active = false;
    _pausedByInterruption = false;
  }
}

/// Feeds the playback automation from the media volume and the audio route.
/// Owns those subscriptions; a revision cancels device checks that a newer
/// request has superseded.
class AutomationInputs {
  AutomationInputs({
    required this.automation,
    required this.volumeChanges,
    required this.isDisposed,
    required this.log,
  });

  final PlaybackAutomation automation;
  final Stream<double> Function() volumeChanges;
  final bool Function() isDisposed;
  final AppLogger log;
  StreamSubscription<double>? _volume;
  StreamSubscription<Set<AudioDevice>>? _devices;
  bool _headphoneMonitoringRequested = false;
  int _headphoneRevision = 0;

  /// Applies the current pause-on-mute and headphone settings. [session] is
  /// null until the audio session exists.
  void refresh({
    required bool pauseOnMute,
    required bool playOnHeadphones,
    required AudioSession? session,
  }) {
    unawaited(
      automation.configure(
        pauseOnMute: pauseOnMute,
        playOnHeadphonesConnected: playOnHeadphones,
      ),
    );
    if (pauseOnMute && _volume == null) {
      _volume = volumeChanges().listen(
        (volume) => unawaited(automation.volumeChanged(volume)),
        onError: (Object error) =>
            log.w('Could not monitor media volume: $error'),
      );
    } else if (!pauseOnMute) {
      final subscription = _volume;
      _volume = null;
      if (subscription != null) unawaited(subscription.cancel());
    }
    if (playOnHeadphones && session != null && !_headphoneMonitoringRequested) {
      _headphoneMonitoringRequested = true;
      unawaited(_startDevices(session, ++_headphoneRevision));
    } else if (!playOnHeadphones) {
      _headphoneMonitoringRequested = false;
      _headphoneRevision++;
      final subscription = _devices;
      _devices = null;
      if (subscription != null) unawaited(subscription.cancel());
    }
  }

  Future<void> _startDevices(AudioSession session, int revision) async {
    try {
      // Query a fresh baseline. devicesStream can replay an old inventory
      // after monitoring was disabled, which would look like a new connection.
      final devices = await session.getDevices();
      if (isDisposed() || revision != _headphoneRevision) return;
      unawaited(automation.devicesChanged(devices));
      _devices = session.devicesChangedEventStream
          .asyncMap((_) => session.getDevices())
          .listen(
            (devices) => unawaited(automation.devicesChanged(devices)),
            onError: (Object error) =>
                log.w('Could not monitor headphone connections: $error'),
          );
    } catch (error) {
      log.w('Could not monitor headphone connections: $error');
    }
  }

  Future<void> dispose() async {
    _headphoneRevision++;
    await _volume?.cancel();
    await _devices?.cancel();
  }
}
