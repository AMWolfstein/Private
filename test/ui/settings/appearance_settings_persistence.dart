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

    testWidgets(
      'glass outlines toggle survives restart and local themes ($mode)',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'theme_style': 'sistrum',
          kThemeModeKey: mode.name,
        });
        final prefs = await SharedPreferences.getInstance();
        await _openSettings(tester, prefs);
        final toggle = find.byKey(const ValueKey('sistrum-glass-outlines'));
        await tester.ensureVisible(toggle);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Glass outlines'));
        await tester.pumpAndSettle();
        expect(prefs.getBool(kAppGlassOutlinesKey), isFalse);
        final context = tester.element(toggle);
        final container = ProviderScope.containerOf(context);
        expect(container.read(appGlassOutlinesProvider), isFalse);
        expect(container.read(appGlassClarityLevelProvider), 3);
        await tester.pumpWidget(const SizedBox());
        await _openSettings(tester, prefs);
        expect(
          ProviderScope.containerOf(
            tester.element(toggle),
          ).read(appGlassOutlinesProvider),
          isFalse,
        );
        await tester.ensureVisible(toggle);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Glass outlines'));
        await tester.pumpAndSettle();
        expect(prefs.getBool(kAppGlassOutlinesKey), isTrue);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('glass clarity previews live and survives restart ($mode)', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'theme_style': 'sistrum',
        kThemeModeKey: mode.name,
      });
      final prefs = await SharedPreferences.getInstance();
      await _openSettings(tester, prefs);
      final slider = find.byKey(const ValueKey('sistrum-glass-clarity'));
      final warning = find.byKey(
        const ValueKey('sistrum-glass-clear-performance'),
      );
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      expect(warning, findsNothing);
      await tester.drag(slider, const Offset(320, 0));
      await tester.pumpAndSettle();
      expect(tester.widget<Slider>(slider).value, 5);
      expect(_savedGlass(prefs)['glassClarityLevel'], 5);
      final context = tester.element(slider);
      expect(
        ProviderScope.containerOf(context).read(appGlassClarityLevelProvider),
        5,
      );
      // Crystal on full glass is the one costly combination.
      expect(warning, findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await _openSettings(tester, prefs);
      expect(tester.widget<Slider>(slider).value, 5);
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      await tester.drag(slider, const Offset(-320, 0));
      await tester.pumpAndSettle();
      expect(tester.widget<Slider>(slider).value, 1);
      expect(_savedGlass(prefs)['glassClarityLevel'], 1);
      expect(warning, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('glass quality persists and gates Crystal warning ($mode)', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({kThemeModeKey: mode.name});
      final prefs = await SharedPreferences.getInstance();
      await _openSettings(tester, prefs);
      final quality = find.byKey(const ValueKey('sistrum-glass-quality'));
      await tester.ensureVisible(quality);
      await tester.pumpAndSettle();
      for (final label in ['Auto', 'Lite', 'Full', 'Off']) {
        expect(
          find.descendant(of: quality, matching: find.text(label)),
          findsOneWidget,
        );
      }
      await tester.tap(
        find.descendant(of: quality, matching: find.text('Lite')),
      );
      await tester.pumpAndSettle();
      expect(_savedGlass(prefs)['glassQuality'], 'lite');
      final slider = find.byKey(const ValueKey('sistrum-glass-clarity'));
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      await tester.drag(slider, const Offset(320, 0));
      await tester.pumpAndSettle();
      // Lite Crystal has no refraction cost, so no warning.
      expect(
        find.byKey(const ValueKey('sistrum-glass-clear-performance')),
        findsNothing,
      );

      await tester.ensureVisible(quality);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: quality, matching: find.text('Off')),
      );
      await tester.pumpAndSettle();
      expect(_savedGlass(prefs)['glassQuality'], 'off');
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      expect(tester.widget<Slider>(slider).onChanged, isNull);
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('sistrum-glass-clarity-unavailable')),
            )
            .data,
        'Glass is off. Choose Auto, Lite or Full to adjust clarity.',
      );
      expect(find.bySubtype<BackdropFilter>(), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await _openSettings(tester, prefs);
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      expect(tester.widget<Slider>(slider).onChanged, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('glass clarity waits for glass on flat devices ($mode)', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'theme_style': 'sistrum',
        kThemeModeKey: mode.name,
      });
      final prefs = await SharedPreferences.getInstance();
      await _openSettings(tester, prefs, lowEnd: true);
      final slider = find.byKey(const ValueKey('sistrum-glass-clarity'));
      final hint = find.byKey(
        const ValueKey('sistrum-glass-clarity-unavailable'),
      );
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      expect(tester.widget<Slider>(slider).onChanged, isNull);
      expect(
        tester.widget<Text>(hint).data,
        'Glass is opaque on this device. Choose Lite or Full to adjust '
        'clarity.',
      );
      await tester.drag(slider, const Offset(160, 0));
      await tester.pumpAndSettle();
      expect(tester.widget<Slider>(slider).value, 3);
      expect(prefs.getString('app_settings'), isNull);

      final quality = find.byKey(const ValueKey('sistrum-glass-quality'));
      await tester.ensureVisible(quality);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: quality, matching: find.text('Lite')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      expect(hint, findsNothing);
      expect(tester.widget<Slider>(slider).onChanged, isNotNull);
      await tester.drag(slider, const Offset(320, 0));
      await tester.pumpAndSettle();
      expect(_savedGlass(prefs)['glassClarityLevel'], 5);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an explicit glass quality overrides system contrast ($mode)', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(highContrast: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      SharedPreferences.setMockInitialValues({
        'theme_style': 'sistrum',
        kThemeModeKey: mode.name,
      });
      final prefs = await SharedPreferences.getInstance();
      await _openSettings(tester, prefs);
      final slider = find.byKey(const ValueKey('sistrum-glass-clarity'));
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      expect(tester.widget<Slider>(slider).onChanged, isNull);
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('sistrum-glass-clarity-unavailable')),
            )
            .data,
        'Your system requests increased contrast, so glass stays opaque. '
        'Choose Lite or Full to use glass anyway; text contrast is '
        'preserved.',
      );
      final quality = find.byKey(const ValueKey('sistrum-glass-quality'));
      await tester.ensureVisible(quality);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: quality, matching: find.text('Full')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      expect(tester.widget<Slider>(slider).onChanged, isNotNull);
      expect(
        find.byKey(const ValueKey('sistrum-glass-clarity-unavailable')),
        findsNothing,
      );
      expect(MediaQuery.highContrastOf(tester.element(slider)), isTrue);
      expect(find.bySubtype<BackdropFilter>(), findsWidgets);
      await tester.drag(slider, const Offset(320, 0));
      await tester.pumpAndSettle();
      expect(_savedGlass(prefs)['glassClarityLevel'], 5);

      // The override and chosen level survive reopening settings.
      await tester.pumpWidget(const SizedBox());
      await _openSettings(tester, prefs);
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      expect(tester.widget<Slider>(slider).onChanged, isNotNull);
      expect(tester.widget<Slider>(slider).value, 5);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Sistrum accent updates live and survives restart ($mode)', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'theme_style': 'sistrum',
        kThemeModeKey: mode.name,
        'seed_color': 0xff123456,
      });
      final prefs = await SharedPreferences.getInstance();
      await _openSettings(tester, prefs);
      final page = find.byType(AppearanceSettingsPage);
      final initial = Theme.of(tester.element(page));
      expect(
        initial.colorScheme.primary,
        AppTheme.accentColor(AppAccent.red, initial.brightness),
      );

      final blue = find.byTooltip('Blue');
      await tester.ensureVisible(blue);
      await tester.tap(blue);
      await tester.pumpAndSettle();
      final theme = Theme.of(tester.element(page));
      expect(
        theme.colorScheme.primary,
        AppTheme.accentColor(AppAccent.blue, theme.brightness),
      );
      expect(prefs.getString(kAppAccentKey), 'blue');
      expect(prefs.getInt('seed_color'), 0xff123456);
      final overlay = AppTheme.fromContext(
        tester.element(page),
        brightness: Brightness.dark,
      );
      expect(overlay.extension<AppTheme>()!.accent, AppAccent.blue);
      expect(
        overlay.colorScheme.primary,
        AppTheme.accentColor(AppAccent.blue, Brightness.dark),
      );

      await tester.pumpWidget(const SizedBox());
      await _openSettings(tester, prefs);
      expect(
        Theme.of(tester.element(page)).colorScheme.primary,
        theme.colorScheme.primary,
      );
      await tester.ensureVisible(find.byTooltip('Red (default)'));
      await tester.tap(find.byTooltip('Red (default)'));
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(page)).colorScheme.primary,
        initial.colorScheme.primary,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
