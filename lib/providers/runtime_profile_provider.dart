import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/core/models/settings.dart';
import 'package:sistrum/providers/settings/settings_provider.dart';
import 'package:sistrum/providers/settings/theme_provider.dart';

/// True on low-end hardware (arm32-only or low-RAM, resolved at startup in
/// main.dart via a ProviderScope override). Low-end devices draw opaque
/// surfaces and skip the blur.
final lowEndDeviceProvider = Provider<bool>((ref) => false);

/// How much of Sistrum's glass the device renders.
enum AppGlassLevel {
  /// Opaque surfaces; no backdrop sampling.
  flat,

  /// Tinted Lite: blur, tint and rim over one backdrop blur. The only glass
  /// look Sistrum draws.
  tinted,
}

/// Flutter also reports Android's medium contrast as high contrast. Glass
/// stays opaque under high contrast so text keeps its contrast.
final appGlassContrastBlockedProvider = Provider.family<bool, bool>(
  (ref, highContrast) => highContrast,
);

/// The glass level: Tinted Lite everywhere, opaque on low-end devices.
final appGlassLevelProvider = Provider<AppGlassLevel>((ref) {
  return ref.watch(lowEndDeviceProvider)
      ? AppGlassLevel.flat
      : AppGlassLevel.tinted;
});

/// The fixed clarity every glass surface renders at. The stored value is
/// ignored, so Tinted Lite looks the same on every device.
final appGlassClarityLevelProvider = Provider<int>(
  (ref) => kDefaultGlassClarityLevel,
);

/// Whether the renderer supports backdrop shader filters (Impeller). Widget
/// tests override this when they need the shader path.
final appShaderFiltersSupportedProvider = Provider<bool>(
  (ref) => ui.ImageFilter.isShaderFilterSupported,
);

/// Backdrop blur for Sistrum surfaces.
final appBlurEnabledProvider = Provider<bool>(
  (ref) => ref.watch(appGlassLevelProvider) != AppGlassLevel.flat,
);

/// Developer A/B switches, only while the developer options are shown.
final appBarSamplerDisabledProvider = Provider<bool>(
  (ref) => ref.watch(
    settingsProvider.select(
      (s) => s.developerOptionsUnlocked && s.barSamplerDisabled,
    ),
  ),
);

final appHeaderBandBlurDisabledProvider = Provider<bool>(
  (ref) => ref.watch(
    settingsProvider.select(
      (s) => s.developerOptionsUnlocked && s.headerBandBlurDisabled,
    ),
  ),
);

final appGlassOutlinesProvider = Provider<bool>(
  (ref) => ref.watch(themeProvider.select((s) => s.appGlassOutlines)),
);
