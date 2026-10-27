import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/models/sistrum_glass.dart';
import 'package:sistrum/services/sistrum_glass_auto_probe.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/providers/theme_provider.dart';

/// True on low-end hardware (arm32-only or low-RAM, resolved at startup in
/// main.dart via a ProviderScope override). UI uses it to skip expensive
/// effects like the shell's backdrop blur.
final lowEndDeviceProvider = Provider<bool>((ref) => false);

/// Whether the GPU supports the higher blur budget and animated artwork /
/// lyric defocus, and full liquid glass under `auto`. Overridden in main.dart.
final deviceSupportsLiquidGlassProvider = Provider<bool>((ref) => true);

/// The Appearance glass quality choice.
final sistrumGlassQualityProvider = Provider<SistrumGlassQuality>(
  (ref) => sistrumGlassQualityFromString(
    ref.watch(settingsProvider.select((s) => s.glassQuality)),
  ),
);

/// Flutter also reports Android's medium contrast as high contrast. Respect
/// that request only while the device picks the glass quality; an explicit
/// choice is used as is. This only controls decorative surfaces, never the
/// inherited text or reduced-motion settings.
final sistrumGlassContrastBlockedProvider = Provider.family<bool, bool>(
  (ref, highContrast) =>
      highContrast &&
      ref.watch(sistrumGlassQualityProvider) == SistrumGlassQuality.auto,
);

/// How much of Sistrum's glass the device renders.
enum SistrumGlassLevel {
  /// Opaque surfaces; no backdrop sampling.
  flat,

  /// LiquidGlassLite: frost, tint and rim over one backdrop blur; no shader.
  lite,

  /// Impeller backdrop refraction, with a lite fallback on other renderers.
  liquid,
}

/// What `auto` picks for a device class.
SistrumGlassLevel sistrumAutoGlassLevel({
  required bool lowEnd,
  required bool liquidCapable,
}) => lowEnd
    ? SistrumGlassLevel.flat
    : liquidCapable
    ? SistrumGlassLevel.liquid
    : SistrumGlassLevel.lite;

/// The device-class choice, before any measurement.
final sistrumAutoDeviceGlassLevelProvider = Provider<SistrumGlassLevel>(
  (ref) => sistrumAutoGlassLevel(
    lowEnd: ref.watch(lowEndDeviceProvider),
    liquidCapable: ref.watch(deviceSupportsLiquidGlassProvider),
  ),
);

/// The saved Auto measurement for this build, loaded in main.dart.
final initialGlassAutoResultProvider = Provider<SistrumGlassAutoResult?>(
  (ref) => null,
);

/// Auto's measured step-down. Written by SistrumGlassAutoProbeHost; cleared
/// from the developer options to measure again.
class SistrumGlassAutoResultNotifier extends Notifier<SistrumGlassAutoResult?> {
  @override
  SistrumGlassAutoResult? build() => ref.watch(initialGlassAutoResultProvider);

  void record(SistrumGlassAutoResult result) {
    state = result;
    saveGlassAutoResult(result);
  }

  void clear() {
    state = null;
    saveGlassAutoResult(null);
  }
}

final sistrumGlassAutoResultProvider =
    NotifierProvider<SistrumGlassAutoResultNotifier, SistrumGlassAutoResult?>(
      SistrumGlassAutoResultNotifier.new,
    );

/// The step Auto renders (and measures) now: the measured one, else the
/// device class's own.
final sistrumGlassAutoStepProvider = Provider<SistrumGlassAutoStep>((ref) {
  final measured = ref.watch(sistrumGlassAutoResultProvider)?.step;
  if (measured != null) return measured;
  return ref.watch(sistrumAutoDeviceGlassLevelProvider) ==
          SistrumGlassLevel.liquid
      ? SistrumGlassAutoStep.full
      : SistrumGlassAutoStep.lite;
});

/// How Auto arrived at its level, for the HUD and Appearance.
enum SistrumGlassAutoStatus {
  /// Not Auto, or Auto without glass (low-end or high contrast).
  device,

