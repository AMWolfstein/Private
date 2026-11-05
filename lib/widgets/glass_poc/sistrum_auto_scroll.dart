import 'dart:typed_data';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:sistrum/services/performance/perf_frame_window.dart';

/// Auto-scroll presets for Scene D of the Glass POC (developer-only). Each speed
/// is the displacement of the list's scroll offset per second of active
/// scrolling, in Flutter logical pixels.
enum SistrumScrollSpeed {
  slow('Slow — 150 px/s', 150),
  normal('Normal — 400 px/s', 400),
  fast('Fast — 900 px/s', 900);

  const SistrumScrollSpeed(this.label, this.pxPerSecond);

  final String label;

  /// Logical pixels of scroll offset per second.
  final double pxPerSecond;
}

/// Active scrolling time before the benchmark sample starts. Scrolling runs
/// during warm-up, but its frames and displacement samples are not counted.
const double kSistrumScrollWarmupSeconds = 2;

/// Minimum span of samples before an actual speed is reported. Shorter spans
/// are too noisy, so the report says unavailable instead.
const double kSistrumScrollMinSpanSeconds = 0.5;

/// Scroll offset after [seconds] of active scrolling at [pxPerSecond].
///
/// The list moves forward to [maxExtent], then back to 0, and so on. This is a
/// triangle wave over the distance travelled, so the offset is continuous: each
/// end is a turn, not a reset, and the speed stays [pxPerSecond] everywhere.
double sistrumAutoScrollOffset({
  required double seconds,
  required double pxPerSecond,
  required double maxExtent,
}) {
  if (!(maxExtent > 0) || !(seconds > 0)) return 0;
  final period = 2 * maxExtent;
  final phase = (seconds * pxPerSecond) % period;
  return phase <= maxExtent ? phase : period - phase;
}

/// Whether the list is moving towards the end (true) or back to the start
/// (false) at [seconds]. The turning points themselves count as moving back.
bool sistrumAutoScrollMovingDown({
  required double seconds,
  required double pxPerSecond,
  required double maxExtent,
}) {
  if (!(maxExtent > 0) || !(seconds > 0)) return true;
  final phase = (seconds * pxPerSecond) % (2 * maxExtent);
  return phase < maxExtent;
}

/// What the scroller reports for a copied benchmark report.
class SistrumScrollStatus {
  const SistrumScrollStatus({
    required this.speed,
    required this.running,
    required this.measuring,
    required this.actualPxPerSecond,
    required this.direction,
    required this.samples,
    required this.boundaryTransitions,
    required this.overallPxPerSecond,
    required this.measuredSeconds,
    required this.totalBoundaryTurns,
    this.measuredPathPx = 0,
    this.measureTicks = 0,
    this.unattachedTicks = 0,
    this.maxTickGapSeconds = 0,
    this.maxExtent = 0,
  });

  /// The target speed (the preset), never the measured one.
  final SistrumScrollSpeed speed;

  /// Whether the ticker is active. A stopped list holds its position.
  final bool running;

  /// Whether warm-up has ended and samples are being counted.
  final bool measuring;

  /// Measured offset displacement per second over the sample window, or null
  /// when there are too few samples to say.
  final double? actualPxPerSecond;

  /// `down`, `up`, or `stopped`.
  final String direction;

  /// Displacement samples in the window (at most one per scrolled frame).
  final int samples;

  /// Turns at the ends of the scroll range, in the sample window. Each turn is
  /// marked on its sample, so a window can be checked for boundary frames.
  final int boundaryTransitions;

  /// Displacement per second over the whole measured interval (not the window),
  /// or null before warm-up ends or when the interval is shorter than 0.5 s.
  final double? overallPxPerSecond;

  /// Active seconds since measurement started (the whole interval).
  final double measuredSeconds;

  /// Turns at the ends of the range since measurement started (the whole
  /// interval, not the sample window).
  final int totalBoundaryTurns;

  /// Total displacement applied to the list since measurement started, in
  /// logical pixels (sum of the absolute offset changes).
  final double measuredPathPx;

  /// Scroll frames (ticks) received while measuring.
  final int measureTicks;

