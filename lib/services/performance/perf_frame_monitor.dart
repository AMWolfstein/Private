import 'dart:ui';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/services/performance/perf_frame_window.dart';

/// Collects FrameTiming samples while started. The callback only writes into
/// the bounded window; it never calls setState or allocates per frame.
class PerfFrameMonitor {
  PerfFrameMonitor({PerfFrameWindow? window})
    : window = window ?? PerfFrameWindow();

  final PerfFrameWindow window;
  bool _running = false;
  bool _collecting = true;

  bool get isRunning => _running;

  /// Whether arriving frames are counted. The Glass POC scroll benchmark turns
  /// this off during warm-up, so warm-up frames stay out of the window.
  bool get collecting => _collecting;

  void setCollecting(bool value) => _collecting = value;

  void start() {
    if (_running) return;
    _running = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void stop() {
    if (!_running) return;
    _running = false;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
  }

  void reset() => window.reset();

  /// Current statistics, using the reported refresh rate or the fallback.
  PerfWindowSnapshot currentSnapshot() {
    final rate = resolvePerfRefreshRate(reportedRefreshRate());
    return window.snapshot(hz: rate.hz, hzIsFallback: rate.isFallback);
  }

  void _onTimings(List<FrameTiming> timings) {
    if (!_collecting) return;
    for (final timing in timings) {
      window.add(
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
