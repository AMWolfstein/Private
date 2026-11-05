import 'dart:ui';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/services/performance/glass_benchmark_aggregator.dart';
import 'package:sistrum/services/performance/perf_frame_window.dart';
import 'package:sistrum/services/performance/perf_spike_recorder.dart';

/// Collects FrameTiming samples while started. The callback only writes into
/// the bounded window; it never calls setState or allocates per frame.
class PerfFrameMonitor {
  PerfFrameMonitor({PerfFrameWindow? window})
    : window = window ?? PerfFrameWindow();

  final PerfFrameWindow window;
  bool _running = false;
  bool _collecting = true;
  bool _beginCounting = false;
  int _beginFrames = 0;
  int _timingsReceived = 0;

  bool get isRunning => _running;

  /// Whether arriving frames are counted. The Glass POC scroll benchmark turns
  /// this off during warm-up, so warm-up frames stay out of the window.
  bool get collecting => _collecting;

  void setCollecting(bool value) => _collecting = value;

  /// Developer POC only: captures sustained budget degradation. Null when no
  /// POC page is open, so the hot path does no extra work.
  PerfSpikeRecorder? spikeRecorder;

  /// Developer POC benchmark only: receives frames of the measured interval.
  /// Null outside a benchmark run.
  GlassBenchmarkAggregator? benchmarkAggregator;

  void start() {
    if (_running) return;
    _running = true;
    SchedulerBinding.instance.addTimingsCallback(onTimings);
    // A persistent callback runs once per drawn frame, independent of the
    // FrameTiming delivery. Comparing the two counts shows lost timings.
    if (!_beginCounting) {
      _beginCounting = true;
      SchedulerBinding.instance.addPersistentFrameCallback(
        (_) => _beginFrames++,
      );
    }
  }

  void stop() {
    if (!_running) return;
    _running = false;
    SchedulerBinding.instance.removeTimingsCallback(onTimings);
  }

  void reset() {
    window.reset();
    spikeRecorder?.reset();
  }

  /// Current statistics, using the reported refresh rate or the fallback.
  PerfWindowSnapshot currentSnapshot() {
    final rate = resolvePerfRefreshRate(reportedRefreshRate());
    return window.snapshot(hz: rate.hz, hzIsFallback: rate.isFallback);
  }

  /// Frame counts since the monitor started. Both only grow.
  ({int beginFrames, int timings}) get frameCounts =>
      (beginFrames: _beginFrames, timings: _timingsReceived);

  /// Called by the engine with each batch of FrameTiming. Public so tests can
  /// feed real timings; the app never calls it directly.
  void onTimings(List<FrameTiming> timings) {
    _timingsReceived += timings.length;
    if (!_collecting) return;
    for (final timing in timings) {
      window.add(
        buildUs: timing.buildDuration.inMicroseconds,
        rasterUs: timing.rasterDuration.inMicroseconds,
        spanUs: timing.totalSpan.inMicroseconds,
        endUs: timing.timestampInMicroseconds(FramePhase.rasterFinish),
      );
      spikeRecorder?.onFrame(
        buildUs: timing.buildDuration.inMicroseconds,
        rasterUs: timing.rasterDuration.inMicroseconds,
        spanUs: timing.totalSpan.inMicroseconds,
        endUs: timing.timestampInMicroseconds(FramePhase.rasterFinish),
      );
      benchmarkAggregator?.onFrame(
        buildUs: timing.buildDuration.inMicroseconds,
        rasterUs: timing.rasterDuration.inMicroseconds,
        spanUs: timing.totalSpan.inMicroseconds,
        endUs: timing.timestampInMicroseconds(FramePhase.rasterFinish),
      );
    }
  }

  /// The display's refresh rate as the engine reports it, or null.
  static double? reportedRefreshRate() {
    final binding = WidgetsBinding.instance;
    final views = binding.platformDispatcher.views;
    if (views.isEmpty) return null;
    return views.first.display.refreshRate;
  }
}

/// The app's single monitor. Its callback is removed when the HUD stops it
/// and when the provider is disposed.
final perfFrameMonitorProvider = Provider<PerfFrameMonitor>((ref) {
  final monitor = PerfFrameMonitor();
  ref.onDispose(monitor.stop);
  return monitor;
});
