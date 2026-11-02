import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/core/models/settings.dart';
import 'package:sistrum/services/playback/music_player/music_player_service.dart';
import 'package:sistrum/services/playback/autoplay/music_player_autoplay.dart';

PlayableMedia track(
  String id, {
  String artist = 'Artist',
  String? genre,
  String? source,
}) => PlayableMedia(
  id: id,
  source: source ?? '/$id.flac',
  title: id,
  artist: artist,
  genre: genre,
);

class _NoNoise implements Random {
  @override
  double nextDouble() => 0;
  @override
  int nextInt(int max) => 0;
  @override
  bool nextBool() => false;
}

void main() {
  test(
    'session genres outweigh a single seed and artists stay spaced when alternatives fit',
    () {
      final seed = track('seed', artist: 'Seed', genre: 'Rock');
      final jazz = track('jazz', artist: 'J', genre: 'Jazz');
      final rock = track('rock', artist: 'R', genre: 'Rock');
      final contextPick = selectAutoplayTracks(
        seed: seed,
        candidates: [rock, jazz],
        upcoming: [],
        recent: [
          for (var i = 0; i < 10; i++)
            track('heard$i', artist: 'Other$i', genre: 'Jazz'),
        ],
        dismissedSources: {},
        random: _NoNoise(),
        limit: 1,
      );
      expect(contextPick.single.id, 'jazz');
      final varied = selectAutoplayTracks(
        seed: seed,
        candidates: [
          track('a1', artist: 'A'),
          track('a2', artist: 'A'),
          track('a3', artist: 'A'),
          for (final artist in ['B', 'C', 'D']) track(artist, artist: artist),
        ],
        upcoming: [],
        recent: [],
        dismissedSources: {},
        random: _NoNoise(),
        preferenceAdjustment: (t) => t.artist == 'A' ? 100 : 0,
        limit: 5,
      );
      expect(varied.take(4).map((t) => t.artist).toSet(), hasLength(4));
      expect(varied.map((t) => t.source).toSet(), hasLength(5));
    },
  );

  test(
    'learned weights change real picks and preserve pre-weight score parts',
    () {
      final seed = track('seed', artist: 'Seed', genre: 'Rock');
      final sameArtist = track('artist', artist: 'A', genre: 'Other');
      final sameGenre = track('genre', artist: 'Other', genre: 'Rock');
      List<AutoplayPick> rank(Map<String, double> weights) =>
          rankAutoplayTracks(
            seed: seed,
            candidates: [sameArtist, sameGenre],
            upcoming: [],
            recent: [],
            dismissedSources: {},
            random: _NoNoise(),
            limit: 1,
            weights: weights,
            preferenceAdjustment: (item) => item.id == 'artist' ? 1 : 0,
          );
      expect(rank({}).single.media.id, 'genre');
      final learned = rank({'preference': 3, 'genre': 0}).single;
      expect(learned.media.id, 'artist');
      expect(learned.parts['preference'], 1);
    },
  );

  test('Autoplay balances artists before repeats and deduplicates', () {
    final seed = track('seed', genre: 'Rock');
    final related = track('related', genre: 'Rock');
    final recent = track('recent', genre: 'Rock');
    final selected = selectAutoplayTracks(
      seed: seed,
      candidates: [
        seed,
        related,
        related,
        recent,
        track('unrelated', artist: 'Other'),
        track('queued'),
        track('dismissed'),
        track('remote', source: 'https://example.com/audio.flac'),
        track('related', source: '/copy.flac', genre: 'Rock'),
      ],
      upcoming: [track('queued')],
      recent: [recent],
      dismissedSources: {'/dismissed.flac'},
      random: Random(1),
    );
    expect(selected.map((item) => item.id), ['unrelated', 'related', 'recent']);
  });

  test('a small Library never recommends the current song to itself', () {
    final seed = track('only');
    expect(
      selectAutoplayTracks(
        seed: seed,
        candidates: [seed],
        upcoming: [],
        recent: [seed],
        dismissedSources: {},
        random: Random(1),
      ),
      isEmpty,
    );
  });

  test('recency uses the latest source or normalized song match', () {
    final source = track('source-match', artist: 'A', source: '/same.flac');
    final song = track(' Song ', artist: ' ARTIST ');
    final older = track('older', artist: 'D');
    final unplayed = track('new', artist: 'E');
    final selected = selectAutoplayTracks(
      seed: track('seed', artist: 'Seed'),
      candidates: [source, song, older, unplayed],
      upcoming: [],
      recent: [
        track('source-match', artist: ' a ', source: '/copy.flac'),
        older,
        track(' song ', artist: 'artist', source: '/other.flac'),
        track('renamed', artist: 'different', source: '/same.flac'),
      ],
      dismissedSources: {},
      random: _NoNoise(),
    );
    expect(selected, [unplayed, older, song, source]);
  });

  test('bounded ranking retains its seeded ordering with a full history', () {
    PlayableMedia song(int id) => PlayableMedia(
      id: '$id',
      source: '/music/$id.flac',
      title: ' Song $id ',
      artist: ' Artist ${id % 24} ',
      album: ' Album ${id % 35} ',
      genre: ' Genre ${id % 8} ',
    );
    List<PlayableMedia> pick() => selectAutoplayTracks(
      seed: song(1000),
      candidates: List.generate(384, song),
      upcoming: [song(16), song(17)],
      recent: List.generate(200, (i) => song(i + 192)),
      dismissedSources: {'/music/18.flac'},
      random: Random(1),
    );
    final selected = pick();
    expect(selected.map((t) => t.id), pick().map((t) => t.id));
    expect(selected, hasLength(6));
    expect(selected.map((t) => t.source).toSet(), hasLength(6));
    expect(selected.every((t) => int.parse(t.id) < 192), isTrue);
    expect(
      selected.map((t) => t.id),
      isNot(anyElement(isIn(['16', '17', '18', '1000']))),
    );
    expect(selected.take(4).map((t) => t.artist).toSet(), hasLength(4));
  });

  test('Autoplay preference and recommendation provenance survive restore', () {
    expect(AppSettings.fromJson({}).autoplay, isFalse);
    final settings = const AppSettings().copyWith(autoplay: true);
    expect(AppSettings.fromJson(settings.toJson()).autoplay, isTrue);
    final media = PlayableMedia.fromJson({
      ...track('one', genre: 'Rock').toJson(),
      'autoplay': true,
    })!;
    final restored = PlayableMedia.fromJson(media.toJson())!;
    expect(restored.autoplay, isTrue);
    expect(restored.genre, 'Rock');
    expect(restored.toMediaItem().extras?['autoplay'], isTrue);
  });
}
