import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_mode.dart';
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
      'shared=${sharedBackdropApplies(mode, sharedBackdrop) ? 'on' : 'off'}';
}
