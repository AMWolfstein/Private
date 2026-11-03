part of 'appearance_settings_test.dart';

void _registerAppearanceSettingsPersistence() {
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('player view choice survives restart ($mode)', (tester) async {
      SharedPreferences.setMockInitialValues({kThemeModeKey: mode.name});
      final prefs = await SharedPreferences.getInstance();
      await _openSettings(tester, prefs);
      final immersive = find.text('Immersive view');
      await tester.scrollUntilVisible(
        immersive,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Normal view'), findsOneWidget);
      expect(find.text('History View'), findsNothing);
      expect(find.text('Layout'), findsNothing);
      await tester.tap(immersive);
      await tester.pumpAndSettle();
      expect(prefs.getString(kPlayerViewKey), 'immersive');
      await tester.pumpWidget(const SizedBox());
      await _openSettings(tester, prefs);
      expect(
        loadBootstrapThemeSettings(prefs).playerView,
        PlayerView.immersive,
      );
      await tester.scrollUntilVisible(
        find.text('Normal view'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Normal view'));
      await tester.pumpAndSettle();
      expect(prefs.getString(kPlayerViewKey), 'normal');
      expect(tester.takeException(), isNull);
    });

    testWidgets('fixed red ignores retired accent preferences ($mode)', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        kThemeModeKey: mode.name,
        'sistrum_accent': 'blue',
      });
      final prefs = await SharedPreferences.getInstance();
      await _openSettings(tester, prefs);
      final page = find.byType(AppearanceSettingsPage);
      final theme = Theme.of(tester.element(page));
      expect(theme.colorScheme.primary, AppTheme.accentColor(theme.brightness));
      expect(find.byTooltip('Blue'), findsNothing);
      expect(prefs.containsKey('sistrum_accent'), isFalse);
      final overlay = AppTheme.fromContext(
        tester.element(page),
        brightness: Brightness.dark,
      );
      expect(overlay.colorScheme.primary, AppTheme.darkAccent);
      await tester.pumpWidget(const SizedBox());
      await _openSettings(tester, prefs);
      expect(
        Theme.of(tester.element(page)).colorScheme.primary,
        theme.colorScheme.primary,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
