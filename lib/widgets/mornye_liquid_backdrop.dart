import 'dart:ui' show ImageFilter;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:mornye/providers/runtime_profile_provider.dart';
import 'package:mornye/providers/settings_provider.dart';
import 'package:mornye/theme/mornye_theme.dart';

/// How a batch of Mornye lenses shares its backdrop read and blurs its
/// members. Only the first option is the reviewed default; the others are
/// diagnostics for comparing renderers on a device without a rebuild.
///
/// Source-verified in liquid_glass_easy 5.2.0: `separatePass` blurs in its
/// own keyed pass over the batch copy; `singlePass` folds the blur into each
/// member's pass; `shader` blurs inside the lens shader with no blur pass,
/// but its grain differs from the Gaussian. None is measured on hardware yet.
enum MornyeGlassBatchRenderer {
  separatePass(
    'separate_pass',
    LiquidGlassBatchMode.separatePass,
    LiquidGlassBlurMethod.engine,
  ),
  singlePass(
    'single_pass',
    LiquidGlassBatchMode.singlePass,
    LiquidGlassBlurMethod.engine,
  ),
  shader(
    'shader_blur',
    LiquidGlassBatchMode.separatePass,
    LiquidGlassBlurMethod.shader,
  );

  const MornyeGlassBatchRenderer(this.wire, this.mode, this.blurMethod);

  /// The persisted value in `AppSettings.glassBatchRenderer`.
  final String wire;
  final LiquidGlassBatchMode mode;
  final LiquidGlassBlurMethod blurMethod;

  /// Unknown or missing values keep the reviewed default.
  static MornyeGlassBatchRenderer fromWire(String value) => values.firstWhere(
    (renderer) => renderer.wire == value,
    orElse: () => separatePass,
  );
}

/// Diagnostic experiments for Mornye glass. [off] is the reviewed look.
/// [headerBatch] shares one backdrop read across Artist and Album headers;
/// [sigmaEarly] moves the sigma-6 band down to clarity 0.4. Neither is
/// measured on hardware yet.
enum MornyeGlassExperiment {
  off('off'),
  headerBatch('header_batch'),
  sigmaEarly('sigma_early');

  const MornyeGlassExperiment(this.wire);

  final String wire;

  static MornyeGlassExperiment fromWire(String value) => values.firstWhere(
    (experiment) => experiment.wire == value,
    orElse: () => off,
  );
}

final mornyeGlassExperimentProvider = Provider<MornyeGlassExperiment>(
  (ref) => MornyeGlassExperiment.fromWire(
    ref.watch(settingsProvider.select((s) => s.glassExperiment)),
  ),
);

/// Puts a Mornye page's glass in one backdrop batch when the header experiment
/// is on. Material has no lenses, so it is returned unchanged.
Widget mornyeHeaderBatch(BuildContext context, WidgetRef ref, Widget child) {
  final enabled =
      context.isMornye &&
      ref.watch(mornyeGlassExperimentProvider) ==
          MornyeGlassExperiment.headerBatch;
  return enabled ? LiquidGlassBatch(child: child) : child;
}

final mornyeGlassBatchRendererProvider = Provider<MornyeGlassBatchRenderer>(
  (ref) => MornyeGlassBatchRenderer.fromWire(
    ref.watch(settingsProvider.select((s) => s.glassBatchRenderer)),
  ),
);

/// The one place that maps the Glass clarity slider (0 to 1) and the glass
/// level to render decisions. Every Mornye glass surface reads these values,
/// so the thresholds and blur budgets cannot drift between surfaces.
abstract final class MornyeGlassRules {
  /// Blur budgets for the backdrop, from the largest to the smallest.
  /// Index 1 is the frosted fallback budget; the others follow clarity.
  static const blurSigmas = [2.0, 3.0, 6.0, 16.0];

  /// Shared, immutable filters so a clarity animation never rebuilds one.
  static final blurFilters = [
    for (final sigma in blurSigmas)
      ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
  ];

  /// Host tests cannot run shader filters; this lets them build the lens.
  @visibleForTesting
  static bool? debugShaderFilterSupport;

  /// Whether the shader lens can render here: Impeller only, and never in a
  /// test host unless [debugShaderFilterSupport] says so.
  static bool get shaderLensSupported =>
      debugShaderFilterSupport ?? ImageFilter.isShaderFilterSupported;

