import 'package:flutter/foundation.dart';

/// One stop of the Appearance glass clarity slider.
///
/// Every clarity-dependent number lives in [kMornyeGlassLevels], so the look
/// can be retuned without a preference migration: only the level index is
/// stored.
@immutable
class MornyeGlassClarity {
  const MornyeGlassClarity({
    required this.level,
    required this.tint,
    required this.blurSigma,
    required this.dispersion,
    required this.clearFill,
    required this.menuOpacity,
    required this.barFill,
  });

  /// 1 (Frosted) to 5 (Crystal).
  final int level;

  /// Opacity of the surface-colour veil laid over the glass fill.
  final double tint;

  /// Backdrop blur of glass surfaces and of the header backing band; 6 at
  /// least.
  final double blurSigma;

  /// Lens colour split in logical pixels; full glass only.
  final double dispersion;

  /// How far lens and lite fills move from the tinted fill to the clear one.
  final double clearFill;

  /// Tint opacity of dark context menus.
  final double menuOpacity;

  /// Multiplier on the light bottom-bar tint while its palette follows the
  /// sampled backdrop (it replaces the 50% white floor).
  final double barFill;

  /// Level 1 always renders as a plain backdrop blur plus tint: no lens, no
  /// lite surface and no refraction, whatever the glass quality.
  bool get plainBlur => level == 1;
}

// Level 1 Frosted · 2 Soft · 3 Balanced (default) · 4 Clear · 5 Crystal.
//
// Blur never drops below sigma 6: on Impeller a small sigma blurs at a
// higher resolution and costs more. Clear and Crystal get their transparency
// from lighter tint and fill instead.
const kMornyeGlassLevels = <MornyeGlassClarity>[
  MornyeGlassClarity(
    level: 1,
    tint: 0.50,
    blurSigma: 10,
    dispersion: 0,
    clearFill: 0,
    menuOpacity: 0.74,
    barFill: 0.88,
  ),
  MornyeGlassClarity(
    level: 2,
    tint: 0.30,
    blurSigma: 8,
    dispersion: 0,
    clearFill: 0.31,
    menuOpacity: 0.71,
    barFill: 0.70,
  ),
  MornyeGlassClarity(
    level: 3,
    tint: 0.15,
    blurSigma: 6,
    dispersion: 0.5,
    clearFill: 0.53,
    menuOpacity: 0.68,
    barFill: 0.64,
  ),
  MornyeGlassClarity(
    level: 4,
    tint: 0.04,
    blurSigma: 6,
    dispersion: 1.0,
    clearFill: 0.80,
    menuOpacity: 0.62,
    barFill: 0.54,
  ),
  MornyeGlassClarity(
    level: 5,
    tint: 0,
    blurSigma: 6,
    dispersion: 1.32,
    clearFill: 1,
    menuOpacity: 0.56,
    barFill: 0.44,
  ),
];

MornyeGlassClarity mornyeGlassClarity(int level) =>
    kMornyeGlassLevels[level.clamp(1, kMornyeGlassLevels.length) - 1];
