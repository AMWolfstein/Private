part of 'music_player_automix.dart';

extension _MusicAutoMixPart5 on MusicAutoMix {
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
      await deck.setAudioContext(musicAudioContext);
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
            await effectDeck.setAudioContext(musicAudioContext);
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
}
