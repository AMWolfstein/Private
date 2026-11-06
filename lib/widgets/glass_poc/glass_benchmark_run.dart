import 'package:sistrum/widgets/glass_poc/sistrum_auto_scroll.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_mode.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_hybrid_config.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_hybrid_atlas.dart';

/// One run of the benchmark: a renderer, the number of glass surfaces it draws
/// and which repeat of that configuration it is. The standard protocol uses
/// four surfaces and one repeat, so it has the same shape as before.
class GlassBenchmarkRun {
  const GlassBenchmarkRun({
    required this.mode,
    this.surfaces = 4,
    this.repeat = 1,
    this.hybrid,
    this.hybridConfig,
    this.speed,
  });

  final SistrumGlassMode mode;

  /// The Sistrum Hybrid matrix variant this run applies, or null. Set only
  /// with [SistrumGlassMode.sistrumHybrid].
  final SistrumHybridVariant? hybrid;

  /// An explicit Hybrid configuration for this run, or null. It takes
  /// precedence over [hybrid]'s fixed settings.
  final SistrumHybridConfig? hybridConfig;

  /// Scroll speed of this run, or null for the standard 900 px/s.
  final SistrumScrollSpeed? speed;

  /// The speed the run scrolls at and is validated against.
  SistrumScrollSpeed get effectiveSpeed => speed ?? SistrumScrollSpeed.fast;

  /// The Hybrid configuration the run applies, or null when it applies none.
  SistrumHybridConfig? get effectiveHybridConfig =>
      hybridConfig ?? hybrid?.config;

  /// Glass surfaces on the stage: 1 (mini player), 2 (mini player and tab bar)
  /// or 4 (adds the header back button and trailing capsule).
  final int surfaces;

  /// 1-based repeat number of this configuration in a diagnostic plan.
  final int repeat;

  /// Stable key of the configuration, without the repeat.
  String get configKey =>
      '${mode.name}-s$surfaces${hybrid == null ? '' : '-${hybrid!.code}'}'
      '${hybridConfig == null ? '' : '-shared${hybridConfig!.sharedBackdrop ? 'On' : 'Off'}-atlas${hybridConfig!.sharedAtlas ? 'On' : 'Off'}'}'
      '${speed == null ? '' : '-${speed!.pxPerSecond.round()}'}';

  /// Human-readable label used in the status line and the reports.
  String get label {
    final variant = hybrid;
    final surfaceText = '$surfaces surface${surfaces == 1 ? '' : 's'}';
    if (variant != null) {
      return 'Hybrid ${variant.code} ${variant.label} · $surfaceText';
    }
    final config = hybridConfig;
    if (config != null) {
      return 'Hybrid shared ${config.sharedBackdrop ? 'ON' : 'OFF'} '
          'atlas ${config.sharedAtlas ? 'ON' : 'OFF'} · '
          '${effectiveSpeed.pxPerSecond.round()} px/s · $surfaceText';
    }
    return '${mode.label} · $surfaceText';
  }
}

/// Surface counts the layer-count experiment uses for New Full Glass.
const List<int> kGlassLayerScalingSurfaces = [1, 2, 4];

/// Six counterbalanced rounds: every configuration occurs twice in each
/// ordinal position and every directed within-round neighbour pair occurs
/// twice. The original five-mode protocol stays unchanged.
List<GlassBenchmarkRun> appGlassBackdropSharingRuns() {
  const modes = [
    SistrumGlassMode.transparentBaseline,
    SistrumGlassMode.newFullGlass,
    SistrumGlassMode.newFullGlassSharedBackdrop,
  ];
  const orders = [
    [0, 1, 2],
    [1, 2, 0],
    [2, 0, 1],
    [2, 1, 0],
    [0, 2, 1],
    [1, 0, 2],
  ];
  return [
    for (var round = 0; round < orders.length; round++)
      for (final index in orders[round])
        GlassBenchmarkRun(mode: modes[index], repeat: round + 1),
  ];
}

