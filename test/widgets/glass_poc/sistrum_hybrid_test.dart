import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/widgets/glass_poc/glass_benchmark_runner.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_mode.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_surface.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_hybrid_config.dart';

Widget _host({
  required SistrumGlassMode mode,
  required SistrumHybridConfig config,
  Brightness brightness = Brightness.light,
}) => MaterialApp(
  theme: ThemeData(brightness: brightness),
  home: Scaffold(
    body: Center(
      child: SistrumHybridConfigScope(
        config: config,
        child: SistrumGlassSurface(
          mode: mode,
          width: 200,
          height: 60,
          borderRadius: 30,
          child: const Text('Now playing'),
        ),
      ),
    ),
  ),
);

void main() {
  group('configuration', () {
    test('defaults are the BitChord reference values', () {
      const c = SistrumHybridConfig();
      expect(c.tier, SistrumHybridTier.frosted);
      expect(c.blurSigma, kSistrumHybridDefaultBlurSigma);
      expect(c.tintOpacity, kSistrumHybridDefaultTintOpacity);
      expect(kSistrumHybridReferenceSaturation, 1.5);
      expect(kSistrumHybridReferenceSamplingScale, 0.33);
    });

    test('blur and tint are clamped to their ranges', () {
      const c = SistrumHybridConfig();
      expect(c.copyWith(blurSigma: 99).blurSigma, 24);
      expect(c.copyWith(blurSigma: -3).blurSigma, 0);
      expect(c.copyWith(tintOpacity: 2).tintOpacity, 1);
      expect(c.copyWith(tintOpacity: -1).tintOpacity, 0);
    });

    test('equal configurations compare equal', () {
      expect(
        const SistrumHybridConfig(blurSigma: 8),
        const SistrumHybridConfig(blurSigma: 8),
      );
      expect(
        const SistrumHybridConfig(blurSigma: 8) ==
            const SistrumHybridConfig(blurSigma: 9),
        isFalse,
      );
    });
  });

  group('capabilities', () {
    test(
      'blur belongs to Frosted, refraction to Full, nothing to Lightweight',
      () {
        expect(
          SistrumHybridCapabilities.of(SistrumHybridTier.lightweight).blur,
          isFalse,
        );
        expect(
          SistrumHybridCapabilities.of(SistrumHybridTier.frosted).blur,
          isTrue,
        );
        expect(
          SistrumHybridCapabilities.of(SistrumHybridTier.full).blur,
          isFalse,
        );
        expect(
          SistrumHybridCapabilities.of(SistrumHybridTier.full).refraction,
          isTrue,
        );
        expect(
          SistrumHybridCapabilities.of(SistrumHybridTier.frosted).refraction,
          isFalse,
        );
      },
    );

    test(
      'saturation, sampling scale and shared backdrop are unsupported on every tier',
      () {
        for (final tier in SistrumHybridTier.values) {
          final caps = SistrumHybridCapabilities.of(tier);
          expect(caps.saturation, isFalse, reason: tier.name);
          expect(caps.samplingScale, isFalse, reason: tier.name);
          expect(caps.sharedBackdrop, isFalse, reason: tier.name);
        }
      },
    );

    test('genuine refraction needs the Full tier with refraction on', () {
      expect(
        const SistrumHybridConfig(
          tier: SistrumHybridTier.full,
        ).isGenuineRefraction,
        isTrue,
      );
      expect(
        const SistrumHybridConfig(
          tier: SistrumHybridTier.full,
          refraction: false,
        ).isGenuineRefraction,
        isFalse,
      );
      // A blur is never a refraction.
      expect(
        const SistrumHybridConfig(
          tier: SistrumHybridTier.frosted,
        ).isGenuineRefraction,
        isFalse,
      );
    });
  });

  group('tiers in the scene', () {
    testWidgets('Lightweight reads no backdrop', (tester) async {
      await tester.pumpWidget(
        _host(
          mode: SistrumGlassMode.sistrumHybrid,
          config: const SistrumHybridConfig(
            tier: SistrumHybridTier.lightweight,
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.text('Now playing'), findsOneWidget);
    });

    testWidgets('Frosted samples the backdrop with the configured sigma', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          mode: SistrumGlassMode.sistrumHybrid,
          config: const SistrumHybridConfig(
            tier: SistrumHybridTier.frosted,
            blurSigma: 12,
          ),
        ),
      );
      final filter = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
      expect(filter, isNotNull);
      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    testWidgets('foreground text is drawn above the blur, not inside it', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          mode: SistrumGlassMode.sistrumHybrid,
          config: const SistrumHybridConfig(tier: SistrumHybridTier.frosted),
        ),
      );
      // The text is a child of the filter's child, so it is painted after the
      // blur and stays sharp.
      expect(
        find.descendant(
          of: find.byType(BackdropFilter),
          matching: find.text('Now playing'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the dark theme uses the dark tint at the configured opacity', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          mode: SistrumGlassMode.sistrumHybrid,
          config: const SistrumHybridConfig(
            tier: SistrumHybridTier.lightweight,
            tintOpacity: 0.5,
          ),
          brightness: Brightness.dark,
        ),
      );
      final box = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(ClipRRect),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final deco = box.decoration as BoxDecoration;
      expect(deco.color!.a, closeTo(0.5, 0.01));
    });
  });

  group('integration with the POC', () {
    test('the mode is a separate, labelled POC renderer', () {
      expect(SistrumGlassMode.sistrumHybrid.label, 'Sistrum Hybrid');
      expect(SistrumGlassMode.values, contains(SistrumGlassMode.sistrumHybrid));
    });

    test('the Hybrid mode is not one of the five standard benchmark runs', () {
      final standard = {
        SistrumGlassMode.transparentBaseline,
        SistrumGlassMode.basicBlur,
        SistrumGlassMode.liquidGlass,
        SistrumGlassMode.newFullGlass,
        SistrumGlassMode.newFakeGlass,
      };
      expect(standard.contains(SistrumGlassMode.sistrumHybrid), isFalse);
    });

    test(
      'its render path is never claimed: the benchmark has no expected path',
      () {
        expect(expectedGlassRenderPath(SistrumGlassMode.sistrumHybrid), isNull);
      },
    );
  });
}
