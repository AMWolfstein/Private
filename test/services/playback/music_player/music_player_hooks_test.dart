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

  test('finishing the last track adds nothing when autoplay is off', () async {
    final deck = FakeCompletionDeck();
    final handler =
        await musicPlayerRuntimeFor(createDeck: (_) => deck).initialize()
            as MusicPlayerHandler;
    await handler.setQueueAndPlay([_track('a'), _track('b')], initialIndex: 1);
    deck.completions.add(null);
    await settleMusicPlayer();
    await settleMusicPlayer();

    expect(handler.queue.value.map((item) => item.id), ['a', 'b']);
  });
}
