/// How Sistrum glass is rendered, as chosen in Appearance.
enum AppGlassQuality {
  /// The device decides: full on liquid-capable hardware, lite on other
  /// standard devices, off on low-end ones.
  auto,

  /// LiquidGlassLite everywhere: frost, tint and rim, no shader.
  lite,

  /// Liquid-glass lenses.
  full,

  /// Opaque surfaces, no backdrop reads.
  off,
}

AppGlassQuality appGlassQualityFromString(String? value) =>
    AppGlassQuality.values.firstWhere(
      (quality) => quality.name == value,
      orElse: () => AppGlassQuality.auto,
    );
