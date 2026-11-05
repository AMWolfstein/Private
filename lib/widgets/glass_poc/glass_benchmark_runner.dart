import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sistrum/services/display/display_refresh_rate.dart';
import 'package:sistrum/services/performance/glass_benchmark_aggregator.dart';
import 'package:sistrum/services/performance/glass_frame_schedule.dart';
import 'package:sistrum/widgets/glass_poc/glass_benchmark_run.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_auto_scroll.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_mode.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_scene.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_render_path.dart';

/// The five modes of the full benchmark, in run order.
const List<SistrumGlassMode> kGlassBenchmarkModes = [
  SistrumGlassMode.transparentBaseline,
  SistrumGlassMode.liquidGlass,
  SistrumGlassMode.newFullGlass,
  SistrumGlassMode.newFakeGlass,
  SistrumGlassMode.basicBlur,
];

/// Scroll validity limits. A run must keep its speed within the tolerance and
/// must not stop for longer than the gap limit, or it is invalid.
const double kGlassBenchmarkSpeedTolerance = 0.05;
const double kGlassBenchmarkMaxScrollGapSeconds = 0.5;
const double kGlassBenchmarkMinActiveFraction = 0.95;

/// Target speed for every run of the benchmark.
const SistrumScrollSpeed kGlassBenchmarkSpeed = SistrumScrollSpeed.fast;

/// Timing and runs of one benchmark. The default is the 60-second protocol with
/// one run per mode. Tests pass shorter values through the same code path.
class GlassBenchmarkPlan {
  GlassBenchmarkPlan({
    List<SistrumGlassMode> modes = kGlassBenchmarkModes,
    List<GlassBenchmarkRun>? runs,
    this.transition = const Duration(seconds: 2),
    this.warmup = const Duration(seconds: 5),
    this.measure = const Duration(seconds: 60),
    this.modeTimeout = const Duration(seconds: 30),
    this.diagnostic = false,
    this.backdropSharing = false,
  }) : runs = runs ?? [for (final mode in modes) GlassBenchmarkRun(mode: mode)];

  /// The diagnostic repeatability protocol: every configuration of
  /// [glassDiagnosticConfigurations] three times, in counterbalanced order.
  /// Same timing as the standard protocol for each run.
  factory GlassBenchmarkPlan.diagnostic({
    GlassBenchmarkPlan? timing,
    bool includeBasicBlur = false,
  }) {
    final base = timing ?? GlassBenchmarkPlan();
    return GlassBenchmarkPlan(
      runs: glassDiagnosticRunOrder(
        configurations: glassDiagnosticConfigurations(
          includeBasicBlur: includeBasicBlur,
        ),
      ),
      transition: base.transition,
      warmup: base.warmup,
      measure: base.measure,
      modeTimeout: base.modeTimeout,
      diagnostic: true,
    );
  }

  /// Isolated A/B protocol; preserves the original benchmark and renderers.
  factory GlassBenchmarkPlan.backdropSharing({GlassBenchmarkPlan? timing}) {
    final base = timing ?? GlassBenchmarkPlan();
    return GlassBenchmarkPlan(
      runs: appGlassBackdropSharingRuns(),
      transition: base.transition,
      warmup: base.warmup,
      measure: base.measure,
      modeTimeout: base.modeTimeout,
      diagnostic: true,
      backdropSharing: true,
    );
  }

  final bool backdropSharing;

  /// The runs in the order they execute.
  final List<GlassBenchmarkRun> runs;

  /// Whether this is the diagnostic repeatability protocol.
  final bool diagnostic;

  /// Pause between runs. The list is stopped and the next renderer mounts.
  final Duration transition;

  /// Active scrolling before measurement. Frames are excluded.
  final Duration warmup;

  /// Length of the measured interval, by the monotonic Stopwatch.
  final Duration measure;

  /// Longest time a run may wait to start measuring (warm-up and a verified
  /// render path). Past this, the run is invalid and the next one starts.
  final Duration modeTimeout;
}

enum GlassBenchmarkPhase {
  idle,
  transition,
  warmup,
  measuring,
  complete,
  failed,
  cancelled,
}

/// Whether one run can be compared. Reasons are listed in the report.
enum GlassBenchmarkValidity {
  /// Frames observed, the render path matched, coverage is complete.
  valid,

  /// Frames observed and complete, but the path cannot be verified for this
  /// mode (the widgets package is not instrumented).
  validPathUnverified,

