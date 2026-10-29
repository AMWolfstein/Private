part of 'music_player_service.dart';

/// Broadcast state, position, metadata and artwork updates for [MusicPlayerHandler].
extension _MusicPlayerHandlerMedia on MusicPlayerHandler {
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
            : mapProcessingState(state),
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

  void _broadcastPosition(Duration position, {bool force = false}) {
    final now = DateTime.now();
    final lastAt = _lastPositionBroadcastAt;
    final elapsed = lastAt == null ? null : now.difference(lastAt);
    final moved = (position - _lastBroadcastPosition).abs();
    if (!force &&
        elapsed != null &&
        elapsed < MusicPlayerHandler._positionBroadcastInterval &&
        moved < MusicPlayerHandler._positionBroadcastInterval) {
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
        now.difference(lastPersistAt) <
            MusicPlayerHandler._positionPersistInterval) {
      return;
    }
    _lastPeriodicPersistAt = now;
    unawaited(_persistSession(position: position));
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
}
