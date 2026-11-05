import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_auto_scroll.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_mode.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_render_path.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_scene.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_surface.dart';

/// The Glass POC mode selected on the developer page. Held in memory only, so
/// a restart returns to the baseline. The performance HUD reads it to label
/// its reports.
final glassPocModeProvider =
    NotifierProvider<GlassPocModeNotifier, SistrumGlassMode>(
      GlassPocModeNotifier.new,
    );

class GlassPocModeNotifier extends Notifier<SistrumGlassMode> {
  @override
  SistrumGlassMode build() => SistrumGlassMode.transparentBaseline;

  void select(SistrumGlassMode mode) {
    if (state != mode) state = mode;
  }
}

/// The comparison switch: whether Reference Glass reads the backdrop as one
/// shared group. Off is the existing per-surface path. Held in memory only.
final glassPocSharedBackdropProvider =
    NotifierProvider<GlassPocSharedBackdropNotifier, bool>(
      GlassPocSharedBackdropNotifier.new,
    );

class GlassPocSharedBackdropNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) {
    if (state != value) state = value;
  }
}

/// The active rendering path as one label, for the screen and copied reports.
/// The shared group is named only where it applies, so the label always says
/// what was really drawn.
String glassPocPathLabel(
  SistrumGlassMode mode, {
  required bool sharedBackdrop,
}) {
  return sharedBackdropApplies(mode, sharedBackdrop)
      ? '${mode.label} (shared backdrop)'
      : mode.label;
}

/// The developer comparison scene (see [SistrumGlassScene]). Held in memory
/// only; the screen applies the scene's animation and scroll state.
final glassPocSceneProvider =
    NotifierProvider<GlassPocSceneNotifier, SistrumGlassScene>(
      GlassPocSceneNotifier.new,
    );

class GlassPocSceneNotifier extends Notifier<SistrumGlassScene> {
  @override
  SistrumGlassScene build() => SistrumGlassScene.fourSurfaces;

  void select(SistrumGlassScene scene) {
    if (state != scene) state = scene;
  }
}

/// The full label copied into reports and shown in the HUD: the active
/// renderer, scene, shared-backdrop state and animation state.
String glassPocReportLabel({
  required SistrumGlassMode mode,
  required bool sharedBackdrop,
  required SistrumGlassScene scene,
}) {
  final path = glassPocPathLabel(mode, sharedBackdrop: sharedBackdrop);
  return '$path; scene=${scene.label}; animated=${scene.animated ? 'on' : 'off'}; '
      'shared=${mode == SistrumGlassMode.newFullGlassSharedBackdrop || sharedBackdropApplies(mode, sharedBackdrop) ? 'on' : 'off'}';
}

/// The Scene D auto-scroll preset. Held in memory only; the page applies it
/// to its scroller.
final glassPocScrollSpeedProvider =
    NotifierProvider<GlassPocScrollSpeedNotifier, SistrumScrollSpeed>(
      GlassPocScrollSpeedNotifier.new,
    );

class GlassPocScrollSpeedNotifier extends Notifier<SistrumScrollSpeed> {
  @override
  SistrumScrollSpeed build() => SistrumScrollSpeed.normal;

  void select(SistrumScrollSpeed speed) {
    if (state != speed) state = speed;
  }
}

/// The open Glass POC page's scroller and render-path probe. Copied reports
/// read both from here; both are null-safe when no page is open.
final glassPocRunRegistryProvider = Provider<GlassPocRunRegistry>(
  (ref) => GlassPocRunRegistry(),
);

/// What the Glass POC page can say about its own run: the render path now and
/// at the start of measurement.
abstract interface class GlassPocRunProbe {
  SistrumGlassRenderReport renderPath();

  /// The path when warm-up ended, or null if measurement has not started.
  SistrumGlassRenderReport? renderPathAtMeasurementStart();
}

class GlassPocRunRegistry {
  SistrumAutoScroller? _scroller;
  GlassPocRunProbe? _probe;

  void attach(SistrumAutoScroller scroller, GlassPocRunProbe probe) {
    _scroller = scroller;
    _probe = probe;
  }

  void detach(SistrumAutoScroller scroller) {
    if (identical(_scroller, scroller)) {
      _scroller = null;
      _probe = null;
    }
  }

  SistrumScrollStatus? scrollStatus() => _scroller?.status();

  SistrumGlassRenderReport renderPath() =>
      _probe?.renderPath() ??
      const SistrumGlassRenderReport.unverified('Glass POC page is not open');

  SistrumGlassRenderReport? renderPathAtMeasurementStart() =>
      _probe?.renderPathAtMeasurementStart();
}

/// Every benchmark line for a copied report, read from the providers at the
/// time of the copy. The HUD, Developer Options and the POC page all use it, so
/// their reports agree. The render path is reconciled: if it changed between the
/// start of measurement and the copy, the report says it is unverified.
List<String> glassPocReportLines(WidgetRef ref) {
  final mode = ref.read(glassPocModeProvider);
  final sharedBackdrop = ref.read(glassPocSharedBackdropProvider);
  final scene = ref.read(glassPocSceneProvider);
  final speed = ref.read(glassPocScrollSpeedProvider);
  final registry = ref.read(glassPocRunRegistryProvider);
  final scroll = registry.scrollStatus();
  final render = _reconcileRenderPath(
    atStart: registry.renderPathAtMeasurementStart(),
    now: registry.renderPath(),
  );
  final shared =
      mode == SistrumGlassMode.newFullGlassSharedBackdrop ||
      sharedBackdropApplies(mode, sharedBackdrop);
  final scrolling = scene.scrolling && scroll != null;
  final fallback = render.fallback;
  return [
    'glass_render_path=${render.path.wire}',
    'glass_fallback=${fallback == null
        ? 'unknown'
        : fallback
        ? 'true'
        : 'false'}',
    if (fallback == true) 'glass_fallback_reason=${render.fallbackReason}',
    if (render.path == SistrumGlassRenderPath.unverified)
      'glass_unverified_reason=${render.unverifiedReason}',
    'scene=${scene.code}',
    'animated_background=${scene.animated ? 'on' : 'off'}',
    'shared_backdrop=${shared ? 'on' : 'off'}',
    if (!scrolling)
      'scroll_mode=off'
    else ...[
      'scroll_mode=auto',
      'scroll_state=${scroll.running ? 'running' : 'paused'}',
      'scroll_speed_preset=${speed.name}',
      'scroll_speed_target=${speed.pxPerSecond.toStringAsFixed(0)}',
      'scroll_speed_actual=${_actualSpeedText(scroll.actualPxPerSecond)}',
      'scroll_speed_unit=logical_px_per_second',
      'scroll_direction=${scroll.direction}',
      'scroll_boundary_behavior=reverse',
      'scroll_boundary_transitions=${scroll.boundaryTransitions}',
      'scroll_warmup=${scroll.measuring ? 'complete' : 'waiting'}',
      'scroll_samples=${scroll.samples}',
    ],
  ];
}

SistrumGlassRenderReport _reconcileRenderPath({
  required SistrumGlassRenderReport? atStart,
  required SistrumGlassRenderReport now,
}) {
  if (atStart == null || atStart == now) return now;
  return SistrumGlassRenderReport.unverified(
    'render path changed during measurement: '
    '${atStart.path.wire} -> ${now.path.wire}',
  );
}

String _actualSpeedText(double? pxPerSecond) =>
    pxPerSecond == null ? 'unavailable' : pxPerSecond.toStringAsFixed(1);
