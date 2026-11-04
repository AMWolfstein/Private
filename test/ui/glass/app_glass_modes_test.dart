import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g1455/g1455.dart' show GlassHost, GlassSurface;
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/widgets/glass/artwork/app_artwork_page_ground.dart';
import 'package:sistrum/widgets/glass/chrome/app_floating_header.dart';
import 'package:sistrum/widgets/glass/thumb/app_glass_surface.dart';

const _child = ValueKey('glass-child');

Future<void> _pump(
  WidgetTester tester, {
  AppGlassMode mode = AppGlassMode.auto,
  AppGlassLevel level = AppGlassLevel.tinted,
  bool host = true,
  bool onGround = false,
  Brightness brightness = Brightness.dark,
}) async {
  Widget surface = AppGlass(
    blurEnabled: true,
    mode: mode,
    child: const SizedBox(key: _child, width: 120, height: 80),
  );
  if (host) surface = GlassHost(child: surface);
  Widget body = Center(child: surface);
  if (onGround) {
    // The header layout: the ground anchor is a sibling and the glass sits
    // over its rect, as the band does in the app.
    body = AppPageGround(
      source: null,
      surface: Colors.black,
      sigma: 6,
      enabled: true,
      cover: null,
      child: Stack(
        children: [
          const AppGroundAnchor(
            layout: AppGroundLayout(),
            child: SizedBox(height: 300),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 80,
            // The header controls re-provide the page ground, as in the app.
            child: AppHeaderControls(child: surface),
          ),
        ],
      ),
    );
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appGlassLevelProvider.overrideWithValue(level)],
      child: MaterialApp(
        theme: AppTheme.build(brightness),
        home: Scaffold(body: body),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectOnly(WidgetTester tester, {int blur = 0, int liquid = 0}) {
  expect(find.byType(BackdropFilter), findsNWidgets(blur));
  expect(find.byType(GlassSurface), findsNWidgets(liquid));
  expect(find.byKey(_child), findsOneWidget);
}

void main() {
  testWidgets('AUTO without a ground is FROSTED, never LIQUID', (tester) async {
    await _pump(tester);
    _expectOnly(tester, blur: 1);
  });

  testWidgets('explicit FROSTED is a clipped blur', (tester) async {
    await _pump(tester, mode: AppGlassMode.frosted);
    _expectOnly(tester, blur: 1);
  });

  testWidgets('explicit LIQUID refracts through GlassSurface, no blur', (
    tester,
  ) async {
    await _pump(tester, mode: AppGlassMode.liquid);
    _expectOnly(tester, liquid: 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('explicit TINT never samples, in either sampling mode', (
    tester,
  ) async {
    await _pump(tester, mode: AppGlassMode.tint);
    _expectOnly(tester);
  });

  testWidgets('a flat level samples nothing, whatever the mode', (
    tester,
  ) async {
    for (final mode in [
      AppGlassMode.auto,
      AppGlassMode.frosted,
      AppGlassMode.liquid,
    ]) {
      await _pump(tester, mode: mode, level: AppGlassLevel.flat);
      _expectOnly(tester);
    }
  });

  testWidgets('LIQUID without a host falls back to its fill, without error', (
    tester,
  ) async {
    await _pump(tester, mode: AppGlassMode.liquid, host: false);
    _expectOnly(tester, liquid: 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('GROUND over a known artwork ground reads no backdrop', (
    tester,
  ) async {
    await _pump(tester, mode: AppGlassMode.ground, onGround: true);
    _expectOnly(tester);
  });

  testWidgets('GROUND with no artwork ground falls back to FROSTED', (
    tester,
  ) async {
    await _pump(tester, mode: AppGlassMode.ground);
    _expectOnly(tester, blur: 1);
  });

  testWidgets('AUTO over an artwork ground uses the ground, not a blur', (
    tester,
  ) async {
    await _pump(tester, onGround: true);
    _expectOnly(tester);
  });

  testWidgets('LIQUID over an artwork ground keeps the ground', (tester) async {
    await _pump(tester, mode: AppGlassMode.liquid, onGround: true);
    _expectOnly(tester);
  });

  testWidgets('FROSTED stays a blur over an artwork ground when asked', (
    tester,
  ) async {
    await _pump(tester, mode: AppGlassMode.frosted, onGround: true);
    _expectOnly(tester, blur: 1);
  });

  testWidgets('light and dark themes both refract under LIQUID', (
    tester,
  ) async {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      await _pump(tester, mode: AppGlassMode.liquid, brightness: brightness);
      _expectOnly(tester, liquid: 1);
    }
  });

  testWidgets('removing a LIQUID surface disposes its glass cleanly', (
    tester,
  ) async {
    await _pump(tester, mode: AppGlassMode.liquid);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(find.byType(GlassSurface), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
