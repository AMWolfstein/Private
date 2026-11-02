// SPDX-License-Identifier: LGPL-3.0-only
// Report test cases adapted from Mornye main 7db0fc76.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/core/models/app_crash_report.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/services/platform/app_crash_service.dart';
import 'package:sistrum/widgets/diagnostics/app_crash_diagnostic.dart';

Map<String, dynamic> _report() => {
  'id': '123456',
  'timestamp': 123456,
  'reason': 'Native crash',
  'description': 'Fatal signal 6 (SIGABRT)',
  'version': '5.2.0 (2162)',
  'device': 'Example Phone',
  'android': '15',
  'sdk': 35,
  'trace': 'Abort message: invalid pointer\n#0 pc 1234 libdecoder.so',
  'runtime_error': 'StateError: request failed access_token=secret-value',
  'runtime_stack': '#0 Example.decode (example.dart:12)',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'report contains original error, native and Dart stacks, and device info',
    () {
      final report = AppCrashReport.fromMap(_report());
      expect(report.report, contains('Example Phone'));
      expect(report.report, contains('5.2.0 (2162)'));
      expect(report.report, contains('Fatal signal 6 (SIGABRT)'));
      expect(report.report, contains('#0 pc 1234 libdecoder.so'));
      expect(report.report, contains('example.dart:12'));
      expect(report.report, contains('[REDACTED]'));
      expect(report.report, isNot(contains('secret-value')));
    },
  );

  test('missing OS trace is explicit and does not fabricate a cause', () {
    final report = AppCrashReport.fromMap(_report()..remove('trace'));
    expect(report.report, contains('Android did not provide a stack trace'));
    expect(report.report, contains('Fatal signal 6 (SIGABRT)'));
  });

  test('crash reports preserve process importance and session duration', () {
    final values = _report()
      ..remove('trace')
      ..addAll({
        'reason_code': 5,
        'process_name': 'example.app',
        'process_id': 123,
        'importance_code': 100,
        'importance_label': 'Foreground activity',
        'session_duration_ms': 65000,
        'pss_kb': 0,
        'rss_kb': 245104,
      });
    final report = AppCrashReport.fromMap(values).report;
    expect(report, contains('Process state before exit: Foreground activity'));
    expect(
      report,
      contains('Process importance before exit (Android code): 100'),
    );
    expect(report, contains('Session duration before exit (ms): 65000'));
    expect(report, contains('Last sampled PSS (KB): 0'));
    expect(report, contains('Last sampled RSS (KB): 245104'));
    expect(report, contains('Android did not provide a stack trace'));
  });

  testWidgets(
    'saved diagnostic survives view recreation and copies redacted trace',
    (tester) async {
      const channel = MethodChannel('com.amwolfstein.sistrum/backend');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'getLatestAppCrash' ? _report() : null,
      );
      String? copied;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(channel, null);
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      });
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.build(Brightness.dark),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: AppCrashDiagnostic()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Fatal signal 6 (SIGABRT)'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.copy));
      await tester.pumpAndSettle();
      expect(copied, contains('libdecoder.so'));
      expect(copied, isNot(contains('secret-value')));
      await tester.tap(find.text('Fatal signal 6 (SIGABRT)'));
      await tester.pumpAndSettle();
      expect(find.byType(SelectableText), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test('runtime context reporting absorbs transport failures', () async {
    const channel = MethodChannel('com.amwolfstein.sistrum/backend');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'storage_failed'),
    );
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await AppCrashService.recordRuntimeError(
      StateError('failed'),
      StackTrace.current,
    );
  });
}
