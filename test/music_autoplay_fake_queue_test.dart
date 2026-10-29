import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/playback/autoplay_personalization.dart';
import 'package:sistrum/services/playback/music_player_service.dart';

PlayableMedia _song(String id, {bool autoplay = false}) => PlayableMedia(
  id: id,
  source: '/music/$id.flac',
  title: 'Song $id',
  artist: 'Artist $id',
  autoplay: autoplay,
);

/// A queue that records what Autoplay asks for, with no handler behind it.
class _FakeQueue implements AutoplayQueueView {
  _FakeQueue(List<PlayableMedia> items)
    : index = 0,
      media = [...items],
      queue = [
        for (final item in items) MediaItem(id: item.id, title: item.title),
      ];

  final List<PlayableMedia> media;
  final List<MediaItem> queue;
  final List<List<PlayableMedia>> appended = [];
  @override
  int index;
  @override
  bool autoplaySetting = true;
  @override
  bool isDisposed = false;
  @override
  AudioServiceRepeatMode repeatMode = AudioServiceRepeatMode.none;
  @override
  int sessionQueueRevision = 0;

  @override
  int get mediaCount => media.length;
  @override
  PlayableMedia mediaAt(int i) => media[i];
  @override
  MediaItem queueItemAt(int i) => queue[i];
  @override
  List<PlayableMedia> upcoming() => media.skip(index + 1).toList();
  @override
  List<PlayableMedia> recentlyPlayed() => const [];
  @override
  AutoplayPreferenceModel? get preferenceModel => null;
  @override
  Random get random => Random(1);

  @override
  void appendAutoplayTracks(List<PlayableMedia> additions) {
    appended.add(additions);
    media.addAll(additions);
    queue.addAll(
      additions.map((item) => MediaItem(id: item.id, title: item.title)),
    );
  }

  @override
  void removeQueuedItem(MediaItem item) {
    final at = queue.indexWhere((entry) => identical(entry, item));
    if (at < 0) return;
    queue.removeAt(at);
    media.removeAt(at);
  }
}

void main() {
  test(
    'fill appends a full set of suggestions when the queue is short',
    () async {
      final view = _FakeQueue([_song('seed')]);
      final candidates = [for (var i = 0; i < 8; i++) _song('c$i')];
      final autoplay = MusicAutoplay(view, (_) async => candidates);

      await autoplay.fill();

      expect(view.appended, hasLength(1));
      expect(view.appended.single, hasLength(6));
      expect(view.appended.single.every((item) => item.autoplay), isTrue);
    },
  );

  test(
    'fill does nothing when the queue already has enough upcoming songs',
    () async {
      final view = _FakeQueue([
        _song('seed'),
        _song('a'),
        _song('b'),
        _song('c'),
      ]);
      var loads = 0;
      final autoplay = MusicAutoplay(view, (_) async {
        loads++;
        return [_song('x')];
      });

      await autoplay.fill();

      expect(loads, 0);
      expect(view.appended, isEmpty);
    },
  );

  test(
    'updateMode removes queued suggestions but keeps manual songs',
    () async {
      final view = _FakeQueue([
        _song('seed'),
        _song('auto', autoplay: true),
        _song('manual'),
        _song('auto2', autoplay: true),
      ]);
      final autoplay = MusicAutoplay(view, (_) async => const []);

      autoplay.updateMode();

      expect(view.media.map((item) => item.id), ['seed', 'manual']);
    },
  );

  test('manualInsertIndex lands before the first queued suggestion', () {
    final view = _FakeQueue([
      _song('seed'),
      _song('manual'),
      _song('auto', autoplay: true),
    ]);
    final autoplay = MusicAutoplay(view, (_) async => const []);

    expect(autoplay.manualInsertIndex, 2);
  });

  test('autoplay stays off when repeat-one is on', () {
    final view = _FakeQueue([_song('seed')])
      ..repeatMode = AudioServiceRepeatMode.one;
    final autoplay = MusicAutoplay(view, (_) async => const []);

    expect(autoplay.enabled, isFalse);
  });
}
