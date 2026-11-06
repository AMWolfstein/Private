import 'package:flutter/widgets.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_render_path.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_hybrid_config.dart';

/// What one Sistrum Hybrid surface actually handed to the engine.
enum SistrumHybridEffectivePath {
  /// Opaque fill, no backdrop read (variant A).
  opaque('opaque'),

  /// Translucent material, no backdrop read (variant B).
  tint('tint'),

  /// `BackdropFilter` with `ImageFilter.blur` only.
  blur('blur'),

  /// `BackdropFilter` with `ImageFilter.compose(lens shader, blur)`.
  lens('lens');

  const SistrumHybridEffectivePath(this.wire);

  final String wire;

  bool get readsBackdrop => this == blur || this == lens;
}

/// Why a Full-tier surface draws something other than the lens.
enum SistrumHybridFallback {
  none('none'),

  /// Refraction is switched off: the Frosted filter was requested.
  refractionOff('refraction_off'),

  /// `ImageFilter.isShaderFilterSupported` is false (not Impeller).
  shaderFiltersUnsupported('shader_filters_unsupported'),

  /// The lens program has not finished loading yet.
  programLoading('lens_program_loading'),

  /// The lens program failed to load (see the program state for the error).
  programFailed('lens_program_failed'),

  /// The surface had no finite, non-empty size to give the shader.
  invalidSize('invalid_size'),

  /// Blur sigma is 0 and no lens is drawn, so no `BackdropFilter` is built at
  /// all: the surface draws the tint material only (a requested bypass).
  zeroBlurBypass('zero_blur_bypass');

  const SistrumHybridFallback(this.wire);

  final String wire;

  /// A requested configuration is not a fallback; everything else is.
  bool get isFallback =>
      this != none && this != refractionOff && this != zeroBlurBypass;
}

/// One surface's rendering decision, recorded where the widget builds its
/// filter. It is what the engine was given, not proof of GPU execution.
@immutable
class SistrumHybridDecision {
  const SistrumHybridDecision({
    required this.requestedTier,
    required this.path,
    this.fallback = SistrumHybridFallback.none,
    this.backdropKey,
  });

  final SistrumHybridTier requestedTier;
  final SistrumHybridEffectivePath path;
  final SistrumHybridFallback fallback;

  /// The key given to `BackdropFilter.backdropGroupKey`, or null for an
  /// independent read (or no read).
  final BackdropKey? backdropKey;

  bool get readsBackdrop => path.readsBackdrop;
  bool get shaderFilter => path == SistrumHybridEffectivePath.lens;

  /// A Full-tier surface that draws the blur instead of the lens.
  bool get fallbackBlur =>
      requestedTier == SistrumHybridTier.full &&
      path == SistrumHybridEffectivePath.blur;

  @override
  bool operator ==(Object other) =>
      other is SistrumHybridDecision &&
      other.requestedTier == requestedTier &&
      other.path == path &&
      other.fallback == fallback &&
      identical(other.backdropKey, backdropKey);

  @override
  int get hashCode =>
      Object.hash(requestedTier, path, fallback, identityHashCode(backdropKey));
}

/// Load state of the first-party lens program.
enum SistrumLensProgramStatus {
  notRequested('not_requested'),
  unsupported('unsupported'),
  loading('loading'),
  loaded('loaded'),
  failed('failed');

  const SistrumLensProgramStatus(this.wire);

  final String wire;
}

/// The lens program's state, as [SistrumLensProgram] last recorded it.
typedef SistrumLensProgramState = ({
  SistrumLensProgramStatus status,
  String? error,
  int? loadMs,
});

/// Collects the decisions of the mounted Hybrid surfaces.
///
/// Surfaces write their decision when they build their filter and remove it
/// when they leave the tree. Reading is a map scan of a few entries, so it
/// needs no tree walk and does nothing per frame by itself.
class SistrumHybridTelemetry {
  final Map<Object, SistrumHybridDecision> _surfaces = {};
  int _changes = 0;

  /// Records [decision] for [owner]. An identical decision is ignored; a
  /// different one for a surface already reported counts as a change.
  void report(Object owner, SistrumHybridDecision decision) {
    final previous = _surfaces[owner];
    if (previous == decision) return;
    if (previous != null) _changes++;
    _surfaces[owner] = decision;
  }

  void remove(Object owner) => _surfaces.remove(owner);

  SistrumHybridTelemetrySnapshot snapshot({SistrumLensProgramState? program}) =>
      SistrumHybridTelemetrySnapshot.of(
        _surfaces.values,
        decisionChanges: _changes,
        program: program,
      );
}

/// Gives the Hybrid surfaces of a stage their telemetry collector.
class SistrumHybridTelemetryScope extends InheritedWidget {
  const SistrumHybridTelemetryScope({
    required this.telemetry,
    required super.child,
    super.key,
  });

