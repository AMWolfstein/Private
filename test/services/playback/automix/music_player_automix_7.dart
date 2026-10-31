part of 'music_player_automix_test.dart';

void _registerMusicPlayerAutomix7() {
  test('repeat one never prepares another deck', () async {
    setAutoMixEnabled(true);
    await handler.setRepeatMode(AudioServiceRepeatMode.one);
    await handler.setQueueAndPlay(_tracks);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(_native.live, {'music-player'});
    expect(_analyzer.calls, isEmpty);
  });
}
