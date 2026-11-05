import 'package:sistrum/services/performance/glass_benchmark_aggregator.dart';
import 'package:sistrum/services/performance/glass_series_stats.dart';

/// Clock labels written into every report. Engine timestamps and Dart delivery
/// times are different clocks: they are never subtracted from each other.
const String kGlassClockEngine =
    'engine FrameTiming timestamps (event time: vsyncStart, rasterFinish)';
const String kGlassClockDelivery =
    'Dart Stopwatch read when the callback runs (delivery time: frame begin, '
    'FrameTiming arrival)';

/// Records frame scheduling over one measured interval.
///
/// Four series, each a set of consecutive intervals:
/// - [begin]: persistent frame callbacks (a frame started drawing). Delivery
///   time on the Dart Stopwatch.
/// - [arrival]: `addTimingsCallback` batches. Delivery time on the Stopwatch.
/// - [vsync]: `FrameTiming.vsyncStart` of each timing. Event time, engine clock.
/// - [raster]: `FramePhase.rasterFinish` of each timing. Event time, engine clock.
///
/// Only the two engine series say when a frame was scheduled. The delivery
/// series say when Dart saw it. [summary] keeps them apart on purpose.
///
/// Every method writes into preallocated buffers. Nothing is allocated per
/// frame, so the recorder adds no measurable work to the frame callbacks.
class GlassFrameScheduleRecorder {
  GlassFrameScheduleRecorder({
    required this.nominalPeriodUs,
    int capacity = kGlassBenchmarkMaxFrames,
    Stopwatch? clock,
  }) : _clock = clock ?? (Stopwatch()..start()),
       _begin = GlassSeriesBuffer(capacity),
       _arrival = GlassSeriesBuffer(capacity),
       _vsync = GlassSeriesBuffer(capacity),
       _raster = GlassSeriesBuffer(capacity);

  /// Nominal frame period from the reported refresh rate, in microseconds.
  /// Missed slots are measured against it.
  final int nominalPeriodUs;

  final Stopwatch _clock;
  final GlassSeriesBuffer _begin;
  final GlassSeriesBuffer _arrival;
  final GlassSeriesBuffer _vsync;
  final GlassSeriesBuffer _raster;

  int _lastBeginUs = -1;
  int _lastArrivalUs = -1;
  int _lastVsyncUs = -1;
  int _lastRasterUs = -1;
  int _beginEvents = 0;
  int _batches = 0;
  int _timings = 0;
  int _longVsync = 0;
  int _missedSlots = 0;

  /// Called from the persistent frame callback, once per drawn frame.
  void onBeginFrame() {
    final now = _clock.elapsedMicroseconds;
    _beginEvents++;
    if (_lastBeginUs >= 0) _begin.add(now - _lastBeginUs);
    _lastBeginUs = now;
  }

  /// Called once per `addTimingsCallback` batch, before its timings.
  void onTimingsArrived(int timingCount) {
    final now = _clock.elapsedMicroseconds;
    _batches++;
    _timings += timingCount;
    if (_lastArrivalUs >= 0) _arrival.add(now - _lastArrivalUs);
    _lastArrivalUs = now;
  }

  /// Called for each FrameTiming with its engine event timestamps.
  void onFrameTiming({required int vsyncStartUs, required int rasterFinishUs}) {
    if (_lastVsyncUs >= 0) {
      final interval = vsyncStartUs - _lastVsyncUs;
      _vsync.add(interval);
      if (nominalPeriodUs > 0) {
        if (interval > nominalPeriodUs * 3 ~/ 2) _longVsync++;
        final slots = (interval / nominalPeriodUs).round();
        if (slots > 1) _missedSlots += slots - 1;
      }
    }
    _lastVsyncUs = vsyncStartUs;
    if (_lastRasterUs >= 0) _raster.add(rasterFinishUs - _lastRasterUs);
    _lastRasterUs = rasterFinishUs;
  }

  GlassFrameScheduleSummary summary() => GlassFrameScheduleSummary(
    nominalPeriodMs: nominalPeriodUs / 1000,
    beginEvents: _beginEvents,
    batches: _batches,
    timings: _timings,
    longVsyncIntervals: _longVsync,
    missedSlots: _missedSlots,
    begin: _begin.stats(),
    arrival: _arrival.stats(),
    vsync: _vsync.stats(),
    raster: _raster.stats(),
  );
}

/// Schedule statistics of one measured run, in milliseconds.
class GlassFrameScheduleSummary {
  const GlassFrameScheduleSummary({
    required this.nominalPeriodMs,
    required this.beginEvents,
    required this.batches,
    required this.timings,
    required this.longVsyncIntervals,
    required this.missedSlots,
    required this.begin,
    required this.arrival,
    required this.vsync,
    required this.raster,
  });

  final double nominalPeriodMs;

  /// Drawn frames (persistent callbacks) in the interval.
  final int beginEvents;

  /// FrameTiming callback batches and the timings they carried.
  final int batches;
  final int timings;

  /// Engine vsync intervals longer than 1.5 nominal periods.
  final int longVsyncIntervals;

  /// Nominal periods skipped by vsync intervals: a 2-period interval counts 1.
  final int missedSlots;

  /// Stopwatch delivery intervals for drawn frames.
  final GlassSeriesStats begin;

  /// Stopwatch delivery intervals between FrameTiming batches.
  final GlassSeriesStats arrival;

  /// Engine vsyncStart intervals.
  final GlassSeriesStats vsync;

  /// Engine rasterFinish intervals.
  final GlassSeriesStats raster;

  /// Refresh rate implied by the median engine vsync interval. Null when there
  /// are too few intervals. This is evidence about the vsync cadence only; it
  /// is not the display's measured frame rate.
  double? get impliedVsyncHz {
    final p50 = vsync.p50;
    if (p50 == null || p50 <= 0) return null;
    return 1000 / p50;
  }
}
