import 'package:audio_service/audio_service.dart';
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

List<String> _ids(MusicPlayerHandler handler) =>
    handler.queue.value.map((item) => item.id).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<MusicPlayerHandler> startHandler() async =>
      await musicPlayerRuntimeFor(createDeck: (_) => FakeDeck()).initialize()
          as MusicPlayerHandler;

  test('the queue starts at the chosen index and plays from it', () async {
    final handler = await startHandler();
    await handler.setQueueAndPlay([
      _track('a'),
      _track('b'),
      _track('c'),
    ], initialIndex: 1);
    expect(_ids(handler), ['a', 'b', 'c']);
    expect(handler.mediaItem.value?.id, 'b');
  });

  test('Play next inserts directly after the current track', () async {
    final handler = await startHandler();
    await handler.setQueueAndPlay([
      _track('a'),
      _track('b'),
      _track('c'),
    ], initialIndex: 1);
    await handler.enqueue(_track('d'), playNext: true);
    expect(_ids(handler), ['a', 'b', 'd', 'c']);
    expect(handler.mediaItem.value?.id, 'b');
  });

  test(
    'Add to queue appends a manual track without moving the current one',
    () async {
      final handler = await startHandler();
      await handler.setQueueAndPlay([_track('a'), _track('b')]);
      await handler.enqueue(_track('z'));
      expect(_ids(handler).last, 'z');
      expect(handler.mediaItem.value?.id, 'a');
    },
  );

  test(
    'moving a track before the current one keeps the same song current',
    () async {
      final handler = await startHandler();
      await handler.setQueueAndPlay([
        _track('a'),
        _track('b'),
        _track('c'),
      ], initialIndex: 1);
      handler.moveQueueItem(0, 2);
      expect(_ids(handler), ['b', 'c', 'a']);
      expect(handler.mediaItem.value?.id, 'b');
    },
  );

  test('the current track cannot be removed from the queue', () async {
    final handler = await startHandler();
    await handler.setQueueAndPlay([_track('a'), _track('b')]);
    final current = handler.queue.value.first;
    handler.removeQueuedItem(current);
    expect(_ids(handler), ['a', 'b']);

    final upcoming = handler.queue.value.last;
    handler.removeQueuedItem(upcoming);
    expect(_ids(handler), ['a']);
    expect(handler.mediaItem.value?.id, 'a');
  });

  test('shuffle keeps the current track and every queued track', () async {
    final handler = await startHandler();
    final tracks = [for (var i = 0; i < 8; i++) _track('t$i')];
    await handler.setQueueAndPlay(tracks, initialIndex: 3);
    await handler.setShuffleMode(AudioServiceShuffleMode.all);
    expect(handler.mediaItem.value?.id, 't3');
    expect(_ids(handler).toSet(), {for (final t in tracks) t.id});
    expect(_ids(handler), hasLength(8));
  });
}
