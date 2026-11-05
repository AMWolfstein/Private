import 'package:sistrum/services/performance/glass_benchmark_aggregator.dart';
import 'package:sistrum/services/performance/glass_frame_schedule.dart';
import 'package:sistrum/services/performance/glass_series_stats.dart';
import 'package:sistrum/widgets/glass_poc/glass_benchmark_run.dart';
import 'package:sistrum/widgets/glass_poc/glass_benchmark_runner.dart';
import 'package:sistrum/widgets/glass_poc/glass_diagnostic_stats.dart';
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
  add('runs_planned=${plan.runs.length}');

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
    add(
      'refresh_hz_start=${_f(r.refreshHzStart, 2)} '
      'refresh_hz_end=${_f(r.refreshHzEnd, 2)} (reported, not measured)',
    );
    for (final line in glassScheduleLines(r.schedule)) {
      add(line);
    }
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

/// Lines of one run's VSync, callback and raster intervals. Engine series and
/// Stopwatch delivery series are labelled with their clock, so they are never
/// read as one timeline.
List<String> glassScheduleLines(GlassFrameScheduleSummary? s) {
  if (s == null) return const ['schedule=not measured'];
  String series(GlassSeriesStats x) =>
      'n=${x.count} overflow=${x.overflow} p50=${_f(x.p50, 2)} '
      'p90=${_f(x.p90, 2)} p99=${_f(x.p99, 2)} max=${_f(x.max, 2)}';
  return [
    'nominal_period_ms=${_f(s.nominalPeriodMs, 3)}',
    'vsync_start_interval_ms[engine]: ${series(s.vsync)}',
    'raster_finish_interval_ms[engine]: ${series(s.raster)}',
    'frame_begin_interval_ms[delivery]: ${series(s.begin)}',
    'frame_timing_arrival_interval_ms[delivery]: ${series(s.arrival)}',
    'implied_vsync_hz_from_median=${_f(s.impliedVsyncHz, 2)}',
    'long_vsync_intervals_over_1.5_periods=${s.longVsyncIntervals} '
        'missed_slots=${s.missedSlots}',
    'frame_begin_events=${s.beginEvents} timing_batches=${s.batches} '
        'timings=${s.timings}',
    // Phase differences name the interval between two recorded points. The raster
    // slice contains every wait inside it; the phases cannot say which wait.
    'phase_vsync_to_build_start_ms[engine]: ${series(s.phases.vsyncToBuildStart)}',
    'phase_build_ms[engine]: ${series(s.phases.build)}',
    'phase_build_finish_to_raster_start_ms[engine]: '
        '${series(s.phases.buildFinishToRasterStart)}',
    'phase_raster_slice_ms[engine]: ${series(s.phases.rasterSlice)}',
    'phase_invalid_samples=${s.phases.invalidSamples} '
        'zero_raster_slices=${s.phases.zeroRasterSlices}',
  ];
}

/// A raster P90 at or above this value is counted as the high-raster plateau in
/// the cross-tab. It is a classification threshold chosen between the clean
/// (about 5 ms) and high (about 23 ms) states, not a measured constant.
const double kGlassRasterPlateauP90Ms = 18;

/// Cadence class of one run from its median engine vsync interval. `nominal`
/// means within 10% of the reported display period; `slow` means the median
/// interval is longer, with the rate it implies.
String _cadenceClass(GlassFrameScheduleSummary? s) {
  final p50 = s?.vsync.p50;
  if (s == null || p50 == null || p50 <= 0) return 'unknown';
  final nominal = s.nominalPeriodMs;
  if ((p50 - nominal).abs() <= nominal * 0.1) return 'nominal';
  return 'slow(${(1000 / p50).toStringAsFixed(1)}Hz)';
}