  /// Frames observed, but a gap or buffer overflow makes it incomplete.
  incomplete,

  /// Not usable: no frames, a render path mismatch, or measurement never
  /// started.
  invalid,

  /// Stopped before the run finished.
  cancelled,

  /// Not reached because the benchmark stopped first.
  notRun,
}

/// The render path a mode must show during measurement, or null when the
/// mode is not verifiable.
SistrumGlassRenderPath? expectedGlassRenderPath(SistrumGlassMode mode) =>
    switch (mode) {
      SistrumGlassMode.transparentBaseline => SistrumGlassRenderPath.none,
      SistrumGlassMode.basicBlur => SistrumGlassRenderPath.backdropFilter,
      SistrumGlassMode.newFullGlass ||
      SistrumGlassMode.newFullGlassSharedBackdrop =>
        SistrumGlassRenderPath.fullGpu,
      SistrumGlassMode.newFakeGlass => SistrumGlassRenderPath.fakeBackdrop,
      SistrumGlassMode.liquidGlass ||
      SistrumGlassMode.referenceGlass ||
      SistrumGlassMode.sistrumHybrid => null,
    };

/// One mode's result.
class GlassBenchmarkModeResult {
  const GlassBenchmarkModeResult({
    required this.mode,
    required this.validity,
    required this.reasons,
    required this.measurementStarted,
    required this.summary,
    required this.expectedPath,
    required this.pathSamples,
    required this.pathMatches,
    required this.lastPath,
    required this.fallbackSeen,
    required this.scrollOverallPxPerSecond,
    required this.scrollMeasuredSeconds,
    required this.boundaryTurns,
    required this.scrollDirection,
    this.scrollDistancePx = 0,
    this.scrollActiveFraction,
    this.scrollTicks = 0,
    this.scrollUnattachedTicks = 0,
    this.scrollMaxTickGapSeconds = 0,
    this.frameBegins = 0,
    this.frameTimings = 0,
    this.surfaces = 4,
    this.repeat = 1,
    this.runOrder = 0,
    this.schedule,
    this.refreshHzStart,
    this.refreshHzEnd,
    this.nominalHz,
    this.nominalSource,
    this.androidStart,
    this.androidEnd,
    this.displayModeChanges = 0,
    this.backdropConfiguration,
  });

  final SistrumGlassMode mode;

  /// Glass surfaces the run drew (1, 2 or 4).
  final int surfaces;

  /// 1-based repeat of this configuration, and the 1-based position of this
  /// run in the executed order. Zero when the run did not start.
  final int repeat;
  final int runOrder;

  /// VSync, callback and raster intervals, or null when measurement never began.
  final GlassFrameScheduleSummary? schedule;

  /// Reported display refresh (`FlutterView.display.refreshRate`) when the
  /// measured interval began and when it ended. Reported by the engine, not
  /// measured on the panel. Null when measurement never began (end) or the
  /// interval never started (start).
  final double? refreshHzStart;
  final double? refreshHzEnd;

  /// Nominal refresh rate the frame budget of this run uses, and where it
  /// came from. Null when measurement never began. Android's active mode is
  /// the source whenever Android reported one.
  final double? nominalHz;
  final DisplayRefreshSource? nominalSource;

  /// Android's display report at the start and end of the measured interval.
  /// Null when measurement never began, or Android gave no report.
  final DisplayRefreshState? androidStart;
  final DisplayRefreshState? androidEnd;

  /// Active-mode changes Android reported during the measured interval. Any
  /// change makes the run invalid: its rate-dependent metrics mix two rates.
  final int displayModeChanges;

  /// Surface-role group assignments and stage geometry at measurement start.
  final String? backdropConfiguration;

  final GlassBenchmarkValidity validity;
  final List<String> reasons;
  final bool measurementStarted;
  final GlassBenchmarkSummary? summary;

  /// The path this mode must show, or null when it is not verifiable.
  final SistrumGlassRenderPath? expectedPath;
  final int pathSamples;
  final int pathMatches;

  /// The last path observed, as its wire name, or `unknown` when none was seen.
  final String lastPath;
  final bool fallbackSeen;

  /// Measured displacement over the whole interval, or null.
  final double? scrollOverallPxPerSecond;
  final double scrollMeasuredSeconds;
  final int boundaryTurns;
  final String scrollDirection;

