import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sistrum/services/performance/glass_benchmark_aggregator.dart';
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

/// Target speed for every run of the benchmark.
const SistrumScrollSpeed kGlassBenchmarkSpeed = SistrumScrollSpeed.fast;

/// Timing of one benchmark. The default is the 60-second protocol. Tests pass
/// shorter values through the same code path.
class GlassBenchmarkPlan {
  const GlassBenchmarkPlan({
    this.modes = kGlassBenchmarkModes,
    this.transition = const Duration(seconds: 2),
    this.warmup = const Duration(seconds: 5),
    this.measure = const Duration(seconds: 60),
    this.modeTimeout = const Duration(seconds: 30),
  });

  final List<SistrumGlassMode> modes;

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
      SistrumGlassMode.newFullGlass => SistrumGlassRenderPath.fullGpu,
      SistrumGlassMode.newFakeGlass => SistrumGlassRenderPath.fakeBackdrop,
      SistrumGlassMode.liquidGlass || SistrumGlassMode.referenceGlass => null,
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
  });

  final SistrumGlassMode mode;
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

  /// Sets the mode and the fixed benchmark settings (Scene D, 900 px/s,
  /// animation and shared backdrop off), resets the frame monitor, holds frames,
  /// and restarts scrolling with the warm-up.
  void applyRun(SistrumGlassMode mode);

  /// Stops scrolling and moves the list back to offset 0.
  void haltRun();

  void restoreConfig(GlassBenchmarkConfig config);

  SistrumGlassRenderReport renderPath();
  SistrumScrollStatus? scrollStatus();

  /// Connects the aggregator to the frame stream, or disconnects it with null.
  void attachAggregator(GlassBenchmarkAggregator? aggregator);
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
    this.plan = const GlassBenchmarkPlan(),
    Stopwatch? stopwatch,
  }) : _stopwatch = stopwatch ?? Stopwatch(),
       progress = ValueNotifier(const GlassBenchmarkProgress.idle()) {
    _aggregator = GlassBenchmarkAggregator(
      budgetUs: budgetUs,
      turnsReader: () => host.scrollStatus()?.totalBoundaryTurns ?? 0,
    );
  }

  final GlassBenchmarkHost host;
  final double budgetUs;
  final GlassBenchmarkPlan plan;

  /// Called on every phase change (start, run boundaries, end). It is not
  /// called once a second, so the page rebuilds only at those points.
  final VoidCallback onPhaseChanged;

  /// Builds the report text from the finished runner. The page supplies the
  /// device lines, which only it can read.
  final String Function(GlassBenchmarkRunner runner) reportBuilder;

  /// Live status for the status widget only.
  final ValueNotifier<GlassBenchmarkProgress> progress;

  final Stopwatch _stopwatch;
  late final GlassBenchmarkAggregator _aggregator;

  GlassBenchmarkPhase _phase = GlassBenchmarkPhase.idle;
  GlassBenchmarkConfig? _savedConfig;
  int _modeIndex = 0;
  final List<GlassBenchmarkModeResult> _results = [];
  Timer? _timer;
  Timer? _tick;
  bool _measurementStarted = false;
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

  /// Begins the run. It refuses to start while another is running.
  void start() {
    if (isRunning) return;
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
    _schedule(plan.transition, _startMode);
  }

  void _startMode() {
    _guard(() {
      final mode = plan.modes[_modeIndex];
      _measurementStarted = false;
      _pathSamples = 0;
      _pathMatches = 0;
      _lastPath = 'unknown';
      _fallbackSeen = false;
      _aggregator.discard();
      host.attachAggregator(null);
      host.applyRun(mode);
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
      _stopwatch
        ..reset()
        ..start();
      _aggregator.begin();
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
      final summary = _measurementStarted
          ? _aggregator.summary(elapsedUs: elapsedUs)
          : null;
      _aggregator.end();
      host.attachAggregator(null);
      host.haltRun();
      _results.add(_result(summary, timedOut: timedOut));
      _modeIndex++;
      if (_modeIndex >= plan.modes.length) {
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
    final partial = _measurementStarted
        ? _aggregator.summary(elapsedUs: _stopwatch.elapsedMicroseconds)
        : null;
    _aggregator.discard();
    host.attachAggregator(null);
    host.haltRun();
    _results.add(_result(partial, cancelled: true));
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
    for (var i = _results.length; i < plan.modes.length; i++) {
      _results.add(_notRun(plan.modes[i]));
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
    final mode = plan.modes[_modeIndex];
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
    final index = _modeIndex.clamp(0, plan.modes.length - 1);
    progress.value = GlassBenchmarkProgress(
      phase: _phase,
      modeIndex: _modeIndex,
      modeCount: plan.modes.length,
      modeLabel: plan.modes[index].label,
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

  GlassBenchmarkModeResult _result(
    GlassBenchmarkSummary? summary, {
    bool timedOut = false,
    bool cancelled = false,
  }) {
    final mode = plan.modes[_modeIndex];
    final expected = expectedGlassRenderPath(mode);
    final scroll = host.scrollStatus();
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
    final frames = summary?.frames ?? 0;
    if (_measurementStarted && frames == 0) {
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

    return GlassBenchmarkModeResult(
      mode: mode,
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
    );
  }

  GlassBenchmarkModeResult _notRun(SistrumGlassMode mode) =>
      GlassBenchmarkModeResult(
        mode: mode,
        validity: GlassBenchmarkValidity.notRun,
        reasons: const ['not reached because the benchmark stopped first'],
        measurementStarted: false,
        summary: null,
        expectedPath: expectedGlassRenderPath(mode),
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
