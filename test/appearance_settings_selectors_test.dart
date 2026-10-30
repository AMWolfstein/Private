import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/l10n/app_localizations.dart';
import 'package:sistrum/models/theme_settings.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/screens/settings/appearance_settings_selectors.dart';
import 'package:sistrum/theme/app_theme.dart';

import 'support/library_section_harness.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [settingsProvider.overrideWith(LibrarySectionSettings.new)],
      child: MaterialApp(
        theme: AppTheme.build(Brightness.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(Scaffold).first));

void main() {
  testWidgets('the theme mode control offers system, light and dark', (
    tester,
  ) async {
    await _pump(
      tester,
      ThemeModeSelector(currentMode: ThemeMode.system, onChanged: (_) {}),
    );
    final l10n = _l10n(tester);
    expect(find.text(l10n.appearanceThemeSystem), findsOneWidget);
    expect(find.text(l10n.appearanceThemeLight), findsOneWidget);
    expect(find.text(l10n.appearanceThemeDark), findsOneWidget);
  });

  testWidgets('choosing dark reports the dark theme mode', (tester) async {
    ThemeMode? chosen;
    await _pump(
      tester,
      ThemeModeSelector(
        currentMode: ThemeMode.light,
        onChanged: (mode) => chosen = mode,
      ),
    );
    await tester.tap(find.text(_l10n(tester).appearanceThemeDark));
    await tester.pumpAndSettle();
    expect(chosen, ThemeMode.dark);
  });

  testWidgets('the language row shows the current language name', (
    tester,
  ) async {
    await _pump(
      tester,
      LanguageSelector(currentLocale: 'en', onChanged: (_) {}),
    );
    expect(find.text(_l10n(tester).appearanceLanguage), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
  });

  testWidgets('the accent picker shows an option for each accent', (
    tester,
  ) async {
    await _pump(
      tester,
      AppAccentPicker(selected: AppAccent.values.first, onChanged: (_) {}),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(AppAccentPicker), findsOneWidget);
  });
}
