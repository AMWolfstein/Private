import 'package:sistrum/services/performance/glass_benchmark_aggregator.dart';
import 'package:sistrum/widgets/glass_poc/glass_benchmark_runner.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_mode.dart';

/// Plain-text report for a finished benchmark. The Copy Report action copies
/// this exact text, so everything the report says is in it, not only the summary
/// that is on screen. It never names a winner: the reader compares validity,
/// spikes and percentiles together.
String formatGlassBenchmarkReport({
  required String status,
  required List<String> deviceLines,
  required GlassBenchmarkPlan plan,
  required DateTime? startedAt,
  required DateTime? endedAt,
  required String? cancelReason,
  required String? failure,
  required List<GlassBenchmarkModeResult> results,
}) {
  final out = <String>[];
  void add(String line) => out.add(line);
  void section(String title) {
    out.add('');
    out.add('== $title ==');
  }

  add('sistrum-glass-benchmark');
  add('status=$status');
  add('started=${startedAt?.toIso8601String() ?? 'n/a'}');
  add('ended=${endedAt?.toIso8601String() ?? 'n/a'}');
  if (cancelReason != null) add('cancel_reason=$cancelReason');
  if (failure != null) add('failure=$failure');

  section('1. Device and benchmark configuration');
  for (final line in deviceLines) {
    add(line);
  }
  add('scene=D (four glass surfaces, scrolling)');
  add('animated_background=off');
  add('shared_backdrop=off');
  add('scroll_speed_preset=${kGlassBenchmarkSpeed.name}');
  add(
    'scroll_speed_target=${kGlassBenchmarkSpeed.pxPerSecond.toStringAsFixed(0)}',
  );
  add('scroll_speed_unit=logical_px_per_second');
  add('scroll_boundary_behavior=reverse');
  add('warmup_s=${plan.warmup.inSeconds}');
  add('measure_s=${plan.measure.inSeconds}');
  add('transition_s=${plan.transition.inSeconds}');
  add('modes_planned=${plan.modes.length}');

  section('2. Measurement validity and interruptions');
  for (final r in results) {
    add('${_label(r.mode)}: ${_validityText(r.validity)}');
    for (final reason in r.reasons) {
      add('  - $reason');
    }
  }

  section('3. Summary comparison');
  add(_summaryTable(results));
  add('');
  add(
    'No winner is declared. Compare validity, spikes and percentiles together;',
  );
  add('P50 alone does not decide a renderer.');

  section('4. Detailed per-renderer metrics');
  for (final r in results) {
    add('');
    add('-- ${_label(r.mode)} [${_validityText(r.validity)}]');
    add('render_path_expected=${r.expectedPath?.wire ?? 'unverified'}');
    add('render_path_last=${r.lastPath}');
    add('render_path_samples=${r.pathSamples} matching=${r.pathMatches}');
    add('fallback_seen=${r.fallbackSeen}');
    add('measurement_started=${r.measurementStarted}');
    add(
      'scroll_speed_target=${kGlassBenchmarkSpeed.pxPerSecond.toStringAsFixed(0)} logical_px_per_second',
    );
    add(
      'scroll_speed_actual=${_f(r.scrollOverallPxPerSecond, 1)} logical_px_per_second over ${_f(r.scrollMeasuredSeconds, 1)} s active',
    );
    add('scroll_distance_px=${_f(r.scrollDistancePx, 0)}');
    add(
      'scroll_active_fraction_pct=${_f(r.scrollActiveFraction == null ? null : r.scrollActiveFraction! * 100, 1)}',
    );
    add(
      'scroll_frames=${r.scrollTicks} unattached_frames=${r.scrollUnattachedTicks} max_scroll_gap_s=${_f(r.scrollMaxTickGapSeconds, 2)}',
    );
    add('scroll_direction_at_end=${r.scrollDirection}');
    add('scroll_boundary_reversals=${r.boundaryTurns}');
    add(
      'frame_begin_callbacks=${r.frameBegins} frame_timings_received=${r.frameTimings}',
    );
    final s = r.summary;
    if (s == null) {
      add('frames=0 (no measured interval)');
      continue;
    }
    add('elapsed_ms_stopwatch=${_f(s.elapsedMs, 0)}');
    add('observed_ms_engine=${_f(s.observedMs, 0)}');
    add('frame_coverage_pct=${_f(s.coverage * 100, 1)}');
    add('frames=${s.frames} overflow=${s.overflow}');
    add('frame_budget_ms=${_f(s.budgetMs, 2)}');
    add(
      'build_ms_p50=${_f(s.buildP50Ms, 2)} p90=${_f(s.buildP90Ms, 2)} p99=${_f(s.buildP99Ms, 2)}',
    );
    add(
      'raster_ms_p50=${_f(s.rasterP50Ms, 2)} p90=${_f(s.rasterP90Ms, 2)} p99=${_f(s.rasterP99Ms, 2)}',
    );
    add(
      'total_span_ms_p50=${_f(s.spanP50Ms, 2)} p90=${_f(s.spanP90Ms, 2)} p99=${_f(s.spanP99Ms, 2)}',
    );
    add('total_span_ms_max=${_f(s.maxSpanMs, 2)}');
    add('frame_budget_exceedance_pct=${_f(s.exceedancePct, 1)}');
    add(
      'estimated_frame_production_rate=${_f(s.estimatedProductionFps, 1)} (estimated from Flutter callbacks; not display FPS)',
    );
    add(
      'frame_gaps_over_2_budgets=${s.gapCount} max_gap_ms=${_f(s.maxGapMs, 1)} gap_total_ms=${_f(s.gapTotalMs, 0)}',
    );
    add('frame_interval_ms=${_intervalText(s.intervalCounts)}');
    add('sustained_degradation_episodes=${s.episodeCount}');
    if (s.worstEpisodes.isNotEmpty) {
      add('worst_episode=${_episodeText(s.worstEpisodes.first)}');
    }
  }

  section('5. Worst spike episodes per renderer (up to 5)');
  for (final r in results) {
    add('');
    add('-- ${_label(r.mode)}');
    final eps = r.summary?.worstEpisodes ?? const <GlassBenchmarkEpisode>[];
    if (eps.isEmpty) {
      add('  none');
      continue;
    }
    for (var i = 0; i < eps.length; i++) {
      add('  #${i + 1} ${_episodeText(eps[i])}');
    }
  }

  section('6. Diagnostic notes and limitations');
  add(
    '- Build, Raster and Total span are Flutter FrameTiming values. Total span is',
  );
  add(
    '  vsync start to raster finish. Exceedance counts total span against the budget.',
  );
  add(
    '- Flutter FrameTiming does not measure displayed (presented) frames. Android',
  );
  add(
    '  presentation can be late or dropped without any change in these numbers.',
  );
  add(
    '- Estimated frame production rate comes from Flutter callbacks. It is not',
  );
  add('  Android display FPS and must not be quoted as one.');
  add(
    '- Gaps where no callback arrived lower frame coverage. They are reported, not',
  );
  add('  counted as 60 FPS.');
  add(
    '- Episodes are sustained over-budget runs (15 of the last 30 frames). Their',
  );
  add(
    '  root cause is not determined by this instrument: every episode is unverified.',
  );
  add(
    '- Device model is not read: Dart cannot see it without a native channel, and',
  );
  add('  production code was not changed to add one.');
  add(
    '- Render path is probed from the widget tree. liquid_glass_widgets is not',
  );
  add('  instrumented, so its path is reported as unverified.');
  add(
    '- Each run waits for a verified render path before measuring. A run that never',
  );
  add('  reached it is invalid, not measured anyway.');
  return out.join('\n');
}

