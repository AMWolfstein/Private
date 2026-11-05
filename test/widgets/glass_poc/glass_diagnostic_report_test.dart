import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/performance/glass_benchmark_aggregator.dart';
import 'package:sistrum/services/performance/glass_frame_schedule.dart';
import 'package:sistrum/services/performance/glass_series_stats.dart';
import 'package:sistrum/widgets/glass_poc/glass_benchmark_report.dart';
import 'package:sistrum/widgets/glass_poc/glass_benchmark_runner.dart';
import 'package:sistrum/widgets/glass_poc/glass_diagnostic_stats.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_mode.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_render_path.dart';

const _empty = GlassSeriesStats(
  count: 0,
  overflow: 0,
  p50: null,
  p90: null,
  p99: null,
  max: null,
);

/// A measured result whose raster P90 is [rasterMs]. Every frame is over the
/// 16.7 ms budget when [over] is true, so the exceedance follows the input.
GlassBenchmarkModeResult _result({
  required SistrumGlassMode mode,
  required int surfaces,
  required int repeat,
  required int order,
  required double rasterMs,
  GlassBenchmarkValidity validity = GlassBenchmarkValidity.valid,
  double? vsyncP50Ms,
  double? refreshStartHz = 60,
  double? refreshEndHz = 60,
}) {
  final a = GlassBenchmarkAggregator(budgetUs: 16667, turnsReader: () => 0)
    ..begin();
  var t = 0;
  final raster = (rasterMs * 1000).round();
  for (var i = 0; i < 300; i++) {
    t += 16667;
    a.onFrame(buildUs: 2000, rasterUs: raster, spanUs: raster + 2000, endUs: t);
  }
  a.end();
  final schedule = GlassFrameScheduleSummary(
    nominalPeriodMs: 16.667,
    beginEvents: 300,
    batches: 300,
    timings: 300,
    longVsyncIntervals: 0,
    missedSlots: 0,
    begin: _empty,
    arrival: _empty,
    vsync: vsyncP50Ms == null
        ? _empty
        : GlassSeriesStats(
            count: 299,
            overflow: 0,
            p50: vsyncP50Ms,
            p90: vsyncP50Ms,
            p99: vsyncP50Ms,
            max: vsyncP50Ms,
          ),
    raster: _empty,
  );
  return GlassBenchmarkModeResult(
    refreshHzStart: refreshStartHz,
    refreshHzEnd: refreshEndHz,
    mode: mode,
    surfaces: surfaces,
    repeat: repeat,
    runOrder: order,
    validity: validity,
    reasons: validity == GlassBenchmarkValidity.valid
        ? const []
        : const ['test reason'],
    measurementStarted: true,
    summary: a.summary(elapsedUs: t),
    expectedPath: SistrumGlassRenderPath.fullGpu,
    pathSamples: 1,
    pathMatches: 1,
    lastPath: 'full_gpu',
    fallbackSeen: false,
    scrollOverallPxPerSecond: 897,
    scrollMeasuredSeconds: 60,
    boundaryTurns: 2,
    scrollDirection: 'down',
    frameBegins: 300,
    frameTimings: 300,
    schedule: schedule,
  );
}