  /// Ticks received while measuring with no attached scroll position. Any
  /// such tick means the list was detached while the run was supposed to scroll.
  final int unattachedTicks;

  /// Longest time, in active seconds, between two consecutive ticks while
  /// measuring. A large value is a scroll stop, separate from a slow frame.
  final double maxTickGapSeconds;

  /// Scrollable range seen while measuring (maxScrollExtent), in logical pixels.
  final double maxExtent;
}

/// The one auto-scroll implementation shared by every renderer on the Glass POC.
///
/// It drives [controller] from a [Ticker], so each frame's offset comes from the
/// elapsed frame time, not from a fixed frame rate. It never uses `animateTo`,
/// so no animation can overlap. Stopping keeps the offset and the active time;
/// resuming continues from there. [restart] begins a fresh run from offset 0.
class SistrumAutoScroller {
  SistrumAutoScroller({
    required TickerProvider vsync,
    required this.controller,
    SistrumScrollSpeed speed = SistrumScrollSpeed.normal,
    this.onMeasurementStart,
    this.measurementReady,
    this.warmupSeconds = kSistrumScrollWarmupSeconds,
  }) : _speed = speed {
    _ticker = vsync.createTicker(_onTick);
  }

  final ScrollController controller;

  /// Active seconds of scrolling before sampling starts. The benchmark uses 5.
  final double warmupSeconds;

  /// Called once per run, when warm-up ends and sampling starts.
  final VoidCallback? onMeasurementStart;

  /// Extra condition before sampling starts (after warm-up). Scroll keeps
  /// moving while it is false, but nothing is sampled.
  final bool Function()? measurementReady;

  late final Ticker _ticker;
  SistrumScrollSpeed _speed;

  /// Active seconds before the current ticker run. Stopping adds the time the
  /// ticker ran, so a paused run resumes from the same point.
  double _baseSeconds = 0;

  /// Active seconds at the last tick.
  double _lastSeconds = 0;

  bool _measuring = false;
  double? _lastPixels;
  double _path = 0;

  // Ring of (cumulative displacement px, active seconds) at measured ticks.
  // One more slot than a 300-frame window, so 300 intervals fit.
  static const int _ringSize = kPerfWindowFrames + 1;
  final Float64List _pathPx = Float64List(_ringSize);
  final Float64List _atSeconds = Float64List(_ringSize);
  final Uint8List _turnFlags = Uint8List(_ringSize);
  bool? _lastMovingDown;
  double _measureSinceSeconds = 0;
  int _totalTurns = 0;
  int _measureTicks = 0;
  int _unattachedTicks = 0;
  double _maxTickGap = 0;
  double? _prevTickSeconds;
  double _maxExtentSeen = 0;
  int _head = 0;
  int _count = 0;

  SistrumScrollSpeed get speed => _speed;

  bool get isRunning => _ticker.isActive;

  /// Starts or resumes the ticker. Does nothing if it is already running.
  void start() {
    if (!_ticker.isActive) _ticker.start();
  }

  /// Stops the ticker and keeps the offset, so no frames are scheduled.
  void stop() {
    if (!_ticker.isActive) return;
    _baseSeconds = _lastSeconds;
    _ticker.stop();
  }

  /// Stops and moves back to offset 0. Used when the scene stops scrolling.
  void halt() {
    stop();
    _clearRun();
  }

  /// Begins a fresh run from offset 0: clears the samples, starts the warm-up
  /// again and runs until stopped.
  void restart() {
    stop();
    _clearRun();
    start();
  }

  /// Changes the preset and begins a fresh run. The previous ticker is stopped
  /// first; the new speed applies from offset 0.
  void setSpeed(SistrumScrollSpeed speed) {
    _speed = speed;
    restart();
  }

  /// The displacement per second over the sample window, or null when it is
  /// not measurable yet.
  double? actualPxPerSecond() {
    if (_count < 2) return null;
    final newest = (_head - 1 + _ringSize) % _ringSize;
    final oldest = (_head - _count + _ringSize) % _ringSize;
    final span = _atSeconds[newest] - _atSeconds[oldest];
    if (span < kSistrumScrollMinSpanSeconds) return null;
    return (_pathPx[newest] - _pathPx[oldest]) / span;
  }

