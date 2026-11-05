import 'package:sistrum/services/display/display_refresh_rate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/performance/glass_benchmark_aggregator.dart';
import 'package:sistrum/services/performance/glass_frame_schedule.dart';
import 'package:sistrum/widgets/glass_poc/glass_benchmark_report.dart';
import 'package:sistrum/widgets/glass_poc/glass_benchmark_run.dart';
import 'package:sistrum/widgets/glass_poc/glass_benchmark_runner.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_auto_scroll.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_mode.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_render_path.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_scene.dart';

const _budgetUs = 16667.0;

final _plan = GlassBenchmarkPlan(
  modes: [SistrumGlassMode.transparentBaseline, SistrumGlassMode.basicBlur],
  transition: Duration(milliseconds: 100),
  warmup: Duration(milliseconds: 100),
  measure: Duration(seconds: 1),
  modeTimeout: Duration(milliseconds: 500),
);

/// A scroll state as the scroller reports it while a run is active: 900 px/s,
/// 60 s measured, one reversal, no detached or stopped frames.
SistrumScrollStatus _activeScroll({
  double overall = 900,
  double measuredSeconds = 60,
  int turns = 2,
  int ticks = 3600,
  int unattached = 0,
  double maxGap = 0.02,
}) => SistrumScrollStatus(
  speed: SistrumScrollSpeed.fast,
  running: true,
  measuring: true,
  actualPxPerSecond: overall,
  direction: 'down',
  samples: 300,
  boundaryTransitions: turns,
  overallPxPerSecond: overall,
  measuredSeconds: measuredSeconds,
  totalBoundaryTurns: turns,
  measuredPathPx: overall * measuredSeconds,
  measureTicks: ticks,
  unattachedTicks: unattached,
  maxTickGapSeconds: maxGap,
  maxExtent: 1600,
);

/// What the scroller reports after it was halted: everything cleared.
const SistrumScrollStatus _clearedScroll = SistrumScrollStatus(
  speed: SistrumScrollSpeed.fast,
  running: false,
  measuring: false,
  actualPxPerSecond: null,
  direction: 'stopped',
  samples: 0,
  boundaryTransitions: 0,
  overallPxPerSecond: null,
  measuredSeconds: 0,
  totalBoundaryTurns: 0,
);

/// A fake page: records every call. [scroll] is what the scroller reports
/// while a run is active; halting clears it, as the real scroller does.
class _FakeHost implements GlassBenchmarkHost {
  final List<String> calls = [];

  /// Reported refresh returned to the runner. Tests change it between calls to
  /// check that the start and end values are recorded separately.
  double refreshHz = 60;

  @override
  double reportedRefreshHz() => refreshHz;

  /// Android's report, as the display controller would give it.
  DisplayRefreshState android = DisplayRefreshState.unavailable;

  /// Active-mode changes counted since the page opened.
  int modeChanges = 0;

  @override
  DisplayRefreshState androidDisplay() => android;

  @override
  int displayModeChangeCount() => modeChanges;

  GlassBenchmarkAggregator? aggregator;
  SistrumGlassMode? current;
  SistrumGlassRenderReport Function(SistrumGlassMode mode)? pathFor;

  /// What the scroller reports for each run, as applyRun restarts it.
  SistrumScrollStatus? scrollTemplate = _activeScroll();
  SistrumScrollStatus? scroll;
  bool throwOnApply = false;
  int restoreCount = 0;
  int beginCount = 0;
  int timingCount = 0;
  GlassBenchmarkConfig config = (
    mode: SistrumGlassMode.referenceGlass,
    sharedBackdrop: false,
    speed: SistrumScrollSpeed.normal,
    scene: SistrumGlassScene.fourSurfaces,
  );

  @override
  GlassBenchmarkConfig captureConfig() => config;

  @override
  void applyRun(GlassBenchmarkRun run) {
    if (throwOnApply) throw StateError('boom');
    current = run.mode;
    surfaces.add(run.surfaces);
    scroll = scrollTemplate;
    calls.add('apply:${run.mode.name}');
  }

  /// Surface counts applied, in run order.
  final List<int> surfaces = [];

  /// Recorder attached to the frame stream, if any.
  GlassFrameScheduleRecorder? schedule;

  @override
  void attachSchedule(GlassFrameScheduleRecorder? recorder) {
    schedule = recorder;
  }