void main() {
  group('repeat statistics', () {
    test('median, min, max and range over repeats', () {
      final s = GlassRepeatStats.of([3, 1, 2])!;
      expect(s.median, 2);
      expect(s.min, 1);
      expect(s.max, 3);
      expect(s.range, 2);
      final even = GlassRepeatStats.of([1, 2, 3, 4])!;
      expect(even.median, 2.5);
    });

    test('an empty set has no statistics and one repeat has no spread', () {
      expect(GlassRepeatStats.of(const []), isNull);
      expect(GlassRepeatStats.of([5])!.cvPercent, isNull);
      expect(GlassRepeatStats.of([10, 10, 10])!.cvPercent, 0);
    });

    test('steps count as separated only when every repeat is above', () {
      final low = GlassRepeatStats.of([10, 11, 12])!;
      final high = GlassRepeatStats.of([13, 14, 15])!;
      final overlap = GlassRepeatStats.of([11, 13, 16])!;
      expect(glassStepsSeparated(low, high), isTrue);
      expect(glassStepsSeparated(low, overlap), isFalse);
    });
  });

  group('diagnostic report', () {
    final plan = GlassBenchmarkPlan.diagnostic(
      timing: GlassBenchmarkPlan(warmup: const Duration(seconds: 5)),
    );

    String render(
      List<GlassBenchmarkModeResult> results, {
      String status = 'COMPLETE',
    }) => formatGlassDiagnosticReport(
      status: status,
      deviceLines: const ['os=android 14', 'build_mode=profile'],
      reportedHz: 60,
      plan: plan,
      startedAt: DateTime.utc(2026, 11, 5, 10),
      endedAt: DateTime.utc(2026, 11, 5, 11),
      cancelReason: null,
      failure: null,
      results: results,
    );

    test(
      'every section is present, with the clock labels and thermal line',
      () {
        final text = render([
          _result(
            mode: SistrumGlassMode.transparentBaseline,
            surfaces: 4,
            repeat: 1,
            order: 1,
            rasterMs: 5,
          ),
        ]);
        for (final section in [
          '== 1. Device, build and clocks ==',
          '== 2. Executed order and validity ==',
          '== 3. VSync and frame production (valid runs) ==',
          '== 4. Per-run performance (valid runs) ==',
          '== 5. Repeatability per configuration (valid repeats only) ==',
          '== 6. Layer-count scaling: New Full Glass ==',
          '== 7. Frame-rate evidence (44.9 frames/s pattern) ==',
          '== 8. Conclusions (evidence only; computed from valid runs) ==',
          '== 9. Unresolved questions ==',
        ]) {
          expect(text, contains(section));
        }
        expect(text, contains('clock_engine='));
        expect(text, contains('clock_delivery='));
        expect(text, contains('thermal_state=not accessible from Dart'));
      },
    );

    test(
      'invalid runs are listed, excluded from statistics and not replaced',
      () {
        final text = render([
          _result(
            mode: SistrumGlassMode.newFullGlass,
            surfaces: 4,
            repeat: 1,
            order: 1,
            rasterMs: 10,
          ),
          _result(
            mode: SistrumGlassMode.newFullGlass,
            surfaces: 4,
            repeat: 2,
            order: 2,
            rasterMs: 90,
            validity: GlassBenchmarkValidity.invalid,
          ),
        ]);
        expect(text, contains('invalid=1'));
        expect(text, contains('No run was replaced or retried'));
        expect(text, contains('  reason: test reason'));
        // The 90 ms run is invalid, so the median is over one valid run only.
        expect(text, contains('config=New Full Glass (4 surfaces) valid=1/2'));
        expect(text, contains('raster_p90_ms median=10.00'));
      },
    );

    test('scaling is judged separated only when every step is', () {
      final separated = render([
        _result(
          mode: SistrumGlassMode.newFullGlass,
          surfaces: 1,
          repeat: 1,
          order: 1,
          rasterMs: 6,
        ),
        _result(
          mode: SistrumGlassMode.newFullGlass,
          surfaces: 2,
          repeat: 1,
          order: 2,
          rasterMs: 9,
        ),
        _result(
          mode: SistrumGlassMode.newFullGlass,
          surfaces: 4,
          repeat: 1,
          order: 3,
          rasterMs: 14,
        ),
      ]);
      expect(separated, contains('scaling_verdict=consistent increase'));

      final missing = render([
        _result(
          mode: SistrumGlassMode.newFullGlass,
          surfaces: 1,
          repeat: 1,
          order: 1,
          rasterMs: 6,
        ),
      ]);
      expect(missing, contains('scaling_verdict=insufficient valid runs'));
    });

    test(
      'frame-rate conclusions name the candidate and stay labelled as evidence',
      () {
        final text = render([
          _result(
            mode: SistrumGlassMode.transparentBaseline,
            surfaces: 4,
            repeat: 1,
            order: 1,
            rasterMs: 5,
          ),
        ]);
        expect(text, contains('8. Conclusions'));
        expect(text, contains('evidence only'));
        expect(text, contains('runs_planned=18'));
      },
    );

    test('the standard report shows the schedule lines for each run', () {
      final text = formatGlassBenchmarkReport(
        status: 'COMPLETE',
        deviceLines: const ['os=android 14'],
        plan: GlassBenchmarkPlan(),
        startedAt: null,
        endedAt: null,
        cancelReason: null,
        failure: null,
        results: [
          _result(
            mode: SistrumGlassMode.transparentBaseline,
            surfaces: 4,
            repeat: 1,
            order: 1,
            rasterMs: 5,
          ),
        ],
      );
      expect(text, contains('vsync_start_interval_ms[engine]'));
      expect(text, contains('frame_begin_interval_ms[delivery]'));
      expect(text, contains('runs_planned=5'));
    });
  });

  group('per-run cross-tab', () {
    test('plateau and cadence are tallied, with the association caveat', () {
      final text = formatGlassDiagnosticReport(
        status: 'COMPLETE',
        deviceLines: const ['os=android 14'],
        reportedHz: 60,
        plan: GlassBenchmarkPlan.diagnostic(),
        startedAt: null,
        endedAt: null,
        cancelReason: null,
        failure: null,
        results: [
          // Clean run, nominal cadence (16.67 ms).
          _result(
            mode: SistrumGlassMode.transparentBaseline,
            surfaces: 4,
            repeat: 1,
            order: 1,
            rasterMs: 5,
            vsyncP50Ms: 16.67,
          ),
          // Plateau run at the slow cadence (22.27 ms).
          _result(
            mode: SistrumGlassMode.newFullGlass,
            surfaces: 4,
            repeat: 1,
            order: 2,
            rasterMs: 23,
            vsyncP50Ms: 22.27,
            refreshEndHz: 45,
          ),
          // Clean run at the slow cadence.
          _result(
            mode: SistrumGlassMode.liquidGlass,
            surfaces: 4,
            repeat: 1,
            order: 3,
            rasterMs: 6,
            vsyncP50Ms: 22.27,
          ),
        ],
      );
      expect(text, contains('== 4b. Per-run cross-tab (existing data) =='));
      expect(text, contains('plateau_runs=1 nominal_cadence=0 slow_cadence=1'));
      expect(text, contains('clean_runs=2 nominal_cadence=1 slow_cadence=1'));
      // Only the plateau run at 22.27 ms reported a refresh away from 44.9 Hz at its end.
      expect(
        text,
        contains(
          'slow_cadence_runs_where_reported_refresh_differs_from_nominal=1',
        ),
      );
      expect(text, contains('Association counts across these runs only'));
      expect(text, contains('cadence=slow(44.9Hz)'));
      expect(text, contains('refresh_start_hz=60.00 refresh_end_hz=45.00'));
    });

    test('a run without VSync data is listed as cadence unknown', () {
      final text = formatGlassDiagnosticReport(
        status: 'COMPLETE',
        deviceLines: const ['os=android 14'],
        reportedHz: 60,
        plan: GlassBenchmarkPlan.diagnostic(),
        startedAt: null,
        endedAt: null,
        cancelReason: null,
        failure: null,
        results: [
          _result(
            mode: SistrumGlassMode.newFullGlass,
            surfaces: 1,
            repeat: 1,
            order: 1,
            rasterMs: 23,
          ),
        ],
      );
      expect(text, contains('cadence=unknown'));
      expect(text, contains('plateau=yes'));
    });

    test('invalid runs stay out of the cross-tab tallies', () {
      final text = formatGlassDiagnosticReport(
        status: 'COMPLETE',
        deviceLines: const ['os=android 14'],
        reportedHz: 60,
        plan: GlassBenchmarkPlan.diagnostic(),
        startedAt: null,
        endedAt: null,
        cancelReason: null,
        failure: null,
        results: [
          _result(
            mode: SistrumGlassMode.newFullGlass,
            surfaces: 4,
            repeat: 1,
            order: 1,
            rasterMs: 23,
            vsyncP50Ms: 22.27,
            validity: GlassBenchmarkValidity.invalid,
          ),
        ],
      );
      expect(text, contains('plateau_runs=0 nominal_cadence=0 slow_cadence=0'));
      expect(text, isNot(contains('order=1 config=')));
    });
  });
}
