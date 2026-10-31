part of 'music_player_automix.dart';

extension _MusicAutoMixPart1 on MusicAutoMix {
  void _setStatus(AutoMixStatus status) => host.publishStatus(status);

  String _beatSummary(AutoMixBeatGrid? grid) => grid == null
      ? 'unavailable'
      : '${grid.bpm.toStringAsFixed(2)} BPM/${grid.confidence.toStringAsFixed(3)} confidence';
}