String _label(SistrumGlassMode mode) => switch (mode) {
  SistrumGlassMode.transparentBaseline => 'Transparent Baseline',
  SistrumGlassMode.liquidGlass => 'Old Liquid Glass',
  SistrumGlassMode.newFullGlass => 'New Full Glass',
  SistrumGlassMode.newFakeGlass => 'New FakeGlass',
  SistrumGlassMode.basicBlur => 'Basic Blur',
  SistrumGlassMode.referenceGlass => 'Reference Glass',
};

String _validityText(GlassBenchmarkValidity v) => switch (v) {
  GlassBenchmarkValidity.valid => 'VALID',
  GlassBenchmarkValidity.validPathUnverified =>
    'VALID (render path unverified)',
  GlassBenchmarkValidity.incomplete => 'INCOMPLETE',
  GlassBenchmarkValidity.invalid => 'INVALID',
  GlassBenchmarkValidity.cancelled => 'CANCELLED',
  GlassBenchmarkValidity.notRun => 'NOT RUN',
};

String _f(double? value, int digits) =>
    value == null || value.isNaN ? 'n/a' : value.toStringAsFixed(digits);

String _intervalText(List<int> counts) {
  final labels = [
    for (final b in kGlassBenchmarkIntervalBucketsMs)
      '<=${b.toStringAsFixed(0)}',
    '>${kGlassBenchmarkIntervalBucketsMs.last.toStringAsFixed(0)}',
  ];
  return [
    for (var i = 0; i < counts.length; i++) '${labels[i]}:${counts[i]}',
  ].join(' ');
}

