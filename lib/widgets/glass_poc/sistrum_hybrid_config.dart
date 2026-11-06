import 'package:flutter/widgets.dart';

/// Rendering tiers of Sistrum Hybrid, the developer-only glass POC.
///
/// - [opaque]: an opaque fill with the same shape and hairline. No glass and
///   no backdrop read; the cost floor of the scene (matrix variant A).
/// - [lightweight]: tint, highlight and hairline only. No backdrop read.
/// - [frosted]: a live `BackdropFilter` blur at native resolution.
/// - [full]: blur, then the first-party lens shader (`shaders/sistrum_lens.frag`)
///   over the backdrop. Refraction is genuine only when
///   [SistrumHybridConfig.refraction] is on; with it off the tier draws the
///   Frosted filter. Falls back to Frosted where shader filters are unsupported.
enum SistrumHybridTier {
  opaque('Opaque'),
  lightweight('Lightweight'),
  frosted('Frosted'),
  full('Full');

  const SistrumHybridTier(this.label);

  final String label;

  /// Whether the tier hands a `BackdropFilter` to the engine.
  bool get readsBackdrop => this == frosted || this == full;
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
    this.sharedBackdrop = false,
    this.sharedAtlas = false,
  });

  final SistrumHybridTier tier;

  /// Gaussian blur sigma in logical pixels (Frosted and Full).
  final double blurSigma;

  /// Opacity of the theme-adaptive tint, 0 to 1 (Lightweight, Frosted, Full).
  final double tintOpacity;

  /// Genuine refraction on [SistrumHybridTier.full]. Off draws the Frosted
  /// filter, which is not refraction.
  final bool refraction;

  /// Chromatic dispersion on [SistrumHybridTier.full], when refraction is on.
  final bool chromaticAberration;

  /// Requests one shared backdrop read for the surfaces of the stage
  /// (`BackdropFilter.backdropGroupKey`). Only tiers that read the backdrop
  /// use it, and the page shares a read only between surfaces whose sampling
  /// regions cannot see each other's paint (`appGlassBackdropGroups`).
  final bool sharedBackdrop;

  /// Experimental: sample one shared backdrop atlas, captured in the frame it
  /// is drawn, instead of a `BackdropFilter` per surface. Supported for the
  /// blur only; see [atlasUnsupportedReason].
  final bool sharedAtlas;

  /// Why the atlas cannot serve this configuration, or null when it can.
  /// Unsupported combinations keep the existing pipeline and say so.
  String? get atlasUnsupportedReason {
    if (!sharedAtlas) return null;
    if (!tier.readsBackdrop) return 'tier_reads_no_backdrop';
    if (blurSigma <= 0) return 'zero_blur_bypass';
    if (isGenuineRefraction) return 'refraction_not_supported_by_atlas';
    return null;
  }

  /// Whether the atlas is requested and supported for this configuration.
  bool get usesAtlas => sharedAtlas && atlasUnsupportedReason == null;

  /// Whether the surface reads the live backdrop through a genuine refraction.
  bool get isGenuineRefraction => tier == SistrumHybridTier.full && refraction;

  /// Whether a shared backdrop read is requested for a tier that can use it.
  bool get sharesBackdrop =>
      sharedBackdrop && tier.readsBackdrop && !sharedAtlas;

  SistrumHybridConfig copyWith({
    SistrumHybridTier? tier,
    double? blurSigma,
    double? tintOpacity,
    bool? refraction,
    bool? chromaticAberration,
    bool? sharedBackdrop,
    bool? sharedAtlas,
  }) => SistrumHybridConfig(
    tier: tier ?? this.tier,
    blurSigma: (blurSigma ?? this.blurSigma).clamp(0.0, 24.0),
    tintOpacity: (tintOpacity ?? this.tintOpacity).clamp(0.0, 1.0),
    refraction: refraction ?? this.refraction,
    chromaticAberration: chromaticAberration ?? this.chromaticAberration,
    sharedBackdrop: sharedBackdrop ?? this.sharedBackdrop,
    sharedAtlas: sharedAtlas ?? this.sharedAtlas,
  );

  /// The controls that take effect for [tier]. The page shows the others as
  /// unsupported rather than as working controls.
  SistrumHybridCapabilities get capabilities =>
      SistrumHybridCapabilities.of(tier);

  /// One-line description for copied reports.
  String get reportText =>
      'tier=${tier.name} blur_sigma=${blurSigma.toStringAsFixed(1)} '
      'tint_opacity=${tintOpacity.toStringAsFixed(2)} '
      'refraction=$refraction chromatic=$chromaticAberration '
      'shared_backdrop_requested=$sharedBackdrop '
      'atlas_requested=$sharedAtlas';

  @override
  bool operator ==(Object other) =>
      other is SistrumHybridConfig &&
      other.tier == tier &&
      other.blurSigma == blurSigma &&
      other.tintOpacity == tintOpacity &&
      other.refraction == refraction &&
      other.chromaticAberration == chromaticAberration &&
      other.sharedBackdrop == sharedBackdrop &&
      other.sharedAtlas == sharedAtlas;

  @override
  int get hashCode => Object.hash(
    tier,
    blurSigma,
    tintOpacity,
    refraction,
    chromaticAberration,
    sharedBackdrop,
    sharedAtlas,
  );
}

/// The comparable configurations of the Scene D raster matrix. Every variant
/// keeps the default blur, tint, refraction and chromatic settings, so only
/// the named difference changes between neighbours:
///
/// - A to B: a translucent material instead of an opaque one.
/// - B to C: a live backdrop read and blur.
/// - C to D: the lens shader after the blur.
/// - D to E: one shared backdrop read instead of one per surface.
enum SistrumHybridVariant {
  a('A', 'No glass (opaque)', SistrumHybridTier.opaque),
  b('B', 'Tint only', SistrumHybridTier.lightweight),
  c('C', 'Frosted', SistrumHybridTier.frosted),
  d('D', 'Full Hybrid', SistrumHybridTier.full),
  e('E', 'Full Hybrid, shared backdrop', SistrumHybridTier.full, shared: true);

  const SistrumHybridVariant(
    this.code,
    this.label,
    this.tier, {
    this.shared = false,
  });

  final String code;
  final String label;
  final SistrumHybridTier tier;
  final bool shared;

  /// The fixed configuration this variant runs with.
  SistrumHybridConfig get config =>
      SistrumHybridConfig(tier: tier, sharedBackdrop: shared);
}

/// Which controls work for a tier. Saturation and the sampling scale are false
/// on every tier: neither is implemented for Hybrid.
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
        SistrumHybridTier.opaque => const SistrumHybridCapabilities(
          blur: false,
          tint: false,
          refraction: false,
          chromaticAberration: false,
          saturation: false,
          samplingScale: false,
          sharedBackdrop: false,
        ),
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
          sharedBackdrop: true,
        ),
        // Full composes the same blur before the lens and draws the same
        // material, so blur and tint apply to it too.
        SistrumHybridTier.full => const SistrumHybridCapabilities(
          blur: true,
          tint: true,
          refraction: true,
          chromaticAberration: true,
          saturation: false,
          samplingScale: false,
          sharedBackdrop: true,
        ),
      };

  final bool blur;
  final bool tint;
  final bool refraction;
  final bool chromaticAberration;
  final bool saturation;
  final bool samplingScale;

  /// Whether the tier reads the backdrop, so a shared read can apply.
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
