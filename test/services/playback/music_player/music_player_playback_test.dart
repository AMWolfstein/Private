import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/playback/music_player/music_player_service.dart';

import '../../../support/music_player_harness.dart';

PlayableMedia _track(String id) => PlayableMedia(
  id: id,
  source: '/$id.flac',
  title: id,
  artist: 'Artist',
  duration: const Duration(seconds: 60),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<MusicPlayerHandler> startHandler(FakeDeck deck) async =>
      await musicPlayerRuntimeFor(createDeck: (_) => deck).initialize()
          as MusicPlayerHandler;

  test('pause holds the current track and play resumes it', () async {
    final deck = FakeDeck();
    final handler = await startHandler(deck);
    await handler.setQueueAndPlay([_track('a'), _track('b')], initialIndex: 1);
    expect(handler.playbackState.value.playing, isTrue);

    await handler.pause();
    await settleMusicPlayer();
    expect(handler.playbackState.value.playing, isFalse);
    expect(deck.state, PlayerState.paused);

    await handler.play();
    await settleMusicPlayer();
    expect(handler.playbackState.value.playing, isTrue);
    expect(handler.mediaItem.value?.id, 'b');
  });

  test('skipping to a queue position plays that track', () async {
    final handler = await startHandler(FakeDeck());
    await handler.setQueueAndPlay([_track('a'), _track('b'), _track('c')]);
    await handler.skipToQueueItem(2);
    await settleMusicPlayer();
    expect(handler.mediaItem.value?.id, 'c');
    expect(handler.playbackState.value.playing, isTrue);
  });

  test(
    'skipping back from the start of a track goes to the previous one',
    () async {
      final handler = await startHandler(FakeDeck());
      await handler.setQueueAndPlay([
        _track('a'),
        _track('b'),
      ], initialIndex: 1);
      await handler.skipToPrevious();
      await settleMusicPlayer();
      expect(handler.mediaItem.value?.id, 'a');
    },
  );

  test('seeking moves the deck to the requested position', () async {
    final deck = FakeDeck();
    final handler = await startHandler(deck);
    await handler.setQueueAndPlay([_track('a')]);
    await handler.seek(const Duration(seconds: 30));
    expect(deck.seeks, [const Duration(seconds: 30)]);
    // The reported position is interpolated from the clock, so allow a few ms.
    expect(
      handler.playbackState.value.position.inMilliseconds,
      closeTo(30000, 50),
    );
  });

  test('stop ends playback and keeps the queue', () async {
    final handler = await startHandler(FakeDeck());
    await handler.setQueueAndPlay([_track('a'), _track('b')]);
    await handler.stop();
    await settleMusicPlayer();
    expect(handler.playbackState.value.playing, isFalse);
    expect(handler.queue.value.map((item) => item.id), ['a', 'b']);
  });
}
