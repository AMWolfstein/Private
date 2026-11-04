import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g1455/g1455.dart' show GlassHost, GlassSurface;
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/widgets/glass/chrome/app_floating_header.dart';
import 'package:sistrum/widgets/glass/debug/app_artist_glass_isolation.dart';
import 'package:sistrum/widgets/glass/thumb/app_glass_surface.dart';

const _glassKey = ValueKey('isolated-glass');

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required Widget Function() child,
  bool inArtistScope = true,
}) async {
  final container = ProviderContainer(
    overrides: [appGlassLevelProvider.overrideWithValue(AppGlassLevel.tinted)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.build(Brightness.dark),
        home: GlassHost(
          child: Scaffold(
            body: Center(
              child: inArtistScope
                  ? AppArtistGlassIsolationHost(
                      videoPlaying: true,
                      child: child(),
                    )
                  : child(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Widget _liquid() => AppGlass(
  key: _glassKey,
  blurEnabled: true,
  mode: AppGlassMode.liquid,
  child: const SizedBox(width: 120, height: 80),
);

void main() {
  testWidgets('the artist diagnostic draws Liquid glass as Tint only', (
    tester,
  ) async {
    await _pump(tester, child: _liquid);
    // Normal: refracted, no blur.
    expect(find.byType(GlassSurface), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
    final normalSize = tester.getSize(find.byKey(_glassKey));

    final container = ProviderScope.containerOf(
      tester.element(find.byKey(_glassKey)),
    );
    container.read(appArtistGlassIsolationProvider.notifier).toggle();
    await tester.pumpAndSettle();

    // Disabled: no capture, no blur, and the same size.
    expect(find.byType(GlassSurface), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(tester.getSize(find.byKey(_glassKey)), normalSize);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the frosted header band on the artist screen draws no blur', (
    tester,
  ) async {
    final band = AppHeaderBacking(visible: true);
    final container = await _pump(tester, child: () => band);
    expect(find.byType(BackdropFilter), findsOneWidget);

    container.read(appArtistGlassIsolationProvider.notifier).toggle();
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the diagnostic never reaches glass outside the artist screen', (
    tester,
  ) async {
    final container = await _pump(tester, child: _liquid, inArtistScope: false);
    container.read(appArtistGlassIsolationProvider.notifier).toggle();
    await tester.pumpAndSettle();

    // No Artist scope: the Liquid surface is still refracted.
    expect(find.byType(GlassSurface), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('toggling switches without a restart and back again', (
    tester,
  ) async {
    final container = await _pump(tester, child: _liquid);
    final notifier = container.read(appArtistGlassIsolationProvider.notifier);

    for (var round = 0; round < 2; round++) {
      notifier.toggle();
      await tester.pumpAndSettle();
      expect(find.byType(GlassSurface), findsNothing);
      notifier.toggle();
      await tester.pumpAndSettle();
      expect(find.byType(GlassSurface), findsOneWidget);
    }
    expect(
      container.read(appArtistGlassIsolationProvider),
      AppArtistGlassIsolation.normal,
    );
    expect(tester.takeException(), isNull);
  });
}
