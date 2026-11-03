import 'package:flutter/foundation.dart';

/// The one glass look Sistrum draws: Tinted Lite.
///
/// Every glass number lives here, so the look can be retuned in one place.
/// Blur never drops below sigma 6: on Impeller a smaller sigma blurs at a
/// higher resolution and costs more.
@immutable
class AppGlassStyle {
  const AppGlassStyle({
    required this.tint,
    required this.blurSigma,
    required this.clearFill,
    required this.menuOpacity,
    required this.barFill,
  });

  /// Opacity of the surface-colour veil laid over the glass fill.
  final double tint;

  /// Backdrop blur of glass surfaces and of the header backing band.
  final double blurSigma;

  /// How far the glass fill moves from the tinted fill to the clear one.
  final double clearFill;

  /// Tint opacity of dark context menus.
  final double menuOpacity;

  /// Multiplier on the light bottom-bar tint while its palette follows the
  /// sampled backdrop.
  final double barFill;
}

const kAppGlassStyle = AppGlassStyle(
  tint: 0.15,
  blurSigma: 6,
  clearFill: 0.53,
  menuOpacity: 0.68,
  barFill: 0.64,
);
