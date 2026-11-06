import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_mode.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_hybrid_config.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_hybrid_surface.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_renderer_glass.dart';

/// Blur radius for [SistrumGlassMode.basicBlur]. A single Flutter blur, not a
/// second custom implementation.
const double kSistrumGlassBasicBlurSigma = 12;

/// Translucent tint shared by the baseline and basic blur modes: black at 45%
/// in dark, white at 55% in light (AGENTS.md header tint).
Color sistrumGlassTint({required bool dark}) =>
    dark ? const Color(0x73000000) : const Color(0x8CFFFFFF);

/// Reference settings: the Apple Podcasts demo's `GlassButton.custom` mini
/// player (`example/lib/apple_podcasts/apple_podcasts_demo.dart`, the
/// `bottomAccessory` block, around lines 386-400), which is a standalone
/// surface drawn with `useOwnLayer: true` and `GlassQuality.premium`.
/// Values are copied as written; the demo's bottom bar uses a different set.
LiquidGlassSettings sistrumReferenceGlassSettings({required bool dark}) {
  return LiquidGlassSettings(
    glassColor: dark ? const Color(0xCC1C1C1E) : const Color(0xCCF2F2F7),
    thickness: 30,
    blur: 2,
    lightIntensity: 0.18,
    chromaticAberration: .01,
    saturation: 1.2,
    fresnelStrength: 0.0,
  );
}

/// Settings for the shared [LiquidGlassLayer] of a region. Only
/// [SistrumGlassMode.liquidGlass] uses a shared layer. Returns null for every
/// other mode.
LiquidGlassSettings? sistrumGlassLayerSettings(
  SistrumGlassMode mode, {
  required bool dark,
}) {
  return switch (mode) {
    SistrumGlassMode.liquidGlass => const LiquidGlassSettings(),
    SistrumGlassMode.transparentBaseline ||
    SistrumGlassMode.basicBlur ||
    SistrumGlassMode.referenceGlass ||
    SistrumGlassMode.newFullGlass ||
    SistrumGlassMode.newFullGlassSharedBackdrop ||
    SistrumGlassMode.newFakeGlass ||
    SistrumGlassMode.sistrumHybrid => null,
  };
}

/// Owns the shared [LiquidGlassLayer] for a region of Liquid Glass surfaces.
///
/// Only [SistrumGlassMode.liquidGlass] is wrapped. The other modes return
/// [child] unchanged, so no package layer exists while they are shown.
/// Reference Glass draws each surface with its own layer, as the demo does for
/// standalone glass, so it does not need this scope.
///
/// Put the background under the surfaces inside [child]: the layer samples
/// what is painted beneath the glass within it.
class SistrumGlassScope extends StatelessWidget {
  const SistrumGlassScope({
    required this.mode,
    required this.child,
    this.sharedBackdrop = false,
    super.key,
  });

  final SistrumGlassMode mode;
  final Widget child;

  /// Whether Reference Glass reads the backdrop as one group (see
  /// [sharedBackdropApplies]). Off by default; the comparison switch sets it.
  final bool sharedBackdrop;

  @override
  Widget build(BuildContext context) {
    // The renderer draws each surface on its own layer (see
    // sistrum_renderer_glass.dart), so the scope adds nothing for it.
    if (mode.usesRenderer) return child;
    if (mode.usesSharedLayer) {
      final dark = Theme.of(context).brightness == Brightness.dark;
      return LiquidGlassLayer(
        settings: sistrumGlassLayerSettings(mode, dark: dark)!,
        child: child,
      );
    }
    if (sharedBackdropApplies(mode, sharedBackdrop)) {
      return GlassBackdropGroup(child: child);
    }
    return child;
  }
}

/// Whether the shared backdrop group applies to [mode] with the switch on.
///
/// Verified in `liquid_glass_widgets` 1.16.1: `GlassBackdropGroup` shares the
/// backdrop read only for premium glass rendered through its own layer
/// (`LiquidGlassLayer` reads `GlassBackdropGroup.keyOf`). The standard
/// lightweight path, which Liquid Glass uses, never reads that key. Basic
/// Blur is a plain `BackdropFilter` of this app, not package glass, so no
/// group reaches it. Only Reference Glass can therefore use the group.
bool sharedBackdropApplies(SistrumGlassMode mode, bool sharedBackdrop) =>
    sharedBackdrop && mode == SistrumGlassMode.referenceGlass;

/// A translucent or glass surface whose mode is set by the Glass POC.
///
/// The geometry is identical in every mode: a [width] by [height] box with a
/// [borderRadius] corner (use `height / 2` for a circle or capsule). Only the
/// material changes, so modes can be compared on the same layout.
///
/// [diagnosticOutline] draws a 2 px red border over the surface. It is a
/// layout aid only. A visible outline does not show that the glass shader ran.
class SistrumGlassSurface extends StatelessWidget {
  const SistrumGlassSurface({
    required this.mode,
    required this.child,
    required this.width,
    required this.height,
    required this.borderRadius,
    this.diagnosticOutline = false,
    this.backdropKey,
    super.key,
  });

  final SistrumGlassMode mode;
  final Widget child;
  final double width;
  final double height;
  final double borderRadius;
  final bool diagnosticOutline;
  final BackdropKey? backdropKey;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(borderRadius);
    final shape = LiquidRoundedSuperellipse(borderRadius: borderRadius);

    final Widget surface = switch (mode) {
      SistrumGlassMode.transparentBaseline => ClipRRect(
        borderRadius: radius,
        child: ColoredBox(
          color: sistrumGlassTint(dark: dark),
          child: child,
        ),
      ),
      SistrumGlassMode.basicBlur => ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: kSistrumGlassBasicBlurSigma,
            sigmaY: kSistrumGlassBasicBlurSigma,
          ),
          child: ColoredBox(
            color: sistrumGlassTint(dark: dark),
            child: child,
          ),
        ),
      ),
      SistrumGlassMode.liquidGlass => GlassContainer(
        shape: shape,
        quality: GlassQuality.standard,
        child: child,
      ),
      // Standalone premium glass, as the demo's mini player: its own layer,
      // its own settings. This is the path the demo uses on its own surfaces.
      SistrumGlassMode.newFullGlass ||
      SistrumGlassMode.newFullGlassSharedBackdrop ||
      SistrumGlassMode.newFakeGlass => sistrumRendererSurface(
        borderRadius: borderRadius,
        dark: dark,
        fake: mode.rendererFake,
        backdropKey: mode == SistrumGlassMode.newFullGlassSharedBackdrop
            ? backdropKey
            : null,
        child: child,
      ),
      // The page gives Hybrid a key only when a shared read is requested and
      // safe for this surface; otherwise the key is null.
      SistrumGlassMode.sistrumHybrid => SistrumHybridSurface(
        config: SistrumHybridConfigScope.of(context),
        dark: dark,
        borderRadius: borderRadius,
        backdropKey: backdropKey,
        child: child,
      ),
      SistrumGlassMode.referenceGlass => GlassContainer(
        shape: shape,
        quality: GlassQuality.premium,
        useOwnLayer: true,
        settings: sistrumReferenceGlassSettings(dark: dark),
        child: child,
      ),
    };

    return SizedBox(
      width: width,
      height: height,
      child: diagnosticOutline
          ? DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: const Color(0xFFFF2D2D), width: 2),
              ),
              child: surface,
            )
          : surface,
    );
  }
}
