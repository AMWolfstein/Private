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

List<String> _savedIds(Map<String, dynamic> session) => [
  for (final entry in session['media'] as List) (entry as Map)['id'] as String,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'the saved session holds the whole queue and the current index',
    () async {
      final store = FakeSessionStore();
      final handler =
          await musicPlayerRuntimeFor(
                createDeck: (_) => FakeDeck(),
                sessionStore: store,
              ).initialize()
              as MusicPlayerHandler;
      await handler.setQueueAndPlay([
        _track('a'),
        _track('b'),
        _track('c'),
      ], initialIndex: 1);
      await handler.persistCurrentSession();

      final session = store.saved.last;
      expect(session['index'], 1);
      expect(_savedIds(session), ['a', 'b', 'c']);
    },
  );

  test('adding a track to the queue saves the longer queue', () async {
    final store = FakeSessionStore();
    final handler =
        await musicPlayerRuntimeFor(
              createDeck: (_) => FakeDeck(),
              sessionStore: store,
            ).initialize()
            as MusicPlayerHandler;
    await handler.setQueueAndPlay([_track('a'), _track('b')]);
    await handler.enqueue(_track('c'));
    await settleMusicPlayer();

    expect(_savedIds(store.saved.last), ['a', 'b', 'c']);
  });
}
