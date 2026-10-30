import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/services/library/covers/cover_palette.dart';
import 'package:sistrum/theme/app_glass_levels.dart';
import 'package:sistrum/theme/app_theme.dart';
import 'package:sistrum/widgets/header/album_detail_header.dart';
import 'package:sistrum/widgets/primitives/app_sliver_header.dart';
import 'package:sistrum/widgets/collection/collection_scaffold.dart';
import 'package:sistrum/widgets/glass/chrome/app_backdrop_groups.dart';
import 'package:sistrum/widgets/glass/chrome/app_chrome.dart';
import 'package:sistrum/widgets/glass/chrome/app_floating_header.dart';
import 'package:sistrum/providers/cover_palette_provider.dart';

Widget maybeGroups(bool groups, Widget child) =>
    groups ? AppChromeBatch(child: child) : child;

void main() {
  final palette = CoverPaletteCache();
  final backing = find.byKey(const ValueKey('sistrum-header-backing'));

  Future<ScrollController> pumpHeader(
    WidgetTester tester, {
    AppGlassLevel level = AppGlassLevel.liquid,
    bool shaders = true,
    bool reduceMotion = false,
    bool highContrast = false,
    Brightness brightness = Brightness.light,
    TextDirection direction = TextDirection.ltr,
    List<Widget>? actions,
    int clarityLevel = 3,
    bool groups = false,
    bool bandBlurOff = false,
  }) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          coverPaletteProvider.overrideWithValue(palette),
          appGlassLevelProvider.overrideWithValue(level),
          appShaderFiltersSupportedProvider.overrideWithValue(shaders),
          appGlassClarityLevelProvider.overrideWithValue(clarityLevel),
          appHeaderBandBlurDisabledProvider.overrideWithValue(bandBlurOff),
        ],
        child: MaterialApp(
          theme: AppTheme.build(brightness),
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                disableAnimations: reduceMotion,
                highContrast: highContrast,
              ),
              child: Directionality(
                textDirection: direction,
                child: maybeGroups(
                  groups,
                  Navigator(
                    onGenerateInitialRoutes: (_, _) => [
                      MaterialPageRoute<void>(
                        builder: (_) => const Scaffold(body: Text('Root')),
                      ),
                      MaterialPageRoute<void>(
                        builder: (_) => Scaffold(
                          body: CustomScrollView(
                            controller: controller,
                            slivers: [
                              AppSliverHeader.page(
                                title: 'Songs',
                                actions: actions,
                              ),
                              SliverList.builder(
                                itemCount: 60,
                                itemBuilder: (_, index) => SizedBox(
                                  height: 64,
                                  child: Text('Row $index'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  SliverAppBar appBar(WidgetTester tester) =>
      tester.widget<SliverAppBar>(find.byType(SliverAppBar));

  Future<void> scrollUnder(WidgetTester tester, ScrollController c) async {
    c.jumpTo(600);
    await tester.pumpAndSettle();
  }

  testWidgets('liquid level floats a glass header with a scrolled backing', (
    tester,
  ) async {
    final controller = await pumpHeader(
      tester,
      actions: [
        IconButton(onPressed: () {}, icon: const Icon(Icons.add)),
        IconButton(onPressed: () {}, icon: const Icon(Icons.share)),
      ],
    );
    expect(appBar(tester).backgroundColor, Colors.transparent);
    // The back circle and one shared capsule for both actions.
    expect(find.byType(LiquidGlassLens), findsNWidgets(2));
    expect(backing, findsNothing);
    expect(find.byType(LiquidGlassView), findsNothing);

    await scrollUnder(tester, controller);
    expect(backing, findsOneWidget);
    final edge = tester.widget<LiquidGlassScrollEdge>(backing);
    // Balanced (the default level) blurs the band with its table sigma.
    expect(edge.blur, 6);
    expect(edge.color.a, closeTo(0.72, 0.001));

    controller.jumpTo(0);
    await tester.pumpAndSettle();
    expect(backing, findsNothing);
  });

  testWidgets('lite, Level 1 and reduced motion keep blur but no lens', (
    tester,
  ) async {
    for (final (level, reduceMotion, shaders, clarity) in [
      (AppGlassLevel.lite, false, true, 3),
      (AppGlassLevel.liquid, true, true, 3),
      (AppGlassLevel.liquid, false, false, 3),
      (AppGlassLevel.liquid, false, true, 1),
    ]) {
      final controller = await pumpHeader(
        tester,
        level: level,
        reduceMotion: reduceMotion,
        shaders: shaders,
        clarityLevel: clarity,
      );
      expect(appBar(tester).backgroundColor, Colors.transparent);
      expect(find.byType(LiquidGlassLens), findsNothing);
      await scrollUnder(tester, controller);
      final edge = tester.widget<LiquidGlassScrollEdge>(backing);
      expect(
        edge.blur,
        appGlassClarity(clarity).blurSigma,
        reason: '$level motion:$reduceMotion',
      );
      expect(edge.color.a, closeTo(0.72, 0.001));
    }
  });

  testWidgets('flat level and high contrast keep the opaque header', (
    tester,
  ) async {
    for (final (level, highContrast) in [
      (AppGlassLevel.flat, false),
      (AppGlassLevel.liquid, true),
    ]) {
      final controller = await pumpHeader(
        tester,
        level: level,
        highContrast: highContrast,
        actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.add))],
      );
      final context = tester.element(find.byType(SliverAppBar));
      expect(
        appBar(tester).backgroundColor,
        Theme.of(context).colorScheme.surface,
      );
      expect(find.byType(LiquidGlassLens), findsNothing);
      await scrollUnder(tester, controller);
      expect(backing, findsNothing);
    }
  });

  testWidgets('back button still pops and the title still collapses', (
    tester,
  ) async {
    final controller = await pumpHeader(tester);
    final title = find.text('Songs');
    final expanded = tester.getRect(title);
    await scrollUnder(tester, controller);
    final collapsed = tester.getRect(title);
    expect(collapsed.height, lessThan(expanded.height));
    expect(collapsed.top, lessThan(expanded.top));

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Root'), findsOneWidget);
  });

  testWidgets('RTL keeps back at the start and actions at the end', (
    tester,
  ) async {
    await pumpHeader(
      tester,
      direction: TextDirection.rtl,
      actions: [
        IconButton(
          tooltip: 'Add',
          onPressed: () {},
          icon: const Icon(Icons.add),
        ),
      ],
    );
    final back = tester.getCenter(find.byTooltip('Back'));
    final add = tester.getCenter(find.byTooltip('Add'));
    expect(back.dx, greaterThan(300));
    expect(add.dx, lessThan(100));
    final title = tester.getRect(find.text('Songs'));
    expect(title.right, greaterThan(300));
  });

  testWidgets('status bar icons follow the header backdrop', (tester) async {
    for (final brightness in Brightness.values) {
      await pumpHeader(tester, brightness: brightness);
      final style = appBar(tester).systemOverlayStyle!;
      expect(style.statusBarColor, Colors.transparent);
      expect(
        style.statusBarIconBrightness,
        brightness == Brightness.dark ? Brightness.light : Brightness.dark,
      );
    }
    expect(
      appHeaderOverlayStyle(Brightness.dark).statusBarIconBrightness,
      Brightness.light,
    );
    expect(
      appHeaderOverlayStyle(Brightness.light),
      isA<SystemUiOverlayStyle>(),
    );
  });

  testWidgets('album toolbar reads its artwork, then the page when collapsed', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('header-verdict-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final cover = File('${directory.path}/cover.png');
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(const Color(0xff101018), BlendMode.src);
      final picture = recorder.endRecording();
      final image = await picture.toImage(64, 64);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      picture.dispose();
      await cover.writeAsBytes(bytes!.buffer.asUint8List());
      expect(await palette.topLightness(cover.path), lessThan(0.2));
    });
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          coverPaletteProvider.overrideWithValue(palette),
          appGlassLevelProvider.overrideWithValue(AppGlassLevel.liquid),
          appShaderFiltersSupportedProvider.overrideWithValue(true),
        ],
        child: MaterialApp(
          theme: AppTheme.build(Brightness.light),
          home: CollectionScaffold(
            scrollController: controller,
            isSelectionMode: false,
            onExitSelectionMode: () {},
            appBar: AlbumDetailHeader(
              title: 'Dark album',
              expandedHeight: 400,
              showTitleInAppBar: false,
              immersive: true,
              paletteSource: cover.path,
              background: const ColoredBox(color: Color(0xff101018)),
              coverBuilder: (_, _) => const SizedBox(),
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
    SliverAppBar bar() =>
        tester.widget<SliverAppBar>(find.byType(SliverAppBar));
    expect(bar().backgroundColor, Colors.transparent);
    expect(bar().systemOverlayStyle!.statusBarIconBrightness, Brightness.light);
    final back = tester.element(find.byTooltip('Back'));
    expect(Theme.of(back).brightness, Brightness.dark);
    expect(backing, findsNothing);

    controller.jumpTo(1200);
    await tester.pumpAndSettle();
    expect(bar().backgroundColor, Colors.transparent);
    expect(bar().systemOverlayStyle!.statusBarIconBrightness, Brightness.dark);
    expect(
      Theme.of(tester.element(find.byTooltip('Back'))).brightness,
      Brightness.light,
    );
    expect(backing, findsOneWidget);
    expect(find.text('Dark album'), findsWidgets);
  });

  test('artwork verdict uses the top band lightness', () {
    ByteData band(List<int> top, List<int> bottom) {
      final data = ByteData(4 * 4 * 4);
      for (var y = 0; y < 4; y++) {
        for (var x = 0; x < 4; x++) {
          final color = y == 0 ? top : bottom;
          final i = (y * 4 + x) * 4;
          data
            ..setUint8(i, color[0])
            ..setUint8(i + 1, color[1])
            ..setUint8(i + 2, color[2])
            ..setUint8(i + 3, 255);
        }
      }
      return data;
    }

    double top(ByteData data) =>
        analyzeCover(data.buffer.asUint8List(), 4, 4, const []).topLightness;
    final darkTop = top(band([0, 0, 0], [255, 255, 255]));
    final lightTop = top(band([255, 255, 255], [0, 0, 0]));
    expect(darkTop, closeTo(0, 0.001));
    expect(lightTop, closeTo(1, 0.001));
    expect(appArtworkBrightness(darkTop), Brightness.dark);
    expect(appArtworkBrightness(lightTop), Brightness.light);
    expect(appArtworkBrightness(null), isNull);
  });

  List<int?> blurIds(WidgetTester tester) => [
    for (final blur in tester.widgetList<AppBackdropBlur>(
      find.byType(AppBackdropBlur),
    ))
      blur.backdropId,
  ];

  int reads(WidgetTester tester) => appCountBackdropReads(
    // ignore: invalid_use_of_protected_member
    tester.binding.renderViews.first.layer,
  ).total;

  int? batchId(WidgetTester tester) => LiquidGlassBatch.backdropIdOf(
    tester.element(find.byType(CustomScrollView).last),
  );

  for (final groups in [false, true]) {
    testWidgets('circle and capsule share the chrome read; the band does not '
        '(batch: $groups)', (tester) async {
      final controller = await pumpHeader(
        tester,
        level: AppGlassLevel.lite,
        groups: groups,
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.add)),
          IconButton(onPressed: () {}, icon: const Icon(Icons.share)),
        ],
      );
      final batch = groups ? batchId(tester) : null;
      if (groups) expect(batch, isNotNull);
      expect(blurIds(tester), [batch, batch]);
      expect(reads(tester), groups ? 1 : 2);

      await scrollUnder(tester, controller);
      // The controls float over the band and must see it: it reads alone.
      expect(LiquidGlassBatch.backdropIdOf(tester.element(backing)), isNull);
      expect(blurIds(tester), [batch, batch]);
      expect(reads(tester), groups ? 2 : 3);
      // Faded by value: no opacity layer isolates the band from the page.
      final opacity = <int?>[];
      void visit(Layer layer) {
        if (layer is OpacityLayer) opacity.add(layer.alpha);
        if (layer is ContainerLayer) {
          for (var c = layer.firstChild; c != null; c = c.nextSibling) {
            visit(c);
          }
        }
      }

      // ignore: invalid_use_of_protected_member
      visit(tester.binding.renderViews.first.layer!);
      // The route transition keeps its opacity layers at full alpha, which
      // the engine applies without an offscreen layer.
      expect(opacity, everyElement(255));
    });
  }

  testWidgets('full glass lenses take the chrome key; page glass does not', (
    tester,
  ) async {
    await pumpHeader(tester, groups: true);
    final batch = batchId(tester);
    expect(batch, isNotNull);
    // The lens joins the batch it finds; on Impeller it pushes that key.
    final lens = find.byType(LiquidGlassLens);
    expect(lens, findsOneWidget);
    expect(LiquidGlassBatch.backdropIdOf(tester.element(lens)), batch);

    // Glass in page content, or in a sheet on the page's navigator, stays out.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator).last);
    showModalBottomSheet<void>(
      context: navigator.context,
      builder: (_) => const SizedBox(
        height: 200,
        child: AppGlassPanel(child: SizedBox.expand()),
      ),
    );
    await tester.pumpAndSettle();
    final panel = find.descendant(
      of: find.byType(AppGlassPanel),
      matching: find.byType(LiquidGlassLens),
    );
    expect(panel, findsOneWidget);
    expect(LiquidGlassBatch.backdropIdOf(tester.element(panel)), isNull);
    // The covered page's header reads on its own too.
    expect(
      LiquidGlassBatch.backdropIdOf(
        tester.element(
          find.descendant(
            of: find.byType(SliverAppBar),
            matching: find.byType(LiquidGlassLens),
          ),
        ),
      ),
      isNull,
    );
  });

  testWidgets('moving or covered pages read on their own', (tester) async {
    await pumpHeader(tester, level: AppGlassLevel.lite, groups: true);
    final settled = blurIds(tester).single;
    expect(settled, isNotNull);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator).last);
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(
          body: CustomScrollView(
            slivers: [AppSliverHeader.page(title: 'Album')],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Both pages paint mid-transition; neither may filter the other's copy.
    final moving = blurIds(tester);
    expect(moving, hasLength(2));
    expect(moving, everyElement(isNull));
    expect(reads(tester), 2);

    await tester.pumpAndSettle();
    expect(blurIds(tester), [settled]);

    navigator.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(blurIds(tester), everyElement(isNull));
    await tester.pumpAndSettle();
    expect(blurIds(tester), [settled]);
  });

  testWidgets('the band blur A/B switch keeps only the tint', (tester) async {
    final controller = await pumpHeader(
      tester,
      level: AppGlassLevel.lite,
      bandBlurOff: true,
    );
    await scrollUnder(tester, controller);
    final edge = tester.widget<LiquidGlassScrollEdge>(backing);
    expect(edge.blur, 0);
    expect(edge.color.a, closeTo(0.72, 0.001));
    expect(reads(tester), 1);
  });
}
