import 'package:flutter_test/flutter_test.dart';
import 'package:mornye/providers/runtime_profile_provider.dart';
import 'package:mornye/widgets/app_liquid_backdrop.dart';

void main() {
  test('liquid glass uses the fixed Clear blur', () {
    expect(AppGlassRules.blurSigma(AppGlassLevel.liquid), 2.0);
    expect(AppGlassRules.clearSigma, 2.0);
  });

  test('frosted glass keeps its small fallback budget', () {
    expect(AppGlassRules.blurSigma(AppGlassLevel.frosted), 3.0);
    expect(AppGlassRules.frostedSigma, 3.0);
  });

  test('each level shares one backdrop filter', () {
    expect(
      identical(
        AppGlassRules.blurFilter(AppGlassLevel.liquid),
        AppGlassRules.blurFilter(AppGlassLevel.liquid),
      ),
      isTrue,
    );
    expect(
      AppGlassRules.blurFilter(AppGlassLevel.liquid),
      isNot(AppGlassRules.blurFilter(AppGlassLevel.frosted)),
    );
  });

  test('dispersion scales with the effect amount only', () {
    expect(AppGlassRules.dispersion(1), closeTo(1.32, 1e-9));
    expect(AppGlassRules.dispersion(0.5), closeTo(0.66, 1e-9));
    expect(AppGlassRules.dispersion(0), 0);
  });
}