/// Configurations of the diagnostic repeatability protocol, in their base
/// order. Each one is run once per repeat.
List<GlassBenchmarkRun> glassDiagnosticConfigurations({
  bool includeBasicBlur = false,
}) => [
  const GlassBenchmarkRun(mode: SistrumGlassMode.transparentBaseline),
  for (final surfaces in kGlassLayerScalingSurfaces)
    GlassBenchmarkRun(mode: SistrumGlassMode.newFullGlass, surfaces: surfaces),
  const GlassBenchmarkRun(mode: SistrumGlassMode.liquidGlass),
  const GlassBenchmarkRun(mode: SistrumGlassMode.newFakeGlass),
  if (includeBasicBlur)
    const GlassBenchmarkRun(mode: SistrumGlassMode.basicBlur),
];

/// The diagnostic run order for [repeats] rounds over [configurations].
///
/// Counterbalanced and deterministic: round `r` starts from a different
/// rotation of the list, and odd rounds run it backwards. Every configuration
/// appears once per round, and its position changes between rounds, so no
/// configuration always runs first, last or right after the same neighbour.
/// The returned runs are in the order they will execute.
List<GlassBenchmarkRun> glassDiagnosticRunOrder({
  required List<GlassBenchmarkRun> configurations,
  int repeats = 3,
}) {
  final n = configurations.length;
  final order = <GlassBenchmarkRun>[];
  for (var round = 0; round < repeats; round++) {
    final offset = n == 0 ? 0 : (round * n) ~/ repeats;
    final forward = round.isEven;
    for (var k = 0; k < n; k++) {
      final index = forward ? (k + offset) % n : (n - 1 - ((k + offset) % n));
      final base = configurations[index];
      order.add(
        GlassBenchmarkRun(
          mode: base.mode,
          surfaces: base.surfaces,
          repeat: round + 1,
          hybrid: base.hybrid,
          hybridConfig: base.hybridConfig,
          speed: base.speed,
        ),
      );
    }
  }
  return order;
}

/// Configurations of the Sistrum Hybrid raster matrix (variants A to E), all
/// in Scene D with four surfaces.
List<GlassBenchmarkRun> glassHybridMatrixConfigurations() => [
  for (final variant in SistrumHybridVariant.values)
    GlassBenchmarkRun(mode: SistrumGlassMode.sistrumHybrid, hybrid: variant),
];

/// Configurations of the atlas resolution sweep: the atlas off, then on at each
/// [SistrumAtlasResolution], at 400 and 900 logical px/s. Only the atlas state,
/// its resolution and the speed differ; everything else is [config] as given.
List<GlassBenchmarkRun> glassHybridAtlasResolutionConfigurations(
  SistrumHybridConfig config,
) => [
  for (final speed in const [
    SistrumScrollSpeed.normal,
    SistrumScrollSpeed.fast,
  ])
    for (final resolution in <SistrumAtlasResolution?>[
      null,
      ...SistrumAtlasResolution.values,
    ])
      GlassBenchmarkRun(
        mode: SistrumGlassMode.sistrumHybrid,
        hybridConfig: resolution == null
            ? config.copyWith(sharedAtlas: false)
            : config.copyWith(sharedAtlas: true, atlasResolution: resolution),
        speed: speed,
      ),
];

/// Configurations of the Hybrid A/B: [config] with the shared read off and on
/// (or, with [atlas], the shared atlas off and on), each at 400 and 900
/// logical px/s. Only that flag and the speed differ; everything else is
/// [config] as given.
List<GlassBenchmarkRun> glassHybridSharedAbConfigurations(
  SistrumHybridConfig config, {
  bool atlas = false,
}) => [
  for (final speed in const [
    SistrumScrollSpeed.normal,
    SistrumScrollSpeed.fast,
  ])
    for (final shared in const [false, true])
      GlassBenchmarkRun(
        mode: SistrumGlassMode.sistrumHybrid,
        hybridConfig: atlas
            ? config.copyWith(sharedAtlas: shared)
            : config.copyWith(sharedBackdrop: shared, sharedAtlas: false),
        speed: speed,
      ),
];
