import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_hybrid_atlas.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_hybrid_config.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_hybrid_surface.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_hybrid_telemetry.dart';

const _atlasConfig = SistrumHybridConfig(
  tier: SistrumHybridTier.frosted,
  blurSigma: 4,
  sharedAtlas: true,
);

/// A backdrop of one colour under one glass surface, inside the atlas scopes.
Widget _stage({
  required SistrumHybridAtlas atlas,
  required SistrumHybridTelemetry telemetry,
  required Color color,
  Widget? extraBackdrop,
  Listenable? invalidations,
}) {
  atlas.configure(
    requested: true,
    unsupportedReason: _atlasConfig.atlasUnsupportedReason,
    sigma: _atlasConfig.blurSigma,
    invalidations: invalidations ?? _never,
  );
  return Directionality(
    textDirection: TextDirection.ltr,
    child: SistrumHybridAtlasScope(
      atlas: atlas,
      child: SistrumHybridTelemetryScope(
        telemetry: telemetry,
        child: RepaintBoundary(
          child: Stack(
            children: [
              Positioned.fill(
                child: SistrumAtlasBackdrop(
                  key: atlas.backdropKey,
                  child: extraBackdrop ?? ColoredBox(color: color),
                ),
              ),
              const Positioned(
                left: 40,
                top: 60,
                width: 200,
                height: 56,
                child: SistrumHybridSurface(
                  config: _atlasConfig,
                  dark: false,
                  borderRadius: 28,
                  child: SizedBox.expand(),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

final _never = ValueNotifier<int>(0);

/// Mean colour of the middle of [image], read back for the test only.
Future<Color> _centre(WidgetTester tester, ui.Image image) async {
  final data = (await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  ))!;
  final x = image.width ~/ 2;
  final y = image.height ~/ 2;
  final i = (y * image.width + x) * 4;
  return Color.fromARGB(
    data.getUint8(i + 3),
    data.getUint8(i),
    data.getUint8(i + 1),
    data.getUint8(i + 2),
  );
}

void main() {
  testWidgets('the atlas is drawn instead of a BackdropFilter', (tester) async {
    final atlas = SistrumHybridAtlas();
    addTearDown(atlas.dispose);
    final telemetry = SistrumHybridTelemetry();
    await tester.pumpWidget(
      _stage(atlas: atlas, telemetry: telemetry, color: Colors.red),
    );
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(SistrumAtlasSlot), findsOneWidget);
    final stats = atlas.stats;
    expect(stats.captureCount, 1);
    expect(stats.activeSurfaces, 1);
    expect(stats.fallbackReason, isNull);
    expect(stats.samplingScale, closeTo(0.5, 1e-9));
    expect(stats.textureSize, isNotNull);
    final snap = telemetry.snapshot(atlas: stats);
    expect(snap.uniformPath, SistrumHybridEffectivePath.atlas);
    expect(snap.backdropReads, 0);
    final lines = snap.lines().join('\n');
    for (final field in [
      'hybrid_atlas_requested=true',
      'hybrid_atlas_active=1/1',
      'hybrid_atlas_fallback_reason=none',
      'hybrid_atlas_capture_count=1',
      'hybrid_atlas_update_count=0',
      'hybrid_atlas_texture_size=',
      'hybrid_atlas_sampling_scale=0.500',
      'hybrid_effective_path=atlas',
    ]) {
      expect(lines, contains(field));
    }
  });

  testWidgets('a declared change is in the atlas of the same frame', (
    tester,
  ) async {
    final atlas = SistrumHybridAtlas();
    addTearDown(atlas.dispose);
    final telemetry = SistrumHybridTelemetry();
    final changes = ValueNotifier<int>(0);
    addTearDown(changes.dispose);
    Widget stage(Color c) => _stage(
      atlas: atlas,
      telemetry: telemetry,
      color: c,
      invalidations: changes,
    );
    await tester.pumpWidget(stage(const Color(0xFFFF0000)));
    final red = await _centre(tester, atlas.debugImage!);
    expect(red.r, greaterThan(0.9));
    expect(red.b, lessThan(0.1));
    // As the page does for the scroll position: the change is declared, so the
    // glass repaints in the frame the backdrop changes, and that frame's
    // capture already holds the new colour.
    changes.value++;
    await tester.pumpWidget(stage(const Color(0xFF0000FF)));
    expect(atlas.stats.captureCount, 2);
    expect(atlas.stats.updateCount, 1);
    expect(atlas.stats.lateInvalidations, 0);
    final blue = await _centre(tester, atlas.debugImage!);
    expect(blue.b, greaterThan(0.9));
    expect(blue.r, lessThan(0.1));
  });

  testWidgets('an undeclared change is caught one frame late and counted', (
    tester,
  ) async {
    final atlas = SistrumHybridAtlas();
    addTearDown(atlas.dispose);
    final telemetry = SistrumHybridTelemetry();
    await tester.pumpWidget(
      _stage(
        atlas: atlas,
        telemetry: telemetry,
        color: const Color(0xFFFF0000),
      ),
    );
    await tester.pumpWidget(
      _stage(
        atlas: atlas,
        telemetry: telemetry,
        color: const Color(0xFF0000FF),
      ),
    );
    // The glass did not repaint in that frame; the post-frame check saw the
    // changed backdrop and repaints it in the next frame.
    expect(atlas.stats.lateInvalidations, 1);
    expect(atlas.stats.captureCount, 1);
    await tester.pump();
    expect(atlas.stats.captureCount, 2);
    final blue = await _centre(tester, atlas.debugImage!);
    expect(blue.b, greaterThan(0.9));
    // Then it settles: no repaint loop on a still screen.
    await tester.pump();
    expect(atlas.stats.lateInvalidations, 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('an unchanged backdrop reuses the capture', (tester) async {
    final atlas = SistrumHybridAtlas();
    addTearDown(atlas.dispose);
    final telemetry = SistrumHybridTelemetry();
    await tester.pumpWidget(
      _stage(atlas: atlas, telemetry: telemetry, color: Colors.green),
    );
    // Repaint the glass without changing what is under it.
    tester
        .renderObject<RenderSistrumAtlasSlot>(find.byType(SistrumAtlasSlot))
        .markNeedsPaint();
    await tester.pump();
    expect(atlas.stats.captureCount, 1);
    expect(atlas.stats.reuseCount, greaterThan(0));
  });

  testWidgets(
    'an unsupported layer under the glass falls back with its reason',
    (tester) async {
      final atlas = SistrumHybridAtlas();
      addTearDown(atlas.dispose);
      final telemetry = SistrumHybridTelemetry();
      await tester.pumpWidget(
        _stage(
          atlas: atlas,
          telemetry: telemetry,
          color: Colors.red,
          extraBackdrop: ShaderMask(
            shaderCallback: (rect) => const LinearGradient(
              colors: [Colors.red, Colors.blue],
            ).createShader(rect),
            child: const ColoredBox(color: Colors.white),
          ),
        ),
      );
      await tester.pump();
      expect(atlas.active, isFalse);
      expect(atlas.stats.fallbackReason, 'unsupported_layer:ShaderMaskLayer');
      // The surface rebuilt with the existing BackdropFilter, and says why.
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(telemetry.snapshot().fallbacks, {
        SistrumHybridFallback.atlasCaptureFailed,
      });
    },
  );

  test('unsupported combinations are named, not degraded silently', () {
    expect(
      const SistrumHybridConfig(
        tier: SistrumHybridTier.full,
        sharedAtlas: true,
      ).atlasUnsupportedReason,
      'refraction_not_supported_by_atlas',
    );
    expect(
      const SistrumHybridConfig(
        tier: SistrumHybridTier.full,
        refraction: false,
        sharedAtlas: true,
      ).usesAtlas,
      isTrue,
    );
    expect(
      const SistrumHybridConfig(
        tier: SistrumHybridTier.frosted,
        blurSigma: 0,
        sharedAtlas: true,
      ).atlasUnsupportedReason,
      'zero_blur_bypass',
    );
    // Shared BackdropFilter reads are off while the atlas is requested.
    expect(
      const SistrumHybridConfig(
        tier: SistrumHybridTier.frosted,
        sharedBackdrop: true,
        sharedAtlas: true,
      ).sharesBackdrop,
      isFalse,
    );
  });

  test('the atlas scale gives about two atlas pixels of blur', () {
    expect(sistrumAtlasScale(sigma: 7, devicePixelRatio: 2.75), 2 / 7);
    expect(sistrumAtlasScale(sigma: 1, devicePixelRatio: 2.75), 2);
    expect(sistrumAtlasScale(sigma: 24, devicePixelRatio: 2.75), 0.25);
  });
}
