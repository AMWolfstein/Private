import 'package:sistrum/widgets/glass_poc/sistrum_glass_mode.dart';

/// One run of the benchmark: a renderer, the number of glass surfaces it draws
/// and which repeat of that configuration it is. The standard protocol uses
/// four surfaces and one repeat, so it has the same shape as before.
class GlassBenchmarkRun {
  const GlassBenchmarkRun({
    required this.mode,
    this.surfaces = 4,
    this.repeat = 1,
  });

  final SistrumGlassMode mode;

  /// Glass surfaces on the stage: 1 (mini player), 2 (mini player and tab bar)
  /// or 4 (adds the header back button and trailing capsule).
  final int surfaces;

  /// 1-based repeat number of this configuration in a diagnostic plan.
  final int repeat;

  /// Stable key of the configuration, without the repeat.
  String get configKey => '${mode.name}-s$surfaces';

  /// Human-readable label used in the status line and the reports.
  String get label =>
      '${mode.label} · $surfaces surface${surfaces == 1 ? '' : 's'}';
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
        ),
      );
    }
  }
  return order;
}
