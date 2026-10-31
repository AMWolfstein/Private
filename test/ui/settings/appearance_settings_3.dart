part of 'appearance_settings_test.dart';

void _registerAppearanceSettings3() {
  for (final style in ['sistrum']) {
    testWidgets(
      'system font persists and restores the default ($style)',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'theme_style': style,
          kAppAccentKey: 'blue',
          'use_dynamic_color': false,
        });
        final prefs = await SharedPreferences.getInstance();
        await _openSettings(tester, prefs);
        final page = find.byType(AppearanceSettingsPage);
        final original = Theme.of(
          tester.element(page),
        ).textTheme.bodyLarge!.fontFamily;
        final setting = find.text('Use system font');
        await tester.scrollUntilVisible(
          setting,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(setting);
        await tester.pumpAndSettle();
        final theme = Theme.of(tester.element(page));
        final systemFamily = theme.textTheme.bodyLarge!.fontFamily;
        expect(systemFamily, isNot('Inter'));
        expect(prefs.getBool(kUseSystemFontKey), isTrue);
        if (style == 'sistrum') {
          final overlay = AppTheme.fromContext(
            tester.element(page),
            brightness: Brightness.dark,
          );
          expect(overlay.extension<AppTheme>()!.useSystemFont, isTrue);
          expect(overlay.extension<AppTheme>()!.accent, AppAccent.blue);
          expect(overlay.textTheme.bodyLarge!.fontFamily, systemFamily);
        }
        await tester.pumpWidget(const SizedBox());
        await _openSettings(tester, prefs);
        expect(
          Theme.of(tester.element(page)).textTheme.bodyLarge!.fontFamily,
          systemFamily,
        );
        await tester.scrollUntilVisible(
          setting,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(setting);
        await tester.pumpAndSettle();
        expect(prefs.getBool(kUseSystemFontKey), isFalse);
        expect(
          Theme.of(tester.element(page)).textTheme.bodyLarge!.fontFamily,
          original,
        );
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.iOS,
      }),
    );
  }
}
