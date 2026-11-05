import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/performance/perf_frame_monitor.dart';

void main() {
  test('collecting is on by default and can be held off and released', () {
    final monitor = PerfFrameMonitor();
    expect(monitor.collecting, isTrue);
    monitor.setCollecting(false);
    expect(monitor.collecting, isFalse);
    monitor.setCollecting(true);
    expect(monitor.collecting, isTrue);
  });

  test('reset does not change whether frames are being collected', () {
    final monitor = PerfFrameMonitor()..setCollecting(false);
    monitor.reset();
    expect(monitor.collecting, isFalse);
  });

  test(
    'frame timings are counted, and held frames are dropped from the window',
    () {
      final monitor = PerfFrameMonitor();
      FrameTiming timing(int startUs) => FrameTiming(
        vsyncStart: startUs,
        buildStart: startUs,
        buildFinish: startUs + 3000,
        rasterStart: startUs + 3000,
        rasterFinish: startUs + 9000,
        rasterFinishWallTime: startUs + 9000,
      );

      monitor.onTimings([timing(0), timing(16000)]);
      expect(monitor.frameCounts.timings, 2);
      expect(monitor.window.count, 2);

      monitor.setCollecting(false);
      monitor.onTimings([timing(32000)]);
      // Still counted as received (the lost-timing check needs that), but kept
      // out of the rolling window while collection is held.
      expect(monitor.frameCounts.timings, 3);
      expect(monitor.window.count, 2);
    },
  );
}