  /// Clarity above which the surface samples its backdrop. Frosted glass
  /// waits longer so a 10 % setting never enables sampling on a mid GPU.
  static double backdropMinClarity(MornyeGlassLevel level) =>
      level == MornyeGlassLevel.frosted ? 0.5 : 0.2;

  /// Index into [blurSigmas] for a level and clarity: frosted always uses
  /// index 1; liquid uses 2 (sigma 6) from 0.6, 0 (sigma 2) from 0.9, else 3.
  static int blurIndex(
    MornyeGlassLevel level,
    double clarity, {
    bool sigmaEarly = false,
  }) {
    if (level == MornyeGlassLevel.frosted) return 1;
    if (clarity >= 0.9) return 0;
    if (clarity >= (sigmaEarly ? 0.4 : 0.6)) return 2;
    return 3;
  }

  /// Opacity of the tint: the slider's tinted end is opaque, the clear end
  /// reveals more of the page.
  static double tintStrength(double clarity) => (1 - clarity) * (1 - clarity);

  /// How much of the clear fill replaces the tint on a liquid lens, from
  /// clarity 0.2 (none) to 1 (all).
  static double clearFillMix(double clarity) =>
      ((clarity - 0.2) / 0.8).clamp(0.0, 1.0);

  /// Widest colour split in logical pixels, for a clarity and an effect
  /// amount (`progress` of a held lens, `1` at rest).
  static double dispersion(double clarity, double effect) =>
      1.32 * clarity * effect;
}

/// A bounded package lens without a captured-screen view or a touch ticker.
class MornyeLiquidBackdrop extends StatelessWidget {
  const MornyeLiquidBackdrop({
    super.key,
    required this.borderRadius,
    required this.clarity,
    required this.blurSigma,
    required this.child,
    this.interaction = false,
    this.progress = 1,
    this.refractionDepth = 0.30,
    this.refractionWidth = 20,
    this.smoothCorners = false,
    this.highlightIntensity = 1,
  });

  final BorderRadius borderRadius;
  final double clarity;
  final double blurSigma;
  final Widget child;
  final bool interaction;
  final double progress;
  final double refractionDepth;
  final double refractionWidth;
  final bool smoothCorners;
  final double highlightIntensity;

  @override
  Widget build(BuildContext context) {
    if (interaction && progress <= 0) return child;
    final effect = interaction ? progress : 1.0;
    final outlines = MornyeTheme.glassOutlinesOf(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Match the old optical lens's edge displacement. Version 5 fixes travel
    // at 70 logical pixels and controls bending through the index alone.
    final edgeBend =
        math.sqrt(1 - 1 / (1.7 * 1.7)) *
        refractionWidth *
        refractionDepth *
        effect *
        5 /
        70;
    final index = 1 / math.sqrt(1 - math.pow(edgeBend.clamp(0, 0.95), 2));
    return LiquidGlassLens(
      style: LiquidGlassStyle(
        // The package's named constructors set the corner style and clip
        // quality together, so the two ternaries become one choice.
        shape: smoothCorners
            ? LiquidGlassShape.squircle(
                cornerRadius: borderRadius.topLeft.x,
                clipQuality: LiquidGlassClipQuality.exact,
              )
            : LiquidGlassShape.roundedRectangle(
                cornerRadius: borderRadius.topLeft.x,
              ),
        specular: LiquidGlassLight.specular(
          thickness: outlines ? 0.75 * 5.4 : 0,
          angle: 0,
          spread: 0.2,
          intensity: outlines
              ? (dark ? 0.25 : 0.12) * effect * highlightIntensity
              : 0,
          color: dark ? Colors.white : const Color(0x88ffffff),
        ),
        glow: LiquidGlassLight.glow(
          thickness: outlines ? 0.75 * 29.4 : 0,
          intensity: outlines ? 0.05 * highlightIntensity : 0,
        ),
        blur: blurSigma,
        refractionIndex: index,
        refractionWidth: refractionWidth,
        // Version 5 expresses the widest colour split in logical pixels.
        dispersion: MornyeGlassRules.dispersion(clarity, effect),
      ),
      child: child,
    );
  }
}
