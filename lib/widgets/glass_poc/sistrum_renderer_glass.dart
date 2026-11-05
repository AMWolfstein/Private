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

/// A renderer glass shape of [borderRadius], drawn on its own layer.
///
/// Observed in this renderer comparison (Linux Impeller harness, without Flutter
/// GPU): a `LiquidGlassLayer` holding several `LiquidGlass` shapes drew none of
/// them, while a standalone `LiquidGlass.auto` drew its glass. So each surface
/// owns its layer, as the Reference mode does. This is a deviation from the
/// library's shared-layer example and is recorded as such in the decision doc.
Widget sistrumRendererSurface({
  required double borderRadius,
  required bool dark,
  required Widget child,
}) {
  return lgr.LiquidGlass.auto(
    shape: lgr.LiquidRoundedSuperellipse(borderRadius: borderRadius),
    settings: sistrumRendererGlassSettings(dark: dark),
    child: child,
  );
}
