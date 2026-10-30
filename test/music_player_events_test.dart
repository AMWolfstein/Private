import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/playback/music_player_service.dart';

import 'support/music_player_harness.dart';

PlayableMedia _track(String id) => PlayableMedia(
  id: id,
  source: '/$id.flac',
  title: id,
  artist: 'Artist',
  duration: const Duration(seconds: 60),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a finished track advances to the next one in the queue', () async {
    final deck = FakeCompletionDeck();
    final handler =
        await musicPlayerRuntimeFor(createDeck: (_) => deck).initialize()
            as MusicPlayerHandler;
    await handler.setQueueAndPlay([_track('a'), _track('b')]);
    deck.completions.add(null);
    await settleMusicPlayer();
    await settleMusicPlayer();

    expect(handler.mediaItem.value?.id, 'b');
    expect(handler.playbackState.value.errorMessage, isNull);
  });

  test('a finished last track stops and keeps the queue', () async {
    final deck = FakeCompletionDeck();
    final handler =
        await musicPlayerRuntimeFor(createDeck: (_) => deck).initialize()
            as MusicPlayerHandler;
    await handler.setQueueAndPlay([_track('a')]);
    deck.completions.add(null);
    await settleMusicPlayer();
    await settleMusicPlayer();

    expect(handler.playbackState.value.playing, isFalse);
    expect(handler.queue.value.map((item) => item.id), ['a']);
  });
}
