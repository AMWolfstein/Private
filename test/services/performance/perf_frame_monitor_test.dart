import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/performance/perf_frame_monitor.dart';
import 'package:sistrum/services/performance/perf_frame_window.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('start and stop are idempotent and track the running state', () {
    final monitor = PerfFrameMonitor(window: PerfFrameWindow(capacity: 8));
    expect(monitor.isRunning, isFalse);
    monitor.start();
    monitor.start();
    expect(monitor.isRunning, isTrue);
    monitor.stop();
    monitor.stop();
    expect(monitor.isRunning, isFalse);
    monitor.stop();
  });

  test('stopping releases the timing callback and reset clears the window', () {
    final monitor = PerfFrameMonitor(window: PerfFrameWindow(capacity: 8));
    monitor.start();
    monitor.stop();
    monitor.reset();
    expect(monitor.window.count, 0);
    expect(monitor.currentSnapshot().totalFrames, 0);
  });

  test(
    'the current snapshot uses a labelled fallback when no refresh rate is known',
    () {
      final monitor = PerfFrameMonitor(window: PerfFrameWindow(capacity: 8));
      final snapshot = monitor.currentSnapshot();
      expect(snapshot.hz, kPerfFallbackHz);
      expect(snapshot.budgetMs, closeTo(1000 / kPerfFallbackHz, 0.001));
    },
  );
}
