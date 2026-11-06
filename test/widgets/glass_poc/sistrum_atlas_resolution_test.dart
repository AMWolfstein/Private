import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_hybrid_atlas.dart';
import 'package:sistrum/widgets/glass_poc/glass_benchmark_run.dart';
import 'package:sistrum/widgets/glass_poc/glass_benchmark_runner.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_hybrid_config.dart';

void main() {
  const dpr = 2.75;

  test('baseline keeps the existing sigma-based scale and is the default', () {
    expect(
      sistrumAtlasScale(sigma: 7, devicePixelRatio: dpr),
      closeTo(2 / 7, 1e-9),
    );
    expect(
      sistrumAtlasScale(
        sigma: 7,
        devicePixelRatio: dpr,
        resolution: SistrumAtlasResolution.baseline,
      ),
      closeTo(2 / 7, 1e-9),
    );
    expect(
      const SistrumHybridConfig().atlasResolution,
      SistrumAtlasResolution.baseline,
    );
  });

  test('fixed options are fractions of native device pixels', () {
    double scale(SistrumAtlasResolution r) =>
        sistrumAtlasScale(sigma: 7, devicePixelRatio: dpr, resolution: r);
    expect(scale(SistrumAtlasResolution.full), closeTo(2.75, 1e-9));
    expect(scale(SistrumAtlasResolution.half), closeTo(1.375, 1e-9));
    expect(scale(SistrumAtlasResolution.third), closeTo(2.75 * 0.33, 1e-9));
    expect(scale(SistrumAtlasResolution.quarter), closeTo(0.6875, 1e-9));
  });

  test('a fixed option ignores sigma, so only the capture size changes', () {
    for (final sigma in [1.0, 7.0, 24.0]) {
      expect(
        sistrumAtlasScale(
          sigma: sigma,
          devicePixelRatio: dpr,
          resolution: SistrumAtlasResolution.half,
        ),
        closeTo(1.375, 1e-9),
      );
    }
  });

  test('wire names and labels are unique', () {
    final wires = {for (final r in SistrumAtlasResolution.values) r.wire};
    expect(wires, hasLength(SistrumAtlasResolution.values.length));
    expect(
      {for (final r in SistrumAtlasResolution.values) r.label},
      hasLength(SistrumAtlasResolution.values.length),
    );
  });

  test('the resolution is part of the config equality and report', () {
    const a = SistrumHybridConfig(sharedAtlas: true);
    final b = a.copyWith(atlasResolution: SistrumAtlasResolution.half);
    expect(a == b, isFalse);
    expect(b.reportText, contains('atlas_resolution=half'));
    expect(a.reportText, contains('atlas_resolution=baseline'));
  });

  test('the resolution sweep is atlas off plus each resolution, two speeds', () {
    final configs = glassHybridAtlasResolutionConfigurations(
      const SistrumHybridConfig(tier: SistrumHybridTier.frosted),
    );
    // Off, then on at five resolutions, at 400 and 900 px/s.
    expect(configs, hasLength(12));
    expect(configs.where((r) => !r.hybridConfig!.sharedAtlas), hasLength(2));
    expect(
      {
        for (final r in configs)
          if (r.hybridConfig!.sharedAtlas) r.hybridConfig!.atlasResolution,
      },
      SistrumAtlasResolution.values.toSet(),
    );
    final plan = GlassBenchmarkPlan.hybridAtlasResolution(
      config: const SistrumHybridConfig(tier: SistrumHybridTier.frosted),
      repeats: 3,
    );
    expect(plan.runs, hasLength(36));
    expect(plan.hybridAbResolution, isTrue);
    expect(plan.hybridAbAtlas, isTrue);
  });
}
