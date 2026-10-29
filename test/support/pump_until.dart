import 'package:flutter_test/flutter_test.dart';

/// Polls [condition] until it holds, letting real asynchronous work (platform
/// file I/O, native callbacks) finish between checks.
///
/// Each round waits [realDelay] on the real event loop, then pumps the fake
/// clock by [pumpStep]. Fails with [description] once [timeout] of wall-clock
/// time has passed, so a stuck test reports what it was waiting for.
Future<void> pumpUntilTrue(
  WidgetTester tester,
  bool Function() condition, {
  required String description,
  Duration timeout = const Duration(seconds: 5),
  Duration realDelay = const Duration(milliseconds: 5),
  Duration pumpStep = const Duration(milliseconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (!DateTime.now().isBefore(deadline)) {
      fail('Timed out waiting for $description');
    }
    await tester.runAsync(() => Future<void>.delayed(realDelay));
    await tester.pump(pumpStep);
  }
}
