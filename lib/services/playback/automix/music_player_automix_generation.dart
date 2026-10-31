part of 'music_player_automix.dart';

extension _MusicAutoMixPart3 on MusicAutoMix {
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
}
