part of 'appearance_settings_test.dart';

Future<void> _openSettings(WidgetTester tester, SharedPreferences prefs) async {
  tester.view.physicalSize = const Size(390, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        initialThemeSettingsProvider.overrideWithValue(
          loadBootstrapThemeSettings(prefs),
        ),
      ],
      child: AppThemeWrapper(
        builder: (light, dark, mode) => MaterialApp(
          theme: light,
          darkTheme: dark,
          themeMode: mode,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const AppSettingsTheme(child: AppearanceSettingsPage()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _registerAppearanceSettingsDefaults() {
  test('locale settings fall back to the system language', () {
    expect(AppSettings.fromJson({'locale': 'pt_BR'}).locale, 'pt_BR');
    expect(AppSettings.fromJson({'locale': 'de'}).locale, 'de');
    expect(AppSettings.fromJson({}).locale, 'system');
    expect(AppSettings.fromJson({'locale': 5}).locale, 'system');
    expect(
      supportedLanguageChoices.where((choice) => choice.$1.startsWith('pt_')),
      [('pt_BR', 'Português (Brasil)', Icons.language)],
    );
  });

  test('player view defaults safely and survives theme serialization', () {
    for (final saved in [null, '', 'unknown', 5]) {
      expect(
        ThemeSettings.fromJson({kPlayerViewKey: saved}).playerView,
        PlayerView.normal,
      );
    }
    const immersive = ThemeSettings(playerView: PlayerView.immersive);
    expect(ThemeSettings.fromJson(immersive.toJson()), immersive);
    expect(
      immersive.copyWith(lyricsTextScale: 1.2).playerView,
      PlayerView.immersive,
    );
    expect(immersive, isNot(const ThemeSettings()));
  });
}
