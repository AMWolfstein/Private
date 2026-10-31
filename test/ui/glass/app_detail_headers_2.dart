part of 'app_detail_headers_test.dart';

void _registerAppDetailHeaders2() {
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'album actions and pinned navigation work in $brightness at $scale',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          tester.view.padding = FakeViewPadding(top: 59, bottom: 34);
          addTearDown(tester.view.reset);
          final controller = ScrollController();
          addTearDown(controller.dispose);
          var plays = 0;
          var shuffles = 0;
          var backs = 0;
          await tester.pumpWidget(
            ProviderScope(
              overrides: [coverPaletteProvider.overrideWithValue(palette)],
              child: MaterialApp(
                theme: AppTheme.build(brightness),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: CollectionScaffold(
                  scrollController: controller,
                  isSelectionMode: false,
                  onExitSelectionMode: () {},

                  appBar: AlbumDetailHeader(
                    immersive: true,
                    title:
                        'A long album title that must wrap without hiding any of its controls',
                    expandedHeight: 400,
                    showTitleInAppBar: false,
                    background: const ColoredBox(
                      key: ValueKey('album-artwork'),
                      color: Colors.orange,
                    ),
                    coverBuilder: (_, _) =>
                        const ColoredBox(color: Colors.orange),
                    subtitle: const Text('Artist name'),
                    leading: HeaderCircleButton(
                      icon: Icons.arrow_back,
                      tooltip: 'Back',
                      onPressed: () => backs++,
                    ),
                    actions: AlbumPlayActions(
                      playLabel: 'Play',
                      shuffleTooltip: 'Shuffle',
                      onPlay: () => plays++,
                      onShuffle: () => shuffles++,
                    ),
                  ),
                  slivers: [
                    SliverList.builder(
                      itemCount: 40,
                      itemBuilder: (_, index) =>
                          SizedBox(height: 64, child: Text('Track $index')),
                    ),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            tester.getSize(find.byKey(const ValueKey('album-artwork'))),
            const Size(390, 390),
          );
          final albumTitle = find
              .text(
                'A long album title that must wrap without hiding any of its controls',
              )
              .last;
          expect(tester.getTopLeft(albumTitle).dy, 370);
          expect(find.byTooltip('Back').hitTestable(), findsOneWidget);
          await tester.ensureVisible(find.text('Play'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Play'));
          await tester.tap(find.text('Shuffle'));
          expect(plays, 1);
          expect(shuffles, 1);
          controller.jumpTo(1300);
          await tester.pumpAndSettle();
          expect(find.byTooltip('Back').hitTestable(), findsOneWidget);
          await tester.tap(find.byTooltip('Back'));
          expect(backs, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('album banner extends behind the raised details and actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = FakeViewPadding(top: 59, bottom: 34);
    addTearDown(tester.view.reset);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var downloads = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [coverPaletteProvider.overrideWithValue(palette)],
        child: MaterialApp(
          theme: AppTheme.build(Brightness.dark),
          home: CollectionScaffold(
            scrollController: controller,
            isSelectionMode: false,
            onExitSelectionMode: () {},

            appBar: AlbumDetailHeader(
              title: 'Album title',
              expandedHeight: 400,
              showTitleInAppBar: false,
              immersive: true,
              squareArtwork: false,
              background: const ColoredBox(
                key: ValueKey('album-banner'),
                color: Colors.orange,
              ),
              subtitle: const Text('Artist name'),
              meta: const Text('2026 · Lossless'),
              actions: HeaderFilledButton(
                icon: CupertinoIcons.arrow_down_circle_fill,
                label: 'Download',
                onPressed: () => downloads++,
              ),
            ),
            slivers: const [SliverToBoxAdapter(child: SizedBox(height: 2000))],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Album title').last).dy, 370);
    final banner = tester.getRect(find.byKey(const ValueKey('album-banner')));
    final action = tester.getRect(find.text('Download'));
    expect(banner.top, 0);
    expect(banner.contains(action.bottomRight), isTrue);
    expect(action.center.dy, lessThan(520));
    expect(find.byTooltip('Back').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Download'));
    expect(downloads, 1);
    controller.jumpTo(1000);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Back').hitTestable(), findsOneWidget);
    controller.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('Download').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'artist identity grows with text and retains navigation after scroll',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      var favorites = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [coverPaletteProvider.overrideWithValue(palette)],
          child: MaterialApp(
            theme: AppTheme.build(Brightness.dark),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: CustomScrollView(
                  controller: controller,
                  slivers: [
                    ...AppArtistHeader(
                      name: 'An artist with a name spanning several lines',
                      showTitle: true,
                      artwork: const ColoredBox(color: Colors.orange),
                      actions: [
                        HeaderCircleButton(
                          icon: Icons.favorite_border,
                          tooltip: 'Favorite',
                          onPressed: () => favorites++,
                        ),
                      ],
                    ).buildSlivers(context),
                    const SliverToBoxAdapter(child: SizedBox(height: 2000)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Favorite'));
      expect(favorites, 1);
      controller.jumpTo(1000);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Back').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
