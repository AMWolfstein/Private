part of 'app_bottom_bar_test.dart';

late AppChromeController chrome;

late ScrollController scroll;

late int searches;

final capture = GlobalKey();

Future<void> _pumpShell(
  WidgetTester tester, {
  bool withPlayer = true,
  bool blur = false,
  bool liquidGlass = true,
  Brightness brightness = Brightness.light,
  Color? backdrop,
  Color? chromeSurface,
  Widget? body,
  int glassLevel = 4,
  ValueNotifier<int>? activeTab,
  bool groups = false,
  bool impellerLite = false,
}) async {
  tester.view.physicalSize = const Size(393, 760);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentMediaItemProvider.overrideWithBuild(
          (ref, notifier) => Stream.value(
            withPlayer
                ? const MediaItem(
                    id: 'track',
                    title: 'A song',
                    artist: 'Artist',
                  )
                : null,
          ),
        ),
        playbackStateProvider.overrideWith((ref) => const Stream.empty()),
        lowEndDeviceProvider.overrideWithValue(!blur),
        appGlassQualityProvider.overrideWithValue(
          blur ? AppGlassQuality.full : AppGlassQuality.auto,
        ),
        appLiquidGlassProvider.overrideWithValue(liquidGlass),
        appGlassClarityLevelProvider.overrideWithValue(glassLevel),
        // Lite glass on the Impeller path, where blur passes carry keys.
        if (impellerLite) ...[
          appGlassLevelProvider.overrideWithValue(AppGlassLevel.lite),
          appShaderFiltersSupportedProvider.overrideWithValue(true),
        ],
      ],
      child: MaterialApp(
        theme: AppTheme.build(brightness, chromeSurface: chromeSurface),
        builder: (_, child) => RepaintBoundary(
          key: capture,
          child: groups ? AppChromeBatch(child: child!) : child,
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          backgroundColor: backdrop,
          extendBody: true,
          body: NotificationListener<ScrollNotification>(
            onNotification: chrome.handleScroll,
            child:
                body ??
                ListView.builder(
                  controller: scroll,
                  itemExtent: 60,
                  itemCount: 50,
                  itemBuilder: (_, index) => Text('Row $index'),
                ),
          ),
          bottomNavigationBar: ListenableBuilder(
            listenable: Listenable.merge([chrome, ?activeTab]),
            builder: (_, _) => AppBottomBar(
              collapsed: chrome.value,
              destinations: const [
                NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
                NavigationDestination(
                  icon: Icon(Icons.music_note),
                  label: 'Library',
                ),
                NavigationDestination(
                  icon: Icon(Icons.grid_view),
                  label: 'Repo',
                ),
                NavigationDestination(
                  icon: Icon(Icons.search),
                  label: 'Search',
                ),
              ],
              selectedIndex: activeTab?.value ?? 0,
              onSelected: (index) {
                activeTab?.value = index;
                chrome.expand();
              },
              onHome: () {
                activeTab?.value = 0;
                chrome.expand();
              },
              onSearch: () {
                searches++;
                activeTab?.value = 3;
              },
              blurEnabled: blur,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const albumBlue = Color(0xff464566);

void _registerAppBottomBar1() {
  setUp(() {
    chrome = AppChromeController();
    scroll = ScrollController();
    searches = 0;
  });
  tearDown(() {
    chrome.dispose();
    scroll.dispose();
  });

  for (final groups in [false, true]) {
    testWidgets(
      'the bar shares the chrome read; folding buttons read on their own '
      '(batch: $groups)',
      (tester) async {
        await _pumpShell(
          tester,
          blur: true,
          groups: groups,
          impellerLite: true,
        );
        final batch = groups
            ? LiquidGlassBatch.backdropIdOf(
                tester.element(find.byType(AppBottomBar)),
              )
            : null;
        if (groups) expect(batch, isNotNull);
        void expectReads(List<int?> ids, int reads) {
          expect(
            tester
                .widgetList<AppBackdropBlur>(
                  find.descendant(
                    of: find.byType(AppBottomBar),
                    matching: find.byType(AppBackdropBlur),
                  ),
                )
                .map((blur) => blur.backdropId)
                .toList(),
            ids,
          );
          expect(
            appCountBackdropReads(
              // ignore: invalid_use_of_protected_member
              tester.binding.renderViews.first.layer,
            ).total,
            reads,
          );
        }

        // Expanded: player and tabs; the hidden side buttons paint nothing.
        expectReads([batch, batch], groups ? 1 : 2);
        chrome.value = true;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 190));
        // Folding, the side buttons cross the tabs: their own reads.
        expectReads([batch, batch, null, null], groups ? 3 : 4);
        await tester.pumpAndSettle();
        // At rest they sit beside the player and join it.
        expectReads([batch, batch, batch], groups ? 1 : 3);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('header and bar share one read over the whole page', (
    tester,
  ) async {
    final pageScroll = ScrollController();
    addTearDown(pageScroll.dispose);
    await _pumpShell(
      tester,
      blur: true,
      groups: true,
      impellerLite: true,
      body: Navigator(
        onGenerateInitialRoutes: (_, _) => [
          MaterialPageRoute<void>(builder: (_) => const SizedBox()),
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              body: CustomScrollView(
                controller: pageScroll,
                slivers: [
                  const AppSliverHeader.page(title: 'Songs'),
                  SliverList.builder(
                    itemCount: 40,
                    itemBuilder: (_, index) =>
                        SizedBox(height: 64, child: Text('Song $index')),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    final batch = LiquidGlassBatch.backdropIdOf(
      tester.element(find.byType(AppBottomBar)),
    );
    expect(batch, isNotNull);
    expect(
      tester
          .widgetList<AppBackdropBlur>(find.byType(AppBackdropBlur))
          .map((blur) => blur.backdropId),
      everyElement(batch),
    );
    Layer root() =>
        // ignore: invalid_use_of_protected_member
        tester.binding.renderViews.first.layer!;
    expect(appCountBackdropReads(root()).total, 1);

    pageScroll.jumpTo(400);
    await tester.pumpAndSettle();
    // Only the band adds a read of its own.
    expect(appCountBackdropReads(root()).total, 2);

    // The engine caches the backdrop at the first member it draws. Every
    // visible row must be composited before it, so the header and the bar
    // both filter the page behind them.
    final order = <Layer>[];
    void visit(Layer layer) {
      order.add(layer);
      if (layer is ContainerLayer) {
        for (var c = layer.firstChild; c != null; c = c.nextSibling) {
          visit(c);
        }
      }
    }

    visit(root());
    final firstMember = order.indexWhere(
      (layer) => layer is AppBackdropLayer && layer.backdropId == batch,
    );
    expect(firstMember, greaterThan(0));
    final rows = find.textContaining('Song ').evaluate().map((element) {
      RenderObject? node = element.renderObject;
      while (node != null && !node.isRepaintBoundary) {
        node = node.parent;
      }
      return node!.debugLayer!;
    }).toSet();
    expect(rows, isNotEmpty);
    for (final row in rows) {
      expect(order.indexOf(row), lessThan(firstMember));
    }
  });

  for (final liquidGlass in [false, true]) {
    testWidgets(
      'navbar keeps its backdrop blurred throughout motion (liquid: $liquidGlass)',
      (tester) async {
        await _pumpShell(
          tester,
          blur: true,
          liquidGlass: liquidGlass,
          brightness: Brightness.dark,
          glassLevel: 5,
          body: const SizedBox.expand(
            child: CustomPaint(painter: _StripedBackdrop()),
          ),
        );

        Future<void> expectBlur(Offset center, String phase) async {
          final variation = await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(capture),
            );
            final image = await boundary.toImage();
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            final values = <int>[];
            for (var x = -9; x <= 9; x++) {
              final offset =
                  (center.dy.floor() * image.width + center.dx.floor() + x) * 4;
              values.add(bytes.getUint8(offset));
            }
            image.dispose();
            values.sort();
            return values.last - values.first;
          });
          expect(variation, lessThan(20), reason: phase);
        }

        const capsuleSample = Offset(196, 745);
        await expectBlur(capsuleSample, 'Expanded capsule');
        final gesture = await tester.startGesture(
          tester.getCenter(find.text('Home').first),
        );
        await gesture.moveBy(const Offset(100, 0));
        await tester.pump(const Duration(milliseconds: 100));
        await expectBlur(capsuleSample, 'Dragging the selected tab');
        await gesture.up();
        await tester.pumpAndSettle();

        for (final collapsed in [true, false]) {
          chrome.value = collapsed;
          await tester.pump();
          if (collapsed) {
            await tester.pump(const Duration(milliseconds: 190));
            await expectBlur(
              capsuleSample,
              'Capsule halfway to collapsed=$collapsed',
            );
          }
          // Sample below the icons once the growing circles are large enough to
          // expose their backdrop; the page stripes must stay blurred while moving.
          await tester.pump(const Duration(milliseconds: 95));
          for (final key in [
            'sistrum-compact-leading',
            'sistrum-compact-search',
          ]) {
            final center = tester.getCenter(find.byKey(ValueKey(key)));
            await expectBlur(
              center + const Offset(0, 18),
              '$key moving to collapsed=$collapsed',
            );
          }
          if (!collapsed) {
            await tester.pump(const Duration(milliseconds: 95));
            await expectBlur(
              capsuleSample,
              'Capsule halfway to collapsed=$collapsed',
            );
          }
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