  /// Total displacement applied during the measured interval, in logical px.
  final double scrollDistancePx;

  /// Active scrolling seconds divided by the Stopwatch time of the interval.
  /// Null when the interval did not start.
  final double? scrollActiveFraction;
  final int scrollTicks;
  final int scrollUnattachedTicks;
  final double scrollMaxTickGapSeconds;

  /// Drawn frames (persistent callbacks) and FrameTiming callbacks during the
  /// measured interval. Their difference shows timings that never arrived.
  final int frameBegins;
  final int frameTimings;
}

/// Live state for the status line. Updated about once a second, and only a
/// small status widget listens to it, so the measured scene is not rebuilt.
class GlassBenchmarkProgress {
  const GlassBenchmarkProgress({
    required this.phase,
    required this.modeIndex,
    required this.modeCount,
    required this.modeLabel,
    required this.measuredMs,
    required this.message,
  });

  const GlassBenchmarkProgress.idle()
    : phase = GlassBenchmarkPhase.idle,
      modeIndex = 0,
      modeCount = 0,
      modeLabel = '',
      measuredMs = 0,
      message = '';

  final GlassBenchmarkPhase phase;
  final int modeIndex;
  final int modeCount;
  final String modeLabel;

  /// Monotonic time measured so far in the current run.
  final double measuredMs;
  final String message;
}

/// The POC settings the benchmark changes, so they can be restored afterwards.
typedef GlassBenchmarkConfig = ({
  SistrumGlassMode mode,
  bool sharedBackdrop,
  SistrumScrollSpeed speed,
  SistrumGlassScene scene,
});

/// What the runner needs from the page. The page owns the providers, the
/// scroller and the frame monitor. Keeping them behind this interface keeps
/// the runner testable and keeps it out of the widget tree.
abstract interface class GlassBenchmarkHost {
  GlassBenchmarkConfig captureConfig();

  /// Sets the mode, the surface count and the fixed benchmark settings (900 px/s,
  /// animation and shared backdrop off), resets the frame monitor, holds frames,
  /// and restarts scrolling with the warm-up.
  void applyRun(GlassBenchmarkRun run);

  /// Stops scrolling and moves the list back to offset 0.
  void haltRun();

  void restoreConfig(GlassBenchmarkConfig config);

  SistrumGlassRenderReport renderPath();
  SistrumScrollStatus? scrollStatus();

  /// Drawn frames and FrameTiming callbacks since the monitor started.
  ({int beginFrames, int timings}) frameCounts();

  /// Connects the aggregator to the frame stream, or disconnects it with null.
  void attachAggregator(GlassBenchmarkAggregator? aggregator);

  /// Connects the schedule recorder to the frame stream, or disconnects it.
  void attachSchedule(GlassFrameScheduleRecorder? recorder);

  /// The display refresh rate the engine reports now. Reported, not measured.
  double reportedRefreshHz();

  /// Android's latest display report (`Display.getMode()` and friends), or
  /// [DisplayRefreshState.unavailable].
  DisplayRefreshState androidDisplay();

  /// Active-mode changes Android has reported since the page opened. The runner
  /// compares the value at the start and end of a measured interval.
  int displayModeChangeCount();
}

/// Deterministic run of the benchmark:
/// idle, transition, warmup, measuring, then transition again or complete.
/// Failed and cancelled are terminal. Nothing resumes after an interruption.
class GlassBenchmarkRunner {
  GlassBenchmarkRunner({
    required this.host,
    required this.budgetUs,
    required this.onPhaseChanged,
    required this.reportBuilder,
    this.backdropConfiguration,
    GlassBenchmarkPlan? plan,
    Stopwatch? stopwatch,
  }) : plan = plan ?? GlassBenchmarkPlan(),
       _stopwatch = stopwatch ?? Stopwatch(),
       progress = ValueNotifier(const GlassBenchmarkProgress.idle()) {
    _aggregator = GlassBenchmarkAggregator(
      budgetUs: budgetUs,
      turnsReader: () => host.scrollStatus()?.totalBoundaryTurns ?? 0,
    );
  }

  final GlassBenchmarkHost host;
  final String Function()? backdropConfiguration;
  String? _backdropAtStart;
  bool _backdropChanged = false;

  /// Called by layout as well as sampled by the timer, so a transient resize
  /// cannot disappear between samples and leave the measured run valid.
  void observeBackdropConfiguration(String configuration) {
    if (_measurementStarted && configuration != _backdropAtStart) {
      _backdropChanged = true;
    }
  }

