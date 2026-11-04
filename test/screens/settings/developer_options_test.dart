import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/l10n/app_localizations.dart';
import 'package:sistrum/providers/performance/perf_hud_settings_provider.dart';
import 'package:sistrum/screens/settings/developer/developer_options_page.dart';

Widget _app(Widget home) => ProviderScope(
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Developer options offers the HUD switch, opacity and tools', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_app(const DeveloperOptionsPage()));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(DeveloperOptionsPage)),
    );
    expect(find.text(l10n.devOptionsPerfHud), findsOneWidget);
    expect(find.text(l10n.devOptionsHudOpacity), findsOneWidget);
    expect(find.text(l10n.devOptionsResetMetrics), findsOneWidget);
    expect(find.text(l10n.devOptionsCopyReport), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the HUD switch in Developer options turns the HUD on', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_app(const DeveloperOptionsPage()));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DeveloperOptionsPage)),
    );
    expect(container.read(perfHudSettingsProvider).enabled, isFalse);
    await tester.tap(
      find.text(
        AppLocalizations.of(
          tester.element(find.byType(DeveloperOptionsPage)),
        ).devOptionsPerfHud,
      ),
    );
    await tester.pumpAndSettle();
    expect(container.read(perfHudSettingsProvider).enabled, isTrue);
  });
}
