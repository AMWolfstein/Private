import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/performance/glass_benchmark_aggregator.dart';
import 'package:sistrum/widgets/glass_poc/glass_benchmark_report.dart';
import 'package:sistrum/widgets/glass_poc/glass_benchmark_runner.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_mode.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_render_path.dart';

/// A measured result with two sustained episodes, one of them with a turn.
GlassBenchmarkModeResult _measured(SistrumGlassMode mode) {
  var turns = 0;
  final a = GlassBenchmarkAggregator(budgetUs: 16667, turnsReader: () => turns)
    ..begin();
  var t = 0;
  for (var i = 0; i < 300; i++) {
    t += 16000;
    if (i == 100) turns = 1;
    final over = (i >= 100 && i < 140) || (i >= 200 && i < 215);
    a.onFrame(
      buildUs: 3000,
      rasterUs: over ? 26000 : 6000,
      spanUs: over ? 30000 : 10000,
      endUs: t,
    );
  }
  a.end();
  return GlassBenchmarkModeResult(
    mode: mode,
    validity: GlassBenchmarkValidity.valid,
    reasons: const [],
    measurementStarted: true,
    summary: a.summary(elapsedUs: t),
    expectedPath: SistrumGlassRenderPath.fullGpu,
    pathSamples: 60,
    pathMatches: 60,
    lastPath: 'full_gpu',
    fallbackSeen: false,
    scrollOverallPxPerSecond: 899.4,
    scrollMeasuredSeconds: 60,
    boundaryTurns: 2,
    scrollDirection: 'down',
  );
}

void main() {
  const plan = GlassBenchmarkPlan();

  String report(List<GlassBenchmarkModeResult> results, {String? cancel}) =>
      formatGlassBenchmarkReport(
        status: cancel == null ? 'COMPLETE' : 'CANCELLED',
        deviceLines: const ['os=android 14', 'refresh_hz=60 (reported)'],
        plan: plan,
        startedAt: DateTime.utc(2026, 11, 5, 10),
        endedAt: DateTime.utc(2026, 11, 5, 10, 6),
        cancelReason: cancel,
        failure: null,
        results: results,
      );

  test('the report has every section and the full statement', () {
    final text = report([
      _measured(SistrumGlassMode.transparentBaseline),
      _measured(SistrumGlassMode.newFullGlass),
    ]);
    for (final section in [
      '1. Device and benchmark configuration',
      '2. Measurement validity and interruptions',
      '3. Summary comparison',
      '4. Detailed per-renderer metrics',
      '5. Worst spike episodes per renderer',
      '6. Diagnostic notes and limitations',
    ]) {
      expect(text, contains(section));
    }
    expect(text, contains('scroll_speed_target=900'));
    expect(text, contains('scroll_speed_unit=logical_px_per_second'));
    expect(text, contains('scroll_boundary_behavior=reverse'));
    expect(text, contains('animated_background=off'));
    expect(text, contains('shared_backdrop=off'));
    expect(text, contains('Flutter FrameTiming does not measure displayed'));
    expect(text, contains('Android display FPS and must not be quoted'));
  });

  test('a summary row and the detail lines carry the measured values', () {
    final text = report([_measured(SistrumGlassMode.newFullGlass)]);
    expect(text, contains('New Full Glass'));
    expect(text, contains('frame_budget_exceedance_pct='));
    expect(text, contains('total_span_ms_p50='));
    expect(text, contains('raster_ms_p50='));
    expect(text, contains('p90='));
    expect(text, contains('estimated_frame_production_rate='));
    expect(text, contains('scroll_speed_actual=899.4'));
    expect(text, contains('scroll_boundary_reversals=2'));
    expect(text, contains('scroll_distance_px='));
    expect(text, contains('scroll_active_fraction_pct='));
    expect(text, contains('scroll_frames='));
    expect(text, contains('frame_begin_callbacks='));
    expect(text, contains('frame_timings_received='));
  });

  test('every episode line says the cause is unverified', () {
    final text = report([_measured(SistrumGlassMode.newFullGlass)]);
    expect(text, contains('cause=unverified'));
    expect(text, isNot(contains('cause=GPU')));
    expect(text, contains('#1 start='));
  });

  test('the report never names a winner from P50 alone', () {
    final text = report([
      _measured(SistrumGlassMode.transparentBaseline),
      _measured(SistrumGlassMode.newFullGlass),
    ]);
    expect(text, contains('No winner is declared'));
    expect(text, contains('P50 alone does not decide'));
    expect(text, isNot(contains('winner=')));
  });

  test('a cancelled report says so and names the reason', () {
    final text = report([
      const GlassBenchmarkModeResult(
        mode: SistrumGlassMode.transparentBaseline,
        validity: GlassBenchmarkValidity.cancelled,
        reasons: ['cancelled: app lifecycle=paused'],
        measurementStarted: true,
        summary: null,
        expectedPath: SistrumGlassRenderPath.none,
        pathSamples: 0,
        pathMatches: 0,
        lastPath: 'unknown',
        fallbackSeen: false,
        scrollOverallPxPerSecond: null,
        scrollMeasuredSeconds: 0,
        boundaryTurns: 0,
        scrollDirection: 'stopped',
      ),
    ], cancel: 'app lifecycle=paused');
    expect(text, contains('status=CANCELLED'));
    expect(text, contains('cancel_reason=app lifecycle=paused'));
    expect(text, contains('CANCELLED'));
    expect(text, contains('cancelled: app lifecycle=paused'));
  });

  test('copied text is the complete report, not the visible summary', () {
    final text = report([
      _measured(SistrumGlassMode.transparentBaseline),
      _measured(SistrumGlassMode.liquidGlass),
      _measured(SistrumGlassMode.newFullGlass),
      _measured(SistrumGlassMode.newFakeGlass),
      _measured(SistrumGlassMode.basicBlur),
    ]);
    for (final label in [
      'Transparent Baseline',
      'Old Liquid Glass',
      'New Full Glass',
      'New FakeGlass',
      'Basic Blur',
    ]) {
      expect(text, contains('-- $label'), reason: label);
    }
    expect(text, contains('Worst spike episodes per renderer'));
    expect(
      plan.modes.length,
      5,
      reason: 'the default plan runs all five modes',
    );
  });
}
