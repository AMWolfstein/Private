part of 'music_player_automix.dart';

extension _MusicAutoMixPart6 on MusicAutoMix {
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
}
