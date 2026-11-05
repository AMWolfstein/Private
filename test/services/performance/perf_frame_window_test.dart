import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/performance/perf_frame_window.dart';

void _add(
  PerfFrameWindow window, {
  required int buildUs,
  required int rasterUs,
  int? spanUs,
  required int endUs,
}) => window.add(
  buildUs: buildUs,
  rasterUs: rasterUs,
  spanUs: spanUs ?? buildUs + rasterUs,
  endUs: endUs,
);

void main() {
  test('an empty window reports nothing measurable, not zero', () {
    final snapshot = PerfFrameWindow().snapshot(hz: 60, hzIsFallback: true);
    expect(snapshot.frames, 0);
    expect(snapshot.buildP50Ms, isNull);
    expect(snapshot.rasterP99Ms, isNull);
    expect(snapshot.exceedancePct, isNull);
    expect(snapshot.fpsEstimate, isNull);
    expect(snapshot.windowMs, isNull);
    expect(snapshot.budgetMs, closeTo(16.667, 0.001));
  });

  test('the window keeps only the newest capacity frames', () {
    final window = PerfFrameWindow(capacity: 3);
    for (var i = 1; i <= 5; i++) {
      _add(window, buildUs: i * 1000, rasterUs: 1000, endUs: i * 16000);
    }
    final snapshot = window.snapshot(hz: 60, hzIsFallback: false);
    expect(window.count, 3);
    expect(snapshot.frames, 3);
    expect(snapshot.totalFrames, 5);
    // Frames 3, 4 and 5 remain: build 3, 4, 5 ms.
    expect(snapshot.buildP50Ms, 4);
    expect(snapshot.buildP99Ms, 5);
  });

  test('percentiles use nearest rank over the sorted window', () {
    final window = PerfFrameWindow(capacity: 10);
    for (var i = 1; i <= 10; i++) {
      _add(window, buildUs: i * 1000, rasterUs: (11 - i) * 1000, endUs: i);
    }
    final snapshot = window.snapshot(hz: 60, hzIsFallback: false);
    expect(snapshot.buildP50Ms, 5);
    expect(snapshot.buildP90Ms, 9);
    expect(snapshot.buildP99Ms, 10);
    // Raster values are 10 down to 1 ms, so the sorted list is 1 to 10.
    expect(snapshot.rasterP50Ms, 5);
    expect(snapshot.rasterP90Ms, 9);
    expect(snapshot.rasterP99Ms, 10);
  });

  test(
    'frame-budget exceedance counts frames whose span passes the budget',
    () {
      final window = PerfFrameWindow(capacity: 4);
      _add(window, buildUs: 1000, rasterUs: 1000, spanUs: 10000, endUs: 1);
      _add(window, buildUs: 1000, rasterUs: 1000, spanUs: 17000, endUs: 2);
      _add(window, buildUs: 1000, rasterUs: 1000, spanUs: 33000, endUs: 3);
      _add(window, buildUs: 1000, rasterUs: 1000, spanUs: 16000, endUs: 4);
      final snapshot = window.snapshot(hz: 60, hzIsFallback: false);
      expect(snapshot.exceedancePct, 50);
    },
  );

  test('fps is estimated from frame end spacing and needs two frames', () {
    final window = PerfFrameWindow(capacity: 10);
    _add(window, buildUs: 1000, rasterUs: 1000, endUs: 0);
    expect(window.snapshot(hz: 60, hzIsFallback: false).fpsEstimate, isNull);
    for (var i = 1; i <= 60; i++) {
      _add(window, buildUs: 1000, rasterUs: 1000, endUs: i * 16667);
    }
    final snapshot = window.snapshot(hz: 60, hzIsFallback: false);
    // Ten frames in the window span nine intervals of 16667 us.
    expect(snapshot.fpsEstimate, closeTo(60, 0.01));
    expect(snapshot.windowMs, closeTo(9 * 16.667, 0.01));
  });

  test('reset clears the window and every derived statistic', () {
    final window = PerfFrameWindow(capacity: 4);
    for (var i = 1; i <= 4; i++) {
      _add(window, buildUs: 5000, rasterUs: 5000, endUs: i * 1000);
    }
    window.reset();
    final snapshot = window.snapshot(hz: 60, hzIsFallback: false);
    expect(window.count, 0);
    expect(snapshot.totalFrames, 0);
    expect(snapshot.buildP50Ms, isNull);
    expect(snapshot.exceedancePct, isNull);
  });

  test('refresh rate uses a reported value and falls back otherwise', () {
    final reported = resolvePerfRefreshRate(120);
    expect(reported.hz, 120);
    expect(reported.isFallback, isFalse);
    for (final unknown in <double?>[null, 0, -1, 5, 1000, double.nan]) {
      final fallback = resolvePerfRefreshRate(unknown);
      expect(fallback.hz, kPerfFallbackHz, reason: 'for $unknown');
      expect(fallback.isFallback, isTrue, reason: 'for $unknown');
    }
  });

  test('the report labels estimates and writes n/a for missing values', () {
    final empty = PerfFrameWindow().snapshot(hz: 60, hzIsFallback: true);
    final report = formatPerfReport(screen: 'home', snapshot: empty);
    expect(report, startsWith('sistrum-perf\nscreen=home\nhz=60\n'));
    expect(report, contains('hz_source=fallback'));
    expect(report, contains('budget=16.67ms'));
    expect(report, contains('frames=0'));
    expect(report, contains('build_ms_p50=n/a'));
    expect(report, contains('frame_budget_exceedance=n/a%'));
    expect(report, contains('fps_estimate=n/a (estimated)'));
  });

  test('the report carries measured values for a filled window', () {
    final window = PerfFrameWindow(capacity: 3);
    _add(window, buildUs: 2000, rasterUs: 3000, endUs: 0);
    _add(window, buildUs: 4000, rasterUs: 6000, spanUs: 20000, endUs: 16667);
    _add(window, buildUs: 6000, rasterUs: 9000, endUs: 33334);
    final report = formatPerfReport(
      screen: 'library',
      snapshot: window.snapshot(hz: 60, hzIsFallback: false),
    );
    expect(report, contains('hz_source=reported'));
    expect(report, contains('frames=3'));
    expect(report, contains('build_ms_p50=4.00'));
    expect(report, contains('raster_ms_p90=9.00'));
    expect(report, contains('frame_budget_exceedance=33.3%'));
    expect(report, contains('window=rolling'));
  });

  test('the report names the selected Glass POC mode when one is given', () {
    final empty = PerfFrameWindow().snapshot(hz: 60, hzIsFallback: true);
    final labelled = formatPerfReport(
      screen: 'developer-options',
      snapshot: empty,
      glassMode: 'Reference Glass',
    );
    expect(labelled, endsWith('\nglass_mode=Reference Glass'));
    final plain = formatPerfReport(screen: 'home', snapshot: empty);
    expect(plain, isNot(contains('glass_mode=')));
  });
}
