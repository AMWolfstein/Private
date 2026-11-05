import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart' as lgr;
import 'package:sistrum/widgets/glass_poc/sistrum_glass_mode.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_render_path.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_surface.dart';

SistrumGlassCensus _census({
  int layers = 0,
  int realLayers = 0,
  int fakeWidgets = 0,
  int backdropFilters = 0,
}) => SistrumGlassCensus(
  layers: layers,
  realLayers: realLayers,
  fakeWidgets: fakeWidgets,
  backdropFilters: backdropFilters,
);

SistrumGlassRenderReport _classify(
  SistrumGlassMode mode,
  SistrumGlassCensus census, {
  int surfaces = 4,
  bool shaders = true,
}) => classifySistrumGlassRenderPath(
  mode: mode,
  expectedSurfaces: surfaces,
  census: census,
  shaderFiltersSupported: shaders,
);

void main() {
  group('render path classification', () {
    test('full GPU needs every surface on the real layer and no FakeGlass', () {
      final report = _classify(
        SistrumGlassMode.newFullGlass,
        _census(layers: 4, realLayers: 4),
      );
      expect(report.path, SistrumGlassRenderPath.fullGpu);
      expect(report.fallback, isFalse);
      expect(report.path.wire, 'full_gpu');
    });

    test('a Full Glass request that built FakeGlass is a fallback', () {
      final report = _classify(
        SistrumGlassMode.newFullGlass,
        _census(layers: 4, fakeWidgets: 4),
      );
      expect(report.path, SistrumGlassRenderPath.fakeBackdrop);
      expect(report.fallback, isTrue);
      expect(report.fallbackReason, contains('fake: false was requested'));
    });

    test('the fallback reason names missing shader filters', () {
      final report = _classify(
        SistrumGlassMode.newFullGlass,
        _census(layers: 4, fakeWidgets: 4),
        shaders: false,
      );
      expect(report.fallbackReason, contains('shader filters'));
    });

    test('a blank or initializing Full Glass tree is never full GPU', () {
      // Layers mounted, but neither the real nor the fake subtree yet.
      final blank = _classify(
        SistrumGlassMode.newFullGlass,
        _census(layers: 4),
      );
      expect(blank.path, SistrumGlassRenderPath.unverified);
      expect(blank.fallback, isNull);
      expect(blank.unverifiedReason, isNotNull);

      // Some layers real, some fake: a mixed tree is not one path.
      final mixed = _classify(
        SistrumGlassMode.newFullGlass,
        _census(layers: 4, realLayers: 2, fakeWidgets: 2),
      );
      expect(mixed.path, SistrumGlassRenderPath.unverified);
    });

    test('an explicit FakeGlass request is FakeGlass with no fallback', () {
      final report = _classify(
        SistrumGlassMode.newFakeGlass,
        _census(layers: 4, fakeWidgets: 4),
      );
      expect(report.path, SistrumGlassRenderPath.fakeBackdrop);
      expect(report.fallback, isFalse);
    });

    test('FakeGlass never reports the real GPU layer', () {
      final report = _classify(
        SistrumGlassMode.newFakeGlass,
        _census(layers: 4, realLayers: 4),
      );
      expect(report.path, SistrumGlassRenderPath.unverified);
    });

    test('Basic Blur is a Flutter BackdropFilter, one per surface', () {
      final report = _classify(
        SistrumGlassMode.basicBlur,
        _census(backdropFilters: 4),
      );
      expect(report.path, SistrumGlassRenderPath.backdropFilter);
      expect(report.fallback, isFalse);
    });

    test('Transparent Baseline has no blur path', () {
      final report = _classify(SistrumGlassMode.transparentBaseline, _census());
      expect(report.path, SistrumGlassRenderPath.none);
    });

    test('the widgets package modes are never probed', () {
      for (final mode in [
        SistrumGlassMode.liquidGlass,
        SistrumGlassMode.referenceGlass,
      ]) {
        expect(sistrumRenderPathVerifiable(mode), isFalse, reason: mode.label);
        final report = _classify(mode, _census(layers: 4, realLayers: 4));
        expect(
          report.path,
          SistrumGlassRenderPath.unverified,
          reason: mode.label,
        );
      }
    });

    test('reports never claim fallback for an unverified path', () {
      const report = SistrumGlassRenderReport.unverified('no tree');
      expect(report.fallback, isNull);
      expect(report.path.wire, 'unverified');
    });
  });

  group('explicit package configuration', () {
    testWidgets('Full Glass asks the package for fake: false per surface', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                for (var i = 0; i < 4; i++)
                  sistrumRendererSurfaceForTest(fake: false),
              ],
            ),
          ),
        ),
      );
      final layers = tester
          .widgetList<lgr.LiquidGlassLayer>(find.byType(lgr.LiquidGlassLayer))
          .toList();
      expect(layers, hasLength(4));
      expect(layers.every((l) => l.fake == false), isTrue);
    });

    testWidgets('FakeGlass asks the package for fake: true per surface', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                for (var i = 0; i < 4; i++)
                  sistrumRendererSurfaceForTest(fake: true),
              ],
            ),
          ),
        ),
      );
      final layers = tester
          .widgetList<lgr.LiquidGlassLayer>(find.byType(lgr.LiquidGlassLayer))
          .toList();
      expect(layers, hasLength(4));
      expect(layers.every((l) => l.fake), isTrue);
    });

    test('the mode maps to the request flag', () {
      expect(SistrumGlassMode.newFullGlass.rendererFake, isFalse);
      expect(SistrumGlassMode.newFakeGlass.rendererFake, isTrue);
    });
  });
}

/// One renderer surface, as the page mounts it, for widget-level checks.
Widget sistrumRendererSurfaceForTest({required bool fake}) {
  return SistrumGlassSurface(
    mode: fake ? SistrumGlassMode.newFakeGlass : SistrumGlassMode.newFullGlass,
    width: 120,
    height: 48,
    borderRadius: 24,
    child: const SizedBox.shrink(),
  );
}
