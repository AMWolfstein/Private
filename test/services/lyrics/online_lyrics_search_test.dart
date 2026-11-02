import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/lyrics/online_lyrics_search.dart';

class _FakeProvider implements OnlineLyricsProvider {
  _FakeProvider(
    this.id,
    this.bestTiming, {
    this.result,
    this.error,
    this.onAsk,
  });

  @override
  final String id;
  @override
  final LyricsTiming bestTiming;
  final OnlineLyricsCandidate? result;
  final Object? error;
  final void Function()? onAsk;
  int asked = 0;

  @override
  Future<OnlineLyricsCandidate?> find(OnlineLyricsQuery query) async {
    asked++;
    onAsk?.call();
    if (error != null) throw error!;
    return result;
  }
}

OnlineLyricsCandidate _word(String provider) => OnlineLyricsCandidate(
  provider: provider,
  timing: LyricsTiming.wordSynced,
  text: '[00:01.00]<00:01.00>Hi <00:01.50>there',
);

OnlineLyricsCandidate _line(String provider) => OnlineLyricsCandidate(
  provider: provider,
  timing: LyricsTiming.lineSynced,
  text: '[00:01.00]Hi there',
);

const _query = OnlineLyricsQuery(title: 'Song', artist: 'Artist');

void main() {
  group('LyricsTiming.detect', () {
    test('classifies from the text itself', () {
      expect(
        LyricsTiming.detect('[00:01.00]<00:01.00>Hi'),
        LyricsTiming.wordSynced,
      );
      expect(LyricsTiming.detect('[00:01.00]Hi'), LyricsTiming.lineSynced);
      expect(LyricsTiming.detect('Hi there\nagain'), LyricsTiming.plain);
    });

    test('a word tag alone is word-synced even without line tags', () {
      expect(LyricsTiming.detect('<00:01.00>Hi'), LyricsTiming.wordSynced);
    });
  });

  group('synced search', () {
    test('prefers word-synced over line-synced regardless of order', () async {
      final lineFirst = _FakeProvider(
        'line',
        LyricsTiming.lineSynced,
        result: _line('line'),
      );
      final word = _FakeProvider(
        'word',
        LyricsTiming.wordSynced,
        result: _word('word'),
      );
      final search = OnlineLyricsSearch([lineFirst, word]);

      final result = await search.findSynced(_query);

      expect(result.found, isTrue);
      expect(result.candidate!.provider, 'word');
      expect(result.candidate!.timing, LyricsTiming.wordSynced);
      expect(lineFirst.asked, 0, reason: 'line stage never reached');
    });

    test('falls back to line-synced when no word source has it', () async {
      final word = _FakeProvider('word', LyricsTiming.wordSynced);
      final line = _FakeProvider(
        'line',
        LyricsTiming.lineSynced,
        result: _line('line'),
      );
      final result = await OnlineLyricsSearch([word, line]).findSynced(_query);

      expect(result.found, isTrue);
      expect(result.candidate!.provider, 'line');
    });

    test('a plain result never counts as synced', () async {
      final plain = _FakeProvider(
        'plain',
        LyricsTiming.plain,
        result: const OnlineLyricsCandidate(
          provider: 'plain',
          timing: LyricsTiming.plain,
          text: 'Hi there',
        ),
      );
      final result = await OnlineLyricsSearch([plain]).findSynced(_query);

      expect(result.found, isFalse);
      expect(result.outcome, OnlineLyricsOutcome.notFound);
    });

    test(
      'a word-synced source that returns only line text is asked once',
      () async {
        final source = _FakeProvider(
          'mixed',
          LyricsTiming.wordSynced,
          result: _line('mixed'),
        );
        final result = await OnlineLyricsSearch([source]).findSynced(_query);

        expect(result.found, isTrue);
        expect(result.candidate!.timing, LyricsTiming.lineSynced);
        expect(source.asked, 1);
      },
    );

    test(
      'an unreachable source is reported and the search continues',
      () async {
        final down = _FakeProvider(
          'down',
          LyricsTiming.wordSynced,
          error: Exception('timeout'),
        );
        final up = _FakeProvider(
          'up',
          LyricsTiming.lineSynced,
          result: _line('up'),
        );
        final result = await OnlineLyricsSearch([down, up]).findSynced(_query);

        expect(result.found, isTrue);
        expect(result.failedProviders, ['down']);
      },
    );

    test(
      'reports notFound, not failure, when everything answers empty',
      () async {
        final result = await OnlineLyricsSearch([
          _FakeProvider('a', LyricsTiming.wordSynced),
          _FakeProvider('b', LyricsTiming.lineSynced),
        ]).findSynced(_query);

        expect(result.outcome, OnlineLyricsOutcome.notFound);
        expect(result.failedProviders, isEmpty);
      },
    );

    test('stops when cancelled between providers', () async {
      var cancelled = false;
      final first = _FakeProvider(
        'first',
        LyricsTiming.wordSynced,
        onAsk: () => cancelled = true,
      );
      final second = _FakeProvider(
        'second',
        LyricsTiming.wordSynced,
        result: _word('second'),
      );
      final result = await OnlineLyricsSearch([
        first,
        second,
      ]).findSynced(_query, isCancelled: () => cancelled);

      expect(result.outcome, OnlineLyricsOutcome.cancelled);
      expect(second.asked, 0);
    });
  });

  group('plain search', () {
    test('accepts plain text after the user agrees', () async {
      final result = await OnlineLyricsSearch([
        _FakeProvider(
          'genius',
          LyricsTiming.plain,
          result: const OnlineLyricsCandidate(
            provider: 'genius',
            timing: LyricsTiming.plain,
            text: 'Hi there',
          ),
        ),
      ]).findPlain(_query);

      expect(result.found, isTrue);
      expect(result.candidate!.timing, LyricsTiming.plain);
    });
  });
}
