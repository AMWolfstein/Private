/// How Sistrum glass is rendered, as chosen in Appearance.
enum SistrumGlassQuality {
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

SistrumGlassQuality sistrumGlassQualityFromString(String? value) =>
    SistrumGlassQuality.values.firstWhere(
      (quality) => quality.name == value,
      orElse: () => SistrumGlassQuality.auto,
    );
