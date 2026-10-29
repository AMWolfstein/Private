part of 'music_player_service.dart';

/// What AutoMix needs from the handler: the live queue, the playing deck and the
/// transition commit. [_HandlerAutoMixHost] supplies it, so AutoMix does not
/// reach the handler's private state itself.
abstract interface class AutoMixHost {
  AppSettings get settings;
  bool get isDisposed;
  bool get sourceReady;
  bool get userPaused;
  bool get interruptionActive;
  bool get isLiveHandler;
  AudioServiceRepeatMode get repeatMode;
  int get mediaCount;
  PlayableMedia mediaAt(int index);
  int get index;
  int get playRequestGeneration;
  int get sessionQueueRevision;
  double get normalizationVolume;
  MusicPlaybackDeck get player;
  Duration? get currentDuration;
  Future<String?> resolveSource(PlayableMedia media);
  Future<double> normalizationVolumeFor(String path, {String? cacheKey});
  MusicPlaybackDeck createDeck(String playerId);
  void listenToPlayer(MusicPlaybackDeck deck);
  Future<void> disposeDeck(MusicPlaybackDeck deck);
  Future<void> cleanupPendingResolvedPaths();
  void broadcastState({PlayerState? playerState});
  void broadcastPosition(Duration position, {bool force = false});
  void commitTransition({
    required MusicPlaybackDeck incoming,
    required int index,
    required PlayableMedia next,
    required String? nextPath,
    required Duration? nextDuration,
    required double normalizationVolume,
    required Duration audiblePosition,
  });
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

class _MusicAutoMix {
  _MusicAutoMix(this.host, this.analyzer, this.renderer);

  final AutoMixHost host;
  final AutoMixAnalyzer analyzer;
  final AutoMixEffectRenderer renderer;
  final _preparationPins = <int, Set<String>>{};
  final _mixPins = <String>{};
  MusicPlaybackDeck? _prepared;
  MusicPlaybackDeck? _outgoing;
  MusicPlaybackDeck? _effectDry;
  MusicPlaybackDeck? _effectPrepared;
  RenderedMixTail? _effectTail;
  AutoMixPlan? _plan;
  PlayableMedia? _next;
  String? _nextPath;
  Duration? _nextDuration;
  String? _attempt;
  int _nextIndex = -1;
  int _queueRevision = -1;
  int _playGeneration = -1;
  int _generation = 0;
  int _cancelling = 0;
  bool _preparing = false;
  bool _starting = false;
  double _incomingVolume = 1;
  double rate = 1;
  Timer? _startTimer;
  Timer? _fadeTimer;
  Future<void> _fadeWrite = Future<void>.value();
  bool _writing = false;

  void _setStatus(AutoMixStatus status) {
    if (host.isLiveHandler) {
      autoMixStatus.value = status;
    }
  }

  String _beatSummary(AutoMixBeatGrid? grid) => grid == null
      ? 'unavailable'
      : '${grid.bpm.toStringAsFixed(2)} BPM/${grid.confidence.toStringAsFixed(3)} confidence';

  Set<String> get pinnedPaths => {
    ..._mixPins,
    for (final paths in _preparationPins.values) ...paths,
  };

  bool get _canMix =>
      host.settings.autoMix &&
      !host.settings.usbBitPerfect &&
      !host.player.isDirect &&
      !host.isDisposed &&
      host.sourceReady &&
      !host.userPaused &&
      !host.interruptionActive &&
      host.player.state == PlayerState.playing &&
      host.repeatMode != AudioServiceRepeatMode.one &&
      host.mediaCount > 1;

  bool _current(int generation) =>
      generation == _generation &&
      _canMix &&
      _playGeneration == host.playRequestGeneration &&
      _queueRevision == host.sessionQueueRevision;