String _episodeText(GlassBenchmarkEpisode e) =>
    'start=+${_f(e.startMs, 0)} ms duration=${_f(e.durationMs, 0)} ms '
    'frames=${e.frames} max_span=${_f(e.maxSpanMs, 1)} ms '
    'max_build=${_f(e.maxBuildMs, 1)} ms max_raster=${_f(e.maxRasterMs, 1)} ms '
    'max_gap=${_f(e.maxGapMs, 1)} ms boundary_reversals=${e.boundaryTurns} '
    'open_at_end=${e.openAtEnd} cause=${e.cause}';

String _summaryTable(List<GlassBenchmarkModeResult> results) {
  const headers = [
    'Renderer',
    'Validity',
    'Frames',
    'Span p50',
    'Span p90',
    'Span p99',
    'Raster p90',
    'Build p90',
    'Exceed %',
    'Max span',
    'Episodes',
    'Worst ms',
    'Prod. rate*',
    'Coverage %',
  ];
  final rows = <List<String>>[headers];
  for (final r in results) {
    final s = r.summary;
    rows.add([
      _label(r.mode),
      _validityText(r.validity),
      '${s?.frames ?? 0}',
      _f(s?.spanP50Ms, 2),
      _f(s?.spanP90Ms, 2),
      _f(s?.spanP99Ms, 2),
      _f(s?.rasterP90Ms, 2),
      _f(s?.buildP90Ms, 2),
      _f(s?.exceedancePct, 1),
      _f(s?.maxSpanMs, 2),
      s == null ? 'n/a' : '${s.episodeCount}',
      _f(
        s?.worstEpisodes.isEmpty ?? true
            ? null
            : s!.worstEpisodes.first.durationMs,
        0,
      ),
      _f(s?.estimatedProductionFps, 1),
      _f(s == null ? null : s.coverage * 100, 1),
    ]);
  }
  final widths = [
    for (var c = 0; c < headers.length; c++)
      rows.map((r) => r[c].length).reduce((a, b) => a > b ? a : b),
  ];
  final lines = [
    for (final row in rows)
      [
        for (var c = 0; c < row.length; c++) row[c].padRight(widths[c]),
      ].join('  ').trimRight(),
  ];
  lines.add(
    '* Estimated frame production rate from Flutter callbacks. Not display FPS.',
  );
  return lines.join('\n');
}
