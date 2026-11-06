import 'package:flutter/painting.dart';
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

  test('refraction comparison is OFF, Edge and Full at two speeds', () {
    final configs = glassHybridRefractionConfigurations(
      const SistrumHybridConfig(tier: SistrumHybridTier.frosted),
    );
    expect(configs, hasLength(6));
    final edge = configs.where((r) => r.hybridConfig!.usesAtlasEdge).toList();
    expect(edge, hasLength(2));
    final full = configs
        .where(
          (r) =>
              r.hybridConfig!.refraction && !r.hybridConfig!.sharedAtlas,
        )
        .toList();
    expect(full, hasLength(2));
    expect(
      configs.where((r) => !r.hybridConfig!.refraction),
      everyElement(
        predicate<GlassBenchmarkRun>((r) => !r.hybridConfig!.sharedAtlas),
      ),
    );
    expect(
      GlassBenchmarkPlan.hybridRefraction(
        config: const SistrumHybridConfig(tier: SistrumHybridTier.frosted),
        repeats: 3,
      ).runs,
      hasLength(18),
    );
  });

  test('the Edge shader uniforms are packed in declaration order', () {
    final values = sistrumAtlasEdgeUniforms(
      surface: const Rect.fromLTWH(10, 20, 200, 100),
      borderRadius: 24,
      chromatic: true,
      sourceInAtlas: const Rect.fromLTWH(4, 8, 400, 200),
      scale: 2,
      atlasSize: const Size(1024, 512),
    );
    expect(values, hasLength(13));
    expect(values.sublist(0, 2), [200, 100]); // uSize
    expect(values[2], 24); // uRadius
    expect(values[3], kSistrumAtlasEdgeBand); // uBand
    expect(values[5], 1); // uDispersion, chromatic on
    expect(values.sublist(6, 8), [10, 20]); // uOrigin
    expect(values.sublist(8, 10), [4, 8]); // uAtlasOrigin
    expect(values[10], 2); // uScale
    expect(values.sublist(11, 13), [1024, 512]); // uAtlasSize
  });

  test('a small surface caps the Edge band at half its short side', () {
    final values = sistrumAtlasEdgeUniforms(
      surface: const Rect.fromLTWH(0, 0, 20, 12),
      borderRadius: 6,
      chromatic: false,
      sourceInAtlas: Rect.zero,
      scale: 1,
      atlasSize: const Size(64, 64),
    );
    expect(values[3], 6);
    expect(values[5], 0);
  });
}
