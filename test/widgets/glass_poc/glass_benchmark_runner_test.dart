import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/performance/glass_benchmark_aggregator.dart';
import 'package:sistrum/widgets/glass_poc/glass_benchmark_report.dart';
import 'package:sistrum/widgets/glass_poc/glass_benchmark_runner.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_auto_scroll.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_mode.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_render_path.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_scene.dart';

const _budgetUs = 16667.0;

const _plan = GlassBenchmarkPlan(
  modes: [SistrumGlassMode.transparentBaseline, SistrumGlassMode.basicBlur],
  transition: Duration(milliseconds: 100),
  warmup: Duration(milliseconds: 100),
  measure: Duration(seconds: 1),
  modeTimeout: Duration(milliseconds: 500),
);

/// A fake page: records every call, and returns a configurable render path.
class _FakeHost implements GlassBenchmarkHost {
  final List<String> calls = [];
  GlassBenchmarkAggregator? aggregator;
  SistrumGlassMode? current;
  SistrumGlassRenderReport Function(SistrumGlassMode mode)? pathFor;
  bool throwOnApply = false;
  int restoreCount = 0;
  GlassBenchmarkConfig config = (
    mode: SistrumGlassMode.referenceGlass,
    sharedBackdrop: false,
    speed: SistrumScrollSpeed.normal,
    scene: SistrumGlassScene.fourSurfaces,
  );

  @override
  GlassBenchmarkConfig captureConfig() => config;

  @override
  void applyRun(SistrumGlassMode mode) {
    if (throwOnApply) throw StateError('boom');
    current = mode;
    calls.add('apply:${mode.name}');
  }

  @override
  void haltRun() => calls.add('halt');

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
  SistrumScrollStatus? scrollStatus() => null;

  @override
  void attachAggregator(GlassBenchmarkAggregator? a) {
    aggregator = a;
    calls.add(a == null ? 'detach' : 'attach');
  }
}

GlassBenchmarkRunner _runner(_FakeHost host, {GlassBenchmarkPlan? plan}) {
  final p = plan ?? _plan;
  return GlassBenchmarkRunner(
    host: host,
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

/// Feeds [frames] normal frames (16 ms apart) into the run's aggregator.
void _feed(_FakeHost host, {int frames = 60, int spanUs = 10000}) {
  final a = host.aggregator!;
  for (var i = 1; i <= frames; i++) {
    a.onFrame(buildUs: 3000, rasterUs: 6000, spanUs: spanUs, endUs: i * 16000);
  }
}

void main() {
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

    // First run done: it returns to transition, then the second mode starts.
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

    // Nothing resumes on its own after an interruption.
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
      // Never call onMeasurementStarted: the render path never verified.
      await tester.pump(const Duration(milliseconds: 550));

      expect(runner.results[0].validity, GlassBenchmarkValidity.invalid);
      expect(runner.results[0].measurementStarted, isFalse);
      expect(runner.results[0].reasons.join(), contains('never started'));
      expect(runner.phase, GlassBenchmarkPhase.transition);
      expect(runner.results, hasLength(1));

      // Clean up the rest so no timer is left pending.
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
      final plan = const GlassBenchmarkPlan(
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
}
