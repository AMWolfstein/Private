import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/providers/performance/glass_poc_mode_provider.dart';
import 'package:sistrum/screens/settings/developer/glass_poc_page.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_mode.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_hybrid_atlas.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_hybrid_config.dart';

Future<ProviderContainer> _pumpHybrid(
  WidgetTester tester,
  SistrumHybridConfig config,
) async {
  tester.view.physicalSize = const Size(1080, 2388);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: GlassPocPage()),
    ),
  );
  container
      .read(glassPocModeProvider.notifier)
      .select(SistrumGlassMode.sistrumHybrid);
  container.read(glassPocHybridProvider.notifier).update((_) => config);
  await tester.pump();
  await tester.pump();
  return container;
}

void main() {
  const frosted = SistrumHybridConfig(
    tier: SistrumHybridTier.frosted,
    blurSigma: 7,
    sharedAtlas: true,
  );

  testWidgets('the atlas captures at the selected resolution', (tester) async {
    final container = await _pumpHybrid(tester, frosted);
    final atlas = container
        .read(glassPocRunRegistryProvider)
        .hybridTelemetry()!
        .atlas!;
    // Default: the existing sigma-based scale, unchanged.
    expect(atlas.resolution, SistrumAtlasResolution.baseline);
    expect(atlas.samplingScale, closeTo(2 / 7, 1e-3));

    container.read(glassPocHybridProvider.notifier).update(
      (c) => c.copyWith(atlasResolution: SistrumAtlasResolution.quarter),
    );
    await tester.pump();
    await tester.pump();
    final quarter = container
        .read(glassPocRunRegistryProvider)
        .hybridTelemetry()!
        .atlas!;
    expect(quarter.resolution, SistrumAtlasResolution.quarter);
    expect(quarter.samplingScale, closeTo(0.6875, 1e-3));

    container.read(glassPocHybridProvider.notifier).update(
      (c) => c.copyWith(atlasResolution: SistrumAtlasResolution.full),
    );
    await tester.pump();
    await tester.pump();
    final full = container
        .read(glassPocRunRegistryProvider)
        .hybridTelemetry()!
        .atlas!;
    expect(full.samplingScale, closeTo(2.75, 1e-3));
    // The real capture is larger at full resolution, not just the display.
    expect(full.textureSize!.width, greaterThan(quarter.textureSize!.width));
    expect(full.textureSize!.height, greaterThan(quarter.textureSize!.height));
    expect(full.captureCount, greaterThan(quarter.captureCount));
    expect(full.fallbackReason, isNull);
  });
}
