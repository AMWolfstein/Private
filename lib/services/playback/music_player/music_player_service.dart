import 'package:sistrum/services/native/media_file_bridge.dart';
import 'package:sistrum/services/playback/music_player/music_player_helpers.dart';
import 'package:sistrum/services/playback/music_player/music_player_session_restore.dart';
import 'package:sistrum/services/playback/core/music_haptics.dart';
import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:sistrum/services/playback/notification/playback_notification.dart';
import 'package:audio_session/audio_session.dart'
    show AudioSession, AudioSessionConfiguration, AudioInterruptionType;
import 'package:audioplayers/audioplayers.dart';
import 'package:sistrum/services/playback/stats/listening_statistics.dart'
    show ListeningTrack;
import 'package:sistrum/services/playback/audio/playback_normalization.dart';
import 'package:sistrum/services/playback/autoplay/playback_automation.dart';
import 'package:sistrum/services/playback/session/playback_session_writer.dart';
import 'package:sistrum/services/playback/core/content_uri_playback_cache.dart';
import 'package:sistrum/services/playback/music_player/music_player_runtime.dart';
import 'package:sistrum/services/playback/autoplay/music_player_autoplay.dart';
import 'package:sistrum/services/playback/automix/music_player_automix.dart';
import 'package:sistrum/services/playback/core/playback_handler.dart';
import 'package:sistrum/services/playback/notification/player_widget_service.dart';
import 'package:sistrum/services/playback/core/playback_policies.dart';
import 'package:sistrum/services/playback/core/music_playback_deck.dart';
import 'package:sistrum/services/playback/autoplay/autoplay_personalization.dart';
import 'package:sistrum/services/playback/automix/automix_analyzer.dart';
import 'package:sistrum/core/models/playable_media.dart';
import 'package:sistrum/core/models/settings.dart';
import 'package:sistrum/services/playback/automix/automix_effect_renderer.dart';
import 'package:sistrum/services/playback/automix/automix_status.dart';
import 'package:sistrum/utils/cover/playback_artwork.dart';
import 'package:sistrum/services/library/covers/embedded_cover_resolver.dart';
import 'package:sistrum/services/library/database/library_database.dart';
import 'package:sistrum/utils/logging/logger.dart';

export 'package:sistrum/core/models/playable_media.dart';
export '../core/playback_metadata.dart';

part 'music_player_service_dependencies.dart';
part 'music_player_service_normalization.dart';

part 'music_player_events.dart';
part 'music_player_hooks.dart';
part 'music_player_lifecycle.dart';
part 'music_player_media.dart';
part 'music_player_playback.dart';
part 'music_player_queue.dart';
part 'music_player_session.dart';
part 'music_player_source.dart';
part 'music_player_service_session_handlers.dart';
part 'music_player_service_media_handlers.dart';

final _log = AppLogger('MusicPlayer');

/// Refreshes gain tags after a successful file update, including SAF copies.
void refreshPlaybackNormalization(String source) {
  final handler = musicPlayerRuntime.handler;
  if (handler != null) unawaited(handler.refreshNormalizationSource(source));
}

class MusicPlayerHandler extends PlaybackHandler {
  final MusicPlayerRuntime _runtime;
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
  void applySettings(AppSettings previous) => _applySettingsImpl(previous);

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
  void setSleepTimer(Duration duration) => _setSleepTimerImpl(duration);

  @override
  void cancelSleepTimer() => _cancelSleepTimerImpl();

  @override
  void refreshNotificationControls() => _refreshNotificationControlsImpl();

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
  Future<void> refreshNormalizationSource(String source) =>
      _refreshNormalizationSourceImpl(source);

  /// What the active output path applies to the playing track, for the
  /// audio information sheet.
  @override
  PlaybackProcessing get processing => PlaybackProcessing(
    normalizationGain: _normalizationVolume,
    direct: _player.isDirect,
    autoMixRate: _autoMix.rate,
  );

  /// Flushes the live engine position and every older queued session write.
  /// Called when the app leaves the foreground so a normal restart resumes at
  /// the latest audible point rather than the beginning of the track.
  @override
  Future<void> persistCurrentSession() => _persistCurrentSessionImpl();

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
  }) => _restoreSessionImpl(
    items: items,
    index: index,
    position: position,
    shuffle: shuffle,
    originalOrder: originalOrder,
    queueNeedsRewrite: queueNeedsRewrite,
    repeatMode: repeatMode,
  );

  @override
  Future<void> setQueueAndPlay(
    List<PlayableMedia> items, {
    int initialIndex = 0,
  }) => _setQueueAndPlayImpl(items, initialIndex: initialIndex);

  @override
  Future<void> enqueue(PlayableMedia item, {bool playNext = false}) =>
      _enqueueImpl(item, playNext: playNext);

  @override
  Future<void> enqueueAll(List<PlayableMedia> items, {bool playNext = false}) =>
      _enqueueAllImpl(items, playNext: playNext);

  @override
  void moveQueueItem(int oldIndex, int newIndex) =>
      _moveQueueItemImpl(oldIndex, newIndex);

  /// Removes one queued occurrence, including when the same song is queued
  /// twice. The current source is protected if playback advances mid-gesture.
  @override
  void removeQueuedItem(MediaItem item) => _removeQueuedItemImpl(item);

  @override
  Future<void> play() => _playImpl();

  @override
  Future<void> click([MediaButton button = MediaButton.media]) =>
      _clickImpl(button);

  @override
  Future<void> pause() => _pauseImpl();

  @override
  Future<void> seek(Duration position) => _seekImpl(position);

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) =>
      _setShuffleModeImpl(shuffleMode);

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) =>
      _setRepeatModeImpl(repeatMode);

  @override
  Future<void> stop() => _stopImpl();

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
  Future<void> skipToNext() => _skipToNextImpl();

  @override
  Future<void> skipToPrevious() => _skipToPreviousImpl();

  @override
  Future<void> skipToQueueItem(int index) => _skipToQueueItemImpl(index);

  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) => _getChildrenImpl(parentMediaId, options);

  @override
  Future<MediaItem?> getMediaItem(String mediaId) => _getMediaItemImpl(mediaId);

  @override
  Future<void> playFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) => _playFromMediaIdImpl(mediaId, extras);

  @override
  Future<void> playMediaItem(MediaItem mediaItem) =>
      _playMediaItemImpl(mediaItem);

  /// Called when a file is deleted from disk. Removes it from the queue and, if
  /// it is the track currently playing, stops or advances so a deleted song can
  /// no longer be played.
  @override
  Future<void> onSourceDeleted(String source) => _onSourceDeletedImpl(source);

  @override
  Future<void> dispose() => _disposeImpl();
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
  autoMixStatus: autoMixStatus,
  bindPlayerWidget: (handler) => PlayerWidgetService.instance.bind(handler),
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
