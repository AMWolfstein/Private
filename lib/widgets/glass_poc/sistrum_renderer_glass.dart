import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart' as lgr;

/// Adapter for the developer-only `liquid_glass_renderer` comparison. Its
/// names (`LiquidGlass`, `LiquidGlassSettings`) clash with
/// `liquid_glass_widgets`, so they are reached only through this file.
///
/// The appearance is the library's own iOS 27 regular preset, not a copy of
/// the widgets settings. The two libraries' blur and refraction models differ,
/// so the look is matched by intent, not by number (see the decision doc).
lgr.LiquidGlassSettings sistrumRendererGlassSettings({required bool dark}) =>
    dark
    ? lgr.LiquidGlassSettings.ios27RegularDark()
    : lgr.LiquidGlassSettings.ios27RegularLight();

/// A renderer glass shape of [borderRadius], on its own `LiquidGlassLayer`.
///
/// [fake] is passed to the package unchanged: `false` requests the full Flutter
/// GPU path (the package may still fall back to FakeGlass), and `true` requests
/// FakeGlass explicitly. The effective path is probed from the tree, not
/// assumed from this flag.
///
/// Each surface owns its layer. Observed earlier (Linux Impeller harness,
/// without Flutter GPU): a shared layer holding several shapes drew none of
/// them, so each surface is its own layer. This deviates from the library's
/// shared-layer example and is recorded in the decision doc.
Widget sistrumRendererSurface({
  required double borderRadius,
  required bool dark,
  required bool fake,
  required Widget child,
  BackdropKey? backdropKey,
  lgr.LiquidGlassSettings? settings,
}) {
  return lgr.LiquidGlass.withOwnLayer(
    shape: lgr.LiquidRoundedSuperellipse(borderRadius: borderRadius),
    settings: settings ?? sistrumRendererGlassSettings(dark: dark),
    fake: fake,
    useBackdropGroup: backdropKey != null,
    backdropKey: backdropKey,
    child: child,
  );
}
