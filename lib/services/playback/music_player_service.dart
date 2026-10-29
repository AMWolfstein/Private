import 'package:sistrum/services/playback/playback_session_prepare.dart';
import 'package:sistrum/services/playback/music_haptics.dart';
import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:sistrum/services/playback/playback_notification.dart';
import 'package:audio_session/audio_session.dart'
    show AudioSession, AudioSessionConfiguration, AudioInterruptionType;
import 'package:audioplayers/audioplayers.dart';
import 'package:sistrum/services/listening_statistics.dart' show ListeningTrack;
import 'package:sistrum/services/platform_bridge.dart';
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
import 'package:sistrum/utils/logger.dart';

export 'package:sistrum/models/playable_media.dart';
export 'playback_metadata.dart';

final _log = AppLogger('MusicPlayer');

/// Refreshes gain tags after a successful file update, including SAF copies.
void refreshPlaybackNormalization(String source) {
  final handler = musicPlayerRuntime.handler;
  if (handler != null) unawaited(handler.refreshNormalizationSource(source));
}

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
  int get _sessionQueueRevision => _sessionWriter.queueRevision;
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
      copy: PlatformBridge.copyContentUriToTemp,
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

  MediaItem _toMediaItem(
    PlayableMedia media, {
    String? resolvedSource,
    String? resolvedArtwork,
  }) => media.toMediaItem(
    resolvedSource: resolvedSource,
    resolvedArtwork: resolvedArtwork,
    unknownTitle: _runtime.unknownTitle,
    unknownArtist: _runtime.unknownArtist,
  );

  void _init() {
    if (_initialized) return;
    _initialized = true;
    _configurePersonalization();
    void recordListening() {
      final item = mediaItem.value;
      final state = playbackState.value;
      _runtime.personalization.updatePlayback(
        source: item?.extras?['source'] as String?,
        duration: item?.duration,
        playing:
            state.playing &&
            state.processingState == AudioProcessingState.ready,
      );
      _dependencies.recorder.update(
        item == null
            ? null
            : ListeningTrack(
                key: item.extras?['source']?.toString() ?? item.id,
                title: item.title,
                artist: item.artist ?? '',
                album: item.album ?? '',
                artwork: item.artUri?.toString(),
              ),
        playing:
            state.playing &&
            state.processingState == AudioProcessingState.ready,
        ended:
            state.processingState == AudioProcessingState.completed ||
            state.processingState == AudioProcessingState.idle,
      );
    }

    _subscriptions.add(mediaItem.listen((_) => recordListening()));
    _subscriptions.add(
      playbackState
          .map(
            (state) => (
              state.playing &&
                  state.processingState == AudioProcessingState.ready,
              state.processingState == AudioProcessingState.completed ||
                  state.processingState == AudioProcessingState.idle,
            ),
          )
          .distinct()
          .listen((_) => recordListening()),
    );
    _subscriptions.add(
      playbackState.map((state) => state.playing).distinct().listen((playing) {
        if (playing) unawaited(_playbackAutomation.playbackStarted());
      }),
    );
    _subscriptions.add(mediaItem.listen((_) => _updateHaptics()));
    _subscriptions.add(playbackState.listen((_) => _updateHaptics()));
    _listeningTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(_dependencies.recorder.flush());
    });
    _player.setReleaseMode(ReleaseMode.stop);
    unawaited(_player.setAudioContext(musicAudioContext));
    unawaited(_configureAudioSession());
    _refreshPlaybackAutomation();

    _listenToPlayer(_player);
  }

  /// Haptics follow only decodable local files; streams have no full copy.
  void _updateHaptics() {
    if (_disposed) return;
    final extras = mediaItem.value?.extras;
    final source = extras?['source']?.toString() ?? '';
    final resolved = extras?['resolvedSource']?.toString().trim() ?? '';
    final document = source.startsWith('content://');
    // Use a stable document identity for both direct playback and AutoMix.
    // Haptics opens its own SAF input; the player's descriptor is short-lived.
    final path = document ? source : (resolved.isNotEmpty ? resolved : source);
    final local =
        path.isNotEmpty &&
        (document || !path.contains('://')) &&
        _settings.musicHaptics;
    _haptics.configure(
      sensitivity: _settings.musicHapticsSensitivity,
      strength: _settings.musicHapticsStrength,
    );
    _haptics.update(local ? path : null);
  }

  void _configurePersonalization() {
    final enabled = _settings.autoplayPersonalization;
    _runtime.personalization.setEnabled(enabled);
    if (enabled && _index >= 0 && _index < _media.length) {
      _runtime.personalization.begin(autoplayLearningTrack(_media[_index]));
      final state = playbackState.value;
      _runtime.personalization.updatePlayback(
        source: mediaItem.value?.extras?['source'] as String?,
        duration: mediaItem.value?.duration,
        playing:
            state.playing &&
            state.processingState == AudioProcessingState.ready,
      );
    }
  }

  void _listenToPlayer(MusicPlaybackDeck player) {
    // Position updates must continue with the display asleep. UI progress is
    // interpolated between updates; querying native playback every frame is
    // unnecessary and would stop preparing AutoMix when there are no frames.
    player.positionUpdater = TimerPositionUpdater(
      interval: const Duration(milliseconds: 200),
      getPosition: player.getCurrentPosition,
    );
    _playerSubscriptions[player] = [
      player.onPlayerStateChanged.listen(
        (state) {
          if (!identical(player, _player)) return;
          if (state == PlayerState.paused && player.needsSourceReload) {
            _userPaused = true;
            _focus.clearPending();
            _playbackAutomation.cancelPendingActions();
          }
          if (_switchingGeneration != 0 &&
              (state == PlayerState.stopped ||
                  state == PlayerState.completed ||
                  state == PlayerState.disposed)) {
            return;
          }
          if (state == PlayerState.completed && _shouldIgnoreComplete) {
            if (_userPaused || _focus.active) {
              _broadcastState(playerState: PlayerState.paused);
            }
            return;
          }
          _broadcastState(playerState: state);
        },
        onError: (Object error, StackTrace stackTrace) {
          // Preparation errors are handled by _loadIndex, including the SAF
          // fallback. Runtime failures must not look like successful completion.
          if (_sourceReady || _switchingGeneration == 0) {
            _reportPlaybackError(player, error, stackTrace);
          }
        },
      ),
      player.onPositionChanged.listen((position) {
        if (identical(player, _player)) _handlePositionChanged(position);
      }),
      player.onDurationChanged.listen((duration) {
        if (!identical(player, _player) || !_sourceReady) return;
        final current = mediaItem.value;
        if (current != null && duration > Duration.zero) {
          mediaItem.add(current.copyWith(duration: duration));
        }
      }),
      player.onPlayerComplete.listen((_) {
        if (identical(player, _player)) {
          _runPlaybackCallback(_handlePlayerComplete);
        }
      }),
    ];
  }

  void _runPlaybackCallback(Future<void> Function() action) {
    final player = _player;
    final operation = Future<void>.sync(action);
    final generation = _playRequestGeneration;
    unawaited(
      operation.catchError((Object error, StackTrace stack) {
        if (_disposed || generation != _playRequestGeneration) return;
        _reportPlaybackError(player, error, stack);
      }),
    );
  }

  void _reportPlaybackError(
    MusicPlaybackDeck player,
    Object error,
    StackTrace stackTrace,
  ) {
    if (_disposed || !identical(player, _player) || _playbackError != null) {
      return;
    }
    _sourceReady = false;
    _playbackError = error;
    _userPaused = true;
    _focus.clearPending();
    _playbackAutomation.cancelPendingActions();
    _log.e('Playback failed for ${mediaItem.value?.title}', error, stackTrace);
    _broadcastState(playerState: PlayerState.stopped);
    final generation = _playRequestGeneration;
    unawaited(
      _serializeSourceChange(() async {
        if (_disposed || generation != _playRequestGeneration) return;
        await _autoMix.cancel();
        if (_disposed || generation != _playRequestGeneration) return;
        await player.stop();
      }).catchError((Object error) {
        _log.w('Could not stop failed playback: $error');
      }),
    );
  }

  Future<void> _disposeDeck(MusicPlaybackDeck player) async {
    final subscriptions = _playerSubscriptions.remove(player);
    if (subscriptions == null) return;
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    await player.dispose();
  }

  /// Configures the OS audio session and reacts to interruptions (e.g. another
  /// app like PowerAmp taking audio focus, or headphones unplugged) so playback
  /// pauses and the UI/notification reflect the real state instead of staying
  /// stuck on "playing".
  Future<void> _configureAudioSession() async {
    try {
      final session = await _dependencies.audioSession();
      _audioSession = session;
      await session.configure(const AudioSessionConfiguration.music());
      if (_disposed) return;
      _refreshPlaybackAutomation();

      _subscriptions.add(
        session.interruptionEventStream.listen((event) {
          _log.d(
            'Audio interruption ${event.begin ? 'began' : 'ended'} '
            'type=${event.type} player=${_player.state} '
            'playing=${playbackState.value.playing}',
          );
          final isDuck = event.type == AudioInterruptionType.duck;
          if (event.begin) {
            // Another app took focus or a transient interruption began.
            final shouldPause = _focus.begin(
              isDuck: isDuck,
              wasPlaying:
                  _player.state == PlayerState.playing ||
                  playbackState.value.playing,
            );
            if (shouldPause) {
              unawaited(_pauseForFocusLoss(reason: 'audio interruption'));
            }
          } else {
            // Focus returned; resume only after a transient pause.
            final shouldResume = _focus.end(
              isDuck: isDuck,
              isPause: event.type == AudioInterruptionType.pause,
              blocksPlayback: _playbackAutomation.blocksPlayback,
            );
            if (shouldResume) _runPlaybackCallback(play);
          }
        }),
      );

      _subscriptions.add(
        session.becomingNoisyEventStream.listen((_) {
          // Headphones unplugged / output route lost.
          _focus.clearPending();
          unawaited(_pauseForFocusLoss(reason: 'becoming noisy'));
        }),
      );
    } catch (e) {
      _log.w('Failed to configure audio session: $e');
    }
  }

  void _refreshPlaybackAutomation() {
    if (_disposed) return;
    _automationInputs.refresh(
      pauseOnMute: _settings.pauseOnMute && !_settings.usbBitPerfect,
      playOnHeadphones: _settings.playOnHeadphonesConnected,
      session: _audioSession,
    );
  }

  bool get _shouldIgnoreComplete =>
      _switchingGeneration != 0 ||
      _focus.active ||
      _userPaused ||
      _playbackError != null;

  Future<void> _pauseForFocusLoss({required String reason}) async {
    _log.i('Pausing internal player because of $reason');
    _playbackAutomation.cancelPendingActions();
    try {
      await _pausePlayback();
    } catch (e) {
      _log.w('Failed to pause after audio focus loss: $e');
      if (!_disposed) _broadcastState(playerState: PlayerState.paused);
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

  Future<void> _activateAudioSession() async {
    try {
      final session = _audioSession ?? await _dependencies.audioSession();
      _audioSession = session;
      final granted = await session.setActive(true);
      if (!granted) {
        _log.w('Audio focus request was not granted');
      }
    } catch (e) {
      _log.w('Failed to activate audio session: $e');
    }
  }

  // Required on some Android builds because audio_session manages focus.
  Future<void> _claimHardwareMediaButtons() async {
    if (!_dependencies.isAndroid) return;
    try {
      await AudioService.androidForceEnableMediaButtons();
    } catch (e) {
      _log.w('Failed to claim Android media-button routing: $e');
    }
  }

  AudioProcessingState _mapProcessingState(PlayerState state) {
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

  void _broadcastState({PlayerState? playerState, bool? loading}) {
    final state = playerState ?? _player.state;
    final failed = _playbackError != null;
    final playing = !failed && state == PlayerState.playing;

    playbackState.add(
      playbackState.value.copyWith(
        controls: _runtime.notification.controls(
          playing: playing,
          item: mediaItem.value,
          shuffle: _shuffle,
        ),
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.skipToPrevious,
          MediaAction.skipToNext,
        },
        androidCompactActionIndices: _runtime.notification.sistrum
            ? const [1, 2, 3]
            : const [0, 1, 2],
        processingState: failed
            ? AudioProcessingState.error
            : (loading == true)
            ? AudioProcessingState.loading
            : _mapProcessingState(state),
        errorCode: failed ? 1 : null,
        errorMessage: _playbackError?.toString(),
        playing: playing,
        queueIndex: _index >= 0 ? _index : null,
        speed: _autoMix.rate,
        shuffleMode: _shuffle
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
        repeatMode: _repeatMode,
      ),
    );
  }

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

  void _broadcastPosition(Duration position, {bool force = false}) {
    final now = DateTime.now();
    final lastAt = _lastPositionBroadcastAt;
    final elapsed = lastAt == null ? null : now.difference(lastAt);
    final moved = (position - _lastBroadcastPosition).abs();
    if (!force &&
        elapsed != null &&
        elapsed < _positionBroadcastInterval &&
        moved < _positionBroadcastInterval) {
      return;
    }
    _lastPositionBroadcastAt = now;
    _lastBroadcastPosition = position;
    playbackState.add(
      playbackState.value.copyWith(
        updatePosition: position,
        speed: _autoMix.rate,
      ),
    );
  }

  void _handlePositionChanged(Duration position) {
    if (!_sourceReady || _switchingGeneration != 0) return;
    _broadcastPosition(position);
    _autoMix.onPosition(position);
    unawaited(_autoplay.fill());
    if (_restoringSession ||
        _player.state != PlayerState.playing ||
        _media.isEmpty ||
        _index < 0 ||
        _index >= _media.length) {
      return;
    }

    final now = DateTime.now();
    final lastPersistAt = _lastPeriodicPersistAt;
    if (lastPersistAt != null &&
        now.difference(lastPersistAt) < _positionPersistInterval) {
      return;
    }
    _lastPeriodicPersistAt = now;
    unawaited(_persistSession(position: position));
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

  Future<double> _normalizationVolumeFor(
    String path, {
    String? cacheKey,
    String? displayName,
  }) async {
    if (!_settings.playbackNormalization ||
        _settings.usbBitPerfect ||
        _player.isDirect) {
      return 1.0;
    }
    return _normalizationCache.volumeFor(
      path,
      cacheKey: cacheKey,
      displayName: displayName,
      preampDb: _settings.playbackNormalizationPreamp,
      preferAlbumGain: _settings.playbackNormalizationMode == 'album',
    );
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
          playbackLease = await PlatformBridge.openContentUriPlaybackLease(
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
        await PlatformBridge.closeContentUriPlaybackLease(playbackLease.token);
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

  Future<String?> _resolveSource(PlayableMedia media) async {
    if (!media.isContentUri) return media.source;
    return _sourceCache.resolve(media.source);
  }

  Future<void> _cleanupPendingResolvedPaths() => _sourceCache.releaseUnpinned();

  void _markSessionQueueChanged() => _sessionWriter.queueChanged();

  /// Makes an AutoMix incoming deck the playing one. The old deck is handled by
  /// AutoMix, so only the handler's own state changes here.
  void _commitAutoMixTransition({
    required MusicPlaybackDeck incoming,
    required int index,
    required PlayableMedia next,
    required String? nextPath,
    required Duration? nextDuration,
    required double normalizationVolume,
    required Duration audiblePosition,
  }) {
    final resolvedSource = next.isContentUri ? nextPath : null;
    _player = incoming;
    _index = index;
    _playRequestGeneration++;
    _playHistory.record(index);
    _normalizationVolume = normalizationVolume;
    _activeResolvedPath = resolvedSource;
    _pendingRestorePosition = null;
    _runtime.personalization.begin(autoplayLearningTrack(next));
    mediaItem.add(
      _toMediaItem(
        next,
        resolvedSource: resolvedSource,
      ).copyWith(duration: nextDuration),
    );
    _broadcastPosition(audiblePosition, force: true);
    _broadcastState(playerState: PlayerState.playing);
    unawaited(_persistSession(position: audiblePosition));
  }

  /// Appends Autoplay suggestions and publishes the new queue in one step.
  void _appendAutoplayTracks(List<PlayableMedia> additions) {
    final queueItems = additions.map(_toMediaItem).toList();
    _media.addAll(additions);
    _queueItems.addAll(queueItems);
    _originalQueueOrder?.addAll(queueItems);
    _markSessionQueueChanged();
    queue.add(List.unmodifiable(_queueItems));
    unawaited(_persistSession(position: playbackState.value.position));
  }

  List<Map<String, dynamic>> _sessionMedia() {
    final original = _originalQueueOrder;
    final ranks = Map<MediaItem, int>.identity();
    if (original != null) {
      for (var i = 0; i < original.length; i++) {
        ranks[original[i]] = i;
      }
    }
    return [
      for (var i = 0; i < _media.length; i++)
        {
          ..._media[i].toJson(),
          'queueOriginalIndex': ranks[_queueItems[i]] ?? i,
        },
    ];
  }

  void _applyQueueOrder(List<MediaItem> order) {
    final current = _index >= 0 && _index < _queueItems.length
        ? _queueItems[_index]
        : null;
    final media = Map<MediaItem, PlayableMedia>.identity();
    for (var i = 0; i < _media.length; i++) {
      media[_queueItems[i]] = _media[i];
    }
    _queueItems
      ..clear()
      ..addAll(order);
    _media
      ..clear()
      ..addAll(order.map((item) => media[item]!));
    _index = current == null
        ? -1
        : order.indexWhere((item) => identical(item, current));
    _playHistory.clear();
    if (_index >= 0) _playHistory.record(_index);
  }

  void _shuffleQueue() {
    _originalQueueOrder ??= List.of(_queueItems);
    final manual = [
      for (var i = 0; i < _media.length; i++)
        if (i == _index || !_media[i].autoplay) i,
    ];
    final order = buildShuffledQueueOrder(
      mediaCount: manual.length,
      currentIndex: manual.indexOf(_index),
      random: _random,
    );
    _applyQueueOrder([
      ...order.map((index) => _queueItems[manual[index]]),
      for (var i = 0; i < _media.length; i++)
        if (i != _index && _media[i].autoplay) _queueItems[i],
    ]);
  }

  void _rememberEnqueued(List<MediaItem> items, {required bool playNext}) {
    final original = _originalQueueOrder;
    if (original == null) return;
    final current = _queueItems[_index];
    final at = original.indexWhere((item) => identical(item, current));
    final firstAutoplay = original.indexWhere(
      (item) => item.extras?['autoplay'] == true && !identical(item, current),
      max(0, at + 1),
    );
    original.insertAll(
      playNext && at >= 0
          ? at + 1
          : firstAutoplay >= 0
          ? firstAutoplay
          : original.length,
      items,
    );
  }

  /// Persists the queue only when it changed. Periodic position updates write
  /// fixed-size scalar columns, avoiding full queue JSON serialization every
  /// ten seconds for large playback sessions.
  Future<void> _persistSession({Duration? position}) {
    if (_restoringSession) return Future<void>.value();
    if (_media.isEmpty || _index < 0 || _index >= _media.length) {
      return _sessionWriter.clear();
    }
    return _sessionWriter.persist(
      serializeQueue: _sessionMedia,
      index: _index,
      position: position ?? Duration.zero,
      shuffle: _shuffle,
      repeatMode: _repeatMode.name,
    );
  }

  Future<Duration> _currentPositionForPersist() async {
    // During restore/source preparation the engine may report a stale zero (or
    // the previous source). The broadcast position already represents the
    // intended start point for the current queue item.
    if (!_sourceReady) return playbackState.value.position;
    try {
      final position = await _player.getCurrentPosition();
      if (position != null) return position;
    } catch (_) {}
    return playbackState.value.position;
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

  bool _isCurrentPlayRequest(int generation, PlayableMedia media) {
    return !_disposed &&
        generation == _playRequestGeneration &&
        _index >= 0 &&
        _index < _media.length &&
        _media[_index].id == media.id &&
        _media[_index].source == media.source;
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

  Future<void> _playIndex(
    int index, {
    bool recordHistory = true,
    bool userSkip = false,
    Duration startPosition = Duration.zero,
  }) async {
    if (_disposed || index < 0 || index >= _media.length) return;
    _runtime.personalization.finish(
      skipped:
          userSkip &&
          mediaItem.value?.extras?['source'] != _media[index].source,
    );
    _playbackAutomation.cancelPendingActions();
    // A normal track change supersedes a pending restore. A restored start
    // keeps it until the source is actually ready so a transient failure can
    // be retried from the same position.
    if (startPosition <= Duration.zero) {
      _pendingRestorePosition = null;
    }
    final generation = ++_playRequestGeneration;
    _sourceReady = false;
    _playbackError = null;
    // Advance the requested index synchronously so consecutive Next taps do
    // not all target the same song while AutoMix/source preparation awaits.
    _index = index;
    unawaited(_autoplay.fill());
    final media = _media[index];
    _switchingGeneration = generation;
    try {
      await _player.cancelPreparation();
      await _serializeSourceChange(() async {
        if (!_isCurrentPlayRequest(generation, media)) return;
        await _autoMix.cancel();
        if (!_isCurrentPlayRequest(generation, media)) return;
        // Retire the audible source before publishing another song's title.
        await _player.stop();
        if (!_isCurrentPlayRequest(generation, media)) return;
        await _loadIndex(
          generation,
          media,
          recordHistory: recordHistory,
          startPosition: startPosition,
        );
      });
    } catch (error, stackTrace) {
      if (_isCurrentPlayRequest(generation, media)) {
        _reportPlaybackError(_player, error, stackTrace);
      }
    } finally {
      if (_switchingGeneration == generation) _switchingGeneration = 0;
    }
  }

  Future<void> _serializeSourceChange(Future<void> Function() action) {
    final operation = _sourceChangeTail.then((_) => action());
    // A failed operation must not poison later transport requests.
    _sourceChangeTail = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _startResolvedSource(
    String path,
    int generation,
    PlayableMedia media,
    Duration? position,
  ) async {
    // AudioPlayer.play combines prepare/seek/resume without a cancellation
    // boundary. A late prepare from an old request could resume the wrong
    // source. Serialize preparation and recheck before making it audible.
    await _player.setSource(
      DeviceFileSource(path),
      preferBitPerfect: _settings.usbBitPerfect,
      directUsb: _settings.usbDirect,
      allowFixedVolume: _settings.usbAllowFixedVolume,
      dapExclusive: _settings.dapExclusive,
      allowDop: _settings.usbDsdOverPcm,
      requiresDsd:
          media.bitDepth == 1 ||
          const ['dsf', 'dff'].contains(media.format?.toLowerCase()) ||
          media.source.toLowerCase().endsWith('.dsf') ||
          media.source.toLowerCase().endsWith('.dff'),
    );
    if (!_isCurrentPlayRequest(generation, media)) return;
    if (position != null) {
      await _player.seek(position);
      if (!_isCurrentPlayRequest(generation, media)) return;
    }
    await _player.resume();
    if (!_isCurrentPlayRequest(generation, media)) await _player.pause();
  }

  Future<void> _loadIndex(
    int generation,
    PlayableMedia media, {
    required bool recordHistory,
    required Duration startPosition,
  }) async {
    _focus.reset();
    _userPaused = false;

    if (recordHistory) _playHistory.record(_index);

    final effectiveStartPosition = normalizedPlaybackResumePosition(
      _pendingRestorePosition ?? startPosition,
      duration: media.duration,
    );
    _announceTrack(media, effectiveStartPosition);
    // Claim the playing state up front (while the app is still in the
    // foreground window) so audio_service can start its foreground service
    // before the async source resolve below.
    await _claimHardwareMediaButtons();
    bool isCurrent() => _isCurrentPlayRequest(generation, media);
    if (!isCurrent()) return;
    unawaited(_recoverEmbeddedArtwork(media, generation));

    // Android opens SAF files through a short-lived file-descriptor lease.
    // MediaPlayer duplicates that descriptor, so the original can be closed
    // immediately after play() without retaining a full-file cache copy.
    var playbackLease = await _openPlaybackLease(media);
    try {
      var resolved = playbackLease?.path ?? await _resolveSource(media);
      var usingLocalSafCopy = media.isContentUri && playbackLease == null;
      if (!isCurrent()) return;
      if (resolved == null) {
        _reportPlaybackError(
          _player,
          StateError('Audio file is unavailable'),
          StackTrace.current,
        );
        return;
      }

      try {
        await _runtime.exclusiveAudioHook?.call();
      } catch (_) {}
      if (!isCurrent()) return;

      _switchingGeneration = generation;
      try {
        // Set before play() so the track never starts at the wrong loudness;
        // always set (1.0 when disabled/untagged) so a previous track's
        // attenuation can't leak into the next one.
        var normalizationVolume = await _normalizationVolumeFor(
          resolved,
          cacheKey: media.isContentUri ? media.source : null,
          displayName: playbackLease?.displayName,
        );
        if (!isCurrent()) return;
        if (!await _prepareOutput(normalizationVolume, isCurrent)) return;

        final startAt = effectiveStartPosition > Duration.zero
            ? effectiveStartPosition
            : null;
        try {
          await _startResolvedSource(resolved, generation, media, startAt);
          await _releaseLease(playbackLease);
          playbackLease = null;
        } catch (directError) {
          if (directError is UsbOutputUnavailable ||
              playbackLease == null ||
              !isCurrent()) {
            rethrow;
          }
          await _releaseLease(playbackLease);
          playbackLease = null;
          _log.w(
            'Direct SAF playback unavailable; using bounded local fallback: '
            '$directError',
          );
          final fallback = await _resolveSource(media);
          if (fallback == null || !isCurrent()) rethrow;
          resolved = fallback;
          usingLocalSafCopy = true;
          normalizationVolume = await _normalizationVolumeFor(
            fallback,
            cacheKey: media.source,
          );
          if (!isCurrent()) return;
          await _player.setVolume(normalizationVolume);
          if (!isCurrent()) return;
          _normalizationVolume = normalizationVolume;
          await _startResolvedSource(fallback, generation, media, startAt);
        }
        if (!isCurrent()) return;
        await _publishLoaded(
          media,
          generation,
          resolved,
          usingLocalSafCopy,
          effectiveStartPosition,
        );
      } catch (e, stackTrace) {
        if (!isCurrent()) return;
        _reportPlaybackError(_player, e, stackTrace);
      } finally {
        await _releaseLease(playbackLease);
        playbackLease = null;
        if (_switchingGeneration == generation) {
          _switchingGeneration = 0;
        }
      }
    } finally {
      // Covers the early returns that happen before the inner try.
      await _releaseLease(playbackLease);
    }
  }

  /// Shows the track to listeners before its source resolves.
  void _announceTrack(PlayableMedia media, Duration effectiveStartPosition) {
    _runtime.personalization.begin(autoplayLearningTrack(media));
    mediaItem.add(_toMediaItem(media));
    _lastBroadcastPosition = Duration.zero;
    _lastPositionBroadcastAt = null;
    _broadcastPosition(effectiveStartPosition, force: true);
    _broadcastState(playerState: PlayerState.playing, loading: true);
  }

  Future<ContentUriPlaybackLease?> _openPlaybackLease(
    PlayableMedia media,
  ) async {
    if (!_dependencies.isAndroid || !media.isContentUri) return null;
    try {
      return await PlatformBridge.openContentUriPlaybackLease(media.source);
    } catch (e) {
      _log.w('Failed to open direct SAF playback lease: $e');
      return null;
    }
  }

  Future<void> _releaseLease(ContentUriPlaybackLease? lease) async {
    if (lease != null) {
      await PlatformBridge.closeContentUriPlaybackLease(lease.token);
    }
  }

  /// Applies gain, audio focus and the audio context before the source starts.
  /// Returns false when a newer request has taken over.
  Future<bool> _prepareOutput(
    double normalizationVolume,
    bool Function() isCurrent,
  ) async {
    await _player.setAudioContext(musicAudioContext);
    if (!isCurrent()) return false;
    await _activateAudioSession();
    if (!isCurrent()) return false;
    await _player.stop();
    _sourceReady = false;
    if (!isCurrent()) return false;
    await _player.setVolume(normalizationVolume);
    _normalizationVolume = normalizationVolume;
    return isCurrent();
  }

  /// Marks the source ready and publishes what the listeners need after a load.
  Future<void> _publishLoaded(
    PlayableMedia media,
    int generation,
    String resolved,
    bool usingLocalSafCopy,
    Duration effectiveStartPosition,
  ) async {
    _sourceReady = true;
    _pendingRestorePosition = null;
    _activeResolvedPath = usingLocalSafCopy ? resolved : null;
    await _cleanupPendingResolvedPaths();
    if (!_isCurrentPlayRequest(generation, media)) return;
    // Plain file paths were already published before loading. Re-publishing
    // them with an identical resolved path made Now Playing clear and probe
    // the same metadata twice on every Next. SAF needs this second event so
    // the UI can inspect its temporary local copy.
    if (usingLocalSafCopy) {
      mediaItem.add(_toMediaItem(_media[_index], resolvedSource: resolved));
    }
    _broadcastPosition(effectiveStartPosition, force: true);
    _broadcastState();
    _lastPeriodicPersistAt = DateTime.now();
    unawaited(_persistSession(position: effectiveStartPosition));
    // Some files do not emit onDurationChanged reliably (stuck at 0:00);
    // poll the engine for the real duration as a fallback.
    unawaited(_ensureDurationKnown(media, generation));
  }

  Future<void> _recoverEmbeddedArtwork(
    PlayableMedia media,
    int generation,
  ) async {
    final artwork = await resolveEmbeddedArtworkUri(
      media.source,
      media.artUri,
      extract: (source) => EmbeddedCoverResolver.resolveOrExtract(source),
    );
    if (artwork == null || !_isCurrentPlayRequest(generation, media)) return;
    final current = mediaItem.value;
    if (current == null) return;
    final updated = current.copyWith(artUri: Uri.parse(artwork));
    mediaItem.add(updated);
    _media[_index] = PlayableMedia.fromJson({
      ..._media[_index].toJson(),
      'artUri': artwork,
    })!;
    final old = _queueItems[_index];
    _queueItems[_index] = updated;
    final original = _originalQueueOrder;
    if (original != null) {
      final i = original.indexWhere((item) => identical(item, old));
      if (i >= 0) original[i] = updated;
    }
    queue.add(List<MediaItem>.unmodifiable(_queueItems));
    unawaited(_persistSession(position: playbackState.value.position));
  }

  /// Resolves the real track duration when the initial metadata had none and
  /// the duration-changed event did not fire, so the seek bar and total time
  /// do not get stuck at 0:00.
  Future<void> _ensureDurationKnown(PlayableMedia media, int generation) async {
    for (var attempt = 0; attempt < 15; attempt++) {
      if (!_isCurrentPlayRequest(generation, media)) return;
      final current = mediaItem.value;
      final existing = current?.duration;
      if (existing != null && existing > Duration.zero) return;

      try {
        final d = await _player.getDuration();
        if (!_isCurrentPlayRequest(generation, media)) return;
        if (d != null && d > Duration.zero) {
          final item = mediaItem.value;
          if (item != null) {
            mediaItem.add(item.copyWith(duration: d));
          }
          return;
        }
      } catch (_) {
        // Duration probing is best-effort; retry until the bounded loop ends.
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }

  Future<void> _onComplete() async {
    if (_repeatMode == AudioServiceRepeatMode.one &&
        _index >= 0 &&
        _index < _media.length) {
      await _playIndex(_index, recordHistory: false);
      return;
    }
    if (_index == _media.length - 1 &&
        _repeatMode == AudioServiceRepeatMode.none) {
      final generation = _playRequestGeneration;
      await _autoplay.fill();
      if (_disposed ||
          generation != _playRequestGeneration ||
          _shouldIgnoreComplete) {
        return;
      }
    }
    if (_index >= 0 && _index < _media.length - 1) {
      await _playIndex(_index + 1);
    } else if (_repeatMode == AudioServiceRepeatMode.all && _media.isNotEmpty) {
      await _playIndex(0);
    } else {
      _broadcastState(playerState: PlayerState.completed);
    }
  }

  Future<void> _handlePlayerComplete() async {
    if (_completing) return;
    if (_shouldIgnoreComplete) {
      if (_userPaused || _focus.active) {
        _broadcastState(playerState: PlayerState.paused);
      }
      return;
    }

    _completing = true;
    try {
      _runtime.personalization.finish();
      await _onComplete();
    } finally {
      _completing = false;
    }
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

  Future<void> _playInternal() async {
    _focus.reset();
    _userPaused = false;
    if (_player.needsSourceReload) {
      final generation = _playRequestGeneration;
      final index = _index;
      final position =
          await _player.getCurrentPosition() ?? playbackState.value.position;
      if (generation != _playRequestGeneration || _disposed) return;
      await _playIndex(index, recordHistory: false, startPosition: position);
      return;
    }
    if ((!_sourceReady ||
            _player.state == PlayerState.stopped ||
            _player.state == PlayerState.completed) &&
        _index >= 0 &&
        _index < _media.length) {
      await _playIndex(
        _index,
        recordHistory: false,
        startPosition: _pendingRestorePosition ?? Duration.zero,
      );
      return;
    }
    final generation = _playRequestGeneration;
    await _serializeSourceChange(() async {
      if (generation != _playRequestGeneration || _disposed) return;
      await _activateAudioSession();
      if (generation != _playRequestGeneration || _disposed) return;
      await _claimHardwareMediaButtons();
      if (generation != _playRequestGeneration || _disposed) return;
      try {
        await _player.resume();
      } catch (error, stackTrace) {
        if (generation != _playRequestGeneration || _disposed) return;
        if (_player.needsSourceReload) {
          _broadcastState(playerState: PlayerState.paused);
        } else {
          _reportPlaybackError(_player, error, stackTrace);
        }
        return;
      }
      if (generation != _playRequestGeneration || _disposed) {
        await _player.pause();
        return;
      }
      _broadcastState(playerState: PlayerState.playing);
    });
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

  Future<void> _pausePlayback() async {
    _runtime.personalization.updatePlayback(
      source: mediaItem.value?.extras?['source'] as String?,
      playing: false,
    );
    unawaited(_runtime.personalization.flush());
    final generation = ++_playRequestGeneration;
    _switchingGeneration = 0;
    _userPaused = true;
    await _autoMix.cancel();
    await _serializeSourceChange(() async {
      if (generation != _playRequestGeneration || _disposed) return;
      await _player.pause();
      if (generation != _playRequestGeneration || _disposed) return;
      _broadcastState(playerState: PlayerState.paused);
      await _persistSession(position: await _currentPositionForPersist());
    });
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

  Future<void> _dispose() async {
    _autoplay.reset();
    _disposed = true;
    _runtime.personalization.finish();
    await _runtime.personalization.flush();
    if (identical(musicPlayerRuntime.handler, this)) {
      autoMixStatus.value = AutoMixStatus.idle;
    }
    _runtime.detach(this);
    cancelSleepTimer();
    _listeningTimer?.cancel();
    _dependencies.recorder.update(null, playing: false, ended: true);
    await _dependencies.recorder.flush();
    _playRequestGeneration++;
    await _automationInputs.dispose();
    await _playbackAutomation.dispose();
    await _sourceChangeTail;
    await _autoMix.dispose();
    _haptics.dispose();
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    _sourceReady = false;
    for (final player in _playerSubscriptions.keys.toList()) {
      await _disposeDeck(player);
    }
    _activeResolvedPath = null;
    await _sourceCache.dispose();
  }
}

Future<PlaybackHandler> initMusicPlayer() => musicPlayerRuntime.initialize();

/// Restores the last persisted playback session (if any) into a freshly
/// initialized handler, paused. Entries whose plain file paths no longer
/// exist are dropped; content URIs are kept and fail gracefully at play time.
Future<void> restorePersistedPlaybackSession() =>
    musicPlayerRuntime.restoreSession();

Future<void> restorePlaybackSession(MusicPlayerRuntime runtime) async {
  try {
    final database = runtime.dependencies.sessionDatabase;
    final session = await database.getPlaybackSession();
    if (session == null) return;

    final rawMedia = session['media'];
    if (rawMedia is! List) {
      await database.clearPlaybackSession();
      return;
    }

    final prepared = await prepareRestoredPlaybackMedia(
      rawMedia,
      loadLibraryCoverPath: (media) async {
        final database = runtime.dependencies.libraryDatabase;
        final row = await database.getById(media.id);
        if (row != null) return row['coverPath'] as String?;
        final matches = await database.findByTrackAndArtist(
          media.title,
          media.artist,
        );
        for (final row in matches) {
          if (row['filePath'] == media.source) {
            return row['coverPath'] as String?;
          }
        }
        return null;
      },
    );
    final (:items, :keptOriginalIndices, :artworkRelocated) = prepared;
    if (items.isEmpty) {
      await database.clearPlaybackSession();
      return;
    }

    // Remap the saved index onto the surviving list; if the current track
    // itself was dropped, land on the nearest earlier survivor at 0:00.
    final savedIndex = (session['index'] as num?)?.toInt() ?? 0;
    var index = 0;
    for (var i = 0; i < keptOriginalIndices.length; i++) {
      if (keptOriginalIndices[i] <= savedIndex) index = i;
    }
    var position = Duration(
      milliseconds: (session['positionMs'] as num?)?.toInt() ?? 0,
    );
    if (keptOriginalIndices[index] != savedIndex) {
      position = Duration.zero;
    }

    final handler = await runtime.initialize();
    await handler.restoreSession(
      items: items,
      index: index,
      position: position,
      shuffle: session['shuffle'] == true,
      originalOrder: [
        for (final i in keptOriginalIndices)
          ((rawMedia[i] as Map)['queueOriginalIndex'] as num?)?.toInt() ?? i,
      ],
      queueNeedsRewrite: items.length != rawMedia.length || artworkRelocated,
      repeatMode: AudioServiceRepeatMode.values.firstWhere(
        (mode) => mode.name == session['repeat'],
        orElse: () => AudioServiceRepeatMode.none,
      ),
    );
    _log.i(
      'Restored playback session: ${items.length} track(s), paused at '
      '${position.inSeconds}s',
    );
  } catch (e) {
    _log.w('Failed to restore playback session: $e');
  }
}

/// The concrete handler behind [runtime], for library code that reaches its
/// private state. Only [createMusicPlayerHandler] builds handlers for it.
MusicPlayerHandler? _concreteHandler(MusicPlayerRuntime runtime) =>
    runtime.handler as MusicPlayerHandler?;

/// The handler the process runtime builds.
PlaybackHandler createMusicPlayerHandler(MusicPlayerRuntime runtime) =>
    MusicPlayerHandler(runtime: runtime);

/// Process wiring for [MusicPlayerRuntime]. Tests build their own dependencies.
const defaultPlaybackDependencies = PlaybackDependencies(
  createHandler: createMusicPlayerHandler,
  restoreSession: restorePlaybackSession,
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

/// The only place AutoMix's reads and writes meet the handler's private state.
class _HandlerAutoMixHost implements AutoMixHost {
  _HandlerAutoMixHost(this._handler);

  final MusicPlayerHandler _handler;

  @override
  AppSettings get settings => _handler._settings;
  @override
  bool get isDisposed => _handler._disposed;
  @override
  bool get sourceReady => _handler._sourceReady;
  @override
  bool get userPaused => _handler._userPaused;
  @override
  bool get interruptionActive => _handler._focus.active;
  @override
  bool get isLiveHandler => identical(musicPlayerRuntime.handler, _handler);
  @override
  AudioServiceRepeatMode get repeatMode => _handler._repeatMode;
  @override
  int get mediaCount => _handler._media.length;
  @override
  PlayableMedia mediaAt(int index) => _handler._media[index];
  @override
  int get index => _handler._index;
  @override
  int get playRequestGeneration => _handler._playRequestGeneration;
  @override
  int get sessionQueueRevision => _handler._sessionQueueRevision;
  @override
  double get normalizationVolume => _handler._normalizationVolume;
  @override
  MusicPlaybackDeck get player => _handler._player;
  @override
  Duration? get currentDuration => _handler.mediaItem.value?.duration;
  @override
  Future<String?> resolveSource(PlayableMedia media) =>
      _handler._resolveSource(media);
  @override
  Future<double> normalizationVolumeFor(String path, {String? cacheKey}) =>
      _handler._normalizationVolumeFor(path, cacheKey: cacheKey);
  @override
  MusicPlaybackDeck createDeck(String playerId) =>
      _handler._dependencies.createDeck(playerId);
  @override
  void listenToPlayer(MusicPlaybackDeck deck) => _handler._listenToPlayer(deck);
  @override
  Future<void> disposeDeck(MusicPlaybackDeck deck) =>
      _handler._disposeDeck(deck);
  @override
  Future<void> cleanupPendingResolvedPaths() =>
      _handler._cleanupPendingResolvedPaths();
  @override
  void broadcastState({PlayerState? playerState}) =>
      _handler._broadcastState(playerState: playerState);
  @override
  void broadcastPosition(Duration position, {bool force = false}) =>
      _handler._broadcastPosition(position, force: force);
  @override
  void commitTransition({
    required MusicPlaybackDeck incoming,
    required int index,
    required PlayableMedia next,
    required String? nextPath,
    required Duration? nextDuration,
    required double normalizationVolume,
    required Duration audiblePosition,
  }) => _handler._commitAutoMixTransition(
    incoming: incoming,
    index: index,
    next: next,
    nextPath: nextPath,
    nextDuration: nextDuration,
    normalizationVolume: normalizationVolume,
    audiblePosition: audiblePosition,
  );
}

/// The only place Autoplay's reads and writes meet the handler's private state.
class _HandlerAutoplayQueue implements AutoplayQueueView {
  _HandlerAutoplayQueue(this._handler);

  final MusicPlayerHandler _handler;

  @override
  bool get autoplaySetting => _handler._settings.autoplay;
  @override
  bool get isDisposed => _handler._disposed;
  @override
  AudioServiceRepeatMode get repeatMode => _handler._repeatMode;
  @override
  int get index => _handler._index;
  @override
  int get mediaCount => _handler._media.length;
  @override
  PlayableMedia mediaAt(int i) => _handler._media[i];
  @override
  MediaItem queueItemAt(int i) => _handler._queueItems[i];
  @override
  List<PlayableMedia> upcoming() =>
      _handler._media.skip(_handler._index + 1).toList();
  @override
  List<PlayableMedia> recentlyPlayed() => _handler._playHistory.entries
      .where((i) => i >= 0 && i < _handler._media.length)
      .map((i) => _handler._media[i])
      .toList();
  @override
  AutoplayPreferenceModel? get preferenceModel =>
      _handler._runtime.personalization.rankingSnapshot;
  @override
  Random get random => _handler._random;
  @override
  int get sessionQueueRevision => _handler._sessionQueueRevision;
  @override
  void appendAutoplayTracks(List<PlayableMedia> additions) =>
      _handler._appendAutoplayTracks(additions);
  @override
  void removeQueuedItem(MediaItem item) => _handler.removeQueuedItem(item);
}