  void onPosition(Duration position) {
    if (!_canMix || _cancelling > 0 || _starting || _fadeTimer != null) return;
    final plan = _plan;
    if (plan != null) {
      if (!_current(_generation)) {
        unawaited(cancel());
        return;
      }
      final delay = plan.start - position;
      _startTimer?.cancel();
      final generation = _generation;
      _startTimer = Timer(delay.isNegative ? Duration.zero : delay, () {
        if (_current(generation)) unawaited(_start(generation));
      });
      return;
    }
    if (_preparing) return;
    final duration = host.currentDuration;
    if (duration == null || duration < const Duration(seconds: 20)) return;
    final key = '${host.playRequestGeneration}:${host.sessionQueueRevision}';
    if (_attempt == key) return;
    _attempt = key;
    unawaited(_prepare(duration));
  }

  Future<void> _prepare(Duration duration) async {
    _preparing = true;
    final generation = ++_generation;
    _playGeneration = host.playRequestGeneration;
    _queueRevision = host.sessionQueueRevision;
    final index = host.index;
    final nextIndex = index + 1 < host.mediaCount
        ? index + 1
        : host.repeatMode == AudioServiceRepeatMode.all
        ? 0
        : -1;
    final pins = <String>{};
    _preparationPins[generation] = pins;
    MusicPlaybackDeck? deck;
    MusicPlaybackDeck? effectDeck;
    RenderedMixTail? effectTail;
    final options = host.settings.autoMixOptions;
    try {
      if (nextIndex < 0 || nextIndex == index || index < 0) return;
      final current = host.mediaAt(index);
      final next = host.mediaAt(nextIndex);
      final currentPath = await host.resolveSource(current);
      if (currentPath == null || !_current(generation)) return;
      pins.add(currentPath);
      final nextPath = await host.resolveSource(next);
      if (nextPath == null || !_current(generation)) return;
      pins.add(nextPath);
      deck = host.createDeck(
        'music-mix-$generation-${DateTime.now().microsecondsSinceEpoch}',
      );
      host.listenToPlayer(deck);
      await deck.setReleaseMode(ReleaseMode.stop);
      await deck.setAudioContext(_musicAudioContext);
      await deck.setVolume(0);
      if (!_current(generation)) return;
      await deck.setSource(DeviceFileSource(nextPath));
      if (!_current(generation)) return;
      final nextDuration =
          await deck.getDuration() ?? next.duration ?? Duration.zero;
      final offset = options.outroWindowOffset(
        duration,
        AutoMixAnalyzer.windowSeconds,
      );
      final outro = await analyzer.analyzeTransition(
        currentPath,
        offset: offset,
      );
      if (!_current(generation)) return;
      final intro = await analyzer.analyzeTransition(nextPath);
      if (!_current(generation)) return;
      final plan = AutoMixPlan.create(
        outgoingDuration: duration,
        incomingDuration: nextDuration,
        outro: outro,
        intro: intro,
        outroOffset: offset,
        options: options,
      );
      if (plan == null) return;
      await deck.seek(plan.incomingStart);
      await deck.setPlaybackRate(plan.rate);
      final volume = await host.normalizationVolumeFor(
        nextPath,
        cacheKey: next.isContentUri ? next.source : null,
      );
      if (!_current(generation)) return;
      if (options.hasEffects || plan.assisted) {
        effectTail = await renderer.render(
          currentPath,
          start: plan.start,
          duration: plan.duration,
          options: options,
          bassHandoff: plan.assisted,
        );
        if (!_current(generation)) return;
        if (effectTail != null) {
          effectDeck = host.createDeck(
            'music-effect-$generation-${DateTime.now().microsecondsSinceEpoch}',
          );
          host.listenToPlayer(effectDeck);
          try {
            await effectDeck.setReleaseMode(ReleaseMode.stop);
            await effectDeck.setAudioContext(_musicAudioContext);
            await effectDeck.setVolume(0);
            await effectDeck.setSource(DeviceFileSource(effectTail.path));
          } catch (error) {
            _log.w('AutoMix effect preparation fallback: $error');
            await host.disposeDeck(effectDeck);
            await effectTail.dispose();
            effectDeck = null;
            effectTail = null;
          }
          if (!_current(generation)) return;
        }
      }
      _effectPrepared = effectDeck;
      _effectTail = effectTail;
      effectDeck = null;
      effectTail = null;
      _prepared = deck;
      deck = null;
      _next = next;
      _nextIndex = nextIndex;
      _nextPath = nextPath;
      _nextDuration = nextDuration;
      _incomingVolume = volume;
      _mixPins.addAll(pins);
      _plan = plan;
      _log.d(
        'AutoMix prepared (${plan.beatMatched ? 'beat matched' : 'crossfade'}, '
        'rate=${plan.rate.toStringAsFixed(3)}, '
        'fallback=${plan.fallbackReason?.name ?? 'none'}, '
        'assisted=${plan.assisted}, '
        'outro=${_beatSummary(outro)}, intro=${_beatSummary(intro)})',
      );
      final position = await host.player.getCurrentPosition();
      if (position != null && _current(generation)) onPosition(position);
    } catch (error) {
      _log.w('AutoMix preparation skipped: $error');
    } finally {
      if (deck != null) await host.disposeDeck(deck);
      if (effectDeck != null) await host.disposeDeck(effectDeck);
      if (effectTail != null) await effectTail.dispose();
      _preparationPins.remove(generation);
      if (generation == _generation) _preparing = false;
      await host.cleanupPendingResolvedPaths();
    }
  }

