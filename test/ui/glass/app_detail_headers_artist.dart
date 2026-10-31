part of 'app_detail_headers_test.dart';

final palette = CoverPaletteCache();

void _registerAppDetailHeadersArtist() {
  testWidgets(
    'local and online album actions share the neutral cover surface',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync('album-surface-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      final cover = File('${directory.path}/cover.png');
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawColor(Colors.white, BlendMode.src);
        canvas.drawRect(
          const Rect.fromLTWH(50, 0, 50, 100),
          Paint()..color = const Color(0xff02020f),
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(100, 100);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        picture.dispose();
        await cover.writeAsBytes(bytes!.buffer.asUint8List());
        await palette.resolve(cover.path, Brightness.dark);
      });
      for (final online in [false, true]) {
        final label = online ? 'Download' : 'Play';
        await tester.pumpWidget(
          ProviderScope(
            overrides: [coverPaletteProvider.overrideWithValue(palette)],
            child: MaterialApp(
              theme: AppTheme.build(Brightness.light),
              home: AppArtistSurface(
                imageSource: cover.path,
                neutralActions: true,
                child: CollectionScaffold(
                  scrollController: scrollController,
                  isSelectionMode: false,
                  onExitSelectionMode: () {},

                  appBar: AlbumDetailHeader(
                    title: 'Monochrome album',
                    expandedHeight: 400,
                    showTitleInAppBar: false,
                    immersive: true,
                    background: const ColoredBox(color: Colors.white),
                    actions: online
                        ? HeaderFilledButton(
                            icon: CupertinoIcons.arrow_down_circle_fill,
                            label: label,
                            onPressed: () {},
                          )
                        : AlbumPlayActions(
                            playLabel: label,
                            shuffleTooltip: 'Shuffle',
                            onPlay: () {},
                            onShuffle: () {},
                          ),
                  ),
                  slivers: const [],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final action = find.text(label);
        final context = tester.element(action);
        final scheme = Theme.of(context).colorScheme;
        expect(scheme.surface.r, scheme.surface.g);
        expect(scheme.surface.g, scheme.surface.b);
        expect(HeaderPalette.of(context), scheme);
        expect(tester.widget<Text>(action).style?.color, Colors.black);
        expect(
          tester
              .widget<CupertinoButton>(
                find.ancestor(
                  of: action,
                  matching: find.byType(CupertinoButton),
                ),
              )
              .color,
          Colors.white,
        );
        if (!online) {
          expect(
            tester.widget<Text>(find.text('Shuffle')).style?.color,
            Colors.white,
          );
        }
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('artist artwork softens, disappears, and returns with scroll', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = FakeViewPadding(top: 59, bottom: 34);
    addTearDown(tester.view.reset);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    const artworkKey = ValueKey('artist-artwork');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [coverPaletteProvider.overrideWithValue(palette)],
        child: MaterialApp(
          theme: AppTheme.build(Brightness.dark),
          home: Scaffold(
            body: CustomScrollView(
              controller: controller,
              slivers: const [
                AppArtistHeader(
                  name: 'Artist',
                  artwork: ColoredBox(key: artworkKey, color: Colors.orange),
                  actions: [Text('Artist action')],
                  showTitle: false,
                ),
                SliverToBoxAdapter(child: SizedBox(height: 2000)),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    double fade() => tester
        .widget<ColoredBox>(find.byKey(const ValueKey('artist-artwork-fade')))
        .color
        .a;
    // The artwork softens through the pre-blurred ground, never a live blur.
    double? soften() {
      final veil = find.byType(AppGroundVeil);
      return veil.evaluate().isEmpty
          ? null
          : tester.widget<AppGroundVeil>(veil).opacity;
    }

    final artwork = tester.element(find.byKey(artworkKey));
    expect(find.byType(ImageFiltered), findsNothing);
    expect(fade(), 0);
    expect(soften() ?? 0, 0);

    controller.jumpTo(120);
    await tester.pumpAndSettle();
    expect(soften(), inExclusiveRange(0, 1));
    expect(fade(), inExclusiveRange(0, 1));
    expect(find.text('Artist action').hitTestable(), findsOneWidget);

    controller.jumpTo(340);
    await tester.pumpAndSettle();
    expect(fade(), 1);
    expect(soften(), isNull);
    expect(TickerMode.valuesOf(artwork).enabled, isFalse);
    expect(find.byTooltip('Back').hitTestable(), findsOneWidget);

    controller.jumpTo(0);
    await tester.pumpAndSettle();
    expect(fade(), 0);
    expect(soften() ?? 0, 0);
    expect(find.byType(ImageFiltered), findsNothing);
    expect(TickerMode.valuesOf(artwork).enabled, isTrue);
    expect(find.text('Artist action').hitTestable(), findsOneWidget);
    expect(tester.element(find.byKey(artworkKey)), same(artwork));
    expect(tester.takeException(), isNull);
  });

  testWidgets('pulling the artist header zooms only the artwork', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = FakeViewPadding(top: 59, bottom: 34);
    addTearDown(tester.view.reset);
    const artworkKey = ValueKey('stretch-artwork');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [coverPaletteProvider.overrideWithValue(palette)],
        child: MaterialApp(
          theme: AppTheme.build(Brightness.dark),
          home: Scaffold(
            body: CustomScrollView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: const [
                AppArtistHeader(
                  name: 'Artist',
                  artwork: ColoredBox(key: artworkKey, color: Colors.orange),
                  actions: [Text('Artist action')],
                  showTitle: false,
                ),
                SliverToBoxAdapter(child: Text('Album list')),
                SliverToBoxAdapter(child: SizedBox(height: 2000)),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final artwork = find.byKey(artworkKey);
    final action = find.text('Artist action');
    final albums = find.text('Album list');
    final originalArt = tester.getRect(artwork);
    final originalAction = tester.getRect(action);
    final originalAlbums = tester.getRect(albums);
    final element = tester.element(artwork);
    final gesture = await tester.startGesture(const Offset(195, 350));
    await gesture.moveBy(const Offset(0, 150));
    await tester.pump();
    final stretchedArt = tester.getRect(artwork);
    expect(stretchedArt.width, greaterThan(originalArt.width));
    expect(
      stretchedArt.width / originalArt.width,
      closeTo(stretchedArt.height / originalArt.height, 0.001),
    );
    expect(stretchedArt.top, closeTo(originalArt.top, 0.01));
    expect(tester.getSize(action), originalAction.size);
    expect(tester.getRect(action).top, greaterThan(originalAction.top));
    expect(tester.getRect(albums).top, greaterThan(originalAlbums.top));
    expect(tester.element(artwork), same(element));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getRect(artwork), originalArt);
    expect(tester.getRect(action), originalAction);
    expect(tester.takeException(), isNull);
  });

  for (final squareArtwork in [true, false]) {
    for (final reduceMotion in [false, true]) {
      testWidgets(
        'album pull preserves controls (square: $squareArtwork, reduced motion: $reduceMotion)',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          tester.view.padding = FakeViewPadding(top: 59, bottom: 34);
          addTearDown(tester.view.reset);
          final controller = ScrollController();
          addTearDown(controller.dispose);
          const artworkKey = ValueKey('stretch-album-artwork');
          var plays = 0;
          await tester.pumpWidget(
            ProviderScope(
              overrides: [coverPaletteProvider.overrideWithValue(palette)],
              child: MaterialApp(
                theme: AppTheme.build(Brightness.dark),
                scrollBehavior: const MaterialScrollBehavior().copyWith(
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(disableAnimations: reduceMotion),
                  child: child!,
                ),
                home: CollectionScaffold(
                  scrollController: controller,
                  isSelectionMode: false,
                  onExitSelectionMode: () {},

                  appBar: AlbumDetailHeader(
                    immersive: true,
                    squareArtwork: squareArtwork,
                    title: 'Album',
                    expandedHeight: 400,
                    showTitleInAppBar: false,
                    background: const ColoredBox(
                      key: artworkKey,
                      color: Colors.orange,
                    ),
                    actions: AlbumPlayActions(
                      playLabel: 'Play',
                      shuffleTooltip: 'Shuffle',
                      onPlay: () => plays++,
                      onShuffle: () {},
                    ),
                  ),
                  slivers: const [
                    SliverToBoxAdapter(child: Text('Track list')),
                    SliverToBoxAdapter(child: SizedBox(height: 2000)),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final artwork = find.byKey(artworkKey);
          final play = find.text('Play');
          final tracks = find.text('Track list');
          final originalArt = tester.getRect(artwork);
          final originalPlay = tester.getRect(play);
          final originalTracks = tester.getRect(tracks);
          final originalBack = tester.getRect(find.byTooltip('Back'));
          final element = tester.element(artwork);
          final gesture = await tester.startGesture(const Offset(195, 250));
          await gesture.moveBy(const Offset(0, 150));
          await tester.pump();
          final stretchedArt = tester.getRect(artwork);
          expect(controller.offset, lessThan(0));
          if (reduceMotion) {
            expect(stretchedArt.size, originalArt.size);
          } else {
            expect(stretchedArt.width, greaterThan(originalArt.width));
            expect(
              stretchedArt.width / originalArt.width,
              closeTo(stretchedArt.height / originalArt.height, 0.001),
            );
            expect(stretchedArt.top, closeTo(originalArt.top, 0.01));
          }
          expect(tester.getSize(play), originalPlay.size);
          expect(tester.getRect(play).top, greaterThan(originalPlay.top));
          expect(tester.getRect(tracks).top, greaterThan(originalTracks.top));
          expect(tester.getRect(find.byTooltip('Back')), originalBack);
          expect(play.hitTestable(), findsOneWidget);
          expect(tester.element(artwork), same(element));
          await gesture.up();
          await tester.pumpAndSettle();
          expect(tester.getRect(artwork), originalArt);
          expect(tester.getRect(play), originalPlay);
          await tester.tap(play);
          expect(plays, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
