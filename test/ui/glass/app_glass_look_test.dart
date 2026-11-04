import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show Layer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g1455/g1455.dart' show GlassHost, GlassOptics, GlassSurface;
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/widgets/glass/debug/app_backdrop_reads.dart';
import 'package:sistrum/widgets/glass/thumb/app_glass_look.dart';
import 'package:sistrum/widgets/glass/thumb/app_glass_surface.dart';

Future<ProviderContainer> _pump(WidgetTester tester) async {
  final container = ProviderContainer(
    overrides: [appGlassLevelProvider.overrideWithValue(AppGlassLevel.tinted)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.build(Brightness.dark),
        home: const GlassHost(
          child: Scaffold(
            body: Column(
              children: [
                AppGlass(
                  blurEnabled: true,
                  mode: AppGlassMode.liquid,
                  child: SizedBox(width: 120, height: 48),
                ),
                AppGlass(
                  blurEnabled: true,
                  mode: AppGlassMode.frosted,
                  child: SizedBox(width: 120, height: 48),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  test('Sistrum is the default look and the HUD toggles it', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(appGlassLookProvider), AppGlassLook.sistrum);
    container.read(appGlassLookProvider.notifier).toggle();
    expect(container.read(appGlassLookProvider), AppGlassLook.bitchord);
    container.read(appGlassLookProvider.notifier).toggle();
    expect(container.read(appGlassLookProvider), AppGlassLook.sistrum);
  });

  test('both looks keep the blur at sigma 6 and differ in the lens only', () {
    final sistrum = appLiquidGlassFinish(AppGlassLook.sistrum);
    final bitchord = appLiquidGlassFinish(AppGlassLook.bitchord);
    expect(sistrum, same(kAppLiquidGlassFinish));
    expect(sistrum.blurSigmaLogical, 6);
    expect(bitchord.blurSigmaLogical, 6);
    expect(sistrum.optics, const GlassOptics());
    expect(bitchord.optics.thickness, greaterThan(sistrum.optics.thickness));
    // One filter object per look, so grouped reads can share one blur.
    expect(
      appFrostFilter(AppGlassLook.bitchord),
      same(appFrostFilter(AppGlassLook.bitchord)),
    );
  });

  testWidgets('switching the look changes parameters, not the surfaces', (
    tester,
  ) async {
    final container = await _pump(tester);
    // ignore: invalid_use_of_protected_member
    Layer? layer() => tester.binding.renderViews.first.layer;
    final before = appCountBackdrops(layer());
    expect(
      tester.widget<GlassSurface>(find.byType(GlassSurface)).finish!.optics,
      const GlassOptics(),
    );

    container.read(appGlassLookProvider.notifier).toggle();
    await tester.pumpAndSettle();

    expect(find.byType(GlassSurface), findsOneWidget);
    expect(
      tester.widget<GlassSurface>(find.byType(GlassSurface)).finish!.optics,
      appLiquidGlassFinish(AppGlassLook.bitchord).optics,
    );
    expect(
      tester.widget<BackdropFilter>(find.byType(BackdropFilter)).filter,
      same(appFrostFilter(AppGlassLook.bitchord)),
    );
    // No extra surface, read or copy for the second identity.
    expect(appCountBackdrops(layer()), before);
    expect(tester.takeException(), isNull);
  });

  test('the contact edge is dark for Sistrum and a light hairline for '
      'BitChord', () {
    expect(
      appGlassContactEdge(AppGlassLook.sistrum, dark: true),
      const Color.fromRGBO(0, 0, 0, 0.5),
    );
    expect(
      appGlassContactEdge(AppGlassLook.bitchord, dark: false),
      const Color.fromRGBO(255, 255, 255, 0.10),
    );
  });
}
