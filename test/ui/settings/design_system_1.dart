part of 'design_system_test.dart';

void _registerDesignSystem1() {
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
        expect(role?.fontFamily, 'Inter');
        expect(role?.letterSpacing, lessThan(0));
      }
      expect(theme.textTheme.headlineLarge?.fontFamily, 'Inter');
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
    for (final direction in TextDirection.values) {
      testWidgets(
        'glass theme selector preserves logical selection in $direction',
        (tester) async {
          var selected = 0;
          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                theme: AppTheme.build(Brightness.light),
                home: Scaffold(
                  body: Directionality(
                    textDirection: direction,
                    child: StatefulBuilder(
                      builder: (context, setState) => AppSegmentedControl(
                        labels: const ['System', 'Light', 'Dark'],
                        selectedIndex: selected,
                        onChanged: (index) => setState(() => selected = index),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle(const Duration(milliseconds: 16));
          final systemX = tester.getCenter(find.text('System').first).dx;
          final darkX = tester.getCenter(find.text('Dark').first).dx;
          expect(systemX < darkX, direction == TextDirection.ltr);
          // The package puts a transparent tap layer above the drawn labels.
          await tester.tapAt(tester.getCenter(find.text('Dark').first));
          await tester.pumpAndSettle(const Duration(milliseconds: 16));
          expect(selected, 2);
          await tester.tapAt(tester.getCenter(find.text('System').first));
          await tester.pumpAndSettle(const Duration(milliseconds: 16));
          expect(selected, 0);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('theme selector skips the glass tab bar with reduced motion', (
      tester,
    ) async {
      var selected = 0;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.build(Brightness.dark),
            home: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: Scaffold(
                body: StatefulBuilder(
                  builder: (context, setState) => AppSegmentedControl(
                    labels: const ['System', 'Light', 'Dark'],
                    selectedIndex: selected,
                    onChanged: (index) => setState(() => selected = index),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        tester.widget<AnimatedAlign>(find.byType(AnimatedAlign)).duration,
        Duration.zero,
      );
      expect(find.text('Dark'), findsOneWidget);
      await tester.tap(find.text('Dark'));
      await tester.pump();
      expect(selected, 2);
      expect(
        tester.getCenter(find.text('System')).dx <
            tester.getCenter(find.text('Dark')).dx,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });
    testWidgets('glass search keeps text editing, submit and clear usable', (
      tester,
    ) async {
      final controller = TextEditingController();
      final changes = <String>[];
      String? submitted;
      var cleared = false;
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.build(Brightness.dark),
            home: Scaffold(
              body: AppSearchField(
                controller: controller,
                hintText: 'Search library',
                clearTooltip: 'Clear search',
                onChanged: changes.add,
                onSubmitted: (value) => submitted = value,
                onClear: () => cleared = true,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(AppGlass), findsOneWidget);
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'Album');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(changes, ['Album']);
      expect(submitted, 'Album');
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump();
      expect(controller.text, isEmpty);
      expect(cleared, isTrue);
      expect(tester.takeException(), isNull);
    });

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
        'lib/screens/now_playing_screen.dart',
        'lib/screens/now_playing_screen_player.dart',
        'lib/screens/now_playing_screen_lyrics.dart',
        'lib/screens/now_playing_screen_menus.dart',
      ].map((path) => File(path).readAsStringSync()).join('\n');

      expect(source, contains('showAppBottomSheet<String>'));
      expect(source, isNot(contains('PopupMenuButton')));
    });
  });
}
