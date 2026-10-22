import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/models/mornye_glass.dart';
import 'package:spotiflac_android/services/mornye_glass_auto_probe.dart';
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

/// The device-class choice, before any measurement.
final mornyeAutoDeviceGlassLevelProvider = Provider<MornyeGlassLevel>(
  (ref) => mornyeAutoGlassLevel(
    lowEnd: ref.watch(lowEndDeviceProvider),
    liquidCapable: ref.watch(deviceSupportsLiquidGlassProvider),
  ),
);

/// The saved Auto measurement for this build, loaded in main.dart.
final initialGlassAutoResultProvider = Provider<MornyeGlassAutoResult?>(
  (ref) => null,
);

/// Auto's measured step-down. Written by MornyeGlassAutoProbeHost; cleared
/// from the developer options to measure again.
class MornyeGlassAutoResultNotifier extends Notifier<MornyeGlassAutoResult?> {
  @override
  MornyeGlassAutoResult? build() => ref.watch(initialGlassAutoResultProvider);

  void record(MornyeGlassAutoResult result) {
    state = result;
    saveGlassAutoResult(result);
  }

  void clear() {
    state = null;
    saveGlassAutoResult(null);
  }
}

final mornyeGlassAutoResultProvider =
    NotifierProvider<MornyeGlassAutoResultNotifier, MornyeGlassAutoResult?>(
      MornyeGlassAutoResultNotifier.new,
    );

/// The step Auto renders (and measures) now: the measured one, else the
/// device class's own.
final mornyeGlassAutoStepProvider = Provider<MornyeGlassAutoStep>((ref) {
  final measured = ref.watch(mornyeGlassAutoResultProvider)?.step;
  if (measured != null) return measured;
  return ref.watch(mornyeAutoDeviceGlassLevelProvider) ==
          MornyeGlassLevel.liquid
      ? MornyeGlassAutoStep.full
      : MornyeGlassAutoStep.lite;
});

/// How Auto arrived at its level, for the HUD and Appearance.
enum MornyeGlassAutoStatus {
  /// Not Auto, or Auto without glass (low-end or high contrast).
  device,

  /// Auto is sampling raster times now.
  measuring,

  /// Auto uses a measured step for this build.
  measured,
}

final mornyeGlassAutoStatusProvider =
    Provider.family<MornyeGlassAutoStatus, bool>((ref, highContrast) {
      if (ref.watch(mornyeGlassQualityProvider) != MornyeGlassQuality.auto ||
          ref.watch(mornyeGlassContrastBlockedProvider(highContrast)) ||
          ref.watch(mornyeAutoDeviceGlassLevelProvider) ==
              MornyeGlassLevel.flat) {
        return MornyeGlassAutoStatus.device;
      }
      return ref.watch(mornyeGlassAutoResultProvider)?.done ?? false
          ? MornyeGlassAutoStatus.measured
          : MornyeGlassAutoStatus.measuring;
    });

final mornyeGlassLevelProvider = Provider<MornyeGlassLevel>((ref) {
  return switch (ref.watch(mornyeGlassQualityProvider)) {
    MornyeGlassQuality.auto =>
      ref.watch(mornyeAutoDeviceGlassLevelProvider) == MornyeGlassLevel.flat
          ? MornyeGlassLevel.flat
          : ref.watch(mornyeGlassAutoStepProvider) == MornyeGlassAutoStep.full
          ? ref.watch(mornyeAutoDeviceGlassLevelProvider)
          : MornyeGlassLevel.lite,
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
///
/// The level glass renders at: the saved one, or Level 1 where Auto measured
/// that this device needs it. Appearance edits the saved value.
final mornyeGlassClarityLevelProvider = Provider<int>((ref) {
  final autoFrosted =
      ref.watch(mornyeGlassQualityProvider) == MornyeGlassQuality.auto &&
      ref.watch(mornyeAutoDeviceGlassLevelProvider) != MornyeGlassLevel.flat &&
      ref.watch(mornyeGlassAutoStepProvider) == MornyeGlassAutoStep.liteFrosted;
  return autoFrosted
      ? 1
      : ref.watch(settingsProvider.select((s) => s.glassClarityLevel));
});

/// Developer A/B switches, only while the developer options are shown.
final mornyeBarSamplerDisabledProvider = Provider<bool>(
  (ref) => ref.watch(
    settingsProvider.select(
      (s) => s.developerOptionsUnlocked && s.barSamplerDisabled,
    ),
  ),
);

final mornyeHeaderBandBlurDisabledProvider = Provider<bool>(
  (ref) => ref.watch(
    settingsProvider.select(
      (s) => s.developerOptionsUnlocked && s.headerBandBlurDisabled,
    ),
  ),
);

final mornyeGlassOutlinesProvider = Provider<bool>(
  (ref) => ref.watch(themeProvider.select((s) => s.mornyeGlassOutlines)),
);
