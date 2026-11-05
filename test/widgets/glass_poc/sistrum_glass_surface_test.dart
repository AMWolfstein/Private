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

    testWidgets('only the glass modes create a shared LiquidGlassLayer', (
      tester,
    ) async {
      for (final mode in SistrumGlassMode.values) {
        await tester.pumpWidget(_harness(mode, onTap: () {}));
        expect(
          find.byType(LiquidGlassLayer),
          mode.usesLiquidGlass ? findsOneWidget : findsNothing,
          reason: mode.label,
        );
      }
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
        _harness(SistrumGlassMode.referenceGlass, onTap: () {}),
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

    test('reference glass uses the Apple Podcasts demo values', () {
      final dark = sistrumGlassLayerSettings(
        SistrumGlassMode.referenceGlass,
        dark: true,
      )!;
      expect(dark.glassColor, const Color(0xAA1C1C1E));
      expect(dark.thickness, 24);
      expect(dark.blur, 3);
      expect(dark.chromaticAberration, .01);
      expect(dark.lightIntensity, .2);
      expect(dark.ambientStrength, 0);
      expect(dark.refractiveIndex, 1.2);
      expect(dark.fresnelStrength, 0.0);
      expect(dark.saturation, 1.2);
      expect(dark.specularSharpness, GlassSpecularSharpness.medium);

      final light = sistrumGlassLayerSettings(
        SistrumGlassMode.referenceGlass,
        dark: false,
      )!;
      expect(light.glassColor, const Color(0xAAF2F2F7));
    });

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
