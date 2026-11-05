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
}
