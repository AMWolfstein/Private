import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/l10n/app_localizations.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/screens/settings/updates_page.dart';
import 'package:sistrum/theme/sistrum_theme.dart';

void main() {
  testWidgets('Updates page checks now and holds the update switches', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: SistrumTheme.build(Brightness.light),
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
}
