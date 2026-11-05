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

  /// `liquid_glass_widgets` 1.16.1 shared `LiquidGlassLayer` with its default
  /// settings. The package's own implementation, unchanged.
  liquidGlass('Old Liquid Glass'),

  /// Standalone `GlassQuality.premium` glass, each surface on its own layer
  /// with the Apple Podcasts demo's mini-player settings (see
  /// `sistrum_glass_surface.dart`).
  referenceGlass('Reference Glass'),

  /// `liquid_glass_renderer` with `fake: false` on each surface's own layer.
  /// Full Glass needs Flutter GPU; the package may fall back to FakeGlass,
  /// which the render-path probe reports (see `sistrum_glass_render_path.dart`).
  newFullGlass('New Full Glass'),

  /// `liquid_glass_renderer` with `fake: true` on each surface's own layer.
  /// FakeGlass by request, never Full Glass.
  newFakeGlass('New FakeGlass'),

  /// Same optics and independent layers as Full Glass; safe surfaces reuse
  /// backdrop inputs, assigned by the developer scene in paint order.
  newFullGlassSharedBackdrop('New Full Glass — Shared Backdrop');

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
  bool get usesRenderer =>
      this == SistrumGlassMode.newFullGlass ||
      this == SistrumGlassMode.newFullGlassSharedBackdrop ||
      this == SistrumGlassMode.newFakeGlass;

  /// Whether the renderer is asked for FakeGlass (`fake: true`).
  bool get rendererFake => this == SistrumGlassMode.newFakeGlass;
}
