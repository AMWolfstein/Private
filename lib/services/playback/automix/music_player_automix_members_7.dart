part of 'music_player_automix.dart';

extension MusicAutoMixPart7 on MusicAutoMix {
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