/// Per-run cross-tab built only from fields already in each run. It shows which
/// runs had the raster plateau and which cadence they ran at. It is a count of
/// co-occurrence in these runs, not evidence of cause.
List<String> glassCrossTabLines(List<GlassBenchmarkModeResult> results) {
  final lines = <String>[];
  var plateau = 0;
  var plateauNominal = 0;
  var plateauSlow = 0;
  var clean = 0;
  var cleanNominal = 0;
  var cleanSlow = 0;
  var refreshDisagrees = 0;
  for (final r in results) {
    if (!_isMeasured(r)) continue;
    final sum = r.summary!;
    final sch = r.schedule;
    final cadence = _cadenceClass(sch);
    final highRaster = (sum.rasterP90Ms ?? 0) >= kGlassRasterPlateauP90Ms;
    final nominalHz = sch == null ? null : 1000 / sch.nominalPeriodMs;
    final refresh = [r.refreshHzStart, r.refreshHzEnd];
    final disagrees =
        cadence.startsWith('slow') &&
        nominalHz != null &&
        refresh.any(
          (hz) => hz != null && (hz - nominalHz).abs() > nominalHz * 0.05,
        );
    if (disagrees) refreshDisagrees++;
    if (highRaster) {
      plateau++;
      if (cadence == 'nominal') plateauNominal++;
      if (cadence.startsWith('slow')) plateauSlow++;
    } else {
      clean++;
      if (cadence == 'nominal') cleanNominal++;
      if (cadence.startsWith('slow')) cleanSlow++;
    }
    lines.add(
      'order=${r.runOrder} config=${_config(r)} '
      'vsync_p50_ms=${_f(sch?.vsync.p50, 2)} cadence=$cadence '
      'raster_p50_ms=${_f(sum.rasterP50Ms, 2)} '
      'raster_p90_ms=${_f(sum.rasterP90Ms, 2)} '
      'plateau=${highRaster ? 'yes' : 'no'} '
      'raster_slice_p90_ms=${_f(sch?.phases.rasterSlice.p90, 2)} '
      'queue_wait_p90_ms=${_f(sch?.phases.buildFinishToRasterStart.p90, 2)} '
      'frames_per_s=${_f(_framesPerSecond(r), 2)} '
      'refresh_start_hz=${_f(r.refreshHzStart, 2)} '
      'refresh_end_hz=${_f(r.refreshHzEnd, 2)}',
    );
  }
  final out = <String>[
    'plateau_threshold_raster_p90_ms=$kGlassRasterPlateauP90Ms',
    'plateau_runs=$plateau nominal_cadence=$plateauNominal '
        'slow_cadence=$plateauSlow',
    'clean_runs=$clean nominal_cadence=$cleanNominal slow_cadence=$cleanSlow',
    'slow_cadence_runs_where_reported_refresh_differs_from_nominal='
        '$refreshDisagrees',
    'Association counts across these runs only. They do not show that one causes the other.',
    ...lines,
  ];
  return out;
}

/// A run that produced a usable measurement. Invalid, cancelled and not-run
/// runs are listed in the report but never enter a statistic.
bool _isMeasured(GlassBenchmarkModeResult r) =>
    r.summary != null &&
    (r.validity == GlassBenchmarkValidity.valid ||
        r.validity == GlassBenchmarkValidity.validPathUnverified);

String _configKey(GlassBenchmarkModeResult r) =>
    '${r.mode.name}-s${r.surfaces}';

String _config(GlassBenchmarkModeResult r) =>
    '${_label(r.mode)} (${r.surfaces} surface${r.surfaces == 1 ? '' : 's'})';

/// Frames per second from the drawn-frame count and the Stopwatch interval.
double? _framesPerSecond(GlassBenchmarkModeResult r) {
  final s = r.summary;
  if (s == null || s.elapsedMs <= 0) return null;
  return r.frameBegins / (s.elapsedMs / 1000);
}

List<double> _pick(
  Iterable<GlassBenchmarkModeResult> runs,
  double? Function(GlassBenchmarkModeResult r) value,
) {
  final out = <double>[];
  for (final r in runs) {
    final v = value(r);
    if (v != null && !v.isNaN) out.add(v);
  }
  return out;
}

String _statLine(String name, List<double> values, {int digits = 2}) {
  final s = GlassRepeatStats.of(values);
  if (s == null) return '$name n/a (no valid repeats)';
  return '$name median=${_f(s.median, digits)} min=${_f(s.min, digits)} '
      'max=${_f(s.max, digits)} range=${_f(s.range, digits)} '
      'cv_pct=${_f(s.cvPercent, 1)} n=${values.length}';
}

