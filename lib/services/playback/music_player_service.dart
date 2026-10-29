import 'package:sistrum/services/native/media_file_bridge.dart';
import 'package:sistrum/services/playback/music_player_helpers.dart';
import 'package:sistrum/services/playback/music_player_session_restore.dart';
import 'package:sistrum/services/playback/music_haptics.dart';
import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:sistrum/services/playback/playback_notification.dart';
import 'package:audio_session/audio_session.dart'
    show AudioSession, AudioSessionConfiguration, AudioInterruptionType;
import 'package:audioplayers/audioplayers.dart';
import 'package:sistrum/services/playback/listening_statistics.dart'
    show ListeningTrack;
import 'package:sistrum/services/playback/playback_normalization.dart';
import 'package:sistrum/services/playback/playback_automation.dart';
import 'package:sistrum/services/playback/playback_session_writer.dart';
import 'package:sistrum/services/playback/content_uri_playback_cache.dart';
import 'package:sistrum/services/playback/music_player_runtime.dart';
import 'package:sistrum/services/playback/music_player_autoplay.dart';
import 'package:sistrum/services/playback/music_player_automix.dart';
import 'package:sistrum/services/playback/playback_handler.dart';
import 'package:sistrum/services/playback/playback_policies.dart';
import 'package:sistrum/services/playback/music_playback_deck.dart';
import 'package:sistrum/services/playback/autoplay_personalization.dart';
import 'package:sistrum/services/playback/automix_analyzer.dart';
import 'package:sistrum/models/playable_media.dart';
import 'package:sistrum/models/settings.dart';
import 'package:sistrum/services/playback/automix_effect_renderer.dart';
import 'package:sistrum/services/playback/automix_status.dart';
import 'package:sistrum/utils/playback_artwork.dart';
import 'package:sistrum/services/library/embedded_cover_resolver.dart';
import 'package:sistrum/services/library/library_database.dart';
import 'package:sistrum/utils/logger.dart';

export 'package:sistrum/models/playable_media.dart';
export 'playback_metadata.dart';

part 'music_player_events.dart';
part 'music_player_hooks.dart';
part 'music_player_lifecycle.dart';
part 'music_player_media.dart';
part 'music_player_playback.dart';
part 'music_player_queue.dart';
part 'music_player_session.dart';
part 'music_player_source.dart';

final _log = AppLogger('MusicPlayer');

/// Refreshes gain tags after a successful file update, including SAF copies.
void refreshPlaybackNormalization(String source) {
  final handler = musicPlayerRuntime.handler;
  if (handler != null) unawaited(handler.refreshNormalizationSource(source));
}

class MusicPlayerHandler extends PlaybackHandler {
  final MusicPlayerRuntime _runtime;
  PlaybackDependencies get _dependencies => _runtime.dependencies;
  AppSettings get _settings => _runtime.settings;
  late MusicPlaybackDeck _player;
  late final MusicAutoMix _autoMix;
  late final MusicAutoplay _autoplay;
  late final MusicHaptics _haptics;
  bool _completing = false;
  double _normalizationVolume = 1;
  final _playerSubscriptions =
      <MusicPlaybackDeck, List<StreamSubscription<dynamic>>>{};
  AudioSession? _audioSession;
  late final PlaybackAutomation _playbackAutomation;
  late final AutomationInputs _automationInputs;
  final List<PlayableMedia> _media = [];
  final List<MediaItem> _queueItems = [];
  late final ContentUriPlaybackCache _sourceCache;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  int _index = -1;
  int _playRequestGeneration = 0;
  String? _activeResolvedPath;
  bool _disposed = false;
  Future<void>? _disposeFuture;
  bool _initialized = false;
  bool _sourceReady = false;
  Object? _playbackError;
  Future<void>? _activePlayOperation;
  int? _activePlayGeneration;
  Future<void> _sourceChangeTail = Future<void>.value();
  final _sleep = SleepTimer();
  Timer? _listeningTimer;

  bool _shuffle = false;
  List<MediaItem>? _originalQueueOrder;
  int _shuffleRequestGeneration = 0;
  AudioServiceRepeatMode _repeatMode = AudioServiceRepeatMode.none;
  final Random _random = Random();
  final _playHistory = PlayHistory();

