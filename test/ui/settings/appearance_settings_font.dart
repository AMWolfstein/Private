part of 'appearance_settings_test.dart';

void _registerAppearanceSettingsFont() {
  testWidgets('system typography is fixed and retired controls stay absent', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'sistrum_accent': 'purple',
      'use_system_font': false,
      'custom_font_id': 'missing-font',
      'custom_font_name': 'Imported.ttf',
      'app_settings': jsonEncode({'heroAnimationsEnabled': false}),
    });
    final prefs = await SharedPreferences.getInstance();
    await _openSettings(tester, prefs);
    final page = find.byType(AppearanceSettingsPage);
    final theme = Theme.of(tester.element(page));
    expect(
      theme.textTheme.bodyLarge!.fontFamily,
      const CupertinoThemeData().textTheme.textStyle.fontFamily,
    );
    expect(
      theme.textTheme.bodyLarge!.fontFamilyFallback,
      isNot(contains('Noto Sans Arabic')),
    );
    final overlay = AppTheme.fromContext(
      tester.element(page),
      brightness: Brightness.dark,
    );
    expect(
      overlay.textTheme.bodyLarge!.fontFamily,
      theme.textTheme.bodyLarge!.fontFamily,
    );
    for (final label in [
      'Use system font',
      'Custom font',
      'Hero animations',
      'Color',
    ]) {
      expect(find.text(label, skipOffstage: false), findsNothing);
    }
    final catalog = SettingsSearchCatalog(
      AppLocalizations.of(tester.element(page)),
    );
    for (final label in [
      'Use system font',
      'Custom font',
      'Hero animations',
      'Color',
    ]) {
      expect(catalog.appearance.any((entry) => entry.title == label), isFalse);
    }
    expect(
      AppSettings.fromJson({'heroAnimationsEnabled': false}).toJson(),
      isNot(contains('heroAnimationsEnabled')),
    );
    await tester.pumpWidget(const SizedBox());
    await _openSettings(tester, prefs);
    expect(
      Theme.of(tester.element(page)).textTheme.bodyLarge!.fontFamily,
      theme.textTheme.bodyLarge!.fontFamily,
    );
    expect(tester.takeException(), isNull);
  }, variant: const TargetPlatformVariant({TargetPlatform.android}));
}
