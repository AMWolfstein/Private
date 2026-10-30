import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/native_log_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.amwolfstein.sistrum/backend');
  const source = NativeLogSource(channel: channel);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  for (final encoded in [false, true]) {
    test('reads native logs and cursor (JSON=$encoded)', () async {
      final payload = {
        'logs': [
          {'level': 'ERROR', 'tag': 'Native', 'message': 'failed'},
        ],
        'next_index': 8,
      };
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'getLogsSince');
        expect(call.arguments, {'index': 3});
        return encoded ? jsonEncode(payload) : payload;
      });
      expect(await source.getSince(3), payload);
    });
  }

  test('keeps the native logging controls on the existing channel', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    await source.setLoggingEnabled(true);
    await source.setLoggingEnabled(false);
    await source.clear();
    expect(calls.map((call) => call.method), [
      'setLoggingEnabled',
      'setLoggingEnabled',
      'clearLogs',
    ]);
    expect(calls[0].arguments, {'enabled': true});
    expect(calls[1].arguments, {'enabled': false});
  });

  test('reports malformed batches instead of silently losing logs', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => '[]');
    await expectLater(source.getSince(0), throwsFormatException);
  });

  test('propagates transport failures to the polling error boundary', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'backend_unavailable');
    });
    await expectLater(source.getSince(0), throwsA(isA<PlatformException>()));
  });

  test('reads the app logcat text on the existing backend channel', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getAppLogcat');
      return 'raw line';
    });
    final result = await source.readAppLogcat();
    expect(result, isA<NativeLogcatText>());
    expect((result as NativeLogcatText).text, 'raw line');
  });

  test('reports logcat transport failures as a typed result', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'unavailable', message: 'no logcat');
    });
    final result = await source.readAppLogcat();
    expect(result, isA<NativeLogcatUnavailable>());
    expect((result as NativeLogcatUnavailable).reason, 'no logcat');
  });

  test('parses threadtime logcat lines into log rows', () {
    const text =
        '--------- beginning of main\n'
        '01-02 03:04:05.006  1234  1234 E Sistrum : boom\n'
        'java.lang.IllegalStateException: x\n'
        '01-02 03:04:06.100  1234  1300 W flutter : careful\n';
    final entries = parseAppLogcat(text, now: DateTime(2026, 10, 30));
    expect(entries.map((e) => (e.level, e.tag, e.message)).toList(), [
      ('ERROR', 'Sistrum', 'boom\njava.lang.IllegalStateException: x'),
      ('WARN', 'flutter', 'careful'),
    ]);
    expect(entries.first.timestamp, DateTime(2026, 1, 2, 3, 4, 5, 6));
  });
}
