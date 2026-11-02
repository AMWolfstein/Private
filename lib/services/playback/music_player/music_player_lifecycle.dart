part of 'music_player_service.dart';

/// Initialisation and disposal for [MusicPlayerHandler].
extension _MusicPlayerHandlerLifecycle on MusicPlayerHandler {
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
      _scheduleListeningFlushes();
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
    _player.setReleaseMode(ReleaseMode.stop);
    unawaited(_player.setAudioContext(musicAudioContext));
    unawaited(_configureAudioSession());
    _refreshPlaybackAutomation();

    _listenToPlayer(_player);
  }

  void _scheduleListeningFlushes() {
    if (_disposed || _dependencies.recorder.idle) return;
    _listeningTimer ??= Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(_flushListening());
    });
  }

  Future<void> _flushListening() async {
    final recorder = _dependencies.recorder;
    await recorder.flush();
    if (_disposed || !recorder.idle) return;
    _listeningTimer?.cancel();
    _listeningTimer = null;
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

  Future<void> _dispose() async {
    _autoplay.dispose();
    _disposed = true;
    _runtime.personalization.finish();
    await _runtime.personalization.flush();
    await _runtime.ranker.flush();
    await _runtime.taste.flush();
    if (identical(_runtime.handler, this)) {
      _runtime.dependencies.autoMixStatus?.value = AutoMixStatus.idle;
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
