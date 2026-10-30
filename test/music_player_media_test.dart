import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/playback/music_player/music_player_service.dart';

import 'support/music_player_harness.dart';

PlayableMedia _track(String id) => PlayableMedia(
  id: id,
  source: '/$id.flac',
  title: 'Title $id',
  artist: 'Artist',
  duration: const Duration(seconds: 60),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'the current item publishes its title and duration while playing',
    () async {
      final handler =
          await musicPlayerRuntimeFor(
                createDeck: (_) => FakeDeck(),
              ).initialize()
              as MusicPlayerHandler;
      await handler.setQueueAndPlay([_track('a')]);
      await settleMusicPlayer();

      expect(handler.mediaItem.value?.title, 'Title a');
      expect(handler.mediaItem.value?.duration, const Duration(seconds: 60));
      expect(handler.playbackState.value.playing, isTrue);
    },
  );
}
