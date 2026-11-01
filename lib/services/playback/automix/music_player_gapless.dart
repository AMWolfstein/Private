part of 'music_player_automix.dart';

/// Shares AutoMix's queue generation, cache pins and deck ownership, but uses
/// Android's native handoff without a fade, trimming or a Dart start timer.
extension MusicGapless on MusicAutoMix {
  void _onGaplessPosition(Duration position) {
    if (_prepared != null) {
      if (!_current(_generation)) unawaited(cancel());
      return;
    }
    final duration = host.currentDuration;
    if (_preparing ||
        duration == null ||
        duration <= Duration.zero ||
        duration - position > const Duration(seconds: 30)) {
      return;
    }
    final key = '${host.playRequestGeneration}:${host.sessionQueueRevision}';
    if (_attempt == key) return;
    _attempt = key;
    unawaited(_prepareGapless());
  }

  Future<void> _prepareGapless() async {
    _preparing = true;
    final generation = ++_generation;
    _playGeneration = host.playRequestGeneration;
    _queueRevision = host.sessionQueueRevision;
    final nextIndex = host.index + 1 < host.mediaCount
        ? host.index + 1
        : host.repeatMode == AudioServiceRepeatMode.all
        ? 0
        : -1;
    MusicPlaybackDeck? deck;
    final pins = <String>{};
    _preparationPins[generation] = pins;
    try {
      if (nextIndex < 0 || nextIndex == host.index) return;
      final next = host.mediaAt(nextIndex);
      if (next.bitDepth == 1 ||
          const ['dsf', 'dff'].contains(next.format?.toLowerCase()) ||
          next.source.toLowerCase().endsWith('.dsf') ||
          next.source.toLowerCase().endsWith('.dff')) {
        return;
      }
      final path = await host.resolveSource(next);
      if (path == null || !_current(generation)) return;
      pins.add(path);
      deck = host.createDeck(
        'music-gapless-$generation-${DateTime.now().microsecondsSinceEpoch}',
      );
      host.listenToPlayer(deck);
      await deck.setReleaseMode(ReleaseMode.stop);
      await deck.setAudioContext(musicAudioContext);
      await deck.setSource(DeviceFileSource(path));
      if (!_current(generation)) return;
      final volume = await host.normalizationVolumeFor(
        path,
        cacheKey: next.isContentUri ? next.source : null,
      );
      await deck.setVolume(volume);
      final duration = await deck.getDuration() ?? next.duration;
      if (!_current(generation)) return;
      final outgoing = host.player;
      final position = await outgoing.getCurrentPosition();
      final currentDuration = host.currentDuration;
      if (!_current(generation) ||
          position == null ||
          currentDuration == null ||
          currentDuration - position < const Duration(seconds: 1)) {
        return;
      }
      // Publish ownership before awaiting the link; cancellation can unlink it.
      _gaplessOutgoing = outgoing;
      await outgoing.setNextDeck(deck);
      if (!_current(generation)) return;
      _prepared = deck;
      deck = null;
      _next = next;
      _nextIndex = nextIndex;
      _nextPath = path;
      _nextDuration = duration;
      _incomingVolume = volume;
      _mixPins.addAll(pins);
    } catch (error) {
      if (generation == _generation) {
        final outgoing = _gaplessOutgoing;
        _gaplessOutgoing = null;
        try {
          await outgoing?.setNextDeck(null);
        } catch (_) {
          /* Normal completion remains available. */
        }
      }
      _log.w(
        'Gapless preparation unavailable; normal completion retained: $error',
      );
    } finally {
      if (deck != null) await host.disposeDeck(deck);
      _preparationPins.remove(generation);
      if (generation == _generation) _preparing = false;
    }
  }

  Future<bool> completeGapless() async {
    final incoming = _prepared;
    final next = _next;
    // Completion changes the outgoing state, so validate the queue and mode
    // explicitly rather than using _current (which requires playing).
    if (_gaplessOutgoing == null ||
        incoming == null ||
        next == null ||
        host.settings.autoMix ||
        host.isDisposed ||
        host.userPaused ||
        host.interruptionActive ||
        _playGeneration != host.playRequestGeneration ||
        _queueRevision != host.sessionQueueRevision) {
      return false;
    }
    final generation = _generation;
    final outgoing = _gaplessOutgoing!;
    final position = await incoming.getCurrentPosition() ?? Duration.zero;
    if (generation != _generation ||
        host.isDisposed ||
        host.userPaused ||
        host.interruptionActive ||
        _queueRevision != host.sessionQueueRevision ||
        _playGeneration != host.playRequestGeneration) {
      return false;
    }
    _prepared = null;
    _gaplessOutgoing = null;
    _starting = true;
    // resume synchronizes audioplayers' Dart state; native play is already active.
    host.commitTransition(
      incoming: incoming,
      index: _nextIndex,
      next: next,
      nextPath: _nextPath,
      nextDuration: _nextDuration,
      normalizationVolume: _incomingVolume,
      audiblePosition: position,
    );
    _next = null;
    _nextPath = null;
    _mixPins.clear();
    _attempt = null;
    try {
      await incoming.resume();
    } finally {
      await host.disposeDeck(outgoing);
      await host.cleanupPendingResolvedPaths();
      if (generation == _generation) _starting = false;
    }
    return true;
  }
}
