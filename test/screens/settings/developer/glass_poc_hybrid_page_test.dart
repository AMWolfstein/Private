import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/providers/performance/glass_poc_mode_provider.dart';
import 'package:sistrum/screens/settings/developer/glass_poc_page.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_mode.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_render_path.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_surface.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_hybrid_config.dart';

/// A phone-sized view (about a 1080 x 2388 panel at DPR 2.75).
Future<ProviderContainer> _pumpPhone(WidgetTester tester) async {
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
  return container;
}

/// Stage size and the four surface rectangles, in paint order.
({Size stage, List<Rect> surfaces}) _scene(WidgetTester tester) => (
  stage: tester.getSize(find.byType(ListView)),
  surfaces: [
    for (final e in find.byType(SistrumGlassSurface).evaluate())
      tester.getRect(find.byWidget(e.widget)),
  ],
);

Future<void> _select(
  WidgetTester tester,
  ProviderContainer container,
  SistrumHybridConfig config,
) async {
  container.read(glassPocHybridProvider.notifier).update((_) => config);
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('variants A to E keep the same stage and surface geometry', (
    tester,
  ) async {
    final container = await _pumpPhone(tester);
    final baseline = _scene(tester);
    expect(baseline.surfaces, hasLength(4));

    container
        .read(glassPocModeProvider.notifier)
        .select(SistrumGlassMode.sistrumHybrid);
    await tester.pump();
    for (final variant in SistrumHybridVariant.values) {
      await _select(tester, container, variant.config);
      final scene = _scene(tester);
      // The stage is an Expanded beside a loose Flexible, so the controls'
      // height never changes it, in any mode or tier.
      expect(scene.stage, baseline.stage, reason: variant.code);
      expect(scene.surfaces, baseline.surfaces, reason: variant.code);
    }
  });

  testWidgets('the probe reports Hybrid from telemetry, with the read count', (
    tester,
  ) async {
    final container = await _pumpPhone(tester);
    container
        .read(glassPocModeProvider.notifier)
        .select(SistrumGlassMode.sistrumHybrid);
    await _select(
      tester,
      container,
      const SistrumHybridConfig(tier: SistrumHybridTier.frosted),
    );
    final registry = container.read(glassPocRunRegistryProvider);
    final snap = registry.hybridTelemetry()!;
    expect(snap.surfaces, 4);
    expect(snap.backdropFilters, 4);
    expect(snap.backdropReads, 4);
    final path = registry.renderPath();
    expect(path.path, SistrumGlassRenderPath.backdropFilter);
    expect(path.fallback, isFalse);

    await _select(
      tester,
      container,
      const SistrumHybridConfig(tier: SistrumHybridTier.opaque),
    );
    expect(registry.renderPath().path, SistrumGlassRenderPath.opaque);
    expect(registry.hybridTelemetry()!.backdropReads, 0);
  });

  testWidgets('variant E shares one read only between safe surfaces', (
    tester,
  ) async {
    final container = await _pumpPhone(tester);
    container
        .read(glassPocModeProvider.notifier)
        .select(SistrumGlassMode.sistrumHybrid);
    await _select(tester, container, SistrumHybridVariant.e.config);
    final snap = container.read(glassPocRunRegistryProvider).hybridTelemetry()!;
    expect(snap.backdropFilters, 4);
    // The back button, trailing capsule and mini player share one read. The
    // tab bar's blur reaches the mini player painted just above it, so it
    // keeps its own read: two flips instead of four.
    expect(snap.sharedGroups, 1);
    expect(snap.sharedMembers, 3);
    expect(snap.backdropReads, 2);

    await _select(tester, container, SistrumHybridVariant.d.config);
    final independent = container
        .read(glassPocRunRegistryProvider)
        .hybridTelemetry()!;
    expect(independent.sharedBackdropActive, isFalse);
    expect(independent.backdropReads, 4);
  });

  testWidgets('other modes report no Hybrid telemetry', (tester) async {
    final container = await _pumpPhone(tester);
    expect(
      container.read(glassPocRunRegistryProvider).hybridTelemetry(),
      isNull,
    );
  });
}