  @override
  void haltRun() {
    calls.add('halt');
    scroll = _clearedScroll;
  }

  @override
  void restoreConfig(GlassBenchmarkConfig c) {
    restoreCount++;
    calls.add('restore');
  }

  @override
  SistrumGlassRenderReport renderPath() {
    final mode = current ?? SistrumGlassMode.transparentBaseline;
    return pathFor?.call(mode) ??
        classifySistrumGlassRenderPath(
          mode: mode,
          expectedSurfaces: 4,
          census: const SistrumGlassCensus(
            layers: 0,
            realLayers: 0,
            fakeWidgets: 0,
            backdropFilters: 4,
          ),
          shaderFiltersSupported: true,
        );
  }

  @override
  SistrumScrollStatus? scrollStatus() => scroll;

  @override
  ({int beginFrames, int timings}) frameCounts() =>
      (beginFrames: beginCount, timings: timingCount);

  @override
  void attachAggregator(GlassBenchmarkAggregator? a) {
    aggregator = a;
    calls.add(a == null ? 'detach' : 'attach');
  }
}

GlassBenchmarkRunner _runner(
  _FakeHost host, {
  GlassBenchmarkPlan? plan,
  String Function()? backdropConfiguration,
}) {
  final p = plan ?? _plan;
  return GlassBenchmarkRunner(
    host: host,
    backdropConfiguration: backdropConfiguration,
    budgetUs: _budgetUs,
    plan: p,
    onPhaseChanged: () {},
    reportBuilder: (r) => formatGlassBenchmarkReport(
      status: r.phase.name.toUpperCase(),
      deviceLines: const ['device_model=test'],
      plan: p,
      startedAt: r.startedAt,
      endedAt: r.endedAt,
      cancelReason: r.cancelReason,
      failure: r.failure,
      results: r.results,
    ),
  );
}

/// Feeds [frames] frames (16 ms apart) into the run's aggregator. Each frame is
/// drawn and has a FrameTiming, so both counters move together.
void _feed(_FakeHost host, {int frames = 60, int spanUs = 10000}) {
  final a = host.aggregator!;
  for (var i = 1; i <= frames; i++) {
    host.beginCount++;
    host.timingCount++;
    a.onFrame(buildUs: 3000, rasterUs: 6000, spanUs: spanUs, endUs: i * 16000);
  }
}