  /// Auto is sampling raster times now.
  measuring,

  /// Auto uses a measured step for this build.
  measured,
}

final sistrumGlassAutoStatusProvider =
    Provider.family<SistrumGlassAutoStatus, bool>((ref, highContrast) {
      if (ref.watch(sistrumGlassQualityProvider) != SistrumGlassQuality.auto ||
          ref.watch(sistrumGlassContrastBlockedProvider(highContrast)) ||
          ref.watch(sistrumAutoDeviceGlassLevelProvider) ==
              SistrumGlassLevel.flat) {
        return SistrumGlassAutoStatus.device;
      }
      return ref.watch(sistrumGlassAutoResultProvider)?.done ?? false
          ? SistrumGlassAutoStatus.measured
          : SistrumGlassAutoStatus.measuring;
    });

final sistrumGlassLevelProvider = Provider<SistrumGlassLevel>((ref) {
  return switch (ref.watch(sistrumGlassQualityProvider)) {
    SistrumGlassQuality.auto =>
      ref.watch(sistrumAutoDeviceGlassLevelProvider) == SistrumGlassLevel.flat
          ? SistrumGlassLevel.flat
          : ref.watch(sistrumGlassAutoStepProvider) == SistrumGlassAutoStep.full
          ? ref.watch(sistrumAutoDeviceGlassLevelProvider)
          : SistrumGlassLevel.lite,
    SistrumGlassQuality.lite => SistrumGlassLevel.lite,
    SistrumGlassQuality.full => SistrumGlassLevel.liquid,
    SistrumGlassQuality.off => SistrumGlassLevel.flat,
  };
});

/// Whether the renderer supports backdrop shader filters (Impeller). Glass
/// lenses need them; widget tests override this to exercise the glass path.
final sistrumShaderFiltersSupportedProvider = Provider<bool>(
  (ref) => ui.ImageFilter.isShaderFilterSupported,
);

/// Backdrop blur for Sistrum surfaces (frosted or liquid).
final sistrumBlurEnabledProvider = Provider<bool>(
  (ref) => ref.watch(sistrumGlassLevelProvider) != SistrumGlassLevel.flat,
);

/// Higher-quality glass and continuously filtered artwork / lyric effects.
final sistrumLiquidGlassProvider = Provider<bool>(
  (ref) => ref.watch(sistrumGlassLevelProvider) == SistrumGlassLevel.liquid,
);

/// Glass preferences stay out of ThemeData, so changing them repaints glass
/// surfaces without rebuilding the app theme.
///
/// The level glass renders at: the saved one, or Level 1 where Auto measured
/// that this device needs it. Appearance edits the saved value.
final sistrumGlassClarityLevelProvider = Provider<int>((ref) {
  final autoFrosted =
      ref.watch(sistrumGlassQualityProvider) == SistrumGlassQuality.auto &&
      ref.watch(sistrumAutoDeviceGlassLevelProvider) != SistrumGlassLevel.flat &&
      ref.watch(sistrumGlassAutoStepProvider) == SistrumGlassAutoStep.liteFrosted;
  return autoFrosted
      ? 1
      : ref.watch(settingsProvider.select((s) => s.glassClarityLevel));
});

/// Developer A/B switches, only while the developer options are shown.
final sistrumBarSamplerDisabledProvider = Provider<bool>(
  (ref) => ref.watch(
    settingsProvider.select(
      (s) => s.developerOptionsUnlocked && s.barSamplerDisabled,
    ),
  ),
);

final sistrumHeaderBandBlurDisabledProvider = Provider<bool>(
  (ref) => ref.watch(
    settingsProvider.select(
      (s) => s.developerOptionsUnlocked && s.headerBandBlurDisabled,
    ),
  ),
);

final sistrumGlassOutlinesProvider = Provider<bool>(
  (ref) => ref.watch(themeProvider.select((s) => s.sistrumGlassOutlines)),
);
