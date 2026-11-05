import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/performance/glass_frame_schedule.dart';
import 'package:sistrum/services/performance/glass_series_stats.dart';

void main() {
  // 60 Hz nominal period.
  const period = 16667;

  void feed(
    GlassFrameScheduleRecorder r,
    List<int> vsyncStarts, {
    int rasterOffset = 9000,
  }) {
    for (final v in vsyncStarts) {
      r.onFrameTiming(vsyncStartUs: v, rasterFinishUs: v + rasterOffset);
    }
  }

  test('a steady 60 Hz cadence has no long intervals and no missed slots', () {
    final r = GlassFrameScheduleRecorder(nominalPeriodUs: period);
    feed(r, [for (var i = 0; i < 20; i++) i * period]);
    final s = r.summary();
    expect(s.vsync.count, 19);
    expect(s.vsync.p50, closeTo(16.667, 0.001));
    expect(s.longVsyncIntervals, 0);
    expect(s.missedSlots, 0);
    expect(s.impliedVsyncHz, closeTo(60, 0.01));
    expect(s.raster.p50, closeTo(16.667, 0.001));
  });

  test('a two-period gap is one missed slot and counts as long', () {
    final r = GlassFrameScheduleRecorder(nominalPeriodUs: period);
    feed(r, [0, period, 3 * period, 4 * period]);
    final s = r.summary();
    expect(s.longVsyncIntervals, 1);
    expect(s.missedSlots, 1);
  });

  test('a three-period gap skips two slots', () {
    final r = GlassFrameScheduleRecorder(nominalPeriodUs: period);
    feed(r, [0, 4 * period]);
    final s = r.summary();
    expect(s.missedSlots, 3);
    expect(s.longVsyncIntervals, 1);
  });

  test('a cadence near 45 Hz shows an implied rate near 45, not 60', () {
    final period45 = 1000000 ~/ 45;
    final r = GlassFrameScheduleRecorder(nominalPeriodUs: period);
    feed(r, [for (var i = 0; i < 40; i++) i * period45]);
    final s = r.summary();
    expect(s.impliedVsyncHz, closeTo(45, 0.1));
    // Each 22 ms interval is 1.3 nominal periods: long by the rule, but not a
    // missed slot (it rounds to one period).
    expect(s.missedSlots, 0);
  });

  test(
    'callback batches and frame begins are counted on the delivery clock',
    () {
      final r = GlassFrameScheduleRecorder(nominalPeriodUs: period);
      r.onBeginFrame();
      r.onBeginFrame();
      r.onBeginFrame();
      r.onTimingsArrived(2);
      r.onTimingsArrived(1);
      final s = r.summary();
      expect(s.beginEvents, 3);
      expect(s.batches, 2);
      expect(s.timings, 3);
      expect(s.begin.count, 2);
      expect(s.arrival.count, 1);
      expect(s.begin.p50, isNotNull);
    },
  );

  test(
    'the report labels the clocks, and the two series are kept separate',
    () {
      expect(kGlassClockEngine, contains('engine'));
      expect(kGlassClockDelivery, contains('Stopwatch'));
    },
  );

  test('buffers keep a bounded window and count what does not fit', () {
    final b = GlassSeriesBuffer(3);
    for (var i = 1; i <= 5; i++) {
      b.add(i * 1000);
    }
    final s = b.stats();
    expect(s.count, 3);
    expect(s.overflow, 2);
    expect(s.max, 3);
  });

  test('percentiles use nearest rank and an empty series has no values', () {
    final b = GlassSeriesBuffer(100);
    for (var i = 1; i <= 100; i++) {
      b.add(i * 1000);
    }
    final s = b.stats();
    expect(s.p50, 50);
    expect(s.p90, 90);
    expect(s.p99, 99);
    final empty = GlassSeriesBuffer(4).stats();
    expect(empty, isA<GlassSeriesStats>());
    expect(empty.count, 0);
    expect(empty.p50, isNull);
  });

  group('frame phases', () {
    test('each phase is the difference of its two timestamps, in ms', () {
      final r = GlassFrameScheduleRecorder(nominalPeriodUs: 16667);
      // vsync 0 -> build start 1 ms -> build finish 4 ms -> raster start 6 ms
      // -> raster finish 10 ms (all engine microseconds).
      for (var i = 0; i < 5; i++) {
        final base = i * 16667;
        r.onFramePhases(
          vsyncStartUs: base,
          buildStartUs: base + 1000,
          buildFinishUs: base + 4000,
          rasterStartUs: base + 6000,
          rasterFinishUs: base + 10000,
        );
      }
      final p = r.summary().phases;
      expect(p.vsyncToBuildStart.p50, closeTo(1.0, 1e-9));
      expect(p.build.p50, closeTo(3.0, 1e-9));
      expect(p.buildFinishToRasterStart.p50, closeTo(2.0, 1e-9));
      expect(p.rasterSlice.p50, closeTo(4.0, 1e-9));
      expect(p.rasterSlice.count, 5);
      expect(p.invalidSamples, 0);
      expect(p.zeroRasterSlices, 0);
    });

    test('a negative difference is dropped from its series and counted', () {
      final r = GlassFrameScheduleRecorder(nominalPeriodUs: 16667);
      // raster starts before the UI finished building: an ordering the
      // definitions do not expect. Only the queue-wait sample is dropped.
      r.onFramePhases(
        vsyncStartUs: 0,
        buildStartUs: 1000,
        buildFinishUs: 5000,
        rasterStartUs: 4000,
        rasterFinishUs: 9000,
      );
      final p = r.summary().phases;
      expect(p.buildFinishToRasterStart.count, 0);
      expect(p.invalidSamples, 1);
      expect(p.rasterSlice.count, 1);
      expect(p.build.count, 1);
    });

    test('zero-length raster slices are counted, not dropped', () {
      final r = GlassFrameScheduleRecorder(nominalPeriodUs: 16667);
      r.onFramePhases(
        vsyncStartUs: 0,
        buildStartUs: 500,
        buildFinishUs: 900,
        rasterStartUs: 1000,
        rasterFinishUs: 1000,
      );
      r.onFramePhases(
        vsyncStartUs: 16667,
        buildStartUs: 17167,
        buildFinishUs: 17500,
        rasterStartUs: 18000,
        rasterFinishUs: 22000,
      );
      final p = r.summary().phases;
      expect(p.zeroRasterSlices, 1);
      expect(p.rasterSlice.count, 2);
    });

    test('a summary without frames reports no phase samples', () {
      final s = GlassFrameScheduleRecorder(nominalPeriodUs: 16667).summary();
      expect(s.phases.rasterSlice.count, 0);
      expect(s.phases.rasterSlice.p90, isNull);
      expect(s.phases.invalidSamples, 0);
    });
  });
}