  // True when playback was paused because another app took audio focus.
  final _focus = AudioInterruptionPolicy();
  bool _userPaused = false;
  // Position saved with the restored session; applied on the first play().
  Duration? _pendingRestorePosition;
  bool _restoringSession = false;
  int _switchingGeneration = 0;
  Duration _lastBroadcastPosition = Duration.zero;
  DateTime? _lastPositionBroadcastAt;
  DateTime? _lastPeriodicPersistAt;
  late final PlaybackSessionWriter _sessionWriter;
  static const Duration _positionBroadcastInterval = Duration(
    milliseconds: 500,
  );
  static const Duration _positionPersistInterval = Duration(seconds: 10);

  @override
  DateTime? get sleepTimerEndsAt => _sleep.endsAt;
  @override
  bool get isDisposed => _disposed;

  /// Reconcile only the playback fields affected by the new settings snapshot.
  @override
  void applySettings(AppSettings previous) {
    final settings = _settings;
    if (previous.autoplayPersonalization != settings.autoplayPersonalization) {
      _configurePersonalization();
    }
    if (previous.playbackNormalization != settings.playbackNormalization ||
        previous.playbackNormalizationPreamp !=
            settings.playbackNormalizationPreamp ||
        previous.playbackNormalizationMode !=
            settings.playbackNormalizationMode) {
      reapplyNormalization();
    }
    if (previous.autoMix != settings.autoMix ||
        previous.autoMixOptions != settings.autoMixOptions ||
        previous.usbBitPerfect != settings.usbBitPerfect) {
      unawaited(_autoMix.cancel());
    }
    // USB changes apply at the next source boundary, without raising volume.
    if (previous.pauseOnMute != settings.pauseOnMute ||
        previous.playOnHeadphonesConnected !=
            settings.playOnHeadphonesConnected ||
        previous.usbBitPerfect != settings.usbBitPerfect) {
      _refreshPlaybackAutomation();
    }
    if (previous.musicHaptics != settings.musicHaptics ||
        previous.musicHapticsSensitivity != settings.musicHapticsSensitivity ||
        previous.musicHapticsStrength != settings.musicHapticsStrength) {
      _updateHaptics();
    }
    if (previous.autoplay != settings.autoplay ||
        previous.autoplayPersonalization != settings.autoplayPersonalization) {
      _autoplay.updateMode();
    }
  }

  MusicPlayerHandler({
    MusicPlayerRuntime? runtime,
    AutoMixAnalyzer? autoMixAnalyzer,
    AutoMixEffectRenderer? autoMixEffectRenderer,
    AutoplayLibraryLoader? autoplayLibraryLoader,
    MusicHapticsAnalyzer? hapticsAnalyzer,
    HapticPulse? hapticPulse,
  }) : _runtime = runtime ?? musicPlayerRuntime {
    _haptics = MusicHaptics(
      state: () => playbackState.value,
      analyzer: hapticsAnalyzer,
      pulse: hapticPulse,
    );
    _sourceCache = ContentUriPlaybackCache(
      copy: MediaFileBridge.copyContentUriToTemp,
      isDisposed: () => _disposed,
      isPinned: (path) =>
          path == _activeResolvedPath || _autoMix.pinnedPaths.contains(path),
      onResolveError: (error) =>
          _log.e('Failed to resolve content URI for playback: $error'),
      onDeleteError: (error) =>
          _log.w('Failed to delete SAF playback temp file: $error'),
    );
    _sessionWriter = PlaybackSessionWriter(
      database: _dependencies.sessionDatabase,
      onError: (error) =>
          _log.w('Failed to update persisted playback session: $error'),
    );
    _player = _dependencies.createDeck('music-player');
    _normalizationCache = PlaybackNormalizationCache(
      readMetadata: _dependencies.readMetadata,
      onReadError: (error) =>
          _log.w('Failed to read gain tags for normalization: $error'),
    );
    _playbackAutomation = PlaybackAutomation(
      isPlaying: () =>
          _player.state == PlayerState.playing || playbackState.value.playing,
      canResume: () =>
          !_disposed && !_focus.active && _index >= 0 && _index < _media.length,
      pause: _pausePlayback,
      play: play,
      onError: (error) => _log.w('Automatic playback failed: $error'),
      onMutedPause: _runtime.notifyMutedPlayback,
    );
    _automationInputs = AutomationInputs(
      automation: _playbackAutomation,
      volumeChanges: () => _dependencies.volumeChanges,
      isDisposed: () => _disposed,
      log: _log,
    );
    _autoMix = MusicAutoMix(
      _HandlerAutoMixHost(this),
      autoMixAnalyzer ?? AutoMixAnalyzer(),
      autoMixEffectRenderer ?? AutoMixEffectRenderer(),
    );
    _autoplay = MusicAutoplay(
      _HandlerAutoplayQueue(this),
      autoplayLibraryLoader ?? (seed) => loadAutoplayLibrary(seed, _runtime),
    );
    try {
      _init();
      _runtime.attach(this);
    } catch (_) {
      unawaited(dispose());
      rethrow;
    }
  }

