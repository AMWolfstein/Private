import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/services/library/covers/cover_palette.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/widgets/header/album_detail_header.dart';
import 'package:sistrum/widgets/primitives/app_sliver_header.dart';
import 'package:sistrum/widgets/collection/collection_scaffold.dart';
import 'package:sistrum/widgets/glass/chrome/app_floating_header.dart';
import 'package:sistrum/providers/library/cover_palette_provider.dart';

void main() {
  final palette = CoverPaletteCache();
  final backing = find.byKey(const ValueKey('sistrum-header-backing'));

  Future<ScrollController> pumpHeader(
    WidgetTester tester, {
    AppGlassLevel level = AppGlassLevel.tinted,
    bool reduceMotion = false,
    bool highContrast = false,
    Brightness brightness = Brightness.light,
    TextDirection direction = TextDirection.ltr,
    List<Widget>? actions,
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
                child: Navigator(
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

  testWidgets('tinted level floats a glass header with a scrolled backing', (
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
    // The back circle and one capsule for both actions, each blurred.
    expect(find.byType(BackdropFilter), findsNWidgets(2));
    expect(backing, findsNothing);

    await scrollUnder(tester, controller);
    expect(backing, findsOneWidget);
    // The band blurs with the glass style's sigma.
    expect(
      find.descendant(of: backing, matching: find.byType(BackdropFilter)),
      findsOneWidget,
    );

    controller.jumpTo(0);
    await tester.pumpAndSettle();
    expect(backing, findsNothing);
  });

  testWidgets('flat level and high contrast keep the opaque header', (
    tester,
  ) async {
    for (final (level, highContrast) in [
      (AppGlassLevel.flat, false),
      (AppGlassLevel.tinted, true),
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
      expect(find.byType(BackdropFilter), findsNothing);
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
          appGlassLevelProvider.overrideWithValue(AppGlassLevel.tinted),
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

  testWidgets('the band blur A/B switch keeps only the tint', (tester) async {
    final controller = await pumpHeader(tester, bandBlurOff: true);
    await scrollUnder(tester, controller);
    expect(backing, findsOneWidget);
    expect(
      find.descendant(of: backing, matching: find.byType(BackdropFilter)),
      findsNothing,
    );
  });
}
