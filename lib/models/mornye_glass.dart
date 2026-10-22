/// How Mornye glass is rendered, as chosen in Appearance.
enum MornyeGlassQuality {
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

MornyeGlassQuality mornyeGlassQualityFromString(String? value) =>
    MornyeGlassQuality.values.firstWhere(
      (quality) => quality.name == value,
      orElse: () => MornyeGlassQuality.auto,
    );

/// Pre-levels clarity preference (a 0–1 double in theme preferences).
const String kLegacyGlassClarityKey = 'mornye_glass_clarity';

/// Pre-quality "Always use blur effects" field of the app settings JSON.
const String kLegacyForceBackdropBlurKey = 'forceBackdropBlur';

/// Maps the retired clarity double and blur override onto quality + level.
///
/// A clarity at or below 0.2 meant opaque glass, so it becomes [off] and
/// keeps the default level for when glass is turned back on; that wins over
/// a forced blur. A missing clarity keeps the default level.
({MornyeGlassQuality quality, int level}) mapLegacyGlassPreferences({
  num? clarity,
  bool? forceBackdropBlur,
}) {
  final value = clarity != null && clarity.isFinite ? clarity : null;
  if (value != null && value <= 0.2) {
    return (quality: MornyeGlassQuality.off, level: 3);
  }
  final level = value == null
      ? 3
      : value <= 0.35
      ? 1
      : value <= 0.55
      ? 2
      : value <= 0.7
      ? 3
      : value < 0.9
      ? 4
      : 5;
  return (
    quality: forceBackdropBlur == true
        ? MornyeGlassQuality.full
        : MornyeGlassQuality.auto,
    level: level,
  );
}
