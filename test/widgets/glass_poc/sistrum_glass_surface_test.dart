import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_mode.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_surface.dart';

Widget _harness(SistrumGlassMode mode, {required VoidCallback onTap}) {
  return MaterialApp(
    home: Scaffold(
      body: SistrumGlassScope(
        mode: mode,
        child: Center(
          child: SistrumGlassSurface(
            key: const ValueKey('surface'),
            mode: mode,
            width: 120,
            height: 48,
            borderRadius: 24,
            child: GestureDetector(
              onTap: onTap,
              child: const Center(child: Text('Child')),
            ),
          ),
        ),
      ),
    ),
  );
}

Finder _outlineFinder() => find.byWidgetPredicate(
  (w) =>
      w is DecoratedBox &&
      w.position == DecorationPosition.foreground &&
      w.decoration is BoxDecoration &&
      (w.decoration as BoxDecoration).border != null,
);

void main() {
  group('SistrumGlassSurface', () {
    for (final mode in SistrumGlassMode.values) {
      testWidgets('${mode.label}: keeps geometry, child and hit testing', (
        tester,
      ) async {
        var taps = 0;
        await tester.pumpWidget(_harness(mode, onTap: () => taps++));

        expect(find.text('Child'), findsOneWidget);
        expect(
          tester.getSize(find.byKey(const ValueKey('surface'))),
          const Size(120, 48),
        );

        await tester.tap(find.text('Child'));
        expect(taps, 1);
      });
    }

    testWidgets('only liquid glass wraps its region in a shared layer', (
      tester,
    ) async {
      for (final mode in SistrumGlassMode.values) {
        await tester.pumpWidget(_harness(mode, onTap: () {}));
        expect(
          find.descendant(
            of: find.byType(SistrumGlassScope),
            matching: find.byType(LiquidGlassLayer),
          ),
          mode == SistrumGlassMode.liquidGlass ? findsOneWidget : findsNothing,
          reason: mode.label,
        );
      }
    });

    testWidgets('reference glass requests premium quality on its own layer', (
      tester,
    ) async {
      // flutter_test has no shader support, so the package takes its fallback
      // path here. This asserts the requested configuration, not the GPU path.
      await tester.pumpWidget(
        _harness(SistrumGlassMode.referenceGlass, onTap: () {}),
      );
      final container = tester.widget<GlassContainer>(
        find.descendant(
          of: find.byKey(const ValueKey('surface')),
          matching: find.byType(GlassContainer),
        ),
      );
      expect(container.quality, GlassQuality.premium);
      expect(container.useOwnLayer, isTrue);
      expect(container.settings, sistrumReferenceGlassSettings(dark: false));
    });

    testWidgets('the diagnostic outline is off by default and independent', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(SistrumGlassMode.referenceGlass, onTap: () {}),
      );
      expect(_outlineFinder(), findsNothing);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SistrumGlassSurface(
              mode: SistrumGlassMode.transparentBaseline,
              width: 120,
              height: 48,
              borderRadius: 24,
              diagnosticOutline: true,
              child: const Text('Child'),
            ),
          ),
        ),
      );
      expect(_outlineFinder(), findsOneWidget);
      expect(find.text('Child'), findsOneWidget);
    });

    testWidgets('only the basic blur mode samples the backdrop', (
      tester,
    ) async {
      for (final mode in SistrumGlassMode.values) {
        await tester.pumpWidget(_harness(mode, onTap: () {}));
        expect(
          find.byType(BackdropFilter),
          mode == SistrumGlassMode.basicBlur ? findsOneWidget : findsNothing,
          reason: mode.label,
        );
      }
    });

    testWidgets('switching modes removes the previous layer', (tester) async {
      await tester.pumpWidget(
        _harness(SistrumGlassMode.liquidGlass, onTap: () {}),
      );
      expect(find.byType(LiquidGlassLayer), findsOneWidget);

      await tester.pumpWidget(
        _harness(SistrumGlassMode.transparentBaseline, onTap: () {}),
      );
      expect(find.byType(LiquidGlassLayer), findsNothing);
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('the blur mode uses the single Flutter blur filter', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(SistrumGlassMode.basicBlur, onTap: () {}),
      );
      final filter = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
      expect(filter.filter, isA<ImageFilter>());
    });
  });

  group('layer settings', () {
    test('baseline and basic blur never configure the package layer', () {
      for (final dark in [true, false]) {
        expect(
          sistrumGlassLayerSettings(
            SistrumGlassMode.transparentBaseline,
            dark: dark,
          ),
          isNull,
        );
        expect(
          sistrumGlassLayerSettings(SistrumGlassMode.basicBlur, dark: dark),
          isNull,
        );
      }
    });

    test(
      'reference glass has no shared layer and uses the demo mini player',
      () {
        expect(
          sistrumGlassLayerSettings(
            SistrumGlassMode.referenceGlass,
            dark: true,
          ),
          isNull,
        );
        final dark = sistrumReferenceGlassSettings(dark: true);
        expect(dark.glassColor, const Color(0xCC1C1C1E));
        expect(dark.thickness, 30);
        expect(dark.blur, 2);
        expect(dark.lightIntensity, .18);
        expect(dark.chromaticAberration, .01);
        expect(dark.saturation, 1.2);
        expect(dark.fresnelStrength, 0.0);

        final light = sistrumReferenceGlassSettings(dark: false);
        expect(light.glassColor, const Color(0xCCF2F2F7));
      },
    );

    test('liquid glass uses the package defaults', () {
      final settings = sistrumGlassLayerSettings(
        SistrumGlassMode.liquidGlass,
        dark: true,
      );
      expect(settings, isNotNull);
      expect(settings!.thickness, const LiquidGlassSettings().thickness);
      expect(settings.blur, const LiquidGlassSettings().blur);
    });
  });
}
