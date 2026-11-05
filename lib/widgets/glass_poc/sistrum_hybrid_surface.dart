import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_hybrid_config.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_lens_glass.dart';

/// Sistrum Hybrid surface for one tier. The geometry (box and corner) is set
/// by the caller; this widget supplies only the material.
///
/// Foreground content is drawn above the material, so it stays sharp in every
/// tier: a `BackdropFilter` blurs only what is painted beneath it.
class SistrumHybridSurface extends StatelessWidget {
  const SistrumHybridSurface({
    required this.config,
    required this.dark,
    required this.borderRadius,
    required this.child,
    super.key,
  });

  final SistrumHybridConfig config;
  final bool dark;
  final double borderRadius;
  final Widget child;

  /// Tint colour per theme: near-black in dark, near-white in light. These are
  /// the same colours as the other POC modes, at the configured opacity.
  Color get _tint => (dark ? const Color(0xFF121212) : const Color(0xFFFAFAFA))
      .withValues(alpha: config.tintOpacity);

  /// Hairline edge, a little brighter in dark theme.
  Color get _edge => dark
      ? Colors.white.withValues(alpha: 0.10)
      : Colors.black.withValues(alpha: 0.08);

  /// Directional light from the top-left edge. It is only a gradient, not a
  /// refraction, and it sits above the tint.
  Gradient get _highlight => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.center,
    colors: [
      Colors.white.withValues(alpha: dark ? 0.14 : 0.45),
      Colors.white.withValues(alpha: 0),
    ],
  );

  BoxDecoration get _decoration => BoxDecoration(
    color: _tint,
    gradient: _highlight,
    borderRadius: BorderRadius.circular(borderRadius),
    border: Border.all(color: _edge, width: 0.5),
  );

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    switch (config.tier) {
      case SistrumHybridTier.lightweight:
        // No backdrop read at all: only the material is drawn.
        return ClipRRect(
          borderRadius: radius,
          child: DecoratedBox(decoration: _decoration, child: child),
        );
      case SistrumHybridTier.frosted:
        return ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: config.blurSigma,
              sigmaY: config.blurSigma,
            ),
            child: DecoratedBox(decoration: _decoration, child: child),
          ),
        );
      case SistrumHybridTier.full:
        // First-party lens: blur, then the Sistrum shader (no package).
        return SistrumLensGlass(
          blurSigma: config.blurSigma,
          refraction: config.refraction,
          chromatic: config.chromaticAberration,
          borderRadius: borderRadius,
          child: DecoratedBox(decoration: _decoration, child: child),
        );
    }
  }
}