void main() {
  testWidgets('a transient backdrop layout change invalidates measurement', (
    tester,
  ) async {
    final host = _FakeHost();
    final runner = _runner(
      host,
      plan: _shortPlan(),
      backdropConfiguration: () => 'groups=0,0,0,1',
    );
    runner.start();
    await tester.pump(const Duration(milliseconds: 100));
    runner.onMeasurementStarted();
    _feed(host);
    runner.observeBackdropConfiguration('groups=0,0,1,2');
    runner.observeBackdropConfiguration('groups=0,0,0,1');
    await tester.pump(const Duration(seconds: 1));
    final result = runner.results.single;
    expect(result.backdropConfiguration, 'groups=0,0,0,1');
    expect(result.validity, GlassBenchmarkValidity.invalid);
    expect(result.reasons.join(' '), contains('Backdrop assignment'));
  });

  testWidgets('a full run goes transition, warm-up, measuring, then complete', (
    tester,
  ) async {
    final host = _FakeHost()
      ..pathFor = (mode) => classifySistrumGlassRenderPath(
        mode: mode,
        expectedSurfaces: 4,
        census: SistrumGlassCensus(
          layers: 0,
          realLayers: 0,
          fakeWidgets: 0,
          backdropFilters: mode == SistrumGlassMode.basicBlur ? 4 : 0,
        ),
        shaderFiltersSupported: true,
      );
    final runner = _runner(host);

    runner.start();
    expect(runner.phase, GlassBenchmarkPhase.transition);
    await tester.pump(const Duration(milliseconds: 100));
    expect(runner.phase, GlassBenchmarkPhase.warmup);
    expect(host.calls, contains('apply:transparentBaseline'));

    runner.onMeasurementStarted();
    expect(runner.phase, GlassBenchmarkPhase.measuring);
    expect(host.calls, contains('attach'));
    _feed(host);
    await tester.pump(const Duration(seconds: 1));

    expect(runner.phase, GlassBenchmarkPhase.transition);
    await tester.pump(const Duration(milliseconds: 100));
    runner.onMeasurementStarted();
    _feed(host);
    await tester.pump(const Duration(seconds: 1));

    expect(runner.phase, GlassBenchmarkPhase.complete);
    expect(host.restoreCount, 1);
    expect(host.aggregator, isNull, reason: 'aggregator detached at the end');
    expect(runner.results, hasLength(2));
    expect(runner.results[0].validity, GlassBenchmarkValidity.valid);
    expect(runner.results[1].validity, GlassBenchmarkValidity.valid);
    expect(runner.reportText, contains('status=COMPLETE'));
    expect(runner.reportText, contains('No winner is declared'));
  });

  testWidgets('a second start while running is refused', (tester) async {
    final host = _FakeHost();
    final runner = _runner(host);
    runner.start();
    runner.start();
    await tester.pump(const Duration(milliseconds: 100));
    expect(host.calls.where((c) => c.startsWith('apply:')), hasLength(1));
    runner.interrupt('test cleanup');
    expect(runner.phase, GlassBenchmarkPhase.cancelled);
  });

  testWidgets('cancelling mid-measurement keeps partial data and restores', (
    tester,
  ) async {
    final host = _FakeHost();
    final runner = _runner(host);
    runner.start();
    await tester.pump(const Duration(milliseconds: 100));
    runner.onMeasurementStarted();
    _feed(host, frames: 20);

    runner.interrupt('app lifecycle=paused');

    expect(runner.phase, GlassBenchmarkPhase.cancelled);
    expect(runner.cancelReason, 'app lifecycle=paused');
    expect(runner.results[0].validity, GlassBenchmarkValidity.cancelled);
    expect(runner.results[0].summary?.frames, 20, reason: 'partial data kept');
    expect(runner.results[1].validity, GlassBenchmarkValidity.notRun);
    expect(host.restoreCount, 1);
    expect(host.aggregator, isNull);

    await tester.pump(const Duration(seconds: 5));
    expect(host.calls.where((c) => c.startsWith('apply:')), hasLength(1));
  });

  testWidgets(
    'a mode that never starts measuring is invalid and the run moves on',
    (tester) async {
      final host = _FakeHost();
      final runner = _runner(host);
      runner.start();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 550));

      expect(runner.results, hasLength(1));
      expect(runner.results[0].validity, GlassBenchmarkValidity.invalid);
      expect(runner.results[0].measurementStarted, isFalse);
      expect(runner.results[0].reasons.join(), contains('never started'));
      expect(runner.phase, GlassBenchmarkPhase.transition);
      runner.interrupt('test cleanup');
    },
  );

  testWidgets(
    'Full Glass that fell back to FakeGlass is never a valid result',
    (tester) async {
      final host = _FakeHost()
        ..pathFor = (mode) => const SistrumGlassRenderReport(
          path: SistrumGlassRenderPath.fakeBackdrop,
          fallback: true,
          fallbackReason: 'Flutter GPU did not load',
        );
      final plan = GlassBenchmarkPlan(
        modes: [SistrumGlassMode.newFullGlass],
        transition: Duration(milliseconds: 100),
        warmup: Duration(milliseconds: 100),
        measure: Duration(seconds: 1),
        modeTimeout: Duration(milliseconds: 500),
      );
      final runner = _runner(host, plan: plan);
      runner.start();
      await tester.pump(const Duration(milliseconds: 100));
      runner.onMeasurementStarted();
      _feed(host);
      await tester.pump(const Duration(seconds: 1));

      final result = runner.results.single;
      expect(result.validity, GlassBenchmarkValidity.invalid);
      expect(result.fallbackSeen, isTrue);
      expect(result.reasons.join(), contains('render path mismatch'));
      expect(runner.reportText, contains('INVALID'));
    },
  );

  testWidgets('a failure stops the run as FAILED and still restores the page', (
    tester,
  ) async {
    final host = _FakeHost()..throwOnApply = true;
    final runner = _runner(host);
    runner.start();
    await tester.pump(const Duration(milliseconds: 100));

    expect(runner.phase, GlassBenchmarkPhase.failed);
    expect(runner.failure, contains('boom'));
    expect(host.restoreCount, 1);
    expect(runner.reportText, contains('failure=Bad state: boom'));
  });

  testWidgets('disposing the runner mid-run cancels it and restores the page', (
    tester,
  ) async {
    final host = _FakeHost();
    final runner = _runner(host);
    runner.start();
    await tester.pump(const Duration(milliseconds: 100));
    runner.onMeasurementStarted();

    runner.dispose();

    expect(runner.phase, GlassBenchmarkPhase.cancelled);
    expect(runner.cancelReason, 'Glass POC closed');
    expect(host.restoreCount, 1);
    await tester.pump(const Duration(seconds: 5));
    expect(host.calls.where((c) => c.startsWith('apply:')), hasLength(1));
  });

  // -- Regressions: scrolling evidence and sustained episodes -----------------

  testWidgets('scroll metrics are captured during the run, not after the halt', (
    tester,
  ) async {
    // The real scroller clears its totals when halted. The result must hold the
    // values seen while the run was active.
    final host = _FakeHost();
    final runner = _runner(
      host,
      plan: GlassBenchmarkPlan(
        modes: [SistrumGlassMode.transparentBaseline],
        transition: Duration(milliseconds: 100),
        warmup: Duration(milliseconds: 100),
        measure: Duration(seconds: 1),
        modeTimeout: Duration(milliseconds: 500),
      ),
    );
    runner.start();
    await tester.pump(const Duration(milliseconds: 100));
    runner.onMeasurementStarted();
    _feed(host);
    await tester.pump(const Duration(seconds: 1));

    final result = runner.results.single;
    expect(result.scrollOverallPxPerSecond, closeTo(900, 0.1));
    expect(result.boundaryTurns, 2);
    expect(result.scrollDirection, 'down');
    expect(result.scrollDistancePx, closeTo(900 * 60, 0.1));
    expect(result.validity, GlassBenchmarkValidity.valid);
    expect(runner.reportText, contains('scroll_speed_actual=900.0'));
    expect(runner.reportText, contains('scroll_boundary_reversals=2'));
    expect(
      runner.reportText,
      isNot(contains('scroll_speed_actual=unavailable')),
    );
  });

  testWidgets(
    'a run whose list never scrolled is INVALID even though its timer completed',
    (tester) async {
      final host = _FakeHost()
        ..scrollTemplate = _activeScroll(
          overall: 0,
          ticks: 0,
          measuredSeconds: 0,
        );
      final runner = _runner(
        host,
        plan: GlassBenchmarkPlan(
          modes: [SistrumGlassMode.transparentBaseline],
          transition: Duration(milliseconds: 100),
          warmup: Duration(milliseconds: 100),
          measure: Duration(seconds: 1),
          modeTimeout: Duration(milliseconds: 500),
        ),
      );
      runner.start();
      await tester.pump(const Duration(milliseconds: 100));
      runner.onMeasurementStarted();
      _feed(host);
      await tester.pump(const Duration(seconds: 1));

      final result = runner.results.single;
      expect(result.validity, GlassBenchmarkValidity.invalid);
      expect(result.reasons.join(), contains('no scroll frames'));
    },
  );

  testWidgets('a run at the wrong speed is INVALID', (tester) async {
    final host = _FakeHost()..scrollTemplate = _activeScroll(overall: 400);
    final runner = _runner(
      host,
      plan: GlassBenchmarkPlan(
        modes: [SistrumGlassMode.transparentBaseline],
        transition: Duration(milliseconds: 100),
        warmup: Duration(milliseconds: 100),
        measure: Duration(seconds: 1),
        modeTimeout: Duration(milliseconds: 500),
      ),
    );
    runner.start();
    await tester.pump(const Duration(milliseconds: 100));
    runner.onMeasurementStarted();
    _feed(host);
    await tester.pump(const Duration(seconds: 1));

    final result = runner.results.single;
    expect(result.validity, GlassBenchmarkValidity.invalid);
    expect(result.reasons.join(), contains('not within 5%'));
  });

  testWidgets(
    'a scroll stop longer than the limit, or a detached list, is INVALID',
    (tester) async {
      for (final scroll in [
        _activeScroll(maxGap: 2),
        _activeScroll(unattached: 5),
      ]) {
        final host = _FakeHost()..scrollTemplate = scroll;
        final runner = _runner(
          host,
          plan: GlassBenchmarkPlan(
            modes: [SistrumGlassMode.transparentBaseline],
            transition: Duration(milliseconds: 100),
            warmup: Duration(milliseconds: 100),
            measure: Duration(seconds: 1),
            modeTimeout: Duration(milliseconds: 500),
          ),
        );
        runner.start();
        await tester.pump(const Duration(milliseconds: 100));
        runner.onMeasurementStarted();
        _feed(host);
        await tester.pump(const Duration(seconds: 1));
        expect(runner.results.single.validity, GlassBenchmarkValidity.invalid);
      }
    },
  );

  testWidgets(
    'a sustained 100% over-budget interval that is still open at the end records an episode',
    (tester) async {
      final host = _FakeHost();
      final runner = _runner(
        host,
        plan: GlassBenchmarkPlan(
          modes: [SistrumGlassMode.transparentBaseline],
          transition: Duration(milliseconds: 100),
          warmup: Duration(milliseconds: 100),
          measure: Duration(seconds: 1),
          modeTimeout: Duration(milliseconds: 500),
        ),
      );
      runner.start();
      await tester.pump(const Duration(milliseconds: 100));
      runner.onMeasurementStarted();
      // Every frame over budget, through the end of the measurement.
      _feed(host, frames: 120, spanUs: 30000);
      await tester.pump(const Duration(seconds: 1));

      final summary = runner.results.single.summary!;
      expect(summary.exceedancePct, 100);
      expect(
        summary.episodeCount,
        1,
        reason: 'the open episode must be finalized',
      );
      expect(summary.worstEpisodes, hasLength(1));
      expect(summary.worstEpisodes.single.openAtEnd, isTrue);
      expect(runner.reportText, contains('sustained_degradation_episodes=1'));
      expect(runner.reportText, contains('open_at_end=true'));
    },
  );

  testWidgets('drawn frames without a FrameTiming make the run INCOMPLETE', (
    tester,
  ) async {
    final host = _FakeHost();
    final runner = _runner(
      host,
      plan: GlassBenchmarkPlan(
        modes: [SistrumGlassMode.transparentBaseline],
        transition: Duration(milliseconds: 100),
        warmup: Duration(milliseconds: 100),
        measure: Duration(seconds: 1),
        modeTimeout: Duration(milliseconds: 500),
      ),
    );
    runner.start();
    await tester.pump(const Duration(milliseconds: 100));
    runner.onMeasurementStarted();
    _feed(host);
    // 50 frames were drawn but their timings never arrived.
    host.beginCount += 50;
    await tester.pump(const Duration(seconds: 1));

    final result = runner.results.single;
    expect(result.validity, GlassBenchmarkValidity.incomplete);
    expect(result.reasons.join(), contains('no FrameTiming callback'));
    expect(result.frameBegins, 110);
    expect(result.frameTimings, 60);
  });

  testWidgets(
    'a multi-run plan applies each surface count in order and records each run',
    (tester) async {
      final host = _FakeHost();
      final plan = GlassBenchmarkPlan(
        runs: [
          GlassBenchmarkRun(
            mode: SistrumGlassMode.transparentBaseline,
            surfaces: 4,
            repeat: 1,
          ),
          GlassBenchmarkRun(
            mode: SistrumGlassMode.transparentBaseline,
            surfaces: 1,
            repeat: 1,
          ),
        ],
        transition: const Duration(milliseconds: 100),
        warmup: const Duration(milliseconds: 100),
        measure: const Duration(seconds: 1),
        modeTimeout: const Duration(milliseconds: 500),
        diagnostic: true,
      );
      final runner = _runner(host, plan: plan);
      runner.start();
      await tester.pump(const Duration(milliseconds: 100));
      runner.onMeasurementStarted();
      expect(host.schedule, isNotNull, reason: 'recorder attached in the run');
      _feed(host);
      await tester.pump(const Duration(seconds: 1));
      // The first run ends, its recorder is detached, and the second starts.
      expect(host.schedule, isNull);
      expect(runner.results[0].schedule, isNotNull);
      await tester.pump(const Duration(milliseconds: 100));
      runner.onMeasurementStarted();
      _feed(host);
      await tester.pump(const Duration(seconds: 1));

      expect(runner.phase, GlassBenchmarkPhase.complete);
      expect(host.surfaces, [4, 1]);
      expect(runner.results.map((r) => r.surfaces), [4, 1]);
      expect(runner.results.map((r) => r.runOrder), [1, 2]);
      expect(runner.plan.diagnostic, isTrue);
      expect(runner.reportText, contains('runs_planned=2'));
    },
  );

  testWidgets(
    'the reported refresh is recorded at the start and at the end of a run',
    (tester) async {
      final host = _FakeHost()..refreshHz = 60;
      final plan = GlassBenchmarkPlan(
        runs: [GlassBenchmarkRun(mode: SistrumGlassMode.transparentBaseline)],
        transition: const Duration(milliseconds: 100),
        warmup: const Duration(milliseconds: 100),
        measure: const Duration(seconds: 1),
        modeTimeout: const Duration(milliseconds: 500),
        diagnostic: true,
      );
      final runner = _runner(host, plan: plan);
      runner.start();
      await tester.pump(const Duration(milliseconds: 100));
      runner.onMeasurementStarted();
      _feed(host);
      // The display reports a different rate by the end of the run.
      host.refreshHz = 45;
      await tester.pump(const Duration(seconds: 1));

      final result = runner.results.single;
      expect(result.refreshHzStart, 60);
      expect(result.refreshHzEnd, 45);
    },
  );

  testWidgets(
    'the frame budget follows Android\'s active mode, not a stale Flutter value',
    (tester) async {
      // Flutter still reports 90 Hz; Android has the panel at 120 Hz.
      final host = _FakeHost()
        ..refreshHz = 90
        ..android = _android(modeHz: 120);
      final plan = _shortPlan();
      final runner = _runner(host, plan: plan);
      runner.start();
      await tester.pump(const Duration(milliseconds: 100));
      runner.onMeasurementStarted();
      _feed(host);
      await tester.pump(const Duration(seconds: 1));

      final result = runner.results.single;
      expect(result.nominalHz, 120);
      expect(result.nominalSource, DisplayRefreshSource.androidActiveMode);
      expect(result.refreshHzStart, 90);
      expect(result.androidStart?.activeModeHz, 120);
      expect(result.schedule!.nominalPeriodMs, closeTo(8.33, 0.01));
      expect(result.displayModeChanges, 0);
      expect(result.validity, GlassBenchmarkValidity.valid);
    },
  );

  testWidgets(
    'a display mode change during measurement makes the run INVALID',
    (tester) async {
      final host = _FakeHost()
        ..refreshHz = 120
        ..android = _android(modeHz: 120);
      final runner = _runner(host, plan: _shortPlan());
      runner.start();
      await tester.pump(const Duration(milliseconds: 100));
      runner.onMeasurementStarted();
      _feed(host);
      // Android switches the panel to 60 Hz part way through.
      host.modeChanges = 1;
      host.android = _android(modeHz: 60);
      await tester.pump(const Duration(seconds: 1));

      final result = runner.results.single;
      expect(result.validity, GlassBenchmarkValidity.invalid);
      expect(result.displayModeChanges, 1);
      expect(
        result.reasons.any((r) => r.contains('display mode change')),
        isTrue,
      );
      expect(result.androidEnd?.activeModeHz, 60);
    },
  );

  testWidgets('a run that never measured has no refresh values', (
    tester,
  ) async {
    final host = _FakeHost()..refreshHz = 60;
    final runner = _runner(host);
    runner.start();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 550));
    final result = runner.results[0];
    expect(result.measurementStarted, isFalse);
    expect(result.refreshHzStart, isNull);
    expect(result.refreshHzEnd, isNull);
    runner.interrupt('test cleanup');
  });
}

DisplayRefreshState _android({required double modeHz}) =>
    DisplayRefreshState.fromMap({
      'attached': true,
      'activeModeId': modeHz.round(),
      'activeModeHz': modeHz,
      'displayRefreshHz': modeHz,
      'supportedRates': [60, 90, 120],
    });

GlassBenchmarkPlan _shortPlan() => GlassBenchmarkPlan(
  runs: [GlassBenchmarkRun(mode: SistrumGlassMode.transparentBaseline)],
  transition: const Duration(milliseconds: 100),
  warmup: const Duration(milliseconds: 100),
  measure: const Duration(seconds: 1),
  modeTimeout: const Duration(milliseconds: 500),
  diagnostic: true,
);
