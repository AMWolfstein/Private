part of 'design_system_test.dart';

void _registerDesignSystemSelection() {
  group('selection bar', () {
    test('root-overlay mounting lives in exactly one place', () {
      final offenders = _libSources()
          .where(
            (file) =>
                file.readAsStringSync().contains('OverlayEntry(') &&
                _basename(file) != 'selection_bottom_bar.dart',
          )
          .map(_basename)
          .toList();

      expect(
        offenders,
        isEmpty,
        reason:
            'Selection bars must mount through SelectionOverlayController so '
            'they animate identically and clear the shell navigation bar.',
      );
    });

    testWidgets('shell host keeps modal routes above the selection bar', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = SelectionOverlayController();
      addTearDown(controller.dispose);
      BuildContext? pageContext;
      var selectionTaps = 0;
      var sheetTaps = 0;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: SelectionOverlayHost(
              child: Builder(
                builder: (context) {
                  pageContext = context;
                  return const Scaffold(body: SizedBox.expand());
                },
              ),
            ),
          ),
        ),
      );

      controller.show(
        pageContext!,
        (_) => GestureDetector(
          key: const ValueKey('selection-hit-target'),
          behavior: HitTestBehavior.opaque,
          onTap: () => selectionTaps++,
          child: const SizedBox(height: 200),
        ),
      );
      await tester.pumpAndSettle();

      final sheetClosed = showModalBottomSheet<void>(
        context: pageContext!,
        useRootNavigator: true,
        enableDrag: false,
        builder: (_) => GestureDetector(
          key: const ValueKey('sheet-hit-target'),
          behavior: HitTestBehavior.opaque,
          onTap: () => sheetTaps++,
          child: const SizedBox(height: 300),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('sheet-hit-target')), findsOneWidget);
      expect(find.byKey(const ValueKey('selection-hit-target')), findsNothing);
      expect(selectionTaps, 0);
      expect(sheetTaps, 0);

      Navigator.of(pageContext!, rootNavigator: true).pop();
      await tester.pumpAndSettle();
      await sheetClosed;

      expect(
        find.byKey(const ValueKey('selection-hit-target')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('selection-hit-target')));
      await tester.pump();
      expect(selectionTaps, 1);
    });
  });

  group('CollectionScaffold', () {
    testWidgets('mounts the selection bar only while selecting', (
      tester,
    ) async {
      Widget host({required bool selecting}) => ProviderScope(
        child: MaterialApp(
          theme: MaterialTestTheme.light(),
          home: CollectionScaffold(
            scrollController: ScrollController(),
            isSelectionMode: selecting,
            onExitSelectionMode: () {},
            appBar: const SliverToBoxAdapter(child: SizedBox(height: 10)),
            slivers: const [SliverToBoxAdapter(child: Text('content'))],
            selectionBar: const Text('selection-bar'),
          ),
        ),
      );

      await tester.pumpWidget(host(selecting: false));
      await tester.pumpAndSettle();
      expect(find.text('selection-bar'), findsNothing);

      await tester.pumpWidget(host(selecting: true));
      await tester.pumpAndSettle();
      expect(find.text('selection-bar'), findsOneWidget);

      await tester.pumpWidget(host(selecting: false));
      await tester.pumpAndSettle();
      expect(find.text('selection-bar'), findsNothing);
    });

    testWidgets('reserves the measured height of a multi-row selection bar', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: MaterialTestTheme.light(),
            home: CollectionScaffold(
              scrollController: ScrollController(),
              isSelectionMode: true,
              onExitSelectionMode: () {},
              appBar: const SliverToBoxAdapter(child: SizedBox(height: 10)),
              slivers: const [SliverToBoxAdapter(child: Text('content'))],
              selectionBar: const SizedBox(height: 260),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .getSize(find.byKey(const ValueKey('collection-selection-spacer')))
            .height,
        260,
      );
    });

    test('every collection screen goes through the shared shell', () {
      const screens = [
        'local_album_screen.dart',
        'library_collection_tracks_screen.dart',
      ];
      final offenders = <String>[];
      for (final name in screens) {
        final source = _libSources()
            .where((candidate) {
              if (_basename(candidate) == name) return true;
              return candidate.readAsStringSync().contains("part of '$name';");
            })
            .map((file) => file.readAsStringSync())
            .join('\n');
        if (!source.contains('CollectionScaffold(')) {
          offenders.add(name);
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'Collection screens must share CollectionScaffold; hand-rolled '
            'Scaffold + PopScope + selection plumbing is what let the four '
            'album-style screens drift apart.',
      );
    });
  });

  group('settings components', () {
    testWidgets('choice chip meets the minimum touch target', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: MaterialTestTheme.light(),
            home: Scaffold(
              body: Row(
                children: [
                  SettingsChoiceChip(
                    label: 'Stable',
                    isSelected: true,
                    onTap: () {},
                    expand: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      final size = tester.getSize(find.byType(SettingsChoiceChip));
      expect(
        size.height,
        greaterThanOrEqualTo(AppTokens.standard.minTouchTarget),
      );
    });
  });
}
