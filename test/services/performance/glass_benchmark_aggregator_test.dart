import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/performance/glass_benchmark_aggregator.dart';

const _budgetUs = 16667.0;

/// One frame at [endUs] with the given total span (raster is 60% of it).
void _frame(
  GlassBenchmarkAggregator a, {
  required int endUs,
  int spanUs = 10000,
}) {
  a.onFrame(
    buildUs: spanUs ~/ 3,
    rasterUs: spanUs * 6 ~/ 10,
    spanUs: spanUs,
    endUs: endUs,
  );
}

GlassBenchmarkAggregator _aggregator({int turns = 0, int capacity = 16384}) =>
    GlassBenchmarkAggregator(
      budgetUs: _budgetUs,
      turnsReader: () => turns,
      capacity: capacity,
    );

void main() {
  test('frames outside begin and end are ignored', () {
    final a = _aggregator();
    _frame(a, endUs: 1000); // before begin
    a.begin();
    _frame(a, endUs: 17000);
    _frame(a, endUs: 34000);
    a.end();
    _frame(a, endUs: 51000); // after end
    expect(a.summary(elapsedUs: 1000000).frames, 2);
  });

  test('percentiles and exceedance come from every frame in the interval', () {
    final a = _aggregator()..begin();
    // 90 frames of 10 ms and 10 frames of 30 ms (over the 16.7 ms budget).
    var t = 0;
    for (var i = 0; i < 90; i++) {
      t += 16000;
      _frame(a, endUs: t, spanUs: 10000);
    }
    for (var i = 0; i < 10; i++) {
      t += 16000;
      _frame(a, endUs: t, spanUs: 30000);
    }
    a.end();
    final s = a.summary(elapsedUs: 100 * 16000);
    expect(s.frames, 100);
    expect(s.spanP50Ms, closeTo(10, 0.01));
    expect(s.spanP90Ms, closeTo(10, 0.01));
    expect(s.spanP99Ms, closeTo(30, 0.01));
    expect(s.maxSpanMs, closeTo(30, 0.01));
    expect(s.exceedancePct, closeTo(10, 0.01));
  });

  test(
    'estimated production rate is labelled as an estimate from callbacks',
    () {
      final a = _aggregator()..begin();
      for (var i = 1; i <= 61; i++) {
        _frame(a, endUs: i * 16667);
      }
      a.end();
      final s = a.summary(elapsedUs: 61 * 16667);
      // 61 frames span 60 intervals of 16.667 ms.
      expect(s.estimatedProductionFps, closeTo(60, 0.05));
    },
  );

  test(
    'a long interval with no callbacks lowers coverage and counts a gap',
    () {
      final a = _aggregator()..begin();
      var t = 0;
      for (var i = 0; i < 30; i++) {
        t += 16667;
        _frame(a, endUs: t);
      }
      // No callbacks for 1.5 s: a stall the frame stream cannot show directly.
      t += 1500000;
      for (var i = 0; i < 30; i++) {
        t += 16667;
        _frame(a, endUs: t);
      }
      a.end();
      final s = a.summary(elapsedUs: t);
      expect(s.gapCount, 1);
      expect(s.maxGapMs, closeTo(1500 + 16.667, 0.5));
      // About 1.0 s of normal flow out of about 2.5 s of interval.
      expect(s.coverage, closeTo(0.4, 0.05));
    },
  );

  test('the worst five episodes are kept, longest first', () {
    final a = _aggregator()..begin();
    var t = 0;
    // Six episodes of increasing length, each 15 over-budget frames inside a
    // 30-frame window, then recovery.
    for (var e = 1; e <= 6; e++) {
      for (var k = 0; k < 15 + e * 5; k++) {
        t += 16000;
        _frame(a, endUs: t, spanUs: 30000);
      }
      for (var k = 0; k < 40; k++) {
        t += 16000;
        _frame(a, endUs: t, spanUs: 10000);
      }
    }
    a.end();
    final s = a.summary(elapsedUs: t);
    expect(s.episodeCount, 6);
    expect(s.worstEpisodes, hasLength(5));
    final durations = [for (final e in s.worstEpisodes) e.durationMs];
    expect(durations, [...durations]..sort((x, y) => y.compareTo(x)));
    expect(s.worstEpisodes.first.cause, 'unverified');
  });

  test('an episode still open at the end is closed and marked', () {
    final a = _aggregator()..begin();
    var t = 0;
    for (var k = 0; k < 40; k++) {
      t += 16000;
      _frame(a, endUs: t, spanUs: 30000);
    }
    a.end();
    final s = a.summary(elapsedUs: t);
    expect(s.episodeCount, 1);
    expect(s.worstEpisodes.single.openAtEnd, isTrue);
  });

  test('boundary reversals are attributed to the episode they fall in', () {
    var turns = 0;
    final a = GlassBenchmarkAggregator(
      budgetUs: _budgetUs,
      turnsReader: () => turns,
    )..begin();
    var t = 0;
    for (var k = 0; k < 40; k++) {
      t += 16000;
      if (k == 35) turns = 1; // inside the episode, which opens at frame 30
      _frame(a, endUs: t, spanUs: 30000);
    }
    a.end();
    expect(a.summary(elapsedUs: t).worstEpisodes.single.boundaryTurns, 1);
  });

  test(
    'frames past the buffer are counted as overflow, not dropped silently',
    () {
      final a = _aggregator(capacity: 10)..begin();
      for (var i = 1; i <= 25; i++) {
        _frame(a, endUs: i * 16000);
      }
      a.end();
      final s = a.summary(elapsedUs: 25 * 16000);
      expect(s.frames, 10);
      expect(s.overflow, 15);
    },
  );

  test('a new interval starts clean and keeps nothing from the last one', () {
    final a = _aggregator()..begin();
    for (var i = 1; i <= 50; i++) {
      _frame(a, endUs: i * 16000, spanUs: 30000);
    }
    a.end();
    expect(a.summary(elapsedUs: 50 * 16000).episodeCount, 1);

    a.begin();
    for (var i = 1; i <= 5; i++) {
      _frame(a, endUs: i * 16000);
    }
    a.end();
    final s = a.summary(elapsedUs: 5 * 16000);
    expect(s.frames, 5);
    expect(s.episodeCount, 0);
    expect(s.exceedancePct, 0);
  });

  test('an empty interval reports nothing measurable, not zero', () {
    final a = _aggregator()..begin();
    a.end();
    final s = a.summary(elapsedUs: 60000000);
    expect(s.frames, 0);
    expect(s.spanP90Ms, isNull);
    expect(s.exceedancePct, isNull);
    expect(s.estimatedProductionFps, isNull);
    expect(s.coverage, 0);
  });
}
