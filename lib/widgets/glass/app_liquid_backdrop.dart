import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/widgets/glass/app_backdrop_groups.dart';

/// A bounded package lens without a captured-screen view or a touch ticker.
class AppLiquidBackdrop extends ConsumerWidget {
  const AppLiquidBackdrop({
    super.key,
    required this.borderRadius,
    required this.dispersion,
    required this.blurSigma,
    required this.child,
    this.interaction = false,
    this.progress = 1,
    this.refractionDepth = 0.30,
    this.refractionWidth = 20,
    this.smoothCorners = false,
    this.highlightIntensity = 1,
  });

  final BorderRadius borderRadius;

  /// Widest colour split in logical pixels (the clarity level's value).
  final double dispersion;
  final double blurSigma;
  final Widget child;
  final bool interaction;
  final double progress;
  final double refractionDepth;
  final double refractionWidth;
  final bool smoothCorners;
  final double highlightIntensity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (interaction && progress <= 0) return child;
    final effect = interaction ? progress : 1.0;
    final outlines = ref.watch(appGlassOutlinesProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Match the old optical lens's edge displacement. Version 5 fixes travel
    // at 70 logical pixels and controls bending through the index alone.
    final edgeBend =
        math.sqrt(1 - 1 / (1.7 * 1.7)) *
        refractionWidth *
        refractionDepth *
        effect *
        5 /
        70;
    final index = 1 / math.sqrt(1 - math.pow(edgeBend.clamp(0, 0.95), 2));
    final lens = LiquidGlassLens(
      style: LiquidGlassStyle(
        shape: appGlassShape(
          radius: borderRadius.topLeft.x,
          smoothCorners: smoothCorners,
        ),
        specular: appGlassSpecular(
          outlines: outlines,
          dark: dark,
          intensity: effect * highlightIntensity,
        ),
        glow: appGlassGlow(
          outlines: outlines,
          intensity: highlightIntensity,
        ),
        blur: blurSigma,
        refractionIndex: index,
        refractionWidth: refractionWidth,
        // Version 5 expresses the widest colour split in logical pixels.
        dispersion: dispersion * effect,
      ),
      child: child,
    );
    // The lens's shader layer is private; the marker lets the performance
    // HUD count its read. A batched lens takes the batch's key.
    return AppBackdropReadMarker(
      backdropId: ui.ImageFilter.isShaderFilterSupported
          ? LiquidGlassBatch.backdropIdOf(context)
          : null,
      child: lens,
    );
  }
}

/// The outline Sistrum lenses and lite rims share.
LiquidGlassShape appGlassShape({
  required double radius,
  required bool smoothCorners,
}) => LiquidGlassShape(
  cornerStyle: smoothCorners
      ? LiquidGlassCornerStyle.squircle
      : LiquidGlassCornerStyle.roundedRectangle,
  clipQuality: smoothCorners
      ? LiquidGlassClipQuality.exact
      : LiquidGlassClipQuality.roundedRectangle,
  cornerRadius: radius,
);

/// The rim highlight: on a lens it is the shader's specular, on lite glass
/// LiquidGlassLite paints the same band. Outlines off draws none.
LiquidGlassLight appGlassSpecular({
  required bool outlines,
  required bool dark,
  double intensity = 1,
}) => LiquidGlassLight.specular(
  thickness: outlines ? 0.75 * 5.4 : 0,
  angle: 0,
  spread: 0.2,
  intensity: outlines ? (dark ? 0.25 : 0.12) * intensity : 0,
  color: dark ? Colors.white : const Color(0x88ffffff),
);

LiquidGlassLight appGlassGlow({
  required bool outlines,
  double intensity = 1,
}) => LiquidGlassLight.glow(
  thickness: outlines ? 0.75 * 29.4 : 0,
  intensity: outlines ? 0.05 * intensity : 0,
);
