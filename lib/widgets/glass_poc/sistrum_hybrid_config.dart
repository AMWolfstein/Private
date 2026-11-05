import 'package:flutter/widgets.dart';

/// Rendering tiers of Sistrum Hybrid, the developer-only glass POC.
///
/// - [lightweight]: tint, highlight and hairline only. No backdrop read.
/// - [frosted]: a live `BackdropFilter` blur at native resolution.
/// - [full]: blur, then the first-party lens shader (`shaders/sistrum_lens.frag`)
///   over the backdrop. Refraction is genuine only when
///   [SistrumHybridConfig.refraction] is on; with it off the tier draws the
///   Frosted filter. Falls back to Frosted where shader filters are unsupported.
enum SistrumHybridTier {
  lightweight('Lightweight'),
  frosted('Frosted'),
  full('Full');

  const SistrumHybridTier(this.label);

  final String label;
}

/// Reference values taken from BitChord's `OptimizedHaze.kt` and
/// `LiquidGlass.kt`. They are starting points, not tuned for Flutter.
const double kSistrumHybridDefaultBlurSigma = 8;
const double kSistrumHybridDefaultTintOpacity = 0.40;

/// BitChord's saturation multiplier (1 + 0.5 x vibrancy). Flutter's
/// `BackdropFilter` has no colour-matrix stage, so it is not applied; the
/// capability table reports it as unsupported.
const double kSistrumHybridReferenceSaturation = 1.5;

/// BitChord's backdrop input scale (0.33). Flutter cannot downsample the
/// backdrop of a `BackdropFilter`, so it is not applied; see
/// [SistrumHybridCapabilities.samplingScale].
const double kSistrumHybridReferenceSamplingScale = 0.33;

/// The controls of one Sistrum Hybrid surface.
@immutable
class SistrumHybridConfig {
  const SistrumHybridConfig({
    this.tier = SistrumHybridTier.frosted,
    this.blurSigma = kSistrumHybridDefaultBlurSigma,
    this.tintOpacity = kSistrumHybridDefaultTintOpacity,
    this.refraction = true,
    this.chromaticAberration = true,
  });

  final SistrumHybridTier tier;

  /// Gaussian blur sigma in logical pixels ([SistrumHybridTier.frosted] only).
  final double blurSigma;

  /// Opacity of the theme-adaptive tint, 0 to 1.
  final double tintOpacity;

  /// Genuine refraction on [SistrumHybridTier.full]. Off draws FakeGlass.
  final bool refraction;

  /// Chromatic dispersion on [SistrumHybridTier.full], when refraction is on.
  final bool chromaticAberration;

  /// Whether the surface reads the live backdrop through a genuine refraction.
  bool get isGenuineRefraction => tier == SistrumHybridTier.full && refraction;

  SistrumHybridConfig copyWith({
    SistrumHybridTier? tier,
    double? blurSigma,
    double? tintOpacity,
    bool? refraction,
    bool? chromaticAberration,
  }) => SistrumHybridConfig(
    tier: tier ?? this.tier,
    blurSigma: (blurSigma ?? this.blurSigma).clamp(0.0, 24.0),
    tintOpacity: (tintOpacity ?? this.tintOpacity).clamp(0.0, 1.0),
    refraction: refraction ?? this.refraction,
    chromaticAberration: chromaticAberration ?? this.chromaticAberration,
  );

  /// The controls that take effect for [tier]. The page shows the others as
  /// unsupported rather than as working controls.
  SistrumHybridCapabilities get capabilities =>
      SistrumHybridCapabilities.of(tier);

  @override
  bool operator ==(Object other) =>
      other is SistrumHybridConfig &&
      other.tier == tier &&
      other.blurSigma == blurSigma &&
      other.tintOpacity == tintOpacity &&
      other.refraction == refraction &&
      other.chromaticAberration == chromaticAberration;

  @override
  int get hashCode => Object.hash(
    tier,
    blurSigma,
    tintOpacity,
    refraction,
    chromaticAberration,
  );
}

/// Which controls work for a tier. Saturation, the sampling scale and the
/// shared backdrop are false on every tier: none is implemented for Hybrid.
@immutable
class SistrumHybridCapabilities {
  const SistrumHybridCapabilities({
    required this.blur,
    required this.tint,
    required this.refraction,
    required this.chromaticAberration,
    required this.saturation,
    required this.samplingScale,
    required this.sharedBackdrop,
  });

  factory SistrumHybridCapabilities.of(SistrumHybridTier tier) =>
      switch (tier) {
        SistrumHybridTier.lightweight => const SistrumHybridCapabilities(
          blur: false,
          tint: true,
          refraction: false,
          chromaticAberration: false,
          saturation: false,
          samplingScale: false,
          sharedBackdrop: false,
        ),
        SistrumHybridTier.frosted => const SistrumHybridCapabilities(
          blur: true,
          tint: true,
          refraction: false,
          chromaticAberration: false,
          saturation: false,
          samplingScale: false,
          sharedBackdrop: false,
        ),
        SistrumHybridTier.full => const SistrumHybridCapabilities(
          blur: false,
          tint: false,
          refraction: true,
          chromaticAberration: true,
          saturation: false,
          samplingScale: false,
          sharedBackdrop: false,
        ),
      };

  final bool blur;
  final bool tint;
  final bool refraction;
  final bool chromaticAberration;
  final bool saturation;
  final bool samplingScale;
  final bool sharedBackdrop;
}

/// Gives the Hybrid surfaces of a scene their configuration without threading
/// it through every constructor. The page wraps the scene once.
class SistrumHybridConfigScope extends InheritedWidget {
  const SistrumHybridConfigScope({
    required this.config,
    required super.child,
    super.key,
  });

  final SistrumHybridConfig config;

  static SistrumHybridConfig of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<SistrumHybridConfigScope>()
          ?.config ??
      const SistrumHybridConfig();

  @override
  bool updateShouldNotify(SistrumHybridConfigScope oldWidget) =>
      oldWidget.config != config;
}