  final SistrumHybridTelemetry telemetry;

  static SistrumHybridTelemetry? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<SistrumHybridTelemetryScope>()
      ?.telemetry;

  @override
  bool updateShouldNotify(SistrumHybridTelemetryScope oldWidget) =>
      !identical(oldWidget.telemetry, telemetry);
}

/// Totals of the recorded decisions at one moment.
@immutable
class SistrumHybridTelemetrySnapshot {
  const SistrumHybridTelemetrySnapshot({
    required this.surfaces,
    required this.paths,
    required this.requestedTiers,
    required this.backdropFilters,
    required this.shaderFilters,
    required this.fallbackBlur,
    required this.sharedMembers,
    required this.sharedGroups,
    required this.backdropReads,
    required this.fallbacks,
    required this.decisionChanges,
    this.program,
  });

  factory SistrumHybridTelemetrySnapshot.of(
    Iterable<SistrumHybridDecision> decisions, {
    int decisionChanges = 0,
    SistrumLensProgramState? program,
  }) {
    final paths = <SistrumHybridEffectivePath, int>{};
    final tiers = <SistrumHybridTier>{};
    final fallbacks = <SistrumHybridFallback>{};
    final keyMembers = <BackdropKey, int>{};
    var surfaces = 0;
    var backdrop = 0;
    var shader = 0;
    var fallbackBlur = 0;
    var independent = 0;
    for (final d in decisions) {
      surfaces++;
      paths[d.path] = (paths[d.path] ?? 0) + 1;
      tiers.add(d.requestedTier);
      if (d.fallback != SistrumHybridFallback.none) fallbacks.add(d.fallback);
      if (d.shaderFilter) shader++;
      if (d.fallbackBlur) fallbackBlur++;
      if (!d.readsBackdrop) continue;
      backdrop++;
      final key = d.backdropKey;
      if (key == null) {
        independent++;
      } else {
        keyMembers[key] = (keyMembers[key] ?? 0) + 1;
      }
    }
    // Impeller (`Canvas::SaveLayer` in impeller/display_list/canvas.cc) caches
    // the backdrop texture only for a key used by more than one filter; a key
    // with a single member is flipped like an independent filter.
    var groups = 0;
    var members = 0;
    for (final count in keyMembers.values) {
      if (count > 1) {
        groups++;
        members += count;
      } else {
        independent += count;
      }
    }
    return SistrumHybridTelemetrySnapshot(
      surfaces: surfaces,
      paths: Map.unmodifiable(paths),
      requestedTiers: Set.unmodifiable(tiers),
      backdropFilters: backdrop,
      shaderFilters: shader,
      fallbackBlur: fallbackBlur,
      sharedMembers: members,
      sharedGroups: groups,
      backdropReads: independent + groups,
      fallbacks: Set.unmodifiable(fallbacks),
      decisionChanges: decisionChanges,
      program: program,
    );
  }

  /// Hybrid surfaces that reported a decision.
  final int surfaces;

  /// Surfaces per effective path.
  final Map<SistrumHybridEffectivePath, int> paths;
  final Set<SistrumHybridTier> requestedTiers;

  /// Surfaces whose decision is a `BackdropFilter`.
  final int backdropFilters;

  /// Surfaces whose filter includes the lens shader.
  final int shaderFilters;

  /// Full-tier surfaces drawing the blur instead of the lens.
  final int fallbackBlur;

  /// Backdrop filters in a shared group of two or more.
  final int sharedMembers;

  /// Backdrop keys used by two or more filters.
  final int sharedGroups;

  /// Backdrop texture flips the engine performs per frame for these surfaces:
  /// one per independent filter plus one per shared group. Derived from the
  /// decisions and the engine source, not measured.
  final int backdropReads;

  /// Fallback and configuration reasons other than none.
  final Set<SistrumHybridFallback> fallbacks;

  /// Changes of an already-reported surface's decision since the collector
  /// was created.
  final int decisionChanges;

  final SistrumLensProgramState? program;

  bool get sharedBackdropActive => sharedGroups > 0;

  /// The single effective path of every surface, or null when they differ or
  /// none reported.
  SistrumHybridEffectivePath? get uniformPath =>
      paths.length == 1 ? paths.keys.single : null;

  /// `lens`, `blur`, ... or `mixed(lens=3,blur=1)`.
  String get effectivePathText {
    if (paths.isEmpty) return 'none_reported';
    final uniform = uniformPath;
    if (uniform != null) return uniform.wire;
    final parts = [
      for (final p in SistrumHybridEffectivePath.values)
        if (paths[p] != null) '${p.wire}=${paths[p]}',
    ];
    return 'mixed(${parts.join(',')})';
  }

  String get fallbackText => fallbacks.isEmpty
      ? 'none'
      : (fallbacks.map((f) => f.wire).toList()..sort()).join(',');

