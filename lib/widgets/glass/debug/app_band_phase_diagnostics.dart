import 'dart:math' as math;
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/scheduler.dart';

/// Developer-only: what the header band over a playing video was doing when
/// each frame was built, so the performance HUD can split frame timings by
/// phase. Recording is a few field writes per frame and runs only while a HUD
/// is open ([enabled]).
///
/// This attributes Dart-side frame timings to phases. It does not measure GPU
/// work, copies or blur passes; for those, a system GPU trace is needed.
enum AppBandPhase {
  /// No band: the header is expanded or the band blur is off.
  hidden,

  /// The band is fading in or out (its 180 ms animation).
  transition,

  /// The band is fully shown with its blur.
  stable,
}

/// One bucket of the split: a band phase and whether a scroll was active.
typedef AppBandBucket = ({AppBandPhase phase, bool scrolling});

/// Frame statistics for one bucket, in milliseconds.
class AppBandBucketStats {
  AppBandBucketStats(List<double> raster, this.budgetMs)
    : frames = raster.length,
      _sorted = [...raster]..sort();

  final int frames;
  final double budgetMs;
  final List<double> _sorted;

  double _percentile(double p) => _sorted.isEmpty
      ? 0
      : _sorted[math.min(_sorted.length - 1, (p * _sorted.length).ceil() - 1)];

  double get p50 => _percentile(0.50);
  double get p95 => _percentile(0.95);
  double get p99 => _percentile(0.99);

  /// Frames whose raster phase alone exceeded one refresh interval.
  double get rasterJankPercent => frames == 0
      ? 0
      : _sorted.where((ms) => ms > budgetMs).length * 100 / frames;

  String format() =>
      'n=$frames raster p50/p95/p99=${p50.toStringAsFixed(1)}/'
      '${p95.toStringAsFixed(1)}/${p99.toStringAsFixed(1)} '
      'jank=${rasterJankPercent.toStringAsFixed(1)}%';
}

class AppBandPhaseDiagnostics {
  AppBandPhaseDiagnostics._();

  static final instance = AppBandPhaseDiagnostics._();

  /// Set while a performance HUD is open.
  bool enabled = false;

  double _bandAmount = 0;
  double _previousAmount = 0;
  bool _scrolling = false;
  bool _registered = false;

  /// Phase at each frame's begin, keyed by the engine's vsync target time in
  /// microseconds (what `onBeginFrame` receives), oldest first.
  final _frames = <(int, AppBandBucket)>[];

  /// Raster milliseconds per bucket since the window started.
  final _raster = <AppBandBucket, List<double>>{};

  /// Timings no recorded frame matched: frames the engine drew without a
  /// Dart frame (a new video frame alone redraws the last scene).
  int unmatched = 0;

  /// The band's current fade amount, 0 hidden to 1 shown. Called by the
  /// band over a live video on every build of its fade.
  void noteBand(double amount) {
    if (!enabled) return;
    _bandAmount = amount;
  }

  /// Whether the page is being scrolled (start/end notifications).
  void noteScrolling(bool scrolling) {
    if (!enabled) return;
    _scrolling = scrolling;
  }

  /// The page went away: nothing is shown or scrolled any more.
  void clearPage() {
    _bandAmount = 0;
    _previousAmount = 0;
    _scrolling = false;
  }

  void start() {
    enabled = true;
    if (_registered) return;
    _registered = true;
    // Persistent callbacks cannot be removed; it does nothing while disabled.
    SchedulerBinding.instance.addPersistentFrameCallback(_onFrame);
  }

  void stop() {
    enabled = false;
    reset();
  }

  void reset() {
    _frames.clear();
    _raster.clear();
    unmatched = 0;
  }

  AppBandBucket get currentBucket {
    final amount = _bandAmount;
    final phase = amount <= 0
        ? AppBandPhase.hidden
        : amount >= 1 && _previousAmount >= 1
        ? AppBandPhase.stable
        : AppBandPhase.transition;
    return (phase: phase, scrolling: _scrolling);
  }

  void _onFrame(Duration timeStamp) {
    if (!enabled) return;
    _record(
      SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds,
    );
  }

  /// Records a frame built for [targetMicros], as a frame callback does.
  @visibleForTesting
  void debugRecordFrame(int targetMicros) => _record(targetMicros);

  void _record(int targetMicros) {
    final bucket = currentBucket;
    _previousAmount = _bandAmount;
    _frames.add((targetMicros, bucket));
    if (_frames.length > 1200) _frames.removeRange(0, _frames.length - 1200);
  }

  /// Files [timings] under the phase their frame was built in. A timing's
  /// vsync start precedes the target its frame was built for by one refresh
  /// interval; a frame the engine drew without a Dart frame takes the phase in
  /// effect at that time and is counted in [unmatched].
  void addTimings(List<FrameTiming> timings, {required double refreshRate}) {
    if (!enabled || _frames.isEmpty) return;
    final interval = (1e6 / refreshRate).round();
    for (final timing in timings) {
      final start = timing.timestampInMicroseconds(FramePhase.vsyncStart);
      final expected = start + interval;
      AppBandBucket? bucket;
      AppBandBucket? before;
      for (var i = _frames.length - 1; i >= 0; i--) {
        final (target, recorded) = _frames[i];
        if ((target - expected).abs() <= interval ~/ 3) {
          bucket = recorded;
          break;
        }
        if (target <= expected) {
          before ??= recorded;
          if (expected - target > interval * 4) break;
        }
      }
      if (bucket == null) unmatched++;
      final chosen = bucket ?? before;
      if (chosen == null) continue;
      (_raster[chosen] ??= <double>[]).add(
        timing.rasterDuration.inMicroseconds / 1000,
      );
    }
  }

  /// Statistics for every bucket that has frames, in a fixed order.
  List<(AppBandBucket, AppBandBucketStats)> stats({
    required double refreshRate,
  }) {
    final budget = 1000 / refreshRate;
    return [
      for (final phase in AppBandPhase.values)
        for (final scrolling in const [false, true])
          if (_raster[(phase: phase, scrolling: scrolling)] case final values?
              when values.isNotEmpty)
            (
              (phase: phase, scrolling: scrolling),
              AppBandBucketStats(values, budget),
            ),
    ];
  }
}

String appBandBucketLabel(AppBandBucket bucket) =>
    '${bucket.phase.name}${bucket.scrolling ? '+scroll' : ''}';
