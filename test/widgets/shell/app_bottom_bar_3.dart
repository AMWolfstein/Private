part of 'app_bottom_bar_test.dart';

void _registerAppBottomBar3() {
  testWidgets(
    'collapse keeps the player and tab contents out of frame rebuilds',
    (tester) async {
      await _pumpShell(tester);
      var tabBuilds = 0;
      var playerBuilds = 0;
      final previous = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        previous?.call(element, builtOnce);
        if (element.widget is AppTabBar) tabBuilds++;
        if (element.widget is MiniPlayer) playerBuilds++;
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previous);
      chrome.value = true;
      await tester.pump();
      for (var frame = 0; frame < 25; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(
        tabBuilds,
        lessThanOrEqualTo(2),
        reason: 'Only the wrapper geometry animates each frame',
      );
      expect(
        playerBuilds,
        lessThanOrEqualTo(2),
        reason:
            'The player rebuilds for compact mode, not for every animation tick',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('folding chrome updates the spacer without rebuilding Settings', (
    tester,
  ) async {
    await _pumpShell(tester, body: const SettingsTab(), blur: true);
    var settingsBuilds = 0;
    var spacerBuilds = 0;
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      previous?.call(element, builtOnce);
      if (element.widget is SettingsTab) settingsBuilds++;
      if (element.widget is NavBarSliverSpacer) spacerBuilds++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = previous);

    for (final collapsed in [true, false]) {
      chrome.value = collapsed;
      await tester.pump();
      for (var frame = 0; frame < 25; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    expect(settingsBuilds, 0);
    expect(spacerBuilds, greaterThan(20));
    expect(tester.takeException(), isNull);
  });

  for (final artist in [true, false]) {
    testWidgets('folding chrome isolates header insets (artist: $artist)', (
      tester,
    ) async {
      var pageBuilds = 0;
      await _pumpShell(
        tester,
        body: Builder(
          builder: (context) {
            pageBuilds++;
            final tracks = SliverFixedExtentList.builder(
              itemExtent: 60,
              itemCount: 50,
              itemBuilder: (_, index) => Text('Track $index'),
            );
            if (artist) {
              return CustomScrollView(
                controller: scroll,
                slivers: [
                  ...const AppArtistHeader(
                    name: 'Artist',
                    showTitle: false,
                    artwork: ColoredBox(color: Colors.blue),
                    actions: [],
                  ).buildSlivers(context),
                  tracks,
                  const NavBarSliverSpacer(),
                ],
              );
            }
            return CollectionScaffold(
              scrollController: scroll,
              isSelectionMode: false,
              onExitSelectionMode: () {},
              appBar: const AlbumDetailHeader(
                title: 'Album',
                expandedHeight: 400,
                immersive: true,
                showTitleInAppBar: false,
                background: ColoredBox(color: Colors.blue),
              ),
              slivers: [tracks],
            );
          },
        ),
      );
      pageBuilds = 0;
      var collectionBuilds = 0;
      final previous = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        previous?.call(element, builtOnce);
        if (element.widget is CollectionScaffold) collectionBuilds++;
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previous);
      for (final collapsed in [true, false]) {
        chrome.value = collapsed;
        await tester.pump();
        for (var frame = 0; frame < 25; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
      }
      expect(pageBuilds, 0);
      expect(collectionBuilds, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'compact tabs survive upward scrolling until the page returns to the top',
    (tester) async {
      await _pumpShell(tester);
      scroll.jumpTo(500);
      await tester.pumpAndSettle();
      expect(chrome.value, isFalse);
      await tester.drag(find.byType(ListView), const Offset(-120, 0));
      await tester.pumpAndSettle();
      expect(chrome.value, isFalse);
      await tester.drag(find.byType(ListView), const Offset(0, -160));
      await tester.pumpAndSettle();
      expect(chrome.value, isTrue);
      await tester.drag(find.byType(ListView), const Offset(0, 90));
      await tester.pumpAndSettle();
      expect(chrome.value, isTrue);
      await tester.drag(find.byType(ListView), const Offset(0, 900));
      await tester.pumpAndSettle();
      expect(chrome.value, isFalse);
    },
  );

  testWidgets('Library keeps compact tabs until the outer header returns', (
    tester,
  ) async {
    await _pumpShell(
      tester,
      body: NestedScrollView(
        headerSliverBuilder: (_, _) => const [
          SliverAppBar(expandedHeight: 180, title: Text('Library')),
        ],
        body: PageView(
          children: [
            ListView.builder(
              itemExtent: 60,
              itemCount: 60,
              itemBuilder: (_, index) => Text('Track $index'),
            ),
          ],
        ),
      ),
    );
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(chrome.value, isTrue);
    await tester.drag(find.byType(ListView), const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(chrome.value, isTrue);
    await tester.drag(find.byType(ListView), const Offset(0, 900));
    await tester.pumpAndSettle();
    expect(chrome.value, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'glass bar stays mounted and pauses its tickers while collapsed',
    (tester) async {
      await _pumpShell(tester, blur: true);
      final glass = tester.element(find.byType(AppSelectionPill));
      final player = tester.state(find.byType(MiniPlayer));
      expect(TickerMode.valuesOf(glass).enabled, isTrue);
      chrome.value = true;
      await tester.pumpAndSettle();
      expect(find.byType(AppSelectionPill), findsNothing);
      expect(
        tester.element(find.byType(AppSelectionPill, skipOffstage: false)),
        same(glass),
      );
      expect(TickerMode.valuesOf(glass).enabled, isFalse);
      chrome.expand();
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(AppSelectionPill)), same(glass));
      expect(tester.state(find.byType(MiniPlayer)), same(player));
      expect(TickerMode.valuesOf(glass).enabled, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('compact navigation works without a playing track', (
    tester,
  ) async {
    await _pumpShell(tester, withPlayer: false);
    await tester.drag(find.byType(ListView), const Offset(0, -240));
    await tester.pumpAndSettle();
    expect(chrome.value, isTrue);
    await tester.tap(find.byTooltip('Search'));
    expect(searches, 1);
    await tester.tap(find.byTooltip('Home'));
    await tester.pumpAndSettle();
    expect(chrome.value, isFalse);
    expect(tester.takeException(), isNull);
  });
}