  SistrumScrollStatus status() {
    return SistrumScrollStatus(
      speed: _speed,
      running: isRunning,
      measuring: _measuring,
      actualPxPerSecond: actualPxPerSecond(),
      direction: isRunning
          ? (sistrumAutoScrollMovingDown(
                  seconds: _lastSeconds,
                  pxPerSecond: _speed.pxPerSecond,
                  maxExtent: _maxExtent(),
                )
                ? 'down'
                : 'up')
          : 'stopped',
      samples: _count,
      boundaryTransitions: _turnsInWindow(),
      overallPxPerSecond: _overallPxPerSecond(),
      measuredSeconds: _measuring ? _lastSeconds - _measureSinceSeconds : 0,
      totalBoundaryTurns: _totalTurns,
      measuredPathPx: _measuring ? _path : 0,
      measureTicks: _measureTicks,
      unattachedTicks: _unattachedTicks,
      maxTickGapSeconds: _maxTickGap,
      maxExtent: _maxExtentSeen,
    );
  }

  double? _overallPxPerSecond() {
    if (!_measuring) return null;
    final span = _lastSeconds - _measureSinceSeconds;
    if (span < kSistrumScrollMinSpanSeconds) return null;
    return _path / span;
  }

  int _turnsInWindow() {
    var turns = 0;
    for (var i = 0; i < _count; i++) {
      turns += _turnFlags[i];
    }
    return turns;
  }

  void dispose() {
    _ticker.dispose();
  }

  void _clearRun() {
    _baseSeconds = 0;
    _lastSeconds = 0;
    _measuring = false;
    _lastPixels = null;
    _path = 0;
    _lastMovingDown = null;
    _measureSinceSeconds = 0;
    _totalTurns = 0;
    _measureTicks = 0;
    _unattachedTicks = 0;
    _maxTickGap = 0;
    _prevTickSeconds = null;
    _maxExtentSeen = 0;
    _head = 0;
    _count = 0;
    if (controller.hasClients) controller.jumpTo(0);
  }

  double _maxExtent() =>
      controller.hasClients ? controller.position.maxScrollExtent : 0;

  void _onTick(Duration elapsed) {
    final seconds =
        _baseSeconds + elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    _lastSeconds = seconds;
    final previous = _prevTickSeconds;
    _prevTickSeconds = seconds;
    if (_measuring) {
      _measureTicks++;
      if (previous != null && seconds - previous > _maxTickGap) {
        _maxTickGap = seconds - previous;
      }
    }
    if (!controller.hasClients) {
      if (_measuring) _unattachedTicks++;
      return;
    }
    final maxExtent = _maxExtent();
    if (maxExtent > _maxExtentSeen) _maxExtentSeen = maxExtent;
    controller.jumpTo(
      sistrumAutoScrollOffset(
        seconds: seconds,
        pxPerSecond: _speed.pxPerSecond,
        maxExtent: maxExtent,
      ),
    );
    final movingDown = sistrumAutoScrollMovingDown(
      seconds: seconds,
      pxPerSecond: _speed.pxPerSecond,
      maxExtent: maxExtent,
    );
    final turned = _lastMovingDown != null && _lastMovingDown != movingDown;
    _lastMovingDown = movingDown;
    _record(seconds, controller.position.pixels, turned);
  }

  void _record(double seconds, double pixels, bool turned) {
    if (!_measuring) {
      _lastPixels = pixels;
      if (seconds < warmupSeconds) return;
      if (measurementReady != null && !measurementReady!()) return;
      _measuring = true;
      _measureSinceSeconds = seconds;
      _path = 0;
      _push(0, seconds, false);
      onMeasurementStart?.call();
      return;
    }
    _path += (pixels - _lastPixels!).abs();
    _lastPixels = pixels;
    if (turned) _totalTurns++;
    _push(_path, seconds, turned);
  }

  void _push(double path, double seconds, bool turned) {
    _pathPx[_head] = path;
    _atSeconds[_head] = seconds;
    _turnFlags[_head] = turned ? 1 : 0;
    _head = (_head + 1) % _ringSize;
    if (_count < _ringSize) _count++;
  }
}
