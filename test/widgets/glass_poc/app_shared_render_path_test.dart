import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_mode.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_render_path.dart';

void main() {
  test('shared Full Glass still requires four real layers', () {
    final real = classifySistrumGlassRenderPath(
      mode: SistrumGlassMode.newFullGlassSharedBackdrop,
      expectedSurfaces: 4,
      census: const SistrumGlassCensus(
        layers: 4,
        realLayers: 4,
        fakeWidgets: 0,
        backdropFilters: 0,
      ),
      shaderFiltersSupported: true,
    );
    expect(real.path, SistrumGlassRenderPath.fullGpu);
    expect(real.fallback, isFalse);
    final fallback = classifySistrumGlassRenderPath(
      mode: SistrumGlassMode.newFullGlassSharedBackdrop,
      expectedSurfaces: 4,
      census: const SistrumGlassCensus(
        layers: 4,
        realLayers: 0,
        fakeWidgets: 4,
        backdropFilters: 4,
      ),
      shaderFiltersSupported: true,
    );
    expect(fallback.path, SistrumGlassRenderPath.fakeBackdrop);
    expect(fallback.fallback, isTrue);
  });

  test('sharing does not request fake glass or change the Old renderer', () {
    expect(SistrumGlassMode.newFullGlassSharedBackdrop.rendererFake, isFalse);
    expect(SistrumGlassMode.newFullGlassSharedBackdrop.usesRenderer, isTrue);
    expect(
      SistrumGlassMode.newFullGlassSharedBackdrop.usesSharedLayer,
      isFalse,
    );
    expect(SistrumGlassMode.liquidGlass.usesRenderer, isFalse);
    expect(SistrumGlassMode.liquidGlass.usesSharedLayer, isTrue);
  });
}