  @override
  void setSleepTimer(Duration duration) => _sleep.start(duration, () {
    if (_disposed) return;
    _log.i('Sleep timer elapsed; pausing playback');
    _runPlaybackCallback(pause);
  });

  @override
  void cancelSleepTimer() => _sleep.cancel();

  @override
  void refreshNotificationControls() {
    if (_disposed) return;
    final state = playbackState.value;
    playbackState.add(
      state.copyWith(
        // copyWith creates a fresh updateTime; keep the extrapolated position
        // so changing a star or theme cannot pull the scrubber backwards.
        updatePosition: state.position,
        controls: _runtime.notification.controls(
          playing: state.playing,
          item: mediaItem.value,
          shuffle: _shuffle,
        ),
        androidCompactActionIndices: _runtime.notification.sistrum
            ? const [1, 2, 3]
            : const [0, 1, 2],
      ),
    );
  }

  bool _savingNotificationFavorite = false;
  bool _changingNotificationShuffle = false;

  @override
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    if (name == PlaybackNotification.favoriteAction) {
      final item = mediaItem.value;
      if (item == null || _savingNotificationFavorite) return;
      _savingNotificationFavorite = true;
      try {
        final loved = await _runtime.toggleFavorite(item);
        final current = mediaItem.value;
        if (!_disposed &&
            loved != null &&
            current?.id == item.id &&
            current?.extras?['source'] == item.extras?['source']) {
          // Widget/provider rebuilds may wait for a frame while the app is
          // backgrounded. Publish the persisted result directly to the OS.
          _runtime.updateFavorite(item, loved);
        }
      } catch (error) {
        _log.w('Notification favorite failed: $error');
      } finally {
        _savingNotificationFavorite = false;
      }
    } else if (name == PlaybackNotification.shuffleAction) {
      if (mediaItem.value == null || _changingNotificationShuffle) return;
      _changingNotificationShuffle = true;
      try {
        await setShuffleMode(
          _shuffle ? AudioServiceShuffleMode.none : AudioServiceShuffleMode.all,
        );
      } catch (error) {
        _log.w('Notification shuffle failed: $error');
      } finally {
        _changingNotificationShuffle = false;
      }
    } else {
      return super.customAction(name, extras);
    }
  }

  late final PlaybackNormalizationCache _normalizationCache;
  int _normalizationGeneration = 0;

  @override
  Future<void> refreshNormalizationSource(String source) async {
    _normalizationGeneration++;
    _normalizationCache.invalidate(source);
    await _sourceCache.invalidate(source, waitForPending: true);
    if (_disposed) return;
    if (_index >= 0 &&
        _index < _media.length &&
        _media[_index].source == source) {
      reapplyNormalization();
    }
  }

  /// What the active output path applies to the playing track, for the
  /// audio information sheet.
  @override
  PlaybackProcessing get processing => PlaybackProcessing(
    normalizationGain: _normalizationVolume,
    direct: _player.isDirect,
    autoMixRate: _autoMix.rate,
  );

  /// Re-applies normalization to the playing track when the setting flips.
  void reapplyNormalization() {
    final index = _index;
    final generation = _playRequestGeneration;
    final normalizationGeneration = ++_normalizationGeneration;
    if (index < 0 || index >= _media.length) return;
    unawaited(() async {
      await _autoMix.cancel();
      if (generation != _playRequestGeneration ||
          index != _index ||
          index >= _media.length ||
          _disposed) {
        return;
      }
      final media = _media[index];
      var resolved = media.isContentUri
          ? _sourceCache.cachedPath(media.source)
          : media.source;
      ContentUriPlaybackLease? playbackLease;
      if (resolved == null && media.isContentUri) {
        try {
          playbackLease = await MediaFileBridge.openContentUriPlaybackLease(
            media.source,
          );
          resolved = playbackLease?.path;
        } catch (_) {}
        resolved ??= await _resolveSource(media);
      }
      if (resolved == null) return;
      final volume = await _normalizationVolumeFor(
        resolved,
        cacheKey: media.isContentUri ? media.source : null,
        displayName: playbackLease?.displayName,
      );
      if (playbackLease != null) {
        await MediaFileBridge.closeContentUriPlaybackLease(playbackLease.token);
      }
      if (_index != index ||
          generation != _playRequestGeneration ||
          normalizationGeneration != _normalizationGeneration) {
        return;
      }
      try {
        await _player.setVolume(volume);
        _normalizationVolume = volume;
      } catch (e) {
        _log.w('Failed to apply normalization volume: $e');
      }
    }());
  }

  /// Flushes the live engine position and every older queued session write.
  /// Called when the app leaves the foreground so a normal restart resumes at
  /// the latest audible point rather than the beginning of the track.
  @override
  Future<void> persistCurrentSession() async {
    if (_media.isEmpty || _index < 0 || _index >= _media.length) return;
    final position = await _currentPositionForPersist();
    _lastPeriodicPersistAt = DateTime.now();
    await _persistSession(position: position);
  }

  /// Restores a persisted session paused: queue and current track become
  /// visible (mini player included) without loading any source; the first
  /// play() prepares the source directly at the saved position.
  @override
  Future<void> restoreSession({
    required List<PlayableMedia> items,
    required int index,
    required Duration position,
    required bool shuffle,
    List<int>? originalOrder,
    bool queueNeedsRewrite = false,
    AudioServiceRepeatMode repeatMode = AudioServiceRepeatMode.none,
  }) async {
    if (items.isEmpty) return;
    // Never clobber a session the user already started this launch.
    if (_media.isNotEmpty || _index >= 0) return;
    _restoringSession = true;
    try {
      _media
        ..clear()
        ..addAll(items);
      _queueItems
        ..clear()
        ..addAll(items.map(_toMediaItem));
      _index = index.clamp(0, items.length - 1);
      _shuffle = shuffle;
      if (shuffle) {
        final order = [for (var i = 0; i < items.length; i++) i];
        if (originalOrder?.length == items.length) {
          order.sort((a, b) => originalOrder![a].compareTo(originalOrder[b]));
        }
        _originalQueueOrder = order.map((i) => _queueItems[i]).toList();
      }
      _repeatMode = repeatMode;
      _pendingRestorePosition = position > Duration.zero ? position : null;
      _sourceReady = false;
      _lastPeriodicPersistAt = null;
      _sessionWriter.queueRestored(needsRewrite: queueNeedsRewrite);
      queue.add(List<MediaItem>.unmodifiable(_queueItems));
      mediaItem.add(_toMediaItem(_media[_index]));
      if (position > Duration.zero) {
        playbackState.add(
          playbackState.value.copyWith(updatePosition: position),
        );
      }
      _broadcastState(playerState: PlayerState.paused);
    } finally {
      _restoringSession = false;
    }
    if (queueNeedsRewrite) {
      await _persistSession(position: position);
    }
    _autoplay.updateMode();
  }

  @override
  Future<void> setQueueAndPlay(
    List<PlayableMedia> items, {
    int initialIndex = 0,
  }) async {
    if (items.isEmpty) return;
    _autoplay.reset();
    _playRequestGeneration++;
    _media
      ..clear()
      ..addAll(items);
    _queueItems
      ..clear()
      ..addAll(items.map(_toMediaItem));
    _originalQueueOrder = null;
    _index = initialIndex.clamp(0, items.length - 1);
    if (_shuffle) _shuffleQueue();
    _markSessionQueueChanged();
    _playHistory.clear();
    queue.add(List<MediaItem>.unmodifiable(_queueItems));
    await _playIndex(_index);
  }

  @override
  Future<void> enqueue(PlayableMedia item, {bool playNext = false}) async {
    if (_media.isEmpty || _index < 0) {
      await setQueueAndPlay([item]);
      return;
    }
    final insertAt = playNext
        ? (_index + 1).clamp(0, _media.length)
        : _autoplay.manualInsertIndex;
    _media.insert(insertAt, item);
    final queueItem = _toMediaItem(item);
    _queueItems.insert(insertAt, queueItem);
    _rememberEnqueued([queueItem], playNext: playNext);
    _markSessionQueueChanged();

    _playHistory.makeRoomAt(insertAt);

    queue.add(List<MediaItem>.unmodifiable(_queueItems));
    _broadcastState();
    unawaited(_persistSession(position: playbackState.value.position));
  }

  @override
  Future<void> enqueueAll(
    List<PlayableMedia> items, {
    bool playNext = false,
  }) async {
    if (items.isEmpty) return;
    if (_media.isEmpty || _index < 0) {
      await setQueueAndPlay(items);
      return;
    }
    var at = playNext
        ? (_index + 1).clamp(0, _media.length)
        : _autoplay.manualInsertIndex;
    final queued = <MediaItem>[];
    for (final item in items) {
      _media.insert(at, item);
      final queueItem = _toMediaItem(item);
      _queueItems.insert(at, queueItem);
      queued.add(queueItem);
      _playHistory.makeRoomAt(at);
      at++;
    }
    _rememberEnqueued(queued, playNext: playNext);
    _markSessionQueueChanged();
    queue.add(List<MediaItem>.unmodifiable(_queueItems));
    _broadcastState();
    unawaited(_persistSession(position: playbackState.value.position));
  }

  @override
  void moveQueueItem(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= _media.length ||
        newIndex < 0 ||
        newIndex >= _media.length ||
        oldIndex == newIndex) {
      return;
    }
    final media = _media.removeAt(oldIndex);
    final qi = _queueItems.removeAt(oldIndex);
    _media.insert(newIndex, media);
    _queueItems.insert(newIndex, qi);
    _markSessionQueueChanged();

    if (_index == oldIndex) {
      _index = newIndex;
    } else {
      if (oldIndex < _index && newIndex >= _index) {
        _index--;
      } else if (oldIndex > _index && newIndex <= _index) {
        _index++;
      }
    }

    _playHistory.clear();

    queue.add(List<MediaItem>.unmodifiable(_queueItems));
    _broadcastState();
    unawaited(_persistSession(position: playbackState.value.position));
  }

  /// Removes one queued occurrence, including when the same song is queued
  /// twice. The current source is protected if playback advances mid-gesture.
  @override
  void removeQueuedItem(MediaItem item) {
    final at = _queueItems.indexWhere((entry) => identical(entry, item));
    if (_disposed || at < 0 || at == _index) return;
    _autoplay.dismiss(_media[at]);
    _queueItems.removeAt(at);
    _media.removeAt(at);
    _originalQueueOrder?.removeWhere((entry) => identical(entry, item));
    if (at < _index) _index--;
    _playHistory.dropQueueEntry(at);
    _markSessionQueueChanged();
    unawaited(_autoMix.cancel());
    queue.add(List<MediaItem>.unmodifiable(_queueItems));
    _broadcastState();
    unawaited(_persistSession(position: playbackState.value.position));
  }

  @override
  Future<void> play() async {
    _playbackAutomation.manualPlaybackRequested();
    final activeOperation = _activePlayOperation;
    if (activeOperation != null &&
        _activePlayGeneration == _playRequestGeneration) {
      await activeOperation;
      return;
    }

    ++_playRequestGeneration;
    final operation = _playInternal();
    _activePlayOperation = operation;
    _activePlayGeneration = _playRequestGeneration;
    try {
      await operation;
    } finally {
      if (identical(_activePlayOperation, operation)) {
        _activePlayOperation = null;
      }
    }
  }

  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    switch (button) {
      case MediaButton.media:
        if (playbackState.value.playing) {
          await pause();
        } else {
          await play();
        }
        break;
      case MediaButton.next:
        await skipToNext();
        break;
      case MediaButton.previous:
        await skipToPrevious();
        break;
    }
  }

  @override
  Future<void> pause() async {
    _playbackAutomation.cancelPendingActions();
    _focus.clearPending();
    await _pausePlayback();
  }

  @override
  Future<void> seek(Duration position) async {
    final generation = _playRequestGeneration;
    if (_disposed || _index < 0 || _index >= _media.length) return;
    if (!_sourceReady) {
      _pendingRestorePosition = position;
      _broadcastPosition(position, force: true);
    }
    await _autoMix.cancel();
    await _serializeSourceChange(() async {
      if (_disposed || generation != _playRequestGeneration) return;
      if (_sourceReady) {
        await _player.seek(position);
        if (_disposed || generation != _playRequestGeneration) return;
      } else {
        _pendingRestorePosition = position;
      }
      _broadcastPosition(position, force: true);
      unawaited(_persistSession(position: position));
    });
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final generation = ++_shuffleRequestGeneration;
    final enabled = shuffleMode == AudioServiceShuffleMode.all;
    await _autoMix.cancel();
    if (generation != _shuffleRequestGeneration ||
        _disposed ||
        enabled == _shuffle) {
      return;
    }
    _shuffle = enabled;
    if (enabled) {
      _shuffleQueue();
    } else {
      final original = _originalQueueOrder;
      if (original != null) _applyQueueOrder(List.of(original));
      _originalQueueOrder = null;
    }
    _markSessionQueueChanged();
    queue.add(List<MediaItem>.unmodifiable(_queueItems));
    _broadcastState();
    if (_media.isNotEmpty && _index >= 0) {
      unawaited(_persistSession(position: playbackState.value.position));
    }
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    await _autoMix.cancel();
    // Group repeat has no meaning for a flat queue; treat it as all.
    _repeatMode = repeatMode == AudioServiceRepeatMode.group
        ? AudioServiceRepeatMode.all
        : repeatMode;
    _autoplay.updateMode();
    _broadcastState();
    if (_media.isNotEmpty && _index >= 0) {
      unawaited(_persistSession(position: playbackState.value.position));
    }
  }

  @override
  Future<void> stop() async {
    _runtime.personalization.finish();
    unawaited(_runtime.personalization.flush());
    _playbackAutomation.cancelPendingActions();
    _autoplay.reset();
    cancelSleepTimer();
    final generation = ++_playRequestGeneration;
    _switchingGeneration = 0;
    _userPaused = true;
    await _autoMix.cancel();
    await _serializeSourceChange(() => _stopSession(generation));
  }

  Future<void> _stopSession(int generation) async {
    if (generation != _playRequestGeneration || _disposed) return;
    await _player.stop();
    if (generation != _playRequestGeneration || _disposed) return;
    _sourceReady = false;
    _playbackError = null;
    _activeResolvedPath = null;
    await _cleanupPendingResolvedPaths();
    if (generation != _playRequestGeneration || _disposed) return;
    _index = -1;
    _focus.reset();
    _userPaused = false;
    _playHistory.clear();
    _pendingRestorePosition = null;
    // An explicit stop ends the session for good; nothing to restore later.
    await _sessionWriter.clear();
    if (generation != _playRequestGeneration || _disposed) return;
    // A stopped session has no current item; this also hides the mini player.
    mediaItem.add(null);
    _broadcastState(playerState: PlayerState.stopped);
    await super.stop();
  }

  @override
  Future<void> skipToNext() async {
    if (_index >= 0 && _index == _media.length - 1) {
      final generation = _playRequestGeneration;
      await _autoplay.fill();
      if (_disposed || generation != _playRequestGeneration) return;
    }
    if (_index < _media.length - 1) {
      await _playIndex(_index + 1, userSkip: true);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    await _autoMix.cancel();
    if (playbackState.value.position > const Duration(seconds: 3)) {
      await seek(Duration.zero);
      return;
    }
    if (_shuffle) {
      if (_playHistory.length >= 2) {
        _playHistory.removeLast();
        final prev = _playHistory.last;
        await _playIndex(prev, recordHistory: false, userSkip: true);
      } else {
        await seek(Duration.zero);
      }
      return;
    }
    if (_index > 0) await _playIndex(_index - 1, userSkip: true);
  }

  @override
  Future<void> skipToQueueItem(int index) => _playIndex(index, userSkip: true);

  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) async {
    if (parentMediaId == AudioService.browsableRootId ||
        parentMediaId == AudioService.recentRootId) {
      return List<MediaItem>.unmodifiable(_queueItems);
    }
    return const [];
  }

  @override
  Future<MediaItem?> getMediaItem(String mediaId) async {
    final index = _media.indexWhere((m) => m.id == mediaId);
    if (index < 0) return null;
    return _queueItems[index];
  }

  @override
  Future<void> playFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) async {
    final index = _media.indexWhere((m) => m.id == mediaId);
    if (index >= 0) await _playIndex(index);
  }

  @override
  Future<void> playMediaItem(MediaItem mediaItem) =>
      playFromMediaId(mediaItem.id);

  /// Called when a file is deleted from disk. Removes it from the queue and, if
  /// it is the track currently playing, stops or advances so a deleted song can
  /// no longer be played.
  @override
  Future<void> onSourceDeleted(String source) async {
    final target = source.trim();
    if (_disposed || target.isEmpty) return;

    final hadPendingResolution = await _sourceCache.invalidate(target);

    final wasCurrent =
        _index >= 0 &&
        _index < _media.length &&
        _media[_index].source == target;

    var removedBeforeCurrent = 0;
    final kept = <PlayableMedia>[];
    final keptQueue = <MediaItem>[];
    for (var i = 0; i < _media.length; i++) {
      if (_media[i].source == target) {
        if (i < _index) removedBeforeCurrent++;
        continue;
      }
      kept.add(_media[i]);
      keptQueue.add(_queueItems[i]);
    }

    if (kept.length == _media.length) return;

    _media
      ..clear()
      ..addAll(kept);
    _queueItems
      ..clear()
      ..addAll(keptQueue);
    final keptSet = Set<MediaItem>.identity()..addAll(keptQueue);
    _originalQueueOrder?.removeWhere((item) => !keptSet.contains(item));
    _markSessionQueueChanged();
    _playHistory.clear();
    queue.add(List<MediaItem>.unmodifiable(_queueItems));

    Future<void>? reaction;
    if (_media.isEmpty) {
      reaction = stop();
    } else if (wasCurrent) {
      final nextIndex = _index.clamp(0, _media.length - 1);
      reaction = _playIndex(nextIndex);
    } else if (_index >= 0) {
      _index = (_index - removedBeforeCurrent).clamp(0, _media.length - 1);
      _broadcastState();
      unawaited(_persistSession(position: playbackState.value.position));
    }
    if (!hadPendingResolution) {
      await reaction;
    } else {
      // Queue invalidation must not wait behind an unavailable SAF provider.
      unawaited(
        reaction?.catchError((Object error) {
          _log.w('Could not update playback after source deletion: $error');
        }),
      );
    }
  }

  @override
  Future<void> dispose() => _disposeFuture ??= _dispose();
}

