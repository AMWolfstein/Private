import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/playback/music_player/music_player_service.dart';

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

  test('a new handler is idle with an empty queue', () async {
    final handler =
        await musicPlayerRuntimeFor(createDeck: (_) => FakeDeck()).initialize()
            as MusicPlayerHandler;
    expect(handler.playbackState.value.playing, isFalse);
    expect(handler.queue.value, isEmpty);
    expect(handler.mediaItem.value, isNull);
  });

  test('disposing the handler releases the playing deck', () async {
    final deck = FakeDeck();
    final handler =
        await musicPlayerRuntimeFor(createDeck: (_) => deck).initialize()
            as MusicPlayerHandler;
    await handler.setQueueAndPlay([_track('a')]);
    await handler.dispose();
    expect(deck.disposals, greaterThan(0));
  });
}
