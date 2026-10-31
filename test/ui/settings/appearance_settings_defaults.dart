part of 'appearance_settings_test.dart';

Map<String, dynamic> _savedGlass(SharedPreferences prefs) =>
    jsonDecode(prefs.getString('app_settings')!) as Map<String, dynamic>;

Future<void> _openSettings(
  WidgetTester tester,
  SharedPreferences prefs, {
  bool lowEnd = false,
}) async {
  tester.view.physicalSize = const Size(390, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        initialThemeSettingsProvider.overrideWithValue(
          loadBootstrapThemeSettings(prefs),
        ),
        // Low-end Android on auto renders flat, opaque glass.
        if (lowEnd) lowEndDeviceProvider.overrideWithValue(true),
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
      immersive.copyWith(useSystemFont: true).playerView,
      PlayerView.immersive,
    );
    expect(immersive, isNot(const ThemeSettings()));
  });
  test(
    'old themes retain outlines and new themes serialize the preference',
    () {
      expect(ThemeSettings.fromJson({}).appGlassOutlines, isTrue);
      const settings = ThemeSettings(appGlassOutlines: false);
      expect(ThemeSettings.fromJson(settings.toJson()), settings);
      expect(settings.copyWith(useSystemFont: true).appGlassOutlines, isFalse);
      expect(settings, isNot(const ThemeSettings()));
    },
  );
  test('glass settings restore safely from old and invalid settings', () {
    expect(AppSettings.fromJson({}).glassClarityLevel, 3);
    expect(AppSettings.fromJson({}).glassQuality, 'auto');
    for (final (saved, expected) in [
      (1, 1),
      (5, 5),
      (0, 1),
      (9, 5),
      (2.6, 3),
      (double.nan, 3),
      ('4', 3),
    ]) {
      final settings = AppSettings.fromJson({'glassClarityLevel': saved});
      expect(settings.glassClarityLevel, expected, reason: '$saved');
      expect(
        AppSettings.fromJson(settings.toJson()).glassClarityLevel,
        expected,
      );
    }
    expect(appGlassQualityFromString('lite'), AppGlassQuality.lite);
    expect(appGlassQualityFromString('fancy'), AppGlassQuality.auto);
    expect(AppSettings().toJson().containsKey('forceBackdropBlur'), isFalse);
  });
  test('custom accents keep text readable in both appearances', () {
    double contrast(Color first, Color second) {
      final a = first.computeLuminance();
      final b = second.computeLuminance();
      return a > b ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05);
    }

    for (final brightness in Brightness.values) {
      for (final accent in AppAccent.values.where(
        (accent) => accent != AppAccent.red,
      )) {
        final scheme = AppTheme.build(brightness, accent: accent).colorScheme;
        expect(
          contrast(scheme.primary, scheme.surface),
          greaterThanOrEqualTo(4.5),
          reason: '$accent on $brightness',
        );
        expect(
          contrast(scheme.onPrimary, scheme.primary),
          greaterThanOrEqualTo(4.5),
          reason: 'Button text for $accent on $brightness',
        );
      }
    }
  });
}