  Future<void> _start(int generation) async {
    final incoming = _prepared;
    final next = _next;
    var plan = _plan;
    if (incoming == null ||
        next == null ||
        plan == null ||
        !_current(generation)) {
      return;
    }
    if (_nextIndex >= host.mediaCount ||
        !identical(host.mediaAt(_nextIndex), next)) {
      return;
    }
    _starting = true;
    try {
      final position = await host.player.getCurrentPosition();
      if (!_current(generation) || position == null) return;
      final delta = position - plan.start;
      if (delta < const Duration(milliseconds: -40)) {
        _starting = false;
        onPosition(position);
        return;
      }
      final outgoingEnd = host.currentDuration ?? plan.start + plan.duration;
      if (outgoingEnd - position <= const Duration(milliseconds: 500)) {
        await _abandonStart(generation);
        return;
      }
      final incomingPosition = await incoming.getCurrentPosition();
      if (!_current(generation)) return;
      await incoming.resume();
      var audiblePosition = await _waitForProgress(
        incoming,
        incomingPosition ?? plan.incomingStart,
        generation,
      );
      if (audiblePosition != null && plan.beatMatched) {
        final alignment = await _alignIncoming(
          incoming,
          host.player,
          plan,
          audiblePosition,
          generation,
        );
        audiblePosition = alignment?.position;
        if (alignment != null && !alignment.aligned) {
          if (!_current(generation)) return;
          await incoming.setPlaybackRate(1);
          plan = plan.withoutBeatMatching();
          _log.w(
            'AutoMix alignment could not be verified; using unstretched crossfade',
          );
        }
      }
      if (!_current(generation)) return;
      if (audiblePosition == null) {
        _log.w('AutoMix standby did not advance; keeping the current song');
        await _abandonStart(generation);
        return;
      }
      final original = host.player;
      final outgoingVolume = host.normalizationVolume;
      var outgoing = original;
      final effectDeck = _effectPrepared;
      if (effectDeck != null) {
        try {
          final livePosition = await original.getCurrentPosition() ?? position;
          if (!_current(generation)) return;
          final effectOffset = livePosition - plan.start;
          final effectStart = effectOffset.isNegative
              ? Duration.zero
              : effectOffset;
          await effectDeck.seek(effectStart);
          if (!_current(generation)) return;
          await effectDeck.resume();
          if (!_current(generation)) return;
          // The render opens with the same dry audio as the live deck. Hand
          // over only once it is audibly playing and aligned: fading the live
          // deck out on resume left a gap while the effect decoder started,
          // and its late start then doubled the music.
          if (await _waitForProgress(effectDeck, effectStart, generation) ==
              null) {
            throw StateError('Effect deck did not start');
          }
          if (!await _alignEffect(
            effectDeck,
            original,
            plan,
            generation,
            tolerance: Duration(milliseconds: plan.beatMatched ? 20 : 50),
          )) {
            if (!_current(generation)) return;
            throw StateError('Effect deck could not be aligned');
          }
          outgoing = effectDeck;
          _effectDry = original;
        } catch (error) {
          if (!_current(generation)) return;
          _log.w('AutoMix effect fallback: $error');
          await host.disposeDeck(effectDeck);
          await _effectTail?.dispose();
          _effectTail = null;
        }
        _effectPrepared = null;
      }
      final outgoingPosition = await original.getCurrentPosition() ?? position;
      if (!_current(generation)) return;
      final remaining = outgoingEnd - outgoingPosition;
      // Native resume acknowledges a command before audio necessarily starts.
      // Keep the old song at full gain until the new decoder advances, then
      // fit the overlap into the remaining outro instead of fading into silence.
      final fadeDuration = remaining <= Duration.zero
          ? const Duration(milliseconds: 40)
          : remaining < plan.duration
          ? remaining
          : plan.duration;
      _outgoing = outgoing;
      _prepared = null;
      _plan = null;
      rate = plan.rate;
      host.commitTransition(
        incoming: incoming,
        index: _nextIndex,
        next: next,
        nextPath: _nextPath,
        nextDuration: _nextDuration,
        normalizationVolume: _incomingVolume,
        audiblePosition: audiblePosition,
      );
      _setStatus(
        plan.beatMatched ? AutoMixStatus.mixing : AutoMixStatus.crossfading,
      );
      final clock = Stopwatch()..start();
      final transition = plan;
      final phaseLock = plan.beatMatched
          ? AutoMixPhaseLock(
              baseRate: plan.rate,
              period: plan.beatPeriod.inMicroseconds / 1e6 * plan.rate,
            )
          : null;
      _log.d(
        'AutoMix started (${plan.beatMatched ? 'beat matched' : 'crossfade'}, '
        'rate=${plan.rate.toStringAsFixed(3)}, '
        'assisted=${plan.assisted && outgoing != original}, '
        'fallback=${plan.fallbackReason?.name ?? 'none'})',
      );
      _fadeTimer = Timer.periodic(const Duration(milliseconds: 40), (_) {
        if (_writing || generation != _generation) return;
        _writing = true;
        _fadeWrite = () async {
          try {
            final levels = autoMixEnvelope(
              clock.elapsed,
              transition,
              fadeDuration: fadeDuration,
            );
            final dry = _effectDry;
            final progress = (clock.elapsedMicroseconds / 240000).clamp(
              0.0,
              1.0,
            );
            final handover = progress * progress * (3 - 2 * progress);
            if (dry != null) {
              await dry.setVolume(
                outgoingVolume * levels.outgoing * (1 - handover),
              );
              if (generation != _generation) return;
            }
            if (_outgoing != null) {
              await outgoing.setVolume(
                outgoingVolume * levels.outgoing * (dry == null ? 1 : handover),
              );
            }
            if (generation != _generation) return;
            await incoming.setVolume(_incomingVolume * levels.incoming);
            if (generation != _generation) return;
            var targetRate = levels.rate;
            if (phaseLock != null &&
                clock.elapsed < fadeDuration &&
                _outgoing != null) {
              targetRate = phaseLock.rateAt(clock.elapsed);
              if (phaseLock.shouldMeasure(clock.elapsed)) {
                final error = await _phaseError(
                  incoming,
                  outgoing,
                  transition,
                  outgoingOffset: outgoing == original
                      ? Duration.zero
                      : transition.start,
                );
                if (generation != _generation) return;
                phaseLock.observe(clock.elapsed, error);
                targetRate = phaseLock.rateAt(clock.elapsed);
                if (!phaseLock.trusted) {
                  _setStatus(AutoMixStatus.crossfading);
                  _log.w(
                    'AutoMix phase tracking lost reliable positions; keeping the fade without further corrections',
                  );
                }
              }
            }
            if ((targetRate - rate).abs() > 0.001 || levels.complete) {
              await incoming.setPlaybackRate(targetRate);
              rate = targetRate;
            }
            if (generation != _generation) return;
            if (dry != null && progress >= 1) {
              _effectDry = null;
              await host.disposeDeck(dry);
              if (generation != _generation) return;
            }
            if (clock.elapsed >= fadeDuration && _outgoing != null) {
              _outgoing = null;
              await host.disposeDeck(outgoing);
              final tail = _effectTail;
              _effectTail = null;
              await tail?.dispose();
              _setStatus(AutoMixStatus.idle);
            }
            if (levels.complete) {
              _fadeTimer?.cancel();
              _fadeTimer = null;
              rate = 1;
              _mixPins.clear();
              await host.cleanupPendingResolvedPaths();
              host.broadcastState();
            }
          } catch (error) {
            _log.w('AutoMix transition ended early: $error');
            // Defer cancellation until this volume write has unwound.
            scheduleMicrotask(() => unawaited(cancel()));
          } finally {
            _writing = false;
          }
        }();
      });
    } catch (error) {
      _log.w('AutoMix start skipped: $error');
      if (generation == _generation) await _abandonStart(generation);
    } finally {
      if (generation == _generation) _starting = false;
    }
  }

