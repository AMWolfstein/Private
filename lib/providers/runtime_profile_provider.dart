import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/models/mornye_glass.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/providers/theme_provider.dart';

/// True on low-end hardware (arm32-only or low-RAM, resolved at startup in
/// main.dart via a ProviderScope override). UI uses it to skip expensive
/// effects like the shell's backdrop blur.
final lowEndDeviceProvider = Provider<bool>((ref) => false);

/// Whether the GPU supports the higher blur budget and animated artwork /
/// lyric defocus, and full liquid glass under `auto`. Overridden in main.dart.
final deviceSupportsLiquidGlassProvider = Provider<bool>((ref) => true);

/// The Appearance glass quality choice.
final mornyeGlassQualityProvider = Provider<MornyeGlassQuality>(
  (ref) => mornyeGlassQualityFromString(
    ref.watch(settingsProvider.select((s) => s.glassQuality)),
  ),
);

/// Flutter also reports Android's medium contrast as high contrast. Respect
/// that request only while the device picks the glass quality; an explicit
/// choice is used as is. This only controls decorative surfaces, never the
/// inherited text or reduced-motion settings.
final mornyeGlassContrastBlockedProvider = Provider.family<bool, bool>(
  (ref, highContrast) =>
      highContrast &&
      ref.watch(mornyeGlassQualityProvider) == MornyeGlassQuality.auto,
);

/// How much of Mornye's glass the device renders.
enum MornyeGlassLevel {
  /// Opaque surfaces; no backdrop sampling.
  flat,

  /// LiquidGlassLite: frost, tint and rim over one backdrop blur; no shader.
  lite,

  /// Impeller backdrop refraction, with a lite fallback on other renderers.
  liquid,
}

/// What `auto` picks for a device class.
MornyeGlassLevel mornyeAutoGlassLevel({
  required bool lowEnd,
  required bool liquidCapable,
}) => lowEnd
    ? MornyeGlassLevel.flat
    : liquidCapable
    ? MornyeGlassLevel.liquid
    : MornyeGlassLevel.lite;

final mornyeGlassLevelProvider = Provider<MornyeGlassLevel>((ref) {
  return switch (ref.watch(mornyeGlassQualityProvider)) {
    MornyeGlassQuality.auto => mornyeAutoGlassLevel(
      lowEnd: ref.watch(lowEndDeviceProvider),
      liquidCapable: ref.watch(deviceSupportsLiquidGlassProvider),
    ),
    MornyeGlassQuality.lite => MornyeGlassLevel.lite,
    MornyeGlassQuality.full => MornyeGlassLevel.liquid,
    MornyeGlassQuality.off => MornyeGlassLevel.flat,
  };
});

/// Whether the renderer supports backdrop shader filters (Impeller). Glass
/// lenses need them; widget tests override this to exercise the glass path.
final mornyeShaderFiltersSupportedProvider = Provider<bool>(
  (ref) => ui.ImageFilter.isShaderFilterSupported,
);

/// Backdrop blur for Mornye surfaces (frosted or liquid).
final mornyeBlurEnabledProvider = Provider<bool>(
  (ref) => ref.watch(mornyeGlassLevelProvider) != MornyeGlassLevel.flat,
);

/// Higher-quality glass and continuously filtered artwork / lyric effects.
final mornyeLiquidGlassProvider = Provider<bool>(
  (ref) => ref.watch(mornyeGlassLevelProvider) == MornyeGlassLevel.liquid,
);

/// Glass preferences stay out of ThemeData, so changing them repaints glass
/// surfaces without rebuilding the app theme.
final mornyeGlassClarityLevelProvider = Provider<int>(
  (ref) => ref.watch(settingsProvider.select((s) => s.glassClarityLevel)),
);

final mornyeGlassOutlinesProvider = Provider<bool>(
  (ref) => ref.watch(themeProvider.select((s) => s.mornyeGlassOutlines)),
);
