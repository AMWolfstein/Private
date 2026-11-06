import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_hybrid_config.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_hybrid_surface.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_lens_glass.dart';

void main() {
  group('first-party lens shader', () {
    test('the shader source is in the repository and declared as an asset', () {
      final source = File(kSistrumLensShaderAsset);
      expect(source.existsSync(), isTrue);
      final text = source.readAsStringSync();
      for (final uniform in [
        'uniform vec2 uSize;',
        'uniform float uRadius;',
        'uniform float uBand;',
        'uniform float uRefraction;',
        'uniform float uDispersion;',
        'uniform sampler2D uBackdrop;',
      ]) {
        expect(text, contains(uniform));
      }
      expect(
        File('pubspec.yaml').readAsStringSync(),
        contains('- $kSistrumLensShaderAsset'),
      );
    });

    test(
      'uniform packing is in physical pixels and matches the shader order',
      () {
        final values = sistrumLensUniforms(
          size: const Size(200, 80),
          borderRadius: 40,
          devicePixelRatio: 2.5,
          refraction: 1,
          chromatic: true,
        );
        expect(values, [500, 200, 100, 40, 1, 1]);
      },
    );

    test('the rim band is capped at half the shorter side', () {
      final values = sistrumLensUniforms(
        size: const Size(200, 20),
        borderRadius: 10,
        devicePixelRatio: 1,
        refraction: 1,
        chromatic: false,
      );
      // 16 px band, but the shorter side is 20 px, so the cap is 10 px.
      expect(values[3], 10);
      expect(values[5], 0);
    });

    test('pill radius reaches the shader unchanged in physical pixels', () {
      // A height/2 radius on a 120x48 pill, at 3x: the shader clamps it.
      final values = sistrumLensUniforms(
        size: const Size(120, 48),
        borderRadius: 24,
        devicePixelRatio: 3,
        refraction: 1,
        chromatic: false,
      );
      expect(values[2], 72);
    });

    test('the Hybrid path imports no third-party glass package', () {
      const files = [
        'lib/widgets/glass_poc/sistrum_hybrid_surface.dart',
        'lib/widgets/glass_poc/sistrum_lens_glass.dart',
        'lib/widgets/glass_poc/sistrum_hybrid_config.dart',
        'lib/widgets/glass_poc/sistrum_hybrid_controls.dart',
      ];
      for (final path in files) {
        final text = File(path).readAsStringSync();
        expect(
          text.contains('liquid_glass'),
          isFalse,
          reason: '$path must not import a Liquid Glass package',
        );
      }
    });

    testWidgets('Full tier renders a backdrop filter and no package layer', (
      tester,
    ) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 200,
              height: 80,
              child: SistrumHybridSurface(
                config: SistrumHybridConfig(tier: SistrumHybridTier.full),
                dark: true,
                borderRadius: 20,
                child: Text('lens'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      // Shader filters are unsupported under the test engine, so the tier must
      // fall back to the blur without throwing.
      expect(tester.takeException(), isNull);
      expect(find.byType(SistrumLensGlass), findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(find.text('lens'), findsOneWidget);
    });

    testWidgets('refraction off keeps the Full tier on the blur path', (
      tester,
    ) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 200,
            height: 80,
            child: SistrumHybridSurface(
              config: SistrumHybridConfig(
                tier: SistrumHybridTier.full,
                refraction: false,
              ),
              dark: false,
              borderRadius: 20,
              child: SizedBox.shrink(),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(BackdropFilter), findsOneWidget);
    });
  });
}
