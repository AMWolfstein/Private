import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/playback/music_player_service.dart';

import 'support/music_player_harness.dart';

PlayableMedia _track(String id) => PlayableMedia(
  id: id,
  source: '/music/$id.flac',
  title: id,
  artist: 'Artist',
  duration: const Duration(seconds: 60),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('each track is handed to the deck from its own file', () async {
    final deck = FakeDeck();
    final handler =
        await musicPlayerRuntimeFor(createDeck: (_) => deck).initialize()
            as MusicPlayerHandler;
    await handler.setQueueAndPlay([_track('a'), _track('b')]);
    await handler.skipToNext();
    await settleMusicPlayer();

    expect(
      deck.sources,
      containsAllInOrder(['/music/a.flac', '/music/b.flac']),
    );
  });
}
