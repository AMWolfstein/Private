part of 'music_player_automix.dart';

extension MusicAutoMixPart4 on MusicAutoMix {
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
}
