import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_mode.dart';

/// Blur radius for [SistrumGlassMode.basicBlur]. A single Flutter blur, not a
/// second custom implementation.
const double kSistrumGlassBasicBlurSigma = 12;

/// Translucent tint shared by the baseline and basic blur modes: black at 45%
/// in dark, white at 55% in light (AGENTS.md header tint).
Color sistrumGlassTint({required bool dark}) =>
    dark ? const Color(0x73000000) : const Color(0x8CFFFFFF);

/// Reference settings: the Apple Podcasts demo's bottom bar configuration
/// (`example/lib/apple_podcasts/apple_podcasts_demo.dart`, `GlassBottomBar`
/// `settings:`), copied field-for-field. Fields not listed keep the package
/// defaults. `chromaticAberration`, `lightAngle` and `specularSharpness` come
/// from the demo as written.
LiquidGlassSettings sistrumReferenceGlassSettings({required bool dark}) {
  return LiquidGlassSettings(
    glassColor: dark ? const Color(0xAA1C1C1E) : const Color(0xAAF2F2F7),
    thickness: 24,
    blur: 3,
    chromaticAberration: .01,
    lightAngle: GlassDefaults.lightAngle,
    lightIntensity: 0.2,
    ambientStrength: 0,
    refractiveIndex: 1.2,
    fresnelStrength: 0.0,
    saturation: 1.2,
    specularSharpness: GlassSpecularSharpness.medium,
  );
}

/// Settings for the one shared [LiquidGlassLayer] of a glass mode. Returns
/// null for modes that do not use the package.
LiquidGlassSettings? sistrumGlassLayerSettings(
  SistrumGlassMode mode, {
  required bool dark,
}) {
  return switch (mode) {
    SistrumGlassMode.referenceGlass => sistrumReferenceGlassSettings(
      dark: dark,
    ),
    SistrumGlassMode.liquidGlass => const LiquidGlassSettings(),
    SistrumGlassMode.transparentBaseline || SistrumGlassMode.basicBlur => null,
  };
}

/// Owns the single rendering layer for a region of glass surfaces.
///
/// Glass modes wrap [child] in one shared [LiquidGlassLayer], so every
/// [SistrumGlassSurface] inside it renders into the same layer. Other modes
/// return [child] unchanged, so no package layer or shader exists while they
/// are shown. The layer and its shader go away when the mode changes.
///
/// Put the background under the surfaces inside [child]: the layer samples
/// what is painted beneath the glass within it.
class SistrumGlassScope extends StatelessWidget {
  const SistrumGlassScope({required this.mode, required this.child, super.key});

  final SistrumGlassMode mode;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!mode.usesLiquidGlass) return child;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return LiquidGlassLayer(
      settings: sistrumGlassLayerSettings(mode, dark: dark)!,
      child: child,
    );
  }
}

/// A translucent or glass surface whose mode is set by the Glass POC.
///
/// The geometry is identical in every mode: a [width] by [height] box with a
/// [borderRadius] corner (use `height / 2` for a circle or capsule). Only the
/// material changes, so modes can be compared on the same layout.
class SistrumGlassSurface extends StatelessWidget {
  const SistrumGlassSurface({
    required this.mode,
    required this.child,
    required this.width,
    required this.height,
    required this.borderRadius,
    super.key,
  });

  final SistrumGlassMode mode;
  final Widget child;
  final double width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(borderRadius);

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
        shape: LiquidRoundedSuperellipse(borderRadius: borderRadius),
        quality: GlassQuality.standard,
        child: child,
      ),
      SistrumGlassMode.referenceGlass => GlassContainer(
        shape: LiquidRoundedSuperellipse(borderRadius: borderRadius),
        quality: GlassQuality.premium,
        child: child,
      ),
    };

    return SizedBox(width: width, height: height, child: surface);
  }
}
