part of 'music_player_service.dart';

/// Player, audio-session and focus event handling for [MusicPlayerHandler].
extension _MusicPlayerHandlerEvents on MusicPlayerHandler {
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
}
