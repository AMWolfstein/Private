import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/display/display_refresh_rate.dart';
import 'package:sistrum/services/performance/perf_frame_monitor.dart';

DisplayRefreshState _android(double hz) => DisplayRefreshState.fromMap({
  'attached': true,
  'activeModeId': 3,
  'activeModeHz': hz,
  'displayRefreshHz': hz,
  'supportedRates': [60, 90, 120],
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the HUD budget follows Android\'s active mode (120 Hz -> 8.33 ms)', () {
    final monitor = PerfFrameMonitor()..androidDisplay = (() => _android(120));
    final snap = monitor.currentSnapshot();
    expect(snap.hz, 120);
    expect(snap.hzIsFallback, isFalse);
    expect(snap.budgetMs, closeTo(8.33, 0.01));
  });

  test('a 60 Hz Android mode gives a 16.67 ms budget', () {
    final monitor = PerfFrameMonitor()..androidDisplay = (() => _android(60));
    expect(monitor.currentSnapshot().budgetMs, closeTo(16.67, 0.01));
  });
}
