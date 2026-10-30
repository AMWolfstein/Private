import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.amwolfstein.sistrum/backend');

  testWidgets('backend implementation query round-trip benchmark', (
    tester,
  ) async {
    for (var i = 0; i < 30; i++) {
      expect(
        await channel.invokeMethod<Object?>('getBackendImplementations'),
        isA<Map<Object?, Object?>>(),
      );
    }
    final rssBefore = ProcessInfo.currentRss;
    final elapsed = <int>[];
    final total = Stopwatch()..start();
    for (var i = 0; i < 500; i++) {
      final timer = Stopwatch()..start();
      final result = await channel.invokeMethod<Object?>(
        'getBackendImplementations',
      );
      elapsed.add(timer.elapsedMicroseconds);
      expect(result, isA<Map<Object?, Object?>>());
    }
    total.stop();
    elapsed.sort();
    int percentile(double p) => elapsed[((elapsed.length - 1) * p).ceil()];
    // End-to-end time includes the native query, scheduling and codec work.
    // RSS is process-wide and is not a per-call allocation measurement.
    // ignore: avoid_print
    print(
      'bridge_device_backend_query n=${elapsed.length} '
      'p50_us=${percentile(.50)} p95_us=${percentile(.95)} '
      'p99_us=${percentile(.99)} ops_per_sec='
      '${(elapsed.length * 1000000 / total.elapsedMicroseconds).toStringAsFixed(1)} '
      'rss_delta_bytes=${ProcessInfo.currentRss - rssBefore}',
    );
  });
}
