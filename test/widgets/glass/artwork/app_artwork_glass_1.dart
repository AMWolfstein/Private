part of 'app_artwork_glass_test.dart';

void _registerAppArtworkGlass1() {
  setUpAll(() async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    await binding.runAsync(AppArtworkGlassProgram.load);
  });

  test('the shader compiles and loads', () {
    expect(AppArtworkGlassProgram.loaded, isNotNull);
  });

  test('gating follows quality, level and the loaded program', () {
    // translucent, lens, program -> mode
    final cases = {
      (false, true, true): AppArtworkGlassMode.opaque, // off, high contrast
      (true, false, true): AppArtworkGlassMode.lite, // lite or Level 1
      (true, true, false): AppArtworkGlassMode.lite, // program not loaded
      (true, true, true): AppArtworkGlassMode.refracted, // full, L2-L5
    };
    for (final MapEntry(key: (translucent, lens, program), value: mode)
        in cases.entries) {
      expect(
        appArtworkGlassMode(
          translucent: translucent,
          lens: lens,
          programReady: program,
        ),
        mode,
      );
    }
  });

  testWidgets('each quality and level draws its own material', (tester) async {
    final controller = AppGroundController(
      vsync: const TestVSync(),
      rectOf: () => Rect.zero,
    );
    addTearDown(controller.dispose);
    Future<RenderAppArtworkGlass?> pump({
      required AppGlassLevel level,
      int clarity = 3,
      bool shaders = true,
      bool highContrast = false,
    }) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        _app(
          level: level,
          clarity: clarity,
          shaders: shaders,
          highContrast: highContrast,
          child: Center(
            child: AppArtworkGroundScope(
              controller: controller,
              overlays: true,
              child: const SizedBox(
                width: 200,
                height: 120,
                child: AppGlassPanel.overlay(child: Text('Menu')),
              ),
            ),
          ),
        ),
      );
      final found = find.byType(AppArtworkGlassRender);
      return found.evaluate().isEmpty
          ? null
          : tester.renderObject<RenderAppArtworkGlass>(found);
    }

    // Off: opaque, as today (no ground drawing at all).
    expect(await pump(level: AppGlassLevel.flat), isNull);
    expect(find.bySubtype<BackdropFilter>(), findsNothing);
    // High contrast blocks Auto's glass (the default quality) the same way.
    expect(await pump(level: AppGlassLevel.liquid, highContrast: true), isNull);
    // Lite: the ground without the shader.
    expect((await pump(level: AppGlassLevel.lite))!.refracts, isFalse);
    // Level 1 on full glass: still no refraction.
    expect(
      (await pump(level: AppGlassLevel.liquid, clarity: 1))!.refracts,
      isFalse,
    );
    // Full glass, Levels 2-5, on Impeller: the shader.
    for (final clarity in [2, 3, 4, 5]) {
      expect(
        (await pump(level: AppGlassLevel.liquid, clarity: clarity))!.refracts,
        isTrue,
        reason: 'level $clarity',
      );
    }
    // Without Impeller (no shader filters) full glass draws like lite.
    expect(
      (await pump(level: AppGlassLevel.liquid, shaders: false))!.refracts,
      isFalse,
    );
  });

  testWidgets('no backdrop filter, lens or view in any mode', (tester) async {
    for (final level in AppGlassLevel.values) {
      for (final clarity in [1, 3, 5]) {
        await tester.pumpWidget(
          _app(
            level: level,
            clarity: clarity,
            child: _Player(source: null, insetKey: GlobalKey()),
          ),
        );
        await tester.tap(find.text('More'));
        await tester.pumpAndSettle();
        final reason = '$level L$clarity';
        expect(find.bySubtype<BackdropFilter>(), findsNothing, reason: reason);
        expect(find.byType(LiquidGlassLens), findsNothing, reason: reason);
        expect(find.byType(LiquidGlassView), findsNothing, reason: reason);
        expect(
          appCountBackdropReads(
            // ignore: invalid_use_of_protected_member
            tester.binding.renderViews.first.layer,
          ).total,
          0,
          reason: reason,
        );
        await tester.tapAt(const Offset(4, 4));
        await tester.pumpAndSettle();
      }
    }
  });

  testWidgets('the menu keeps one material for its whole animation', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(child: _Player(source: null, insetKey: GlobalKey())),
    );
    final ground = _playerGround(tester);
    await _settle(tester, () => ground.hasGround);
    await tester.tap(find.text('More'));
    final seen = <(bool, bool, Color?)>{};
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      final glass = find.byType(AppArtworkGlassRender);
      expect(glass, findsOneWidget, reason: 'frame $frame');
      expect(find.bySubtype<BackdropFilter>(), findsNothing);
      final render = tester.renderObject<RenderAppArtworkGlass>(glass);
      final widget = tester.widget<AppArtworkGlassRender>(glass);
      seen.add((render.opaque, render.refracts, widget.fill));
    }
    // Opening and closing: the same material on every frame.
    await tester.tapAt(const Offset(4, 4));
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      final glass = find.byType(AppArtworkGlassRender);
      if (glass.evaluate().isEmpty) break;
      final render = tester.renderObject<RenderAppArtworkGlass>(glass);
      final widget = tester.widget<AppArtworkGlassRender>(glass);
      seen.add((render.opaque, render.refracts, widget.fill));
    }
    expect(seen, hasLength(1));
    expect(seen.single.$1, isFalse, reason: 'ground was ready: glass');
    expect(seen.single.$2, isTrue, reason: 'full glass refracts');
  });

  testWidgets('a menu opened before its ground stays opaque throughout', (
    tester,
  ) async {
    // A real cover: it decodes only once the test lets real time pass.
    await tester.pumpWidget(
      _app(
        child: _Player(source: _cover, insetKey: GlobalKey()),
      ),
    );
    // Tap at once: the ground is still being built.
    await tester.tap(find.text('More'));
    await tester.pump();
    final glass = find.byType(AppArtworkGlassRender);
    expect(tester.renderObject<RenderAppArtworkGlass>(glass).opaque, isTrue);
    final ground = _playerGround(tester);
    await _settle(tester, () => ground.hasGround);
    expect(tester.renderObject<RenderAppArtworkGlass>(glass).opaque, isTrue);
  });

  test('ground mapping: the panel samples the ground under it', () {
    const image = Size(384, 768);
    const ground = Rect.fromLTWH(0, 0, 400, 800);
    // A 100 x 50 panel at (100, 200), drawn at its own size.
    final mapping = appGroundMapping(
      panel: const Rect.fromLTWH(100, 200, 100, 50),
      ground: ground,
      image: image,
      local: const Size(100, 50),
    )!;
    expect(mapping.source, const Rect.fromLTWH(96, 192, 96, 48));
    expect(mapping.target, const Rect.fromLTWH(0, 0, 100, 50));
    // A menu half-way through its scale: the panel's screen rect is smaller
    // than its local size, and still samples exactly what is under it.
    final scaled = appGroundMapping(
      panel: const Rect.fromLTWH(150, 225, 50, 25),
      ground: ground,
      image: image,
      local: const Size(100, 50),
    )!;
    expect(scaled.source, const Rect.fromLTWH(144, 216, 48, 24));
    expect(scaled.target, const Rect.fromLTWH(0, 0, 100, 50));
    // A header circle whose artwork has scrolled up by 300: only the part
    // still over the ground maps; the rest is the edge colour.
    final scrolled = appGroundMapping(
      panel: const Rect.fromLTWH(16, 40, 44, 44),
      ground: const Rect.fromLTWH(0, -300, 400, 360),
      image: const Size(384, 346),
      local: const Size(44, 44),
    )!;
    expect(scrolled.target.top, 0);
    expect(scrolled.target.bottom, closeTo(20, 1e-9));
    expect(scrolled.source.top, closeTo(340 * 346 / 360, 1e-9));
    expect(
      appGroundMapping(
        panel: const Rect.fromLTWH(16, 40, 44, 44),
        ground: const Rect.fromLTWH(0, -400, 400, 360),
        image: const Size(384, 346),
        local: const Size(44, 44),
      ),
      isNull,
    );
  });

  testWidgets('player ground follows the player, track and size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final inset = GlobalKey();
    Future<void> show(String source) => tester.pumpWidget(
      _app(
        child: _Player(source: source, insetKey: inset),
      ),
    );
    await show(_cover);
    final ground = _playerGround(tester);
    await _settle(tester, () => ground.hasGround);
    expect(ground.rect, const Rect.fromLTWH(0, 0, 400, 800));
    final first = ground.to!.image;
    expect(first.width, kAppGroundWidth);
    expect(first.height, 768);
    // A track change builds a new ground and crossfades into it.
    await show(_otherCover);
    await _settle(tester, () => !identical(ground.to!.image, first));
    expect(identical(ground.from!.image, first), isTrue);
    // The crossfade's first frame starts its clock; 380 ms later it is done.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(identical(ground.from, ground.to), isTrue);
    // A size change (rotation) rebuilds it at the new shape.
    final beforeRotation = ground.to!.image;
    tester.view.physicalSize = const Size(800, 400);
    await tester.pump();
    await _settle(tester, () => !identical(ground.to!.image, beforeRotation));
    expect(ground.to!.image.height, 192);
    expect(ground.rect, const Rect.fromLTWH(0, 0, 800, 400));
  });

  testWidgets('scrolled album and artist pages map their artwork rect', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      _app(
        child: AppPageGround(
          source: _cover,
          surface: const Color(0xff302820),
          sigma: 8,
          enabled: true,
          cover: FileImage(File(_cover)),
          child: Scaffold(
            body: CustomScrollView(
              controller: scroll,
              slivers: [
                SliverAppBar(
                  pinned: true,
                  leading: AppHeaderControls(
                    child: AppHeaderCircle(
                      child: IconButton(
                        onPressed: () {},
                        icon: const Icon(Icons.arrow_back),
                      ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(
                  child: SizedBox(
                    height: 360,
                    child: AppGroundAnchor(
                      layout: AppGroundLayout(),
                      child: SizedBox.expand(),
                    ),
                  ),
                ),
                // Page content glass keeps its own material.
                const SliverToBoxAdapter(
                  child: SizedBox(
                    height: 60,
                    child: AppGlass.navigation(
                      blurEnabled: true,
                      child: Text('content'),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 2000)),
              ],
            ),
          ),
        ),
      ),
    );
    final page = tester.state(find.byType(AppPageGround));
    final controller = (page.context.findRenderObject() != null
        ? AppArtworkGroundScope.pageOf(
            tester.element(find.byType(CustomScrollView)),
          )
        : null)!;
    await _settle(tester, () => controller.hasGround);
    // Below the 56 px toolbar.
    expect(controller.rect, const Rect.fromLTWH(0, 56, 400, 360));
    // Header controls opt in and draw from it; page content does not.
    expect(
      find.ancestor(
        of: find.byIcon(Icons.arrow_back),
        matching: find.byType(AppArtworkGlassRender),
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.text('content'),
        matching: find.byType(AppArtworkGlassRender),
      ),
      findsNothing,
    );
    // It reads its own backdrop: a lens on full glass, a blur otherwise.
    expect(
      find.ancestor(
        of: find.text('content'),
        matching: find.byWidgetPredicate(
          (widget) => widget is BackdropFilter || widget is LiquidGlassLens,
        ),
      ),
      findsOneWidget,
    );
    scroll.jumpTo(120);
    await tester.pump();
    expect(controller.rect, const Rect.fromLTWH(0, -64, 400, 360));
    // Moving the ground under fixed controls repaints them, uniforms only:
    // the ground is not rebuilt.
    final image = controller.to!.image;
    scroll.jumpTo(300);
    await tester.pump();
    expect(identical(controller.to!.image, image), isTrue);
    expect(controller.rect!.top, -244);
  });
}