  String get programText {
    final p = program;
    if (p == null) return 'unknown';
    return [
      p.status.wire,
      if (p.loadMs != null) 'load_ms=${p.loadMs}',
      if (p.error != null) 'error=${p.error}',
    ].join(' ');
  }

  /// Report lines. Every value comes from the recorded decisions.
  List<String> lines({String prefix = 'hybrid_'}) => [
    '${prefix}telemetry_source=widget_decisions '
        '(filters handed to the engine; GPU execution is not observable from Dart)',
    '${prefix}requested_tiers=${requestedTiers.isEmpty ? 'none' : (requestedTiers.map((t) => t.name).toList()..sort()).join(',')}',
    '${prefix}effective_path=$effectivePathText',
    '${prefix}surfaces=$surfaces',
    '${prefix}backdrop_filter_surfaces=$backdropFilters',
    '${prefix}shader_filter_surfaces=$shaderFilters',
    '${prefix}lens_shader_active=${shaderFilters > 0 ? '$shaderFilters/$surfaces' : 'false'}',
    '${prefix}fallback_blur_surfaces=$fallbackBlur',
    '${prefix}shared_backdrop_active=$sharedBackdropActive '
        'groups=$sharedGroups members=$sharedMembers',
    '${prefix}backdrop_reads_per_frame=$backdropReads '
        '(engine FlipBackdrop calls implied by the decisions; not measured)',
    '${prefix}fallback_reasons=$fallbackText',
    '${prefix}decision_changes=$decisionChanges',
    '${prefix}lens_program=$programText',
  ];

  @override
  bool operator ==(Object other) =>
      other is SistrumHybridTelemetrySnapshot &&
      other.surfaces == surfaces &&
      other.effectivePathText == effectivePathText &&
      other.backdropFilters == backdropFilters &&
      other.shaderFilters == shaderFilters &&
      other.fallbackBlur == fallbackBlur &&
      other.sharedMembers == sharedMembers &&
      other.sharedGroups == sharedGroups &&
      other.backdropReads == backdropReads &&
      other.fallbackText == fallbackText &&
      other.decisionChanges == decisionChanges;

  @override
  int get hashCode => Object.hash(
    surfaces,
    effectivePathText,
    backdropFilters,
    shaderFilters,
    fallbackBlur,
    sharedMembers,
    sharedGroups,
    backdropReads,
    fallbackText,
    decisionChanges,
  );
}

/// The render path a Hybrid configuration must show.
SistrumGlassRenderPath expectedHybridRenderPath(SistrumHybridConfig config) =>
    switch (config.tier) {
      SistrumHybridTier.opaque => SistrumGlassRenderPath.opaque,
      SistrumHybridTier.lightweight => SistrumGlassRenderPath.tint,
      SistrumHybridTier.frosted =>
        config.blurSigma > 0
            ? SistrumGlassRenderPath.backdropFilter
            : SistrumGlassRenderPath.tint,
      SistrumHybridTier.full =>
        config.refraction
            ? SistrumGlassRenderPath.lensShader
            : config.blurSigma > 0
            ? SistrumGlassRenderPath.backdropFilter
            : SistrumGlassRenderPath.tint,
    };

/// Classifies the Hybrid render path from the recorded decisions. Anything
/// but every expected surface on one path is unverified, never a guess.
SistrumGlassRenderReport classifyHybridRenderPath({
  required int expectedSurfaces,
  required SistrumHybridTelemetrySnapshot snapshot,
}) {
  if (snapshot.surfaces != expectedSurfaces) {
    return SistrumGlassRenderReport.unverified(
      'Hybrid surfaces reported ${snapshot.surfaces} of $expectedSurfaces',
    );
  }
  final uniform = snapshot.uniformPath;
  if (uniform == null) {
    return SistrumGlassRenderReport.unverified(
      'Hybrid surfaces differ: ${snapshot.effectivePathText}',
    );
  }
  final path = switch (uniform) {
    SistrumHybridEffectivePath.opaque => SistrumGlassRenderPath.opaque,
    SistrumHybridEffectivePath.tint => SistrumGlassRenderPath.tint,
    SistrumHybridEffectivePath.blur => SistrumGlassRenderPath.backdropFilter,
    SistrumHybridEffectivePath.lens => SistrumGlassRenderPath.lensShader,
  };
  final fallback = snapshot.fallbacks.where((f) => f.isFallback).toList();
  if (fallback.isEmpty) {
    return SistrumGlassRenderReport(path: path, fallback: false);
  }
  return SistrumGlassRenderReport(
    path: path,
    fallback: true,
    fallbackReason:
        'lens requested, blur drawn: '
        '${(fallback.map((f) => f.wire).toList()..sort()).join(',')}',
  );
}