/// The full diagnostic report: device, VSync and frame production, per-run and
/// repeatability results, layer-count scaling, frame-rate evidence, validity,
/// conclusions and open questions. Every conclusion is computed from the
/// valid runs and worded as evidence, not as a fix.
String formatGlassDiagnosticReport({
  required String status,
  required List<String> deviceLines,
  required double reportedHz,
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

  final valid = results.where(_isMeasured).toList();
  final repeats = plan.runs.fold<int>(0, (m, r) => r.repeat > m ? r.repeat : m);

  add('sistrum-glass-diagnostic');
  add('status=$status');
  add('started=${startedAt?.toIso8601String() ?? 'n/a'}');
  add('ended=${endedAt?.toIso8601String() ?? 'n/a'}');
  if (cancelReason != null) add('cancel_reason=$cancelReason');
  if (failure != null) add('failure=$failure');
  add('repeats_per_configuration=$repeats runs_planned=${plan.runs.length}');
  add(
    'warmup_s=${plan.warmup.inSeconds} measure_s=${plan.measure.inSeconds} '
    'transition_s=${plan.transition.inSeconds}',
  );
  add(
    'scroll_speed_target=${kGlassBenchmarkSpeed.pxPerSecond.toStringAsFixed(0)} '
    'logical_px_per_second (Ticker-driven, deterministic)',
  );
  add(
    'run_order=counterbalanced: each round rotates the configuration list, '
    'odd rounds run it backwards',
  );

  section('1. Device, build and clocks');
  for (final line in deviceLines) {
    add(line);
  }
  add('refresh_reported_hz=${_f(reportedHz, 2)}');
  add(
    'refresh_requested_hz=not accessible from Flutter (needs a native read '
    'of the window preferred mode; see the adb steps in the root-cause doc)',
  );
  add(
    'thermal_state=not accessible from Dart; capture with '
    '`adb shell dumpsys thermalservice` before and after the run',
  );
  add('clock_engine=$kGlassClockEngine');
  add('clock_delivery=$kGlassClockDelivery');
  add('Engine and delivery intervals are never subtracted from each other.');

  section('2. Executed order and validity');
  add(
    'valid=${valid.length} '
    'invalid=${results.where((r) => r.validity == GlassBenchmarkValidity.invalid).length} '
    'incomplete=${results.where((r) => r.validity == GlassBenchmarkValidity.incomplete).length} '
    'cancelled=${results.where((r) => r.validity == GlassBenchmarkValidity.cancelled).length} '
    'not_run=${results.where((r) => r.validity == GlassBenchmarkValidity.notRun).length}',
  );
  add(
    'Invalid, incomplete, cancelled and not-run runs are listed here and '
    'excluded from every statistic. No run was replaced or retried.',
  );
  for (final r in results) {
    add(
      'order=${r.runOrder} repeat=${r.repeat} config=${_config(r)} '
      'validity=${_validityText(r.validity)}',
    );
    for (final reason in r.reasons) {
      add('  reason: $reason');
    }
  }

  section('3. VSync and frame production (valid runs)');
  if (valid.isEmpty) add('no valid runs');
  for (final r in valid) {
    final sch = r.schedule;
    add(
      'order=${r.runOrder} config=${_config(r)} '
      'nominal_ms=${_f(sch?.nominalPeriodMs, 3)} '
      'vsync_p50_ms=${_f(sch?.vsync.p50, 2)} '
      'vsync_p90_ms=${_f(sch?.vsync.p90, 2)} '
      'vsync_p99_ms=${_f(sch?.vsync.p99, 2)} '
      'implied_vsync_hz=${_f(sch?.impliedVsyncHz, 2)} '
      'long_vsync=${sch?.longVsyncIntervals ?? 'n/a'} '
      'missed_slots=${sch?.missedSlots ?? 'n/a'} '
      'begin_p50_ms=${_f(sch?.begin.p50, 2)} '
      'begin_p90_ms=${_f(sch?.begin.p90, 2)} '
      'raster_finish_p50_ms=${_f(sch?.raster.p50, 2)} '
      'frames_per_s=${_f(_framesPerSecond(r), 2)} '
      'frame_begin_callbacks=${r.frameBegins} '
      'frame_timings_received=${r.frameTimings}',
    );
  }

  section('4. Per-run performance (valid runs)');
  if (valid.isEmpty) add('no valid runs');
  for (final r in valid) {
    final s = r.summary!;
    add(
      'order=${r.runOrder} config=${_config(r)} '
      'raster_ms p50=${_f(s.rasterP50Ms, 2)} p90=${_f(s.rasterP90Ms, 2)} '
      'p99=${_f(s.rasterP99Ms, 2)} | '
      'span_ms p50=${_f(s.spanP50Ms, 2)} p90=${_f(s.spanP90Ms, 2)} '
      'p99=${_f(s.spanP99Ms, 2)} | '
      'exceedance_pct=${_f(s.exceedancePct, 1)} frames=${s.frames} '
      'elapsed_ms=${_f(s.elapsedMs, 0)} '
      'scroll_px_per_s=${_f(r.scrollOverallPxPerSecond, 1)}',
    );
  }

  // Configurations in first-appearance order.
  final groups = <String, List<GlassBenchmarkModeResult>>{};
  for (final r in results) {
    groups.putIfAbsent(_configKey(r), () => []).add(r);
  }
  List<GlassBenchmarkModeResult> measuredOf(String key) => [
    for (final r in groups[key]!)
      if (_isMeasured(r)) r,
  ];

  section('4b. Per-run cross-tab (existing data)');
  for (final line in glassCrossTabLines(results)) {
    add(line);
  }

  section('5. Repeatability per configuration (valid repeats only)');
  for (final key in groups.keys) {
    final all = groups[key]!;
    final ok = measuredOf(key);
    add('config=${_config(all.first)} valid=${ok.length}/${all.length}');
    if (ok.isEmpty) continue;
    add(
      '  ${_statLine('raster_p50_ms', _pick(ok, (r) => r.summary!.rasterP50Ms))}',
    );
    add(
      '  ${_statLine('raster_p90_ms', _pick(ok, (r) => r.summary!.rasterP90Ms))}',
    );
    add(
      '  ${_statLine('raster_p99_ms', _pick(ok, (r) => r.summary!.rasterP99Ms))}',
    );
    add(
      '  ${_statLine('span_p90_ms', _pick(ok, (r) => r.summary!.spanP90Ms))}',
    );
    add(
      '  ${_statLine('span_p99_ms', _pick(ok, (r) => r.summary!.spanP99Ms))}',
    );
    add(
      '  ${_statLine('exceedance_pct', _pick(ok, (r) => r.summary!.exceedancePct), digits: 1)}',
    );
    add('  ${_statLine('frames_per_s', _pick(ok, _framesPerSecond))}');
    add(
      '  ${_statLine('implied_vsync_hz', _pick(ok, (r) => r.schedule?.impliedVsyncHz))}',
    );
  }

  section('6. Layer-count scaling: New Full Glass');
  final scalingKeys = [
    for (final n in kGlassLayerScalingSurfaces) 'newFullGlass-s$n',
  ];
  final scaling = <int, GlassRepeatStats?>{};
  for (final key in scalingKeys) {
    final surfaces = int.parse(key.split('-s').last);
    if (!groups.containsKey(key)) {
      scaling[surfaces] = null;
      continue;
    }
    final ok = measuredOf(key);
    scaling[surfaces] = GlassRepeatStats.of(
      _pick(ok, (r) => r.summary!.rasterP90Ms),
    );
    final spans = GlassRepeatStats.of(_pick(ok, (r) => r.summary!.spanP90Ms));
    final exceed = GlassRepeatStats.of(
      _pick(ok, (r) => r.summary!.exceedancePct),
    );
    add(
      'surfaces=$surfaces valid=${ok.length}/${groups[key]!.length} '
      'raster_p90_median_ms=${_f(scaling[surfaces]?.median, 2)} '
      '[min ${_f(scaling[surfaces]?.min, 2)}, max ${_f(scaling[surfaces]?.max, 2)}] '
      'span_p90_median_ms=${_f(spans?.median, 2)} '
      'exceedance_median_pct=${_f(exceed?.median, 1)}',
    );
  }
  final one = scaling[1];
  final two = scaling[2];
  final four = scaling[4];
  if (one == null || two == null || four == null) {
    add(
      'scaling_verdict=insufficient valid runs to judge (need 1, 2 and 4 surfaces)',
    );
  } else {
    final s12 = glassStepsSeparated(one, two);
    final s24 = glassStepsSeparated(two, four);
    final s14 = glassStepsSeparated(one, four);
    add(
      'step_1_to_2_separated=$s12 step_2_to_4_separated=$s24 '
      'step_1_to_4_separated=$s14',
    );
    add(
      'scaling_verdict=${s12 && s24
          ? 'consistent increase with surface count (every step separated by its repeats)'
          : s14
          ? 'increase from 1 to 4 surfaces; the intermediate step is not separated'
          : 'no repeat-separated increase in this run'}',
    );
  }
  add('geometry_1=mini player only');
  add('geometry_2=mini player and tab bar');
  add('geometry_4=mini player, tab bar, header back button and header capsule');
  add(
    'interpretation=the surface steps also add glass-covered area, so this '
    'is layer count together with covered pixels; it is scaling overhead, not '
    'evidence of repeated backdrop readbacks.',
  );

  section('7. Frame-rate evidence (44.9 frames/s pattern)');
  for (final key in groups.keys) {
    final ok = measuredOf(key);
    if (ok.isEmpty) continue;
    final fps = GlassRepeatStats.of(_pick(ok, _framesPerSecond));
    final vsyncHz = GlassRepeatStats.of(
      _pick(ok, (r) => r.schedule?.impliedVsyncHz),
    );
    add(
      'config=${_config(ok.first)} frames_per_s_median=${_f(fps?.median, 2)} '
      'implied_vsync_hz_median=${_f(vsyncHz?.median, 2)} '
      'reported_hz=${_f(reportedHz, 2)}',
    );
  }

  section('8. Conclusions (evidence only; computed from valid runs)');
  var concluded = false;
  for (final key in groups.keys) {
    final ok = measuredOf(key);
    if (ok.isEmpty) continue;
    concluded = true;
    final fps = GlassRepeatStats.of(_pick(ok, _framesPerSecond))?.median;
    final vsyncHz = GlassRepeatStats.of(
      _pick(ok, (r) => r.schedule?.impliedVsyncHz),
    )?.median;
    final missed = GlassRepeatStats.of(
      _pick(ok, (r) => r.schedule?.missedSlots.toDouble()),
    )?.median;
    final name = _config(ok.first);
    if (fps == null || vsyncHz == null) {
      add('$name: inconclusive (no frame or vsync data)');
    } else if (_within(vsyncHz, reportedHz, 0.05) && fps < reportedHz * 0.9) {
      add(
        '$name: the vsync cadence matches the reported refresh, but frames '
        'per second are lower; missed_slots median=${_f(missed, 1)}. '
        'Candidate: frames are not produced or presented on some vsyncs '
        '(scheduling or presentation side). Confirm with the FrameTimeline trace.',
      );
    } else if (_within(vsyncHz, fps, 0.05)) {
      add(
        '$name: the engine vsync cadence itself runs near the frame rate. '
        'Candidate: the display or its refresh policy runs below the reported '
        'rate. Confirm with the adb refresh query.',
      );
    } else if (fps >= reportedHz * 0.95) {
      add(
        '$name: frames per second are near the reported refresh; the '
        '44.9 pattern is not reproduced in this configuration.',
      );
    } else {
      add(
        '$name: inconclusive from Flutter timings; capture the adb and '
        'FrameTimeline steps in the root-cause doc.',
      );
    }
  }
  if (!concluded) add('no valid runs, so no conclusion is drawn');

  section('9. Unresolved questions');
  add(
    '- Requested versus observed display refresh during each run: needs the adb '
    'refresh query, not available from Dart.',
  );
  add(
    '- Android presentation drops after raster: needs the FrameTimeline trace.',
  );
  add(
    '- Whether the surface steps cost more from layers or from covered pixels: '
    'needs an equal-area experiment (one large layer against four small ones).',
  );
  add(
    '- Whether New Full Glass runs its shaders on the device: only the widget '
    'tree is checked (full_gpu is a configuration result, not a GPU execution result).',
  );
  add(
    '- Thermal state during the runs: not captured by Dart; see the adb command above.',
  );
  return out.join('\n');
}

bool _within(double a, double b, double tolerance) =>
    b != 0 && (a - b).abs() / b.abs() <= tolerance;
