part of 'design_system_test.dart';

void _registerDesignSystemTokens() {
  group('AppTokens', () {
    test('is registered on both themes', () {
      expect(
        MaterialTestTheme.light().extension<AppTokens>(),
        AppTokens.standard,
      );
      expect(
        MaterialTestTheme.dark().extension<AppTokens>(),
        AppTokens.standard,
      );
      expect(
        MaterialTestTheme.dark(isAmoled: true).extension<AppTokens>(),
        AppTokens.standard,
      );
      expect(
        AppTheme.build(Brightness.light).extension<AppTokens>(),
        AppTheme.tokens,
      );
      expect(
        AppTheme.build(Brightness.dark).colorScheme.primary,
        AppTheme.darkAccent,
      );
    });

    testWidgets('Sistrum keeps a font family and tracking in text roles', (
      tester,
    ) async {
      final theme = AppTheme.build(Brightness.light);
      for (final role in [
        theme.textTheme.bodyLarge,
        theme.textTheme.bodyMedium,
        theme.textTheme.titleMedium,
        theme.textTheme.titleSmall,
        theme.textTheme.labelLarge,
        theme.textTheme.labelSmall,
      ]) {
        expect(
          role?.fontFamily,
          const CupertinoThemeData().textTheme.textStyle.fontFamily,
        );
        expect(role?.letterSpacing, lessThan(0));
      }
      expect(
        theme.textTheme.headlineLarge?.fontFamily,
        const CupertinoThemeData().textTheme.navLargeTitleTextStyle.fontFamily,
      );
    });

    testWidgets('context.tokens falls back to the standard scale', (
      tester,
    ) async {
      AppTokens? seen;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ThemeData(),
            home: Builder(
              builder: (context) {
                seen = context.tokens;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(seen, AppTokens.standard);
    });

    test('lerp interpolates the scale instead of snapping', () {
      const other = AppTokens.standard;
      final doubled = other.copyWith(radiusCard: 40);
      final mid = other.lerp(doubled, 0.5);

      expect(mid.radiusCard, (other.radiusCard + 40) / 2);
    });

    test('badge text stays legible', () {
      // 9-10px badge labels were the accessibility floor violation this token
      // was introduced to fix.
      expect(AppTokens.standard.badgeFontSize, greaterThanOrEqualTo(11));
    });

    test('minimum touch target matches the Material floor', () {
      expect(AppTokens.standard.minTouchTarget, 48);
    });
  });

  group('accessibility contracts', () {
    test('every IconButton has a tooltip-backed accessible name', () {
      final offenders = <String>[];
      for (final file in _libSources()) {
        final result = parseFile(
          path: file.absolute.path,
          featureSet: FeatureSet.latestLanguageVersion(),
        );
        result.unit.accept(
          _IconButtonTooltipVisitor(
            file: file,
            lineInfo: result.lineInfo,
            offenders: offenders,
          ),
        );
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'Icon-only controls must expose a tooltip so TalkBack, VoiceOver, '
            'keyboard users, and pointer users receive the same action name.',
      );
    });

    testWidgets('selection actions expose their label and disabled state', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: MaterialTestTheme.light(),
              home: Scaffold(
                body: Center(
                  child: SelectionActionButton(
                    icon: Icons.delete,
                    label: 'Delete selected tracks',
                    onPressed: null,
                    colorScheme: MaterialTestTheme.light().colorScheme,
                  ),
                ),
              ),
            ),
          ),
        );

        expect(
          tester.getSemantics(find.bySemanticsLabel('Delete selected tracks')),
          matchesSemantics(
            label: 'Delete selected tracks',
            isButton: true,
            hasEnabledState: true,
            isEnabled: false,
          ),
        );
        expect(
          tester.getSize(find.byType(SelectionActionButton)).height,
          greaterThanOrEqualTo(AppTokens.standard.minTouchTarget),
        );
      } finally {
        semantics.dispose();
      }
    });
  });

  group('AppSearchField', () {
    testWidgets('uses the shared filled search style and clears input', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'quality');
      var cleared = false;
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: MaterialTestTheme.light(),
            home: Scaffold(
              body: AppSearchField(
                controller: controller,
                hintText: 'Search settings',
                clearTooltip: 'Clear',
                onChanged: (_) {},
                onClear: () => cleared = true,
              ),
            ),
          ),
        ),
      );

      final field = tester.widget<TextField>(find.byType(TextField));
      final border = field.decoration!.enabledBorder! as OutlineInputBorder;

      expect(field.decoration!.filled, isTrue);
      expect(border.borderRadius.topLeft.x, AppTokens.standard.radiusSheet);
      expect(find.byTooltip('Clear'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear'));
      await tester.pump();

      expect(controller.text, isEmpty);
      expect(cleared, isTrue);
    });
  });

  group('Now Playing actions', () {
    test('uses the app bottom sheet instead of a platform popup menu', () {
      final source = [
        'lib/screens/player/now_playing_screen.dart',
        'lib/screens/player/now_playing_screen_player.dart',
        'lib/screens/player/now_playing_screen_lyrics.dart',
        'lib/screens/player/now_playing_screen_menus.dart',
      ].map((path) => File(path).readAsStringSync()).join('\n');

      expect(source, contains('showAppBottomSheet<String>'));
      expect(source, isNot(contains('PopupMenuButton')));
    });
  });
}
