import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('sistrum.audit/transport');

  test(
    'mocked transport propagates errors and unregisters its handler',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(
          code: 'AUDIT_ERROR',
          message: 'simulated failure',
        );
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await expectLater(
        channel.invokeMethod<void>('failure'),
        throwsA(
          isA<PlatformException>().having((e) => e.code, 'code', 'AUDIT_ERROR'),
        ),
      );
      messenger.setMockMethodCallHandler(channel, null);
      await expectLater(
        channel.invokeMethod<void>('afterDetach'),
      throwsA(isA<MissingPluginException>()),
      );
    },
  );

  test('host-only mocked channel serialization benchmark', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async => call.arguments);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    for (final size in [0, 1024, 65536]) {
      final payload = Uint8List(size);
      for (var i = 0; i < 50; i++) {
        await channel.invokeMethod<Uint8List>('echo', payload);
      }
      final rssBefore = ProcessInfo.currentRss;
      final samples = <int>[];
      final total = Stopwatch()..start();
      for (var i = 0; i < 1000; i++) {
        final watch = Stopwatch()..start();
        final response = await channel.invokeMethod<Uint8List>('echo', payload);
        samples.add(watch.elapsedMicroseconds);
        expect(response?.length, size);
      }
      total.stop();
      samples.sort();
      int percentile(double p) => samples[((samples.length - 1) * p).ceil()];
      // These are host mock timings, not platform-channel or native timings.
      // ignore: avoid_print
      print(
        'bridge_host_mock bytes=$size n=${samples.length} '
        'p50_us=${percentile(.50)} p95_us=${percentile(.95)} '
        'p99_us=${percentile(.99)} ops_per_sec='
        '${(samples.length * 1000000 / total.elapsedMicroseconds).toStringAsFixed(1)} '
        'rss_delta_bytes=${ProcessInfo.currentRss - rssBefore}',
      );
    }
  });
}
