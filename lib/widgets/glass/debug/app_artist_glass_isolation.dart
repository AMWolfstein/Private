import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Developer-only diagnostic: what the Artist screen draws while its video
/// plays. Not a production setting; it is switched from the performance HUD
/// and is never persisted, so every launch starts at [normal].
enum AppArtistGlassIsolation {
  /// The current rendering, unchanged.
  normal,

  /// The Artist screen's glass draws Tint only: no Frosted backdrop blur, no
  /// Liquid refraction and no capture for it. The video keeps playing.
  glassDisabled,
}

class AppArtistGlassIsolationNotifier
    extends Notifier<AppArtistGlassIsolation> {
  @override
  AppArtistGlassIsolation build() => AppArtistGlassIsolation.normal;

  void toggle() {
    state = state == AppArtistGlassIsolation.normal
        ? AppArtistGlassIsolation.glassDisabled
        : AppArtistGlassIsolation.normal;
    appDiagnosticWindowEpoch.value++;
  }
}

final appArtistGlassIsolationProvider =
    NotifierProvider<AppArtistGlassIsolationNotifier, AppArtistGlassIsolation>(
      AppArtistGlassIsolationNotifier.new,
    );

/// Whether the Artist screen's video is playing, for the HUD.
final ValueNotifier<bool> appArtistVideoPlaying = ValueNotifier<bool>(false);

/// Increments when a measurement window must restart: a mode change or a
/// video state change. The HUD drops frames from the old window.
final ValueNotifier<int> appDiagnosticWindowEpoch = ValueNotifier<int>(0);

/// Marks the Artist screen's subtree: glass below it reads [disabled].
class AppArtistGlassIsolationScope extends InheritedWidget {
  const AppArtistGlassIsolationScope({
    super.key,
    required this.disabled,
    required super.child,
  });

  final bool disabled;

  /// Whether glass at [context] sits on the Artist screen with glass disabled.
  /// False everywhere else, so the diagnostic reaches no other screen.
  static bool disabledOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<AppArtistGlassIsolationScope>()
          ?.disabled ??
      false;

  @override
  bool updateShouldNotify(AppArtistGlassIsolationScope oldWidget) =>
      oldWidget.disabled != disabled;
}

/// Wraps the Artist screen. Reports whether its video plays and applies the
/// current isolation to the glass beneath it. Nothing else changes.
class AppArtistGlassIsolationHost extends ConsumerStatefulWidget {
  const AppArtistGlassIsolationHost({
    super.key,
    required this.videoPlaying,
    required this.child,
  });

  final bool videoPlaying;
  final Widget child;

  @override
  ConsumerState<AppArtistGlassIsolationHost> createState() =>
      _AppArtistGlassIsolationHostState();
}

class _AppArtistGlassIsolationHostState
    extends ConsumerState<AppArtistGlassIsolationHost> {
  @override
  void initState() {
    super.initState();
    _report();
  }

  @override
  void didUpdateWidget(AppArtistGlassIsolationHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoPlaying != widget.videoPlaying) _report();
  }

  // Notifiers are written after the frame, never during build.
  void _report() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (appArtistVideoPlaying.value != widget.videoPlaying) {
        appArtistVideoPlaying.value = widget.videoPlaying;
        appDiagnosticWindowEpoch.value++;
      }
    });
  }

  @override
  void dispose() {
    // The screen is leaving: the HUD should show the video as off.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      appArtistVideoPlaying.value = false;
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disabled =
        ref.watch(appArtistGlassIsolationProvider) ==
        AppArtistGlassIsolation.glassDisabled;
    return AppArtistGlassIsolationScope(
      disabled: disabled,
      child: widget.child,
    );
  }
}

/// How the Artist header band and its controls read a playing video.
enum AppArtistVideoBand {
  /// The band blurs the live video each frame (the default).
  live,

  /// The band uses the still cover as its ground: no live read of the video.
  still,
}

class AppArtistVideoBandNotifier extends Notifier<AppArtistVideoBand> {
  @override
  AppArtistVideoBand build() => AppArtistVideoBand.live;

  void toggle() {
    state = state == AppArtistVideoBand.live
        ? AppArtistVideoBand.still
        : AppArtistVideoBand.live;
    appDiagnosticWindowEpoch.value++;
  }
}

/// Developer-only for now: switched from the performance HUD, never persisted.
final appArtistVideoBandProvider =
    NotifierProvider<AppArtistVideoBandNotifier, AppArtistVideoBand>(
      AppArtistVideoBandNotifier.new,
    );
