/// Rendering modes for the developer-only Glass POC.
///
/// Only [SistrumGlassSurface] and [SistrumGlassScope] read these. Production
/// screens never reference the mode; it is selected on the Developer Options
/// Glass POC page and reported by the performance HUD.
enum SistrumGlassMode {
  /// Translucent tint only. No blur, no backdrop sampling, no shader.
  transparentBaseline('Transparent Baseline'),

  /// Flutter's built-in `BackdropFilter` blur under the same tint.
  basicBlur('Basic Blur'),

  /// The package's shared `LiquidGlassLayer` with its default settings.
  liquidGlass('Liquid Glass'),

  /// The package's shared layer with the Apple Podcasts demo settings, at
  /// `GlassQuality.premium` (see `sistrum_glass_surface.dart`).
  referenceGlass('Reference Glass');

  const SistrumGlassMode(this.label);

  final String label;

  /// Whether this mode renders through the liquid glass package.
  bool get usesLiquidGlass =>
      this == SistrumGlassMode.liquidGlass ||
      this == SistrumGlassMode.referenceGlass;
}