  final double budgetUs;

  /// The plan of the current or last run. [start] may replace it.
  GlassBenchmarkPlan plan;

  /// Called on every phase change (start, run boundaries, end). It is not
  /// called once a second, so the page rebuilds only at those points.
  final VoidCallback onPhaseChanged;

  /// Builds the report text from the finished runner. The page supplies the
  /// device lines, which only it can read.
  final String Function(GlassBenchmarkRunner runner) reportBuilder;

  /// Live status for the status widget only.
  final ValueNotifier<GlassBenchmarkProgress> progress;

  final Stopwatch _stopwatch;
  late GlassBenchmarkAggregator _aggregator;
  GlassFrameScheduleRecorder? _frameSchedule;
  double? _refreshHzStart;
  DisplayRefreshReference? _nominal;
  DisplayRefreshState? _androidStart;
  DisplayRefreshState? _androidEnd;
  int _modeChangesStart = 0;
  int _modeChangesEnd = 0;

  GlassBenchmarkPhase _phase = GlassBenchmarkPhase.idle;
  GlassBenchmarkConfig? _savedConfig;
  int _modeIndex = 0;
  final List<GlassBenchmarkModeResult> _results = [];
  Timer? _timer;
  Timer? _tick;
  bool _measurementStarted = false;
  ({int beginFrames, int timings})? _frameStart;
  int _pathSamples = 0;
  int _pathMatches = 0;
  String _lastPath = 'unknown';
  bool _fallbackSeen = false;
  String? _failure;
  String? _cancelReason;
  DateTime? _startedAt;
  DateTime? _endedAt;
  String? _reportText;

  GlassBenchmarkPhase get phase => _phase;
  bool get isRunning =>
      _phase == GlassBenchmarkPhase.transition ||
      _phase == GlassBenchmarkPhase.warmup ||
      _phase == GlassBenchmarkPhase.measuring;

  /// Full text of the report. Null until the run ends (complete, failed or
  /// cancelled).
  String? get reportText => _reportText;

  List<GlassBenchmarkModeResult> get results => List.unmodifiable(_results);
  String? get failure => _failure;
  String? get cancelReason => _cancelReason;
  DateTime? get startedAt => _startedAt;
  DateTime? get endedAt => _endedAt;

  /// Begins the run. It refuses to start while another is running. [plan]
  /// replaces the plan for this run only when given.
  void start({GlassBenchmarkPlan? plan}) {
    if (isRunning) return;
    if (plan != null) this.plan = plan;
    _results.clear();
    _reportText = null;
    _failure = null;
    _cancelReason = null;
    _startedAt = DateTime.now();
    _endedAt = null;
    _savedConfig = host.captureConfig();
    _modeIndex = 0;
    _enter(GlassBenchmarkPhase.transition);
    _publish('starting');
    _schedule(this.plan.transition, _startMode);
  }

  void _startMode() {
    _guard(() {
      final run = plan.runs[_modeIndex];
      _measurementStarted = false;
      _backdropAtStart = null;
      _backdropChanged = false;
      _pathSamples = 0;
      _pathMatches = 0;
      _lastPath = 'unknown';
      _fallbackSeen = false;
      _aggregator.discard();
      host.attachAggregator(null);
      _frameSchedule = null;
      _refreshHzStart = null;
      _nominal = null;
      _androidStart = null;
      _androidEnd = null;
      host.attachSchedule(null);
      host.applyRun(run);
      _enter(GlassBenchmarkPhase.warmup);
      _publish('warm-up');
      _schedule(plan.modeTimeout, _modeTimedOut);
      _startTick();
    });
  }