Future<PlaybackHandler> initMusicPlayer() => musicPlayerRuntime.initialize();

/// Restores the last persisted playback session (if any) into a freshly
/// initialized handler, paused. Entries whose plain file paths no longer
/// exist are dropped; content URIs are kept and fail gracefully at play time.
Future<void> restorePersistedPlaybackSession() =>
    musicPlayerRuntime.restoreSession();

/// The concrete handler behind [runtime], for library code that reaches its
/// private state. Only [createMusicPlayerHandler] builds handlers for it.
MusicPlayerHandler? _concreteHandler(MusicPlayerRuntime runtime) =>
    runtime.handler as MusicPlayerHandler?;

/// The handler the process runtime builds.
PlaybackHandler createMusicPlayerHandler(MusicPlayerRuntime runtime) =>
    MusicPlayerHandler(runtime: runtime);

/// Process wiring for [MusicPlayerRuntime]. The background audio service runs
/// outside the widget tree, so it takes the library database here, once.
/// Tests build their own dependencies.
final defaultPlaybackDependencies = PlaybackDependencies(
  createHandler: createMusicPlayerHandler,
  restoreSession: restorePlaybackSession,
  libraryDatabase: LibraryDatabase.instance,
);

final musicPlayerRuntime = MusicPlayerRuntime(
  dependencies: defaultPlaybackDependencies,
);

Future<void> resetAutoplayLearning({MusicPlayerRuntime? runtime}) async {
  final target = runtime ?? musicPlayerRuntime;
  await target.personalization.reset();
  final handler = _concreteHandler(target);
  if (handler == null || handler.isDisposed) return;
  handler._configurePersonalization();
  handler._autoplay.updateMode();
}
