part of 'music_player_service.dart';

/// Source preparation and transport internals for [MusicPlayerHandler].
extension _MusicPlayerHandlerPlayback on MusicPlayerHandler {
  bool _isCurrentPlayRequest(int generation, PlayableMedia media) {
    return !_disposed &&
        generation == _playRequestGeneration &&
        _index >= 0 &&
        _index < _media.length &&
        _media[_index].id == media.id &&
        _media[_index].source == media.source;
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
}