  /// Called by the page when warm-up ends and the scroller starts sampling.
  void onMeasurementStarted() {
    if (_phase != GlassBenchmarkPhase.warmup) return;
    _guard(() {
      _cancelTimer();
      _measurementStarted = true;
      _backdropAtStart = backdropConfiguration?.call();
      _stopwatch
        ..reset()
        ..start();
      // The budget follows the active display mode, not the value the engine
      // reports (see nominalDisplayRefresh). Fixed for this run.
      final flutterHz = host.reportedRefreshHz();
      final android = host.androidDisplay();
      final nominal = nominalDisplayRefresh(
        android: android,
        flutterHz: flutterHz,
      );
      _nominal = nominal;
      _androidStart = android;
      _modeChangesStart = host.displayModeChangeCount();
      final nominalBudgetUs = 1e6 / nominal.hz;
      _aggregator = GlassBenchmarkAggregator(
        budgetUs: nominalBudgetUs,
        turnsReader: () => host.scrollStatus()?.totalBoundaryTurns ?? 0,
      );
      _aggregator.begin();
      _frameStart = host.frameCounts();
      final schedule = GlassFrameScheduleRecorder(
        nominalPeriodUs: nominalBudgetUs.round(),
      );
      _frameSchedule = schedule;
      _refreshHzStart = flutterHz;
      host.attachSchedule(schedule);
      host.attachAggregator(_aggregator);
      _enter(GlassBenchmarkPhase.measuring);
      _publish('measuring');
      _schedule(plan.measure, _finishMode);
      _sampleRenderPath();
    });
  }

  void _modeTimedOut() {
    if (_phase != GlassBenchmarkPhase.warmup) return;
    _guard(() => _finishMode(timedOut: true));
  }

  void _finishMode({bool timedOut = false}) {
    if (_phase != GlassBenchmarkPhase.measuring &&
        _phase != GlassBenchmarkPhase.warmup) {
      return;
    }
    _guard(() {
      _cancelTimer();
      _stopTick();
      _stopwatch.stop();
      final elapsedUs = _stopwatch.elapsedMicroseconds;
      // Capture while the run is still active: halting clears the scroller.
      final scroll = host.scrollStatus();
      final frames = _frameDelta();
      // Close the aggregator before summarising, so an episode still open at the
      // end is closed and included.
      _aggregator.end();
      final summary = _measurementStarted
          ? _aggregator.summary(elapsedUs: elapsedUs)
          : null;
      final schedule = _measurementStarted ? _frameSchedule?.summary() : null;
      final refreshEnd = _measurementStarted ? host.reportedRefreshHz() : null;
      _captureDisplayEnd();
      host.attachAggregator(null);
      host.attachSchedule(null);
      host.haltRun();
      _results.add(
        _result(
          summary,
          scroll: scroll,
          frames: frames,
          elapsedUs: elapsedUs,
          timedOut: timedOut,
          schedule: schedule,
          refreshEnd: refreshEnd,
        ),
      );
      _modeIndex++;
      if (_modeIndex >= plan.runs.length) {
        _complete();
      } else {
        _enter(GlassBenchmarkPhase.transition);
        _publish('transition');
        _schedule(plan.transition, _startMode);
      }
    });
  }

  void _complete() {
    // Finalize first: the phase change notifies the page, which reads the report.
    _finalize(GlassBenchmarkPhase.complete);
    _enter(GlassBenchmarkPhase.complete);
    _publish('complete');
  }

  /// Stops the run because the app left the foreground or the POC closed. The
  /// interrupted run is kept as cancelled with its partial data. Nothing resumes.
  void interrupt(String reason) {
    if (!isRunning) return;
    _cancelReason = reason;
    _cancelTimer();
    _stopTick();
    _stopwatch.stop();
    final elapsedUs = _stopwatch.elapsedMicroseconds;
    final scroll = host.scrollStatus();
    final frames = _frameDelta();
    _aggregator.end();
    final partial = _measurementStarted
        ? _aggregator.summary(elapsedUs: elapsedUs)
        : null;
    final schedule = _measurementStarted ? _frameSchedule?.summary() : null;
    final refreshEnd = _measurementStarted ? host.reportedRefreshHz() : null;
    _captureDisplayEnd();
    _aggregator.discard();
    host.attachAggregator(null);
    host.attachSchedule(null);
    host.haltRun();
    _results.add(
      _result(
        partial,
        scroll: scroll,
        frames: frames,
        elapsedUs: elapsedUs,
        cancelled: true,
        schedule: schedule,
        refreshEnd: refreshEnd,
      ),
    );
    _finalize(GlassBenchmarkPhase.cancelled);
    _enter(GlassBenchmarkPhase.cancelled);
    _publish('cancelled: $reason');
  }

  void _fail(Object error) {
    _failure = error.toString();
    _cancelTimer();
    _stopTick();
    _stopwatch.stop();
    _aggregator.discard();
    host.attachAggregator(null);
    host.attachSchedule(null);
    try {
      host.haltRun();
    } on Object {
      // The run already failed; restoring the configuration is still attempted.
    }
    _finalize(GlassBenchmarkPhase.failed);
    _enter(GlassBenchmarkPhase.failed);
    _publish('failed');
  }

