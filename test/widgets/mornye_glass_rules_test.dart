import 'package:flutter_test/flutter_test.dart';
import 'package:mornye/providers/runtime_profile_provider.dart';
import 'package:mornye/widgets/mornye_liquid_backdrop.dart';

void main() {
  // Clarity positions the slider exposes and the values the rules change at.
  const positions = [0.0, 0.2, 0.25, 0.5, 0.6, 0.75, 0.9, 1.0];

  group('liquid level', () {
    test('samples the backdrop only above 0.2', () {
      expect(MornyeGlassRules.backdropMinClarity(MornyeGlassLevel.liquid), 0.2);
      expect(
        0.2 > MornyeGlassRules.backdropMinClarity(MornyeGlassLevel.liquid),
        isFalse,
      );
      expect(
        0.25 > MornyeGlassRules.backdropMinClarity(MornyeGlassLevel.liquid),
        isTrue,
      );
    });

    test('blur budget follows clarity bands', () {
      final sigmas = {
        for (final c in positions)
          c:
              MornyeGlassRules.blurSigmas[MornyeGlassRules.blurIndex(
                MornyeGlassLevel.liquid,
                c,
              )],
      };
      expect(sigmas, {
        0.0: 16.0,
        0.2: 16.0,
        0.25: 16.0,
        0.5: 16.0,
        0.6: 6.0,
        0.75: 6.0,
        0.9: 2.0,
        1.0: 2.0,
      });
    });

    test('dispersion is proportional to clarity and the effect amount', () {
      expect(MornyeGlassRules.dispersion(0.75, 1), closeTo(0.99, 1e-9));
      expect(MornyeGlassRules.dispersion(1, 1), closeTo(1.32, 1e-9));
      expect(MornyeGlassRules.dispersion(1, 0.5), closeTo(0.66, 1e-9));
      expect(MornyeGlassRules.dispersion(0, 1), 0);
    });
  });

  group('frosted level', () {
    test('waits until clarity is above 0.5 to sample', () {
      expect(
        MornyeGlassRules.backdropMinClarity(MornyeGlassLevel.frosted),
        0.5,
      );
      expect(
        0.5 > MornyeGlassRules.backdropMinClarity(MornyeGlassLevel.frosted),
        isFalse,
      );
    });

    test('always uses the frosted fallback budget', () {
      for (final c in positions) {
        expect(
          MornyeGlassRules.blurIndex(MornyeGlassLevel.frosted, c),
          1,
          reason: 'clarity $c',
        );
      }
      expect(MornyeGlassRules.blurSigmas[1], 3.0);
    });
  });

  test('tint and clear fill ramps keep their endpoints', () {
    expect(MornyeGlassRules.tintStrength(0), 1);
    expect(MornyeGlassRules.tintStrength(0.75), closeTo(0.0625, 1e-9));
    expect(MornyeGlassRules.tintStrength(1), 0);

    expect(MornyeGlassRules.clearFillMix(0), 0);
    expect(MornyeGlassRules.clearFillMix(0.2), 0);
    expect(MornyeGlassRules.clearFillMix(0.6), closeTo(0.5, 1e-9));
    expect(MornyeGlassRules.clearFillMix(1), 1);
  });
}
