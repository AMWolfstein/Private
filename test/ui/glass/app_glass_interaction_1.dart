part of 'app_glass_interaction_test.dart';

void _registerAppGlassInteraction1() {
  testWidgets('selection color follows rounded pill corners', (tester) async {
    final capture = GlobalKey();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Center(
            child: RepaintBoundary(
              key: capture,
              child: SizedBox(
                width: 200,
                child: AppSelectionPill(
                  labels: const ['A', 'B'],
                  selectedIndex: 0,
                  onChanged: (_) {},
                  padding: EdgeInsets.zero,
                  selectionColor: Colors.red,
                  itemBuilder: (_, _, _) => const SizedBox(
                    height: 64,
                    child: ColoredBox(color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => ui.FragmentProgram.fromAsset(
        'assets/shaders/app_selection_mask.frag',
      ),
    );
    await tester.pumpAndSettle();
    final colors = (await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(capture),
      );
      final image = await boundary.toImage();
      try {
        final bytes = (await image.toByteData())!;
        return [
          for (final point in [
            const Offset(2, 2),
            const Offset(20, 32),
            const Offset(98, 2),
            const Offset(150, 32),
          ])
            Color.fromARGB(
              bytes.getUint8(
                (point.dy.toInt() * image.width + point.dx.toInt()) * 4 + 3,
              ),
              bytes.getUint8(
                (point.dy.toInt() * image.width + point.dx.toInt()) * 4,
              ),
              bytes.getUint8(
                (point.dy.toInt() * image.width + point.dx.toInt()) * 4 + 1,
              ),
              bytes.getUint8(
                (point.dy.toInt() * image.width + point.dx.toInt()) * 4 + 2,
              ),
            ),
        ];
      } finally {
        image.dispose();
      }
    }))!;
    expect(
      colors.map((color) => color.toARGB32()),
      [
        Colors.white,
        Colors.red,
        Colors.white,
        Colors.white,
      ].map((color) => color.toARGB32()),
    );
    expect(tester.takeException(), isNull);
  });

  _maskCullingTests();

  for (final direction in TextDirection.values) {
    testWidgets('tab dragging previews, commits and cancels ($direction)', (
      tester,
    ) async {
      var selected = -1;
      final changes = <int>[];
      final capture = GlobalKey();
      final theme = AppTheme.build(Brightness.dark);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: theme,
            home: Directionality(
              textDirection: direction,
              child: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 360,
                    child: StatefulBuilder(
                      builder: (context, setState) => RepaintBoundary(
                        key: capture,
                        child: AppTabBar(
                          destinations: const [
                            NavigationDestination(
                              icon: Icon(Icons.home),
                              label: 'Home',
                            ),
                            NavigationDestination(
                              icon: AppNavigationIcon(
                                icon: Icons.music_note,
                                badgeCount: 7,
                              ),
                              label: 'Library',
                            ),
                            NavigationDestination(
                              icon: Icon(Icons.search),
                              label: 'Search',
                            ),
                          ],
                          selectedIndex: selected,
                          onSelected: (next) {
                            changes.add(next);
                            setState(() => selected = next);
                          },
                          blurEnabled: true,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // No selection must still allow activating the first destination.
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(changes, [0]);
      final home = tester.getCenter(find.text('Home'));
      final library = tester.getCenter(find.text('Library'));
      final pill = find.descendant(
        of: find.byType(AppSelectionPill),
        matching: find.byType(FractionallySizedBox),
      );
      final gesture = await tester.startGesture(home);
      // Move within tabs, across their boundaries, and reverse direction.
      // One frame must put the pill under the finger without a settling delay.
      for (final fraction in [0.35, 0.45, 0.5, 0.85, 1.2, 1.1, 0.9, 1.5]) {
        final position = Offset(
          home.dx + (library.dx - home.dx) * fraction,
          home.dy,
        );
        await gesture.moveTo(position);
        await tester.pump();
        expect(tester.getCenter(pill).dx, closeTo(position.dx, 0.1));
        expect(changes, [0]);
        if (fraction == 0.5) {
          // Halfway between destinations, both icons and both labels contain
          // active and inactive pixels. A nearest-index color swap cannot pass.
          for (final finder in [
            find.byIcon(Icons.home),
            find.byIcon(Icons.music_note),
            find.text('Home'),
            find.text('Library'),
          ]) {
            final colors = await _foregroundPixels(tester, capture, finder, [
              theme.colorScheme.primary,
              theme.colorScheme.onSurface,
            ]);
            expect(colors, everyElement(greaterThan(3)));
          }
          final badgePixels = await _foregroundPixels(
            tester,
            capture,
            find.text('7'),
            [theme.colorScheme.onError],
          );
          expect(badgePixels.single, greaterThan(3));
        }
      }
      await gesture.moveTo(tester.getCenter(find.text('Search')));
      await tester.pumpAndSettle();
      expect(changes, [0]);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(changes, [0, 2]);
      expect(
        tester.getCenter(pill).dx,
        closeTo(tester.getCenter(find.text('Search')).dx, 0.1),
      );
      final cancelled = await tester.startGesture(
        tester.getCenter(find.text('Search')),
      );
      await cancelled.moveTo(tester.getCenter(find.text('Home')));
      await tester.pump();
      await cancelled.cancel();
      await tester.pumpAndSettle();
      expect(changes, [0, 2]);
      expect(
        tester.getCenter(pill).dx,
        closeTo(tester.getCenter(find.text('Search')).dx, 0.1),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(changes.length, 3);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Search'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('switch drag toggles once with no filter ($direction)', (
      tester,
    ) async {
      var value = false;
      final changes = <bool>[];
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.build(Brightness.dark),
            home: Directionality(
              textDirection: direction,
              child: Scaffold(
                body: Center(
                  child: StatefulBuilder(
                    builder: (context, setState) => AppSwitch(
                      value: value,
                      onChanged: (next) {
                        changes.add(next);
                        setState(() => value = next);
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final sign = direction == TextDirection.ltr ? 1.0 : -1.0;
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(AppSwitch)),
      );
      await gesture.moveBy(Offset(25 * sign, 0));
      await gesture.moveBy(Offset(25 * sign, 0));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(changes, [true]);
      expect(find.bySubtype<BackdropFilter>(), findsNothing);
      expect(find.byType(ImageFiltered), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('nested glass uses one bounded filter and large text fits', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.build(Brightness.dark),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(3)),
            child: Scaffold(
              body: Column(
                children: [
                  AppGlassPanel(
                    child: AppSegmentedControl(
                      labels: const ['A', 'B'],
                      selectedIndex: 0,
                      onChanged: (_) {},
                    ),
                  ),
                  AppTabBar(
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.home),
                        label: 'Home',
                      ),
                    ],
                    selectedIndex: 0,
                    onSelected: (_) {},
                    blurEnabled: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AppGlassPanel),
        matching: find.bySubtype<BackdropFilter>(),
      ),
      findsOneWidget,
    );
    expect(tester.getSize(find.byType(AppTabBar)).height, greaterThan(80));
    expect(tester.takeException(), isNull);
  });
}