  /// Runs a step. Any error stops the run as failed, and the configuration is
  /// still restored.
  void _guard(void Function() step) {
    try {
      step();
    } on Object catch (error) {
      _fail(error);
    }
  }

  /// Sets the terminal phase, then builds the report from it, so the report and
  /// the phase always agree.
  void _finalize(GlassBenchmarkPhase terminal) {
    _phase = terminal;
    _endedAt = DateTime.now();
    // Mark modes that never ran, so the report lists every mode.
    for (var i = _results.length; i < plan.runs.length; i++) {
      _results.add(_notRun(plan.runs[i], i + 1));
    }
    final saved = _savedConfig;
    if (saved != null) {
      try {
        host.restoreConfig(saved);
      } on Object catch (error) {
        _failure ??= 'restore failed: $error';
      }
    }
    _stopTick();
    _cancelTimer();
    _reportText = reportBuilder(this);
  }

  void _enter(GlassBenchmarkPhase next) {
    _phase = next;
    onPhaseChanged();
  }

  /// Records one render-path observation for the current mode.
  void _sampleRenderPath() {
    if (_measurementStarted &&
        backdropConfiguration?.call() != _backdropAtStart) {
      _backdropChanged = true;
    }
    final mode = plan.runs[_modeIndex].mode;
    final expected = expectedGlassRenderPath(mode);
    final report = host.renderPath();
    _pathSamples++;
    _lastPath = report.path.wire;
    if (report.fallback == true) _fallbackSeen = true;
    if (expected != null && report.path == expected) _pathMatches++;
  }

