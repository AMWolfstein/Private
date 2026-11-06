import 'package:flutter_test/flutter_test.dart';
import 'package:mornye/models/settings.dart';
import 'package:mornye/services/performance/performance_recorder.dart';

void main() {
  PerformanceRecorder recorder({int window = 10000}) => PerformanceRecorder()
    ..configure(
      enabled: true,
      firstInteraction: true,
      windowMs: window,
      idleMs: 3000,
      nowUs: 0,
    );
  void frame(
    PerformanceRecorder r,
    int engine, {
    int? receipt,
    double build = 2,
    double raster = 3,
    double? budget = 16.67,
  }) => r.addFrame(
    observedUs: receipt ?? engine,
    engineUs: engine,
    buildMs: build,
    rasterMs: raster,
    spanMs: build + raster + 1,
    budgetMs: budget,
  );
  test(
    'percentiles interpolate, reject nonfinite data, handle empty/single',
    () {
      expect(performancePercentile([], .95), isNull);
      expect(performancePercentile([9], .99), 9);
      expect(performancePercentile([4, 1, 3, 2, double.nan], .5), 2.5);
      expect(performancePercentile([0, 100], .95), 95);
    },
  );
  test(
    'engine gaps are independent of batched receipt times and idle is not jank',
    () {
      final r = recorder();
      frame(r, 1000, receipt: 9000000);
      frame(r, 17667, receipt: 9000000);
      frame(r, 5017667, receipt: 9000000);
      final s = r.snapshot(9000000);
      expect(s.frames[0].gapMs, isNull);
      expect(s.frames[1].gapMs, 16.667);
      expect(s.percentile('gap', 1), 5000);
      expect(s.slow, 0);
      expect(s.jankPercent, 0);
    },
  );
  test(
    'jank uses max build/raster and reported budget, not sum or missing data',
    () {
      final r = recorder();
      frame(r, 1, build: 6, raster: 6, budget: 8.33);
      frame(r, 2, raster: 10, budget: 8.33);
      frame(r, 3, build: 100, budget: null);
      final s = r.snapshot(1000000);
      expect(s.slow, 1);
      expect(s.classified, 2);
      expect(s.jankPercent, 50);
    },
  );
  test(
    'rolling windows prune and cap samples, screen changes reset denominator',
    () {
      final r = recorder(window: 1000);
      frame(r, 1);
      frame(r, 1000001);
      frame(r, 1000002);
      expect(r.snapshot(1000002).frames.length, 2);
      expect(r.snapshot(3000000).frames, isEmpty);
      for (var i = 0; i < 17000; i++) {
        frame(r, 3000000 + i);
      }
      expect(r.snapshot(3017000).frames.length, PerformanceRecorder.maxFrames);
      r.changeScreen('library', 3017000);
      frame(r, 3517000);
      final s = r.snapshot(4017000);
      expect(s.screen, 'library');
      expect(s.durationMs, 1000);
      expect(s.fps, 1);
    },
  );
  test(
    'stopping freezes measurements and previous screens remain exportable',
    () {
      final r = recorder();
      r.changeScreen('home', 0);
      frame(r, 1000000);
      r.configure(
        enabled: false,
        firstInteraction: false,
        windowMs: 10000,
        idleMs: 3000,
        nowUs: 2000000,
      );
      expect(r.snapshot(90000000).frames.length, 1);
      expect(r.snapshot(90000000).fps, .5);
      r.changeScreen('/settings/app/performance', 90000000);
      expect(r.recentSnapshots['home']!.fps, .5);
      expect(r.recentSnapshots['home']!.frames.length, 1);
      r.reset(90000000);
      expect(r.recentSnapshots, isEmpty);
      expect(r.snapshot(90000000).frames, isEmpty);
    },
  );
  test('archived screen windows have a fixed count limit', () {
    final r = recorder();
    for (var i = 0; i < 12; i++) {
      frame(r, i * 10000 + 1);
      r.changeScreen('screen_$i', i * 10000 + 2);
    }
    expect(r.recentSnapshots.length, 8);
    expect(r.recentSnapshots.containsKey('unavailable'), false);
  });
  test(
    'idle detection observes activity and captures only the next bounded window',
    () {
      final r = recorder();
      final utc = DateTime.utc(2026);
      expect(r.pointer(2000000, utc), isFalse);
      expect(r.pointer(4999000, utc), isFalse);
      expect(r.pointer(8000000, utc, eventUs: 123456), isTrue);
      expect(r.activeInteraction!.idleMs, 3001);
      expect(r.activeInteraction!.pointerEventUs, 123456);
      r.observeInteractionFrame(8010000, 20000000);
      frame(r, 19999999, receipt: 8020000); // earlier batched frame
      frame(r, 20000000, receipt: 8020000);
      frame(r, 20990001, receipt: 9000000); // outside pointer + 1000ms
      expect(r.activeInteraction!.frames.length, 1);
      expect(r.activeInteraction!.firstFrameObservedUs, 8010000);
      r.finishInteraction();
      expect(r.activeInteraction, isNull);
      expect(r.lastInteractionUtc, utc);
    },
  );
  test(
    'late release timing delivery still fills the bounded interaction window',
    () {
      final r = recorder();
      r.pointer(4000000, DateTime.utc(2026));
      r.observeInteractionFrame(4010000, 50000000);
      r.finishInteraction();
      frame(r, 50000000, receipt: 7000000);
      frame(r, 51000000, receipt: 7000000);
      expect(r.interactions.single.frames.length, 1);
    },
  );
  test(
    'no frame after interaction remains unavailable; disabling stops capture',
    () {
      final r = recorder();
      r.pointer(4000000, DateTime.utc(2026));
      r.observeInteractionFrame(5000001, 123);
      expect(r.activeInteraction!.firstFrameObservedUs, isNull);
      r.configure(
        enabled: false,
        firstInteraction: true,
        windowMs: 10000,
        idleMs: 3000,
        nowUs: 6000000,
      );
      frame(r, 6000001);
      expect(r.snapshot(7000000).frames, isEmpty);
      expect(r.activeInteraction, isNull);
    },
  );
  test(
    'active display rate controls budget independently of request and transitions',
    () {
      final d = PerformanceDisplay({
        'requested_hz': 60,
        'active_hz': 120,
        'transition_count': 2,
        'changes': [
          {'at_ms': 1, 'hz': 120},
        ],
      });
      expect(d.budgetMs, closeTo(8.3333, .001));
      expect(d.transitions, 2);
      expect(
        PerformanceDisplay({'active_hz': 60}).budgetMs,
        closeTo(16.6667, .001),
      );
      expect(PerformanceDisplay().budgetMs, isNull);
      expect(PerformanceDisplay().transitions, isNull);
    },
  );
  test(
    'report uses real numbers, unavailable values and explicit limitations',
    () {
      final r = recorder();
      frame(r, 10000);
      final report = formatPerformanceReport(
        snapshot: r.snapshot(1000000),
        display: PerformanceDisplay(),
        build: 'release',
        abi: 'arm64-v8a',
        flutterHz: '90.00',
        enabled: true,
        interactions: [],
      );
      expect(
        report,
        startsWith('mornye-performance\nbuild=release\nabi=arm64-v8a'),
      );
      expect(report, contains('reported_hz=unavailable'));
      expect(report, contains('refresh_transition_count=unavailable'));
      expect(report, contains('fps_rendered=1.00'));
      expect(report, contains('first_interaction_frame_delay_ms=unavailable'));
      expect(report, contains('presentation_latency=unavailable'));
      expect(report, contains('glass_mode=original_mornye'));
    },
  );
  test(
    'new preferences default off and survive existing settings JSON/copyWith',
    () {
      final s = AppSettings.fromJson({});
      expect(s.performanceMonitoring, false);
      expect(s.performanceHud, false);
      expect(s.performanceFirstInteraction, false);
      expect(s.performanceIdleMs, 3000);
      final changed = s.copyWith(
        performanceMonitoring: true,
        performanceHud: true,
        performanceFirstInteraction: true,
        performanceIdleMs: 5000,
        performanceWindowMs: 30000,
      );
      final restored = AppSettings.fromJson(changed.toJson());
      expect(restored.performanceMonitoring, true);
      expect(restored.performanceHud, true);
      expect(restored.performanceFirstInteraction, true);
      expect(restored.performanceIdleMs, 5000);
      expect(restored.performanceWindowMs, 30000);
      expect(restored.audioQuality, s.audioQuality);
    },
  );
}
