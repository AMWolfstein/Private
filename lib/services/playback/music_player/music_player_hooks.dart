part of 'music_player_service.dart';

/// AutoMix and Autoplay hooks for [MusicPlayerHandler], plus their host adapters.
extension _MusicPlayerHandlerHooks on MusicPlayerHandler {
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
