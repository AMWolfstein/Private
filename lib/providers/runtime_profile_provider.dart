import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/core/models/app_glass.dart';
import 'package:sistrum/services/glass/app_glass_auto_probe.dart';
import 'package:sistrum/providers/settings/settings_provider.dart';
import 'package:sistrum/providers/settings/theme_provider.dart';

/// True on low-end hardware (arm32-only or low-RAM, resolved at startup in
/// main.dart via a ProviderScope override). UI uses it to skip expensive
/// effects like the shell's backdrop blur.
final lowEndDeviceProvider = Provider<bool>((ref) => false);

/// Whether the GPU supports the higher blur budget and animated artwork /
/// lyric defocus, and full liquid glass under `auto`. Overridden in main.dart.
final deviceSupportsLiquidGlassProvider = Provider<bool>((ref) => true);

/// The Appearance glass quality choice.
final appGlassQualityProvider = Provider<AppGlassQuality>(
  (ref) => appGlassQualityFromString(
    ref.watch(settingsProvider.select((s) => s.glassQuality)),
  ),
);

/// Flutter also reports Android's medium contrast as high contrast. Respect
/// that request only while the device picks the glass quality; an explicit
/// choice is used as is. This only controls decorative surfaces, never the
/// inherited text or reduced-motion settings.
final appGlassContrastBlockedProvider = Provider.family<bool, bool>(
  (ref, highContrast) =>
      highContrast &&
      ref.watch(appGlassQualityProvider) == AppGlassQuality.auto,
);

/// How much of Sistrum's glass the device renders.
enum AppGlassLevel {
  /// Opaque surfaces; no backdrop sampling.
  flat,

  /// LiquidGlassLite: frost, tint and rim over one backdrop blur; no shader.
  lite,

  /// Impeller backdrop refraction, with a lite fallback on other renderers.
  liquid,
}

/// What `auto` picks for a device class.
AppGlassLevel appAutoGlassLevel({
  required bool lowEnd,
  required bool liquidCapable,
}) => lowEnd
    ? AppGlassLevel.flat
    : liquidCapable
    ? AppGlassLevel.liquid
    : AppGlassLevel.lite;

/// The device-class choice, before any measurement.
final appAutoDeviceGlassLevelProvider = Provider<AppGlassLevel>(
  (ref) => appAutoGlassLevel(
    lowEnd: ref.watch(lowEndDeviceProvider),
    liquidCapable: ref.watch(deviceSupportsLiquidGlassProvider),
  ),
);

/// The saved Auto measurement for this build, loaded in main.dart.
final initialGlassAutoResultProvider = Provider<AppGlassAutoResult?>(
  (ref) => null,
);

/// Auto's measured step-down. Written by AppGlassAutoProbeHost; cleared
/// from the developer options to measure again.
class AppGlassAutoResultNotifier extends Notifier<AppGlassAutoResult?> {
  @override
  AppGlassAutoResult? build() => ref.watch(initialGlassAutoResultProvider);

  void record(AppGlassAutoResult result) {
    state = result;
    saveGlassAutoResult(result);
  }

  void clear() {
    state = null;
    saveGlassAutoResult(null);
  }
}

final appGlassAutoResultProvider =
    NotifierProvider<AppGlassAutoResultNotifier, AppGlassAutoResult?>(
      AppGlassAutoResultNotifier.new,
    );

/// The step Auto renders (and measures) now: the measured one, else the
/// device class's own.
final appGlassAutoStepProvider = Provider<AppGlassAutoStep>((ref) {
  final measured = ref.watch(appGlassAutoResultProvider)?.step;
  if (measured != null) return measured;
  return ref.watch(appAutoDeviceGlassLevelProvider) == AppGlassLevel.liquid
      ? AppGlassAutoStep.full
      : AppGlassAutoStep.lite;
});

/// How Auto arrived at its level, for the HUD and Appearance.
enum AppGlassAutoStatus {
  /// Not Auto, or Auto without glass (low-end or high contrast).
  device,

  /// Auto is sampling raster times now.
  measuring,

  /// Auto uses a measured step for this build.
  measured,
}

final appGlassAutoStatusProvider = Provider.family<AppGlassAutoStatus, bool>((
  ref,
  highContrast,
) {
  if (ref.watch(appGlassQualityProvider) != AppGlassQuality.auto ||
      ref.watch(appGlassContrastBlockedProvider(highContrast)) ||
      ref.watch(appAutoDeviceGlassLevelProvider) == AppGlassLevel.flat) {
    return AppGlassAutoStatus.device;
  }
  return ref.watch(appGlassAutoResultProvider)?.done ?? false
      ? AppGlassAutoStatus.measured
      : AppGlassAutoStatus.measuring;
});

final appGlassLevelProvider = Provider<AppGlassLevel>((ref) {
  return switch (ref.watch(appGlassQualityProvider)) {
    AppGlassQuality.auto =>
      ref.watch(appAutoDeviceGlassLevelProvider) == AppGlassLevel.flat
          ? AppGlassLevel.flat
          : ref.watch(appGlassAutoStepProvider) == AppGlassAutoStep.full
          ? ref.watch(appAutoDeviceGlassLevelProvider)
          : AppGlassLevel.lite,
    AppGlassQuality.lite => AppGlassLevel.lite,
    AppGlassQuality.full => AppGlassLevel.liquid,
    AppGlassQuality.off => AppGlassLevel.flat,
  };
});

/// Whether the renderer supports backdrop shader filters (Impeller). Glass
/// lenses need them; widget tests override this to exercise the glass path.
final appShaderFiltersSupportedProvider = Provider<bool>(
  (ref) => ui.ImageFilter.isShaderFilterSupported,
);

/// Backdrop blur for Sistrum surfaces (frosted or liquid).
final appBlurEnabledProvider = Provider<bool>(
  (ref) => ref.watch(appGlassLevelProvider) != AppGlassLevel.flat,
);

/// Higher-quality glass and continuously filtered artwork / lyric effects.
final appLiquidGlassProvider = Provider<bool>(
  (ref) => ref.watch(appGlassLevelProvider) == AppGlassLevel.liquid,
);

/// Glass preferences stay out of ThemeData, so changing them repaints glass
/// surfaces without rebuilding the app theme.
///
/// The level glass renders at: the saved one, or Level 1 where Auto measured
/// that this device needs it. Appearance edits the saved value.
final appGlassClarityLevelProvider = Provider<int>((ref) {
  final autoFrosted =
      ref.watch(appGlassQualityProvider) == AppGlassQuality.auto &&
      ref.watch(appAutoDeviceGlassLevelProvider) != AppGlassLevel.flat &&
      ref.watch(appGlassAutoStepProvider) == AppGlassAutoStep.liteFrosted;
  return autoFrosted
      ? 1
      : ref.watch(settingsProvider.select((s) => s.glassClarityLevel));
});

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
