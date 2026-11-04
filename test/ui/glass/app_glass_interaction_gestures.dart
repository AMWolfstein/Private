part of 'app_glass_interaction_test.dart';

void _registerAppGlassInteractionGestures() {
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
    testWidgets('glass tabs select by tap and by drag ($direction)', (
      tester,
    ) async {
      var selected = 0;
      final changes = <int>[];
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.build(Brightness.dark),
            home: Directionality(
              textDirection: direction,
              child: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 360,
                    child: StatefulBuilder(
                      builder: (context, setState) => AppTabBar(
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
      );
      await tester.pumpAndSettle();
      // A tap on an unselected tab selects it.
      await tester.tap(find.text('Library'));
      await tester.pumpAndSettle();
      expect(changes, [1]);
      expect(selected, 1);
      // A drag across tabs settles on the tab it is released over.
      final from = tester.getCenter(find.text('Library'));
      final to = tester.getCenter(find.text('Search'));
      final gesture = await tester.startGesture(from);
      for (var i = 1; i <= 8; i++) {
        await gesture.moveTo(from + (to - from) * (i / 8));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(changes.last, 2);
      expect(selected, 2);
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
                      NavigationDestination(
                        icon: Icon(Icons.search),
                        label: 'Search',
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
    // The g1455 tab bar keeps its fixed 60dp height plus the 10dp padding
    // on each side; large text scales the labels inside it, and it must not
    // overflow.
    expect(tester.getSize(find.byType(AppTabBar)).height, closeTo(80, 0.5));
    expect(tester.takeException(), isNull);
  });
}
