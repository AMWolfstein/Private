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

  /// Standalone `GlassQuality.premium` glass, each surface on its own layer
  /// with the Apple Podcasts demo's mini-player settings (see
  /// `sistrum_glass_surface.dart`).
  referenceGlass('Reference Glass'),

  /// `liquid_glass_renderer` 1.0.0-dev.2 (developer comparison only): one
  /// `LiquidGlassLayer` for the region, `LiquidGlass` shapes on top of it.
  /// Needs Flutter GPU, enabled in the profile build type only.
  rendererGlass('New renderer (liquid_glass_renderer)');

  const SistrumGlassMode(this.label);

  final String label;

  /// Whether this mode renders through the liquid glass package.
  bool get usesLiquidGlass =>
      this == SistrumGlassMode.liquidGlass ||
      this == SistrumGlassMode.referenceGlass;

  /// Whether this mode renders its surfaces through one shared layer of the
  /// widgets package.
  bool get usesSharedLayer => this == SistrumGlassMode.liquidGlass;

  /// Whether this mode renders through `liquid_glass_renderer`.
  bool get usesRenderer => this == SistrumGlassMode.rendererGlass;
}
