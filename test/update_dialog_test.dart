import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/l10n/app_localizations.dart';
import 'package:sistrum/services/update_checker.dart';
import 'package:sistrum/theme/app_theme.dart';
import 'package:sistrum/widgets/sheets/update_dialog.dart';

void main() {
  Future<void> open(
    WidgetTester tester, {
    required UpdateInfo info,
    bool forced = false,
    VoidCallback? onDisable,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.build(Brightness.dark),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showUpdateDialog(
                context,
                updateInfo: info,
                forced: forced,
                onDisableUpdates: onDisable ?? () {},
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  final info = UpdateInfo(
    version: '9.9.9',
    changelog: '### What\'s New\n- **Faster** scans\n- `Fix` lyrics',
    downloadUrl: 'https://example.test/release',
    apkDownloadUrl: 'https://example.test/app.apk',
    publishedAt: DateTime(2026),
  );

  testWidgets('shows the release notes and offers Later / Don\'t remind', (
    tester,
  ) async {
    var disabled = false;
    await open(tester, info: info, onDisable: () => disabled = true);
    expect(find.text('Update Available'), findsOneWidget);
    expect(find.text('v9.9.9'), findsOneWidget);
    expect(find.textContaining('• Faster scans'), findsOneWidget);
    expect(find.text('Download & Install'), findsOneWidget);
    await tester.tap(find.text('Don\'t remind'));
    await tester.pumpAndSettle();
    expect(disabled, isTrue);
    expect(find.text('Update Available'), findsNothing);
  });

  testWidgets('a forced update cannot be dismissed', (tester) async {
    await open(tester, info: info, forced: true);
    expect(find.text('Update required'), findsOneWidget);
    expect(find.text('Later'), findsNothing);
    expect(find.text('Don\'t remind'), findsNothing);
  });

  testWidgets('without an APK the button opens the release page', (
    tester,
  ) async {
    await open(
      tester,
      info: UpdateInfo(
        version: '9.9.9',
        changelog: '',
        downloadUrl: 'https://example.test/release',
        publishedAt: DateTime(2026),
      ),
    );
    expect(find.text('View Release'), findsOneWidget);
    expect(find.text('See release notes for details.'), findsOneWidget);
  });
}
