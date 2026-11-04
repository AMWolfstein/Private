import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/l10n/app_localizations.dart';
import 'package:sistrum/providers/performance/perf_hud_settings_provider.dart';
import 'package:sistrum/screens/settings/about_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('seven taps on the version row unlock Developer options', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const AboutPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(tester.element(find.byType(AboutPage)));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AboutPage)),
    );

    expect(find.text(l10n.devOptionsEntry), findsNothing);
    for (var i = 0; i < 6; i++) {
      await tester.tap(find.byKey(const ValueKey('about-version')));
      await tester.pump();
    }
    expect(find.text(l10n.devOptionsEntry), findsNothing);
    expect(container.read(perfHudSettingsProvider).developerUnlocked, isFalse);

    await tester.tap(find.byKey(const ValueKey('about-version')));
    await tester.pumpAndSettle();
    expect(container.read(perfHudSettingsProvider).developerUnlocked, isTrue);
    expect(find.text(l10n.devOptionsEntry), findsOneWidget);
    expect(find.text(l10n.devOptionsUnlocked), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
