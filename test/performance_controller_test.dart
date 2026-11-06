import 'dart:ui' show AppLifecycleState, FrameTiming;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mornye/providers/performance_provider.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.zarz.mornye/performance_display');
  testWidgets(
    'monitoring registers once, removes callbacks, reset and dispose are safe',
    (tester) async {
      final c = PerformanceController(androidOverride: false);
      expect(c.registered, false);
      c.configure(true, true, 10000, 3000);
      c.configure(true, true, 10000, 3000);
      expect(c.registered, true);
      // Deliver actual release-safe FrameTiming through the scheduler binding.
      final timings = [
        FrameTiming(
          buildStart: 1000,
          buildFinish: 2000,
          rasterStart: 2500,
          rasterFinish: 5000,
          rasterFinishWallTime: 5000,
          vsyncStart: 0,
        ),
      ];
      binding.platformDispatcher.onReportTimings!(timings);
      expect(c.snapshot.frames.length, 1);
      c.reset();
      expect(c.snapshot.frames, isEmpty);
      c.configure(false, true, 10000, 3000);
      expect(c.registered, false);
      binding.platformDispatcher.onReportTimings?.call(timings);
      expect(c.snapshot.frames, isEmpty);
      c.configure(true, false, 10000, 3000);
      c.dispose();
      expect(c.registered, false);
      await tester.pump();
    },
  );
  testWidgets('pause suspends timing callbacks and resumes only when enabled', (
    tester,
  ) async {
    final c = PerformanceController(androidOverride: false);
    c.configure(true, true, 10000, 3000);
    expect(c.registered, true);
    c.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(c.registered, false);
    c.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(c.registered, true);
    c.configure(false, true, 10000, 3000);
    c.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(c.registered, false);
    c.dispose();
    await tester.pump();
  });
  testWidgets(
    'native updates are event driven and distinct from requested rate',
    (tester) async {
      var reads = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            reads++;
            return {
              'requested_hz': 60,
              'active_hz': 120,
              'transition_count': 0,
            };
          });
      final c = PerformanceController(androidOverride: true);
      await tester.pump();
      expect(reads, 1);
      expect(c.display.hz, 120);
      expect(c.display.budgetMs, closeTo(8.3333, .001));
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            channel.name,
            const StandardMethodCodec().encodeMethodCall(
              const MethodCall('onState', {
                'requested_hz': 60,
                'active_hz': 60,
                'transition_count': 1,
                'changes': [
                  {'at_ms': 42, 'mode_id': 2, 'hz': 60},
                ],
              }),
            ),
            (_) {},
          );
      expect(c.display.hz, 60);
      expect(c.display.transitions, 1);
      expect(c.display.changes.length, 1);
      c.configure(true, false, 10000, 3000);
      await tester.pump(const Duration(seconds: 5));
      expect(reads, 1); // No per-frame or polling queries.
      c.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    },
  );
  testWidgets('route context follows active tab, nested and overlay routes', (
    tester,
  ) async {
    final c = PerformanceController(androidOverride: false);
    c.setRoute('root', '/');
    c.setRoute('library', 'library');
    expect(c.snapshot.screen, 'home');
    c.setTab('library');
    expect(c.snapshot.screen, 'library');
    c.setRoute('library', 'unavailable');
    expect(c.snapshot.screen, 'unavailable');
    c.setRoute('root', '/settings/app/performance');
    expect(c.snapshot.screen, '/settings/app/performance');
    c.setRoute('root', '/');
    expect(c.snapshot.screen, 'unavailable');
    c.dispose();
  });
}
