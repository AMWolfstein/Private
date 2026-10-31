import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/l10n/app_localizations.dart';
import 'package:sistrum/providers/settings/settings_provider.dart';
import 'package:sistrum/screens/settings/updates_page.dart';
import 'package:sistrum/services/platform/update_checker.dart';
import 'package:sistrum/core/theme/app_theme.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('Updates page checks now and holds the update switches', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.build(Brightness.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const UpdatesPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(UpdatesPage)),
    );

    // Not Android in tests, so the check finds nothing to offer.
    await tester.tap(find.text('Check now'));
    await tester.pumpAndSettle();
    expect(find.text("You're on the latest version"), findsOneWidget);

    await tester.tap(find.text('Get preview releases'));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).updateChannel, 'preview');
    await tester.tap(find.byKey(const ValueKey('check-for-updates')));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).checkForUpdates, false);
    expect(find.text('Get preview releases'), findsNothing);
  });

  testWidgets('a failed update check offers a retry, not an up-to-date claim', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final checker = UpdateChecker(
      isAndroid: true,
      client: MockClient((_) async => throw http.ClientException('Offline')),
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.build(Brightness.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: UpdatesPage(checker: checker),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Check now'));
    await tester.pumpAndSettle();
    expect(find.text('Could not check for updates'), findsOneWidget);
    expect(find.text("You're on the latest version"), findsNothing);

    // The retry action runs the check again instead of staying disabled.
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Could not check for updates'), findsWidgets);
  });
}
