import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/lyrics/online_lyrics_search.dart';

class _FakeProvider implements OnlineLyricsProvider {
  _FakeProvider(this.id, {this.result, this.error});

  @override
  final String id;
  final OnlineLyricsCandidate? result;
  final Object? error;
  int asked = 0;

  @override
  Future<OnlineLyricsCandidate?> find(OnlineLyricsQuery query) async {
    asked++;
    if (error != null) throw error!;
    return result;
  }
}

class _PendingProvider implements OnlineLyricsProvider {
  _PendingProvider(this.id);
  @override
  final String id;
  final pending = Completer<OnlineLyricsCandidate?>();
  @override
  Future<OnlineLyricsCandidate?> find(OnlineLyricsQuery query) =>
      pending.future;
}

OnlineLyricsCandidate _word(String provider) => OnlineLyricsCandidate(
  provider: provider,
  timing: LyricsTiming.wordSynced,
  text: '[00:01.00]<00:01.00>Hi <00:01.50>there',
  title: 'Song',
  artist: 'Artist',
  durationSeconds: 200,
);

OnlineLyricsCandidate _line(String provider) => OnlineLyricsCandidate(
  provider: provider,
  timing: LyricsTiming.lineSynced,
  text: '[00:01.00]Hi there',
);

OnlineLyricsCandidate _plain(String provider) => OnlineLyricsCandidate(
  provider: provider,
  timing: LyricsTiming.plain,
  text: 'Hi there',
);

const _query = OnlineLyricsQuery(title: 'Song', artist: 'Artist');

void main() {
  test('timing is classified from the text, never from the source', () {
    expect(LyricsTiming.detect(_word('x').text), LyricsTiming.wordSynced);
    expect(LyricsTiming.detect(_line('x').text), LyricsTiming.lineSynced);
    expect(LyricsTiming.detect('Just words'), LyricsTiming.plain);
  });

  test('every source is asked once and each match is kept', () async {
    final sources = [
      _FakeProvider('musixmatch', result: _word('musixmatch')),
      _FakeProvider('lrclib', result: _line('lrclib')),
      _FakeProvider('genius', result: _plain('genius')),
    ];
    final result = await OnlineLyricsSearch(sources).searchAll(_query);

    expect(result.candidates.map((c) => c.provider), [
      'musixmatch',
      'lrclib',
      'genius',
    ]);
    expect(result.failedProviders, isEmpty);
    expect(sources.map((s) => s.asked), everyElement(1));
  });

  test('results are grouped by their own timing', () async {
    final result = await OnlineLyricsSearch([
      _FakeProvider('genius', result: _plain('genius')),
      _FakeProvider('lrclib', result: _line('lrclib')),
      _FakeProvider('musixmatch', result: _word('musixmatch')),
    ]).searchAll(_query);

    expect(result.withTiming(LyricsTiming.wordSynced).map((c) => c.provider), [
      'musixmatch',
    ]);
    expect(result.withTiming(LyricsTiming.lineSynced).map((c) => c.provider), [
      'lrclib',
    ]);
    expect(result.withTiming(LyricsTiming.plain).map((c) => c.provider), [
      'genius',
    ]);
  });

  test('a source that throws is listed as failed, not as a miss', () async {
    final result = await OnlineLyricsSearch([
      _FakeProvider('spotify', error: Exception('down')),
      _FakeProvider('lrclib', result: _line('lrclib')),
      _FakeProvider('netease'),
    ]).searchAll(_query);

    expect(result.failedProviders, ['spotify']);
    expect(result.candidates.map((c) => c.provider), ['lrclib']);
  });

  test('a source with no match adds nothing', () async {
    final result = await OnlineLyricsSearch([
      _FakeProvider('netease'),
    ]).searchAll(_query);

    expect(result.candidates, isEmpty);
    expect(result.failedProviders, isEmpty);
  });

  test('a match keeps the song details its source reported', () async {
    final result = await OnlineLyricsSearch([
      _FakeProvider('musixmatch', result: _word('musixmatch')),
    ]).searchAll(_query);

    final candidate = result.candidates.single;
    expect(candidate.title, 'Song');
    expect(candidate.artist, 'Artist');
    expect(candidate.durationSeconds, 200);
  });
  test(
    'fast results are exposed before a stalled source and cancellation rejects late replies',
    () async {
      final stalled = _PendingProvider('stalled');
      final token = LyricsSearchCancellation();
      final fastArrived = Completer<void>();
      var updates = 0;
      final pending =
          OnlineLyricsSearch([
            stalled,
            _FakeProvider('fast', result: _line('fast')),
          ]).searchAll(
            _query,
            cancellation: token,
            onProgress: (snapshot) {
              updates++;
              if (snapshot.candidates.isNotEmpty && !fastArrived.isCompleted) {
                fastArrived.complete();
              }
            },
          );
      await fastArrived.future;
      expect(stalled.pending.isCompleted, isFalse);
      token.cancel();
      final result = await pending;
      expect(result.candidates.single.provider, 'fast');
      final delivered = updates;
      stalled.pending.complete(_line('stalled'));
      await Future<void>.delayed(Duration.zero);
      expect(updates, delivered);
    },
  );
  test(
    'a stalled source reaches its deadline without holding other results',
    () async {
      final stalled = _PendingProvider('stalled');
      final result = await OnlineLyricsSearch([
        stalled,
        _FakeProvider('fast', result: _line('fast')),
      ]).searchAll(_query, timeout: const Duration(milliseconds: 20));
      expect(result.failedProviders, ['stalled']);
      expect(result.candidates.single.provider, 'fast');
      stalled.pending.complete(null);
    },
  );
}
