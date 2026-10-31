part of 'playlist_playback_test.dart';

void _registerPlaylistPlaybackEmpty() {
  test('empty playlist leaves existing _playback alone', () async {
    await container.read(playbackProvider.notifier).playTrackList([]);
    expect(_player.index, isNull);
  });

  test(
    'no playable files reports an error without replacing playback',
    () async {
      _playback.paths.clear();
      await expectLater(
        container.read(playbackProvider.notifier).playTrackList(_tracks),
        throwsA(isA<Exception>()),
      );
      expect(_player.index, isNull);
    },
  );

  test(
    'old external preference cannot redirect local queue playback',
    () async {
      final calls = <MethodCall>[];
      const channel = MethodChannel('com.amwolfstein.sistrum/backend');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final legacy = AppSettings.fromJson({'playerMode': 'external'});
      expect(legacy.toJson().containsKey('playerMode'), false);
      await container
          .read(playbackProvider.notifier)
          .playTrackList(_tracks, startIndex: 2);
      expect(_player.queue[_player.index!].title, 'Selected');
      expect(_player.queue.length, 3);
      expect(calls, isEmpty);
    },
  );
}