  void _startTick() {
    _stopTick();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  void _stopTick() {
    _tick?.cancel();
    _tick = null;
  }

  void _onTick() {
    _guard(() {
      _sampleRenderPath();
      _publish(
        _phase == GlassBenchmarkPhase.measuring ? 'measuring' : 'warm-up',
      );
    });
  }

  void _publish(String message) {
    final index = _modeIndex.clamp(0, plan.runs.length - 1);
    progress.value = GlassBenchmarkProgress(
      phase: _phase,
      modeIndex: _modeIndex,
      modeCount: plan.runs.length,
      modeLabel: plan.runs[index].label,
      measuredMs: _stopwatch.elapsedMicroseconds / 1000,
      message: message,
    );
  }

  void _schedule(Duration after, void Function() action) {
    _cancelTimer();
    _timer = Timer(after, action);
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// Frame counts over the measured interval (end minus start).
  ({int beginFrames, int timings}) _frameDelta() {
    final start = _frameStart;
    if (!_measurementStarted || start == null) {
      return (beginFrames: 0, timings: 0);
    }
    final now = host.frameCounts();
    return (
      beginFrames: now.beginFrames - start.beginFrames,
      timings: now.timings - start.timings,
    );
  }

  /// Records Android's display report and the mode-change count at the end of
  /// the measured interval. Nothing is recorded before measurement began.
  void _captureDisplayEnd() {
    if (!_measurementStarted) return;
    _androidEnd = host.androidDisplay();
    _modeChangesEnd = host.displayModeChangeCount();
  }

  GlassBenchmarkModeResult _result(
    GlassBenchmarkSummary? summary, {
    required SistrumScrollStatus? scroll,
    required ({int beginFrames, int timings}) frames,
    required int elapsedUs,
    bool timedOut = false,
    bool cancelled = false,
    GlassFrameScheduleSummary? schedule,
    double? refreshEnd,
  }) {
    final run = plan.runs[_modeIndex];
    final mode = run.mode;
    _sampleRenderPath();
    final expected = expectedGlassRenderPath(mode);
    final reasons = <String>[];
    var validity = GlassBenchmarkValidity.valid;

    void worsen(GlassBenchmarkValidity v) {
      const order = [
        GlassBenchmarkValidity.valid,
        GlassBenchmarkValidity.validPathUnverified,
        GlassBenchmarkValidity.incomplete,
        GlassBenchmarkValidity.invalid,
        GlassBenchmarkValidity.cancelled,
      ];
      if (order.indexOf(v) > order.indexOf(validity)) validity = v;
    }

    if (_measurementStarted && _backdropChanged) {
      worsen(GlassBenchmarkValidity.invalid);
      reasons.add(
        'Backdrop assignment or stage geometry changed during measurement',
      );
    }
    if (cancelled) {
      worsen(GlassBenchmarkValidity.cancelled);
      reasons.add('cancelled: ${_cancelReason ?? 'unknown'}');
    }
    if (timedOut || (!_measurementStarted && !cancelled)) {
      worsen(GlassBenchmarkValidity.invalid);
      reasons.add(
        'measurement never started within ${plan.modeTimeout.inSeconds} s; '
        'last render path: $_lastPath',
      );
    }
    final frameCount = summary?.frames ?? 0;
    if (_measurementStarted && frameCount == 0) {
      worsen(GlassBenchmarkValidity.invalid);
      reasons.add('no frames observed during measurement');
    }
    if (expected != null) {
      if (_fallbackSeen || _pathMatches < _pathSamples) {
        worsen(GlassBenchmarkValidity.invalid);
        reasons.add(
          'render path mismatch: expected ${expected.wire}; '
          'samples matching $_pathMatches/$_pathSamples; '
          'last $_lastPath; fallback seen: $_fallbackSeen',
        );
      }
    } else if (_measurementStarted) {
      worsen(GlassBenchmarkValidity.validPathUnverified);
      reasons.add('render path not verified for this mode (not instrumented)');
    }

    // Scrolling: it must have run for the whole interval, at the target speed.
    // A run that only completed its timer is not valid.
    final elapsedS = elapsedUs / Duration.microsecondsPerSecond;
    final activeFraction = _measurementStarted && elapsedS > 0 && scroll != null
        ? scroll.measuredSeconds / elapsedS
        : null;
    if (_measurementStarted) {
      final target = kGlassBenchmarkSpeed.pxPerSecond;
      if (scroll == null) {
        worsen(GlassBenchmarkValidity.invalid);
        reasons.add('scroll state unavailable during measurement');
      } else {
        if (scroll.measureTicks == 0) {
          worsen(GlassBenchmarkValidity.invalid);
          reasons.add(
            'no scroll frames during measurement: the list did not move',
          );
        }
        if (scroll.unattachedTicks > 0) {
          worsen(GlassBenchmarkValidity.invalid);
          reasons.add(
            'scroll position detached during ${scroll.unattachedTicks} frames',
          );
        }
        if (scroll.maxTickGapSeconds > kGlassBenchmarkMaxScrollGapSeconds) {
          worsen(GlassBenchmarkValidity.invalid);
          reasons.add(
            'scrolling stopped for ${scroll.maxTickGapSeconds.toStringAsFixed(2)} s',
          );
        }
        if (activeFraction != null &&
            activeFraction < kGlassBenchmarkMinActiveFraction) {
          worsen(GlassBenchmarkValidity.invalid);
          reasons.add(
            'active scrolling for ${(activeFraction * 100).toStringAsFixed(1)}% '
            'of the interval',
          );
        }
        final overall = scroll.overallPxPerSecond;
        if (overall == null) {
          worsen(GlassBenchmarkValidity.invalid);
          reasons.add('actual scroll speed not measurable');
        } else if ((overall - target).abs() >
            target * kGlassBenchmarkSpeedTolerance) {
          worsen(GlassBenchmarkValidity.invalid);
          reasons.add(
            'actual scroll speed ${overall.toStringAsFixed(1)} px/s is not '
            'within ${(kGlassBenchmarkSpeedTolerance * 100).toStringAsFixed(0)}% '
            'of the ${target.toStringAsFixed(0)} px/s target',
          );
        }
      }
    }

    // Frames: every drawn frame should have a timing, and every timing should
    // be in the summary (or counted as overflow).
    if (_measurementStarted) {
      final tolerance = _frameTolerance(frames.beginFrames);
      final timingsGap = frames.beginFrames - frames.timings;
      if (timingsGap > tolerance) {
        worsen(GlassBenchmarkValidity.incomplete);
        reasons.add(
          '$timingsGap drawn frames had no FrameTiming callback '
          '(drawn ${frames.beginFrames}, timings ${frames.timings})',
        );
      }
      final kept = frameCount + (summary?.overflow ?? 0);
      if (frames.timings - kept > tolerance) {
        worsen(GlassBenchmarkValidity.incomplete);
        reasons.add(
          '${frames.timings - kept} timings did not reach the measurement',
        );
      }
    }

    if (summary != null) {
      if (summary.overflow > 0) {
        worsen(GlassBenchmarkValidity.incomplete);
        reasons.add(
          '${summary.overflow} frames past the buffer were not in the percentiles',
        );
      }
      if (summary.coverage < kGlassBenchmarkMinCoverage) {
        worsen(GlassBenchmarkValidity.incomplete);
        reasons.add(
          'frame coverage ${(summary.coverage * 100).toStringAsFixed(1)}%: '
          'callbacks were missing for part of the interval',
        );
      }
    }

    final nominal = _nominal;
    final modeChanges = _measurementStarted
        ? (_modeChangesEnd - _modeChangesStart).clamp(0, 1 << 30)
        : 0;
    if (_measurementStarted && modeChanges > 0) {
      worsen(GlassBenchmarkValidity.invalid);
      reasons.add(
        'Android reported $modeChanges display mode change(s) during the '
        'measured interval: rate-dependent metrics mix two rates',
      );
    }
    if (nominal != null && nominal.source == DisplayRefreshSource.fallback) {
      worsen(GlassBenchmarkValidity.incomplete);
      reasons.add(
        'no display refresh rate was available: the frame budget uses the '
        '${kDisplayRefreshFallbackHz.toStringAsFixed(0)} Hz fallback',
      );
    }

    return GlassBenchmarkModeResult(
      mode: mode,
      surfaces: run.surfaces,
      repeat: run.repeat,
      runOrder: _modeIndex + 1,
      schedule: schedule,
      refreshHzStart: _measurementStarted ? _refreshHzStart : null,
      refreshHzEnd: refreshEnd,
      nominalHz: _measurementStarted ? nominal?.hz : null,
      nominalSource: _measurementStarted ? nominal?.source : null,
      androidStart: _measurementStarted ? _androidStart : null,
      androidEnd: _measurementStarted ? _androidEnd : null,
      displayModeChanges: modeChanges,
      backdropConfiguration: _backdropAtStart,
      validity: validity,
      reasons: reasons,
      measurementStarted: _measurementStarted,
      summary: summary,
      expectedPath: expected,
      pathSamples: _pathSamples,
      pathMatches: _pathMatches,
      lastPath: _lastPath,
      fallbackSeen: _fallbackSeen,
      scrollOverallPxPerSecond: scroll?.overallPxPerSecond,
      scrollMeasuredSeconds: scroll?.measuredSeconds ?? 0,
      boundaryTurns: scroll?.totalBoundaryTurns ?? 0,
      scrollDirection: scroll?.direction ?? 'unknown',
      scrollDistancePx: scroll?.measuredPathPx ?? 0,
      scrollActiveFraction: activeFraction,
      scrollTicks: scroll?.measureTicks ?? 0,
      scrollUnattachedTicks: scroll?.unattachedTicks ?? 0,
      scrollMaxTickGapSeconds: scroll?.maxTickGapSeconds ?? 0,
      frameBegins: frames.beginFrames,
      frameTimings: frames.timings,
    );
  }

  /// Frames that may be in flight at the end of an interval (timings arrive
  /// a little after their frames). Two frames or 2 %, whichever is larger.
  int _frameTolerance(int drawn) => drawn * 2 ~/ 100 > 2 ? drawn * 2 ~/ 100 : 2;

  GlassBenchmarkModeResult _notRun(GlassBenchmarkRun run, int runOrder) =>
      GlassBenchmarkModeResult(
        mode: run.mode,
        surfaces: run.surfaces,
        repeat: run.repeat,
        runOrder: runOrder,
        validity: GlassBenchmarkValidity.notRun,
        reasons: const ['not reached because the benchmark stopped first'],
        measurementStarted: false,
        summary: null,
        expectedPath: expectedGlassRenderPath(run.mode),
        pathSamples: 0,
        pathMatches: 0,
        lastPath: 'unknown',
        fallbackSeen: false,
        scrollOverallPxPerSecond: null,
        scrollMeasuredSeconds: 0,
        boundaryTurns: 0,
        scrollDirection: 'unknown',
      );

  /// Stops timers and releases the progress notifier. Interrupts a run still
  /// in progress first, so nothing outlives the page.
  void dispose() {
    if (isRunning) interrupt('Glass POC closed');
    _cancelTimer();
    _stopTick();
    // The progress notifier is not disposed here: the status widget may still
    // be removing its listener as the page goes away.
  }
}
