import 'package:flutter/widgets.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_mode.dart';

/// The effective rendering path of the mounted glass, as far as the mounted
/// widget tree proves it.
enum SistrumGlassRenderPath {
  /// `liquid_glass_renderer` real layer (`_RawShapes`), drawn with Flutter GPU.
  fullGpu('full_gpu'),

  /// `liquid_glass_renderer` FakeGlass (a `RawFakeGlass` surface).
  fakeBackdrop('fake_backdrop'),

  /// Flutter's own `BackdropFilter` (Basic Blur).
  backdropFilter('backdrop_filter'),

  /// No blur or glass (Transparent Baseline).
  none('none'),

  /// The path cannot be determined from the tree, or the tree is incomplete.
  unverified('unverified');

  const SistrumGlassRenderPath(this.wire);

  /// The value written to copied reports.
  final String wire;
}

/// What the page can prove about the rendering path right now.
class SistrumGlassRenderReport {
  const SistrumGlassRenderReport({
    required this.path,
    required this.fallback,
    this.fallbackReason,
    this.unverifiedReason,
  });

  const SistrumGlassRenderReport.unverified(String reason)
    : path = SistrumGlassRenderPath.unverified,
      fallback = null,
      fallbackReason = null,
      unverifiedReason = reason;

  final SistrumGlassRenderPath path;

  /// Whether a requested Full Glass path was replaced by FakeGlass. Null when
  /// the path is unverified, because then nothing is known.
  final bool? fallback;

  /// Why the fallback happened. Set only when [fallback] is true.
  final String? fallbackReason;

  /// Why the path is unverified. Set only for [SistrumGlassRenderPath.unverified].
  final String? unverifiedReason;

  @override
  bool operator ==(Object other) =>
      other is SistrumGlassRenderReport &&
      other.path == path &&
      other.fallback == fallback &&
      other.fallbackReason == fallbackReason &&
      other.unverifiedReason == unverifiedReason;

  @override
  int get hashCode =>
      Object.hash(path, fallback, fallbackReason, unverifiedReason);
}

/// Counts of the rendering widgets in the mounted stage. Type names are the
/// only evidence the package exposes: its effective mode is not public.
class SistrumGlassCensus {
  const SistrumGlassCensus({
    required this.layers,
    required this.realLayers,
    required this.fakeWidgets,
    required this.backdropFilters,
  });

  /// `LiquidGlassLayer` widgets (public package type).
  final int layers;

  /// Layers that built the real GPU subtree (`_RawShapes`, which exists only
  /// once Flutter GPU geometry is loaded).
  final int realLayers;

  /// FakeGlass widgets (`RawFakeGlass` or its consolidated layer).
  final int fakeWidgets;

  /// Flutter `BackdropFilter` widgets in the stage.
  final int backdropFilters;
}

/// Counts the rendering widgets below [root]. Read-only; it never marks the
/// tree dirty.
SistrumGlassCensus sistrumGlassCensus(Element root) {
  var layers = 0;
  var realLayers = 0;
  var fakeWidgets = 0;
  var backdropFilters = 0;
  void visit(Element element) {
    final name = element.widget.runtimeType.toString();
    if (name == 'LiquidGlassLayer') layers++;
    if (name == '_RawShapes') realLayers++;
    if (name.contains('FakeGlass')) fakeWidgets++;
    if (name == 'BackdropFilter') backdropFilters++;
    element.visitChildren(visit);
  }

  visit(root);
  return SistrumGlassCensus(
    layers: layers,
    realLayers: realLayers,
    fakeWidgets: fakeWidgets,
    backdropFilters: backdropFilters,
  );
}

/// Whether the render path of [mode] can be classified from the tree. Old
/// Liquid Glass and Reference Glass come from `liquid_glass_widgets`, which is
/// not instrumented, so their path is always reported as unverified.
bool sistrumRenderPathVerifiable(SistrumGlassMode mode) =>
    mode == SistrumGlassMode.transparentBaseline ||
    mode == SistrumGlassMode.basicBlur ||
    mode == SistrumGlassMode.newFullGlass ||
    mode == SistrumGlassMode.newFullGlassSharedBackdrop ||
    mode == SistrumGlassMode.newFakeGlass;

/// Classifies the path from the census. Anything that does not match exactly
/// one of the expected shapes is unverified, never a guess.
///
/// [shaderFiltersSupported] is `ImageFilter.isShaderFilterSupported`. It only
/// explains a fallback; it never proves Full Glass on its own.
SistrumGlassRenderReport classifySistrumGlassRenderPath({
  required SistrumGlassMode mode,
  required int expectedSurfaces,
  required SistrumGlassCensus census,
  required bool shaderFiltersSupported,
}) {
  switch (mode) {
    case SistrumGlassMode.transparentBaseline:
      return const SistrumGlassRenderReport(
        path: SistrumGlassRenderPath.none,
        fallback: false,
      );
    case SistrumGlassMode.basicBlur:
      if (census.backdropFilters >= expectedSurfaces) {
        return const SistrumGlassRenderReport(
          path: SistrumGlassRenderPath.backdropFilter,
          fallback: false,
        );
      }
      return const SistrumGlassRenderReport.unverified(
        'BackdropFilter count is below the surface count',
      );
    case SistrumGlassMode.liquidGlass:
    case SistrumGlassMode.referenceGlass:
      return const SistrumGlassRenderReport.unverified(
        'liquid_glass_widgets is not instrumented; its path is not probed',
      );
    case SistrumGlassMode.newFakeGlass:
      // fake: true was requested, so FakeGlass is the only correct result.
      if (census.layers == expectedSurfaces &&
          census.realLayers == 0 &&
          census.fakeWidgets >= expectedSurfaces) {
        return const SistrumGlassRenderReport(
          path: SistrumGlassRenderPath.fakeBackdrop,
          fallback: false,
        );
      }
      return const SistrumGlassRenderReport.unverified(
        'FakeGlass layers are not all mounted yet (or the tree is mixed)',
      );
    case SistrumGlassMode.newFullGlass:
    case SistrumGlassMode.newFullGlassSharedBackdrop:
      if (census.layers == expectedSurfaces &&
          census.realLayers == expectedSurfaces &&
          census.fakeWidgets == 0) {
        return const SistrumGlassRenderReport(
          path: SistrumGlassRenderPath.fullGpu,
          fallback: false,
        );
      }
      if (census.layers == expectedSurfaces &&
          census.realLayers == 0 &&
          census.fakeWidgets >= expectedSurfaces) {
        return SistrumGlassRenderReport(
          path: SistrumGlassRenderPath.fakeBackdrop,
          fallback: true,
          fallbackReason: shaderFiltersSupported
              ? 'Flutter GPU geometry did not load; LiquidGlassLayer built FakeGlass although fake: false was requested'
              : 'Impeller shader filters are unsupported; LiquidGlassLayer built FakeGlass although fake: false was requested',
        );
      }
      return const SistrumGlassRenderReport.unverified(
        'Full Glass layers are not all mounted yet, or the tree is mixed (blank or initializing)',
      );
  }
}
