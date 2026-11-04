import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/rendering.dart' show Layer;
import 'package:flutter_test/flutter_test.dart';
import 'package:g1455/g1455.dart' show GlassHost, GlassSurface;
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/widgets/glass/chrome/app_floating_header.dart'
    show AppHeaderBacking, AppHeaderControls;
import 'package:sistrum/widgets/glass/debug/app_backdrop_reads.dart';
import 'package:sistrum/widgets/glass/thumb/app_glass_look.dart';
import 'package:sistrum/widgets/glass/thumb/app_glass_surface.dart';

final _sharedKey = BackdropKey();

Widget _control() => const AppGlass(
  blurEnabled: true,
  mode: AppGlassMode.liquid,
  child: SizedBox(width: 48, height: 48),
);

/// A toolbar's leading and trailing controls, each in [AppHeaderControls].
Future<void> _pumpHeader(WidgetTester tester, {required bool liveVideo}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appGlassLevelProvider.overrideWithValue(AppGlassLevel.tinted),
      ],
      child: MaterialApp(
        theme: AppTheme.build(Brightness.dark),
        home: AppLiveVideoBackdrop(
          live: liveVideo,
          backdropKey: _sharedKey,
          child: Scaffold(
            body: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                AppHeaderControls(child: _control()),
                AppHeaderControls(
                  child: Row(children: [_control(), _control()]),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pump(WidgetTester tester, {required bool liveVideo}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appGlassLevelProvider.overrideWithValue(AppGlassLevel.tinted),
      ],
      child: MaterialApp(
        theme: AppTheme.build(Brightness.dark),
        home: GlassHost(
          child: AppLiveVideoBackdrop(
            live: liveVideo,
            child: const Scaffold(
              body: Center(
                child: AppGlass(
                  blurEnabled: true,
                  mode: AppGlassMode.liquid,
                  child: SizedBox(width: 120, height: 80),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('LIQUID over a live video reads the live backdrop (FROSTED)', (
    tester,
  ) async {
    await _pump(tester, liveVideo: true);
    expect(find.byType(GlassSurface), findsNothing);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('LIQUID without a live video keeps its refraction', (
    tester,
  ) async {
    await _pump(tester, liveVideo: false);
    expect(find.byType(GlassSurface), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('header controls over a live video share one backdrop copy', (
    tester,
  ) async {
    await _pumpHeader(tester, liveVideo: true);
    final filters = tester
        .widgetList<BackdropFilter>(find.byType(BackdropFilter))
        .toList();
    expect(filters, hasLength(3));
    for (final filter in filters) {
      expect(
        filter.backdropGroupKey ??
            BackdropGroup.of(
              tester.element(find.byWidget(filter)),
            )?.backdropKey,
        same(_sharedKey),
      );
    }
    // ignore: invalid_use_of_protected_member
    final layer = tester.binding.renderViews.first.layer;
    final counted = appCountBackdrops(layer);
    expect(counted.reads, 3);
    expect(counted.copies, 1);
  });

  testWidgets('glass over a live video outside the toolbar joins the read', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appGlassLevelProvider.overrideWithValue(AppGlassLevel.tinted),
        ],
        child: MaterialApp(
          theme: AppTheme.build(Brightness.dark),
          home: AppLiveVideoBackdrop(
            live: true,
            backdropKey: _sharedKey,
            child: Scaffold(
              body: Column(
                children: [
                  // The toolbar's controls.
                  AppHeaderControls(
                    child: Row(children: [_control(), _control()]),
                  ),
                  // The header's Favorite and Shuffle circles, in the page.
                  Row(children: [_control(), _control()]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // ignore: invalid_use_of_protected_member
    final layer = tester.binding.renderViews.first.layer;
    // Four live reads over the video, one copy of the page.
    expect(appCountBackdrops(layer), (reads: 4, copies: 1));
  });

  testWidgets('without a live video the header controls stay LIQUID', (
    tester,
  ) async {
    await _pumpHeader(tester, liveVideo: false);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(BackdropGroup), findsNothing);
  });

  group('header band over a live video', () {
    Future<ValueNotifier<bool>> pumpBand(
      WidgetTester tester, {
      required bool bandShown,
      ValueNotifier<bool>? covers,
      bool settle = true,
    }) async {
      final notifier = covers ?? ValueNotifier<bool>(false);
      if (covers == null) addTearDown(notifier.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appGlassLevelProvider.overrideWithValue(AppGlassLevel.tinted),
          ],
          child: MaterialApp(
            theme: AppTheme.build(Brightness.dark),
            home: AppLiveVideoBackdrop(
              live: true,
              backdropKey: _sharedKey,
              child: AppLiveVideoBand(
                covers: notifier,
                child: Scaffold(
                  body: SizedBox(
                    height: 100,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: AppHeaderBacking(visible: bandShown),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            AppHeaderControls(child: _control()),
                            AppHeaderControls(
                              child: Row(children: [_control(), _control()]),
                            ),
                          ],
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
      if (settle) await tester.pumpAndSettle();
      return notifier;
    }

    testWidgets('a fully shown band holds the controls: one copy in all', (
      tester,
    ) async {
      final covers = await pumpBand(tester, bandShown: true);
      expect(covers.value, isTrue);
      // ignore: invalid_use_of_protected_member
      final layer = tester.binding.renderViews.first.layer;
      // Only the band reads the video; the controls draw their fill on it.
      expect(appCountBackdrops(layer), (reads: 1, copies: 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a hidden band leaves the controls their shared read', (
      tester,
    ) async {
      final covers = await pumpBand(tester, bandShown: false);
      expect(covers.value, isFalse);
      // ignore: invalid_use_of_protected_member
      final layer = tester.binding.renderViews.first.layer;
      expect(appCountBackdrops(layer), (reads: 3, copies: 1));
    });

    testWidgets('the controls read again once the band is gone', (
      tester,
    ) async {
      final covers = await pumpBand(tester, bandShown: true);
      expect(covers.value, isTrue);
      await pumpBand(tester, bandShown: false, covers: covers);
      expect(covers.value, isFalse);
      expect(find.byType(BackdropFilter), findsNWidgets(3));
    });

    testWidgets('a fading band copies the page once, not twice', (
      tester,
    ) async {
      final covers = await pumpBand(tester, bandShown: false);
      // ignore: invalid_use_of_protected_member
      Layer? layer() => tester.binding.renderViews.first.layer;
      Future<void> expectOneCopyWhileFading() async {
        // The band's first visible frame; the controls hear about it after
        // that frame, so they overlap it for that one frame only.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        for (var ms = 32; ms < 170; ms += 16) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(appCountBackdrops(layer()).copies, 1, reason: 'at $ms ms');
        }
      }

      // Fading in: the band and the controls never read together.
      await pumpBand(tester, bandShown: true, covers: covers, settle: false);
      await expectOneCopyWhileFading();
      expect(covers.value, isTrue);
      await tester.pumpAndSettle();

      // Fading out: the controls wait for the band to be gone.
      await pumpBand(tester, bandShown: false, covers: covers, settle: false);
      await expectOneCopyWhileFading();
      expect(covers.value, isTrue);
      await tester.pumpAndSettle();
      expect(covers.value, isFalse);
      expect(find.byType(BackdropFilter), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('over a live video the read keeps the plain sigma 6 blur', (
    tester,
  ) async {
    await _pump(tester, liveVideo: true);
    // BitChord is the default look; its saturation pass and lighter blur
    // stay off the per-frame read over a video.
    expect(
      tester.widget<BackdropFilter>(find.byType(BackdropFilter)).filter,
      same(appFrostFilter(AppGlassLook.sistrum)),
    );
  });
}