  Future<void> _abandonStart(int generation) async {
    final attempt = _attempt;
    await cancel();
    // Do not repeatedly prepare the same stalled transition on every tick.
    if (_generation == generation + 1) _attempt = attempt;
  }

  /// Keeps the silent effect deck within [tolerance] of the live song. Two
  /// players cannot share a clock, so a corrected seek is checked again.
  Future<bool> _alignEffect(
    MusicPlaybackDeck effect,
    MusicPlaybackDeck live,
    AutoMixPlan plan,
    int generation, {
    Duration tolerance = const Duration(milliseconds: 50),
  }) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final effectPosition = await effect.getCurrentPosition();
      final livePosition = await live.getCurrentPosition();
      if (!_current(generation)) return false;
      if (effectPosition == null || livePosition == null) return false;
      final target = livePosition - plan.start;
      if ((target - effectPosition).abs() <= tolerance) return true;
      if (target.isNegative) return false;
      await effect.seek(target);
      if (!_current(generation)) return false;
      if (await _waitForProgress(effect, target, generation) == null) {
        return false;
      }
    }
    return false;
  }

  /// Puts the silent incoming deck on the outgoing song's beat grid. It was
  /// cued on its first beat, but the start timer, platform calls and decoder
  /// startup delay it by an unknown amount, and at 150 BPM 100 ms is already
  /// a quarter beat. A seek takes time as well, so each retry leads the target
  /// by the lag the previous seek left behind. Returns null when the deck
  /// stops advancing or the transition is no longer current.
  Future<({Duration position, bool aligned})?> _alignIncoming(
    MusicPlaybackDeck incoming,
    MusicPlaybackDeck outgoing,
    AutoMixPlan plan,
    Duration position,
    int generation, {
    Duration tolerance = const Duration(milliseconds: 20),
  }) async {
    var current = position;
    var lead = Duration.zero;
    for (var attempt = 0; attempt <= 3; attempt++) {
      final before = await outgoing.getCurrentPosition();
      final incomingPosition = await incoming.getCurrentPosition();
      final after = await outgoing.getCurrentPosition();
      if (!_current(generation)) return null;
      if (before == null || incomingPosition == null || after == null) {
        return (position: current, aligned: false);
      }
      if (after < before || after - before > const Duration(milliseconds: 80)) {
        return (position: incomingPosition, aligned: false);
      }
      // The incoming reading falls between the two outgoing readings.
      final elapsed = (before + after) ~/ 2 - plan.start;
      final target = plan.incomingStart + elapsed * plan.rate;
      final error = target - incomingPosition;
      if (error.abs() <= tolerance) {
        _log.d('AutoMix alignment verified: error=${error.inMilliseconds}ms');
        return (position: incomingPosition, aligned: true);
      }
      if (attempt == 3) {
        _log.w(
          'AutoMix alignment exceeded tolerance: error=${error.inMilliseconds}ms',
        );
        return (position: incomingPosition, aligned: false);
      }
      // The first error is startup delay; later ones are what a seek lost.
      if (attempt > 0) lead += error;
      var destination = target + lead;
      if (destination.isNegative) destination = Duration.zero;
      await incoming.seek(destination);
      if (!_current(generation)) return null;
      final progressed = await _waitForProgress(
        incoming,
        destination,
        generation,
      );
      if (progressed == null) return null;
      current = progressed;
    }
    return (position: current, aligned: false);
  }

  Future<double?> _phaseError(
    MusicPlaybackDeck incoming,
    MusicPlaybackDeck outgoing,
    AutoMixPlan plan, {
    Duration outgoingOffset = Duration.zero,
  }) async {
    try {
      final before = await outgoing.getCurrentPosition();
      final next = await incoming.getCurrentPosition();
      final after = await outgoing.getCurrentPosition();
      if (before == null ||
          next == null ||
          after == null ||
          after < before ||
          after - before > const Duration(milliseconds: 80)) {
        return null;
      }
      final expected =
          plan.incomingStart +
          ((before + after) ~/ 2 + outgoingOffset - plan.start) * plan.rate;
      return (next - expected).inMicroseconds / 1e6;
    } catch (_) {
      // A missing position report must not interrupt either audible deck.
      return null;
    }
  }

  Future<Duration?> _waitForProgress(
    MusicPlaybackDeck deck,
    Duration initialPosition,
    int generation,
  ) async {
    final clock = Stopwatch()..start();
    while (_current(generation) && clock.elapsed < const Duration(seconds: 2)) {
      final position = await deck.getCurrentPosition();
      if (position != null &&
          position - initialPosition >= const Duration(milliseconds: 20)) {
        return position;
      }
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    return null;
  }

  Future<void> cancel() async {
    _generation++;
    _cancelling++;
    analyzer.cancel();
    renderer.cancel();
    _setStatus(AutoMixStatus.idle);
    _startTimer?.cancel();
    _startTimer = null;
    _fadeTimer?.cancel();
    _fadeTimer = null;
    final prepared = _prepared;
    final outgoing = _outgoing;
    final effectDry = _effectDry;
    final effectPrepared = _effectPrepared;
    final effectTail = _effectTail;
    final restore = outgoing != null || rate != 1;
    _prepared = null;
    _outgoing = null;
    _effectDry = null;
    _effectPrepared = null;
    _effectTail = null;
    _plan = null;
    _next = null;
    _nextPath = null;
    _nextDuration = null;
    _preparing = false;
    _starting = false;
    _attempt = null;
    try {
      await _fadeWrite;
      if (prepared != null) await host.disposeDeck(prepared);
      if (outgoing != null) await host.disposeDeck(outgoing);
      if (effectDry != null) await host.disposeDeck(effectDry);
      if (effectPrepared != null) await host.disposeDeck(effectPrepared);
      await effectTail?.dispose();
      if (restore && !host.isDisposed) {
        await host.player.setPlaybackRate(1);
        await host.player.setVolume(host.normalizationVolume);
      }
      rate = 1;
      _mixPins.clear();
      await host.cleanupPendingResolvedPaths();
    } catch (error) {
      _log.w('AutoMix cleanup: $error');
    } finally {
      _cancelling--;
    }
  }

  Future<void> dispose() async {
    await cancel();
    analyzer.dispose();
    renderer.dispose();
  }
}
