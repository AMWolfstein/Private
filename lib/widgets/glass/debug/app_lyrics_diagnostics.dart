import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/widgets/glass/debug/app_artist_glass_isolation.dart';

/// Developer-only switches for isolating the Now Playing lyrics' GPU cost.
/// Each flag group can be turned off on its own, from the performance HUD, on
/// the Now Playing route only. Every flag is on by default, which is the
/// normal rendering, and none is persisted.
@immutable
class AppLyricsDiagnostics {
  const AppLyricsDiagnostics({
    this.glass = true,
    this.background = true,
    this.text = true,
    this.motion = true,
  });

  /// A: the lyrics' glass (Glass Engine V2 surfaces, including the g1455
  /// slider and its capture) draws as Tint only.
  final bool glass;

  /// B: the player background's artwork effects (its gradient mask and the
  /// drift) draw as a plain image.
  final bool background;

  /// C: lyric text effects: the per-line blur, the sung-word glow and the
  /// viewport's edge mask. Text is still laid out, scrolled and drawn.
  final bool text;

  /// D: lyric animations: line transitions, scale and opacity. The current
  /// line stays visible.
  final bool motion;

  AppLyricsDiagnostics toggled(AppLyricsDiagnosticGroup group) =>
      switch (group) {
        AppLyricsDiagnosticGroup.glass => AppLyricsDiagnostics(
          glass: !glass,
          background: background,
          text: text,
          motion: motion,
        ),
        AppLyricsDiagnosticGroup.background => AppLyricsDiagnostics(
          glass: glass,
          background: !background,
          text: text,
          motion: motion,
        ),
        AppLyricsDiagnosticGroup.text => AppLyricsDiagnostics(
          glass: glass,
          background: background,
          text: !text,
          motion: motion,
        ),
        AppLyricsDiagnosticGroup.motion => AppLyricsDiagnostics(
          glass: glass,
          background: background,
          text: text,
          motion: !motion,
        ),
      };

  bool get isNormal => glass && background && text && motion;
}

/// The four groups the HUD switches, A to D.
enum AppLyricsDiagnosticGroup { glass, background, text, motion }

class AppLyricsDiagnosticsNotifier extends Notifier<AppLyricsDiagnostics> {
  @override
  AppLyricsDiagnostics build() => const AppLyricsDiagnostics();

  void toggle(AppLyricsDiagnosticGroup group) {
    state = state.toggled(group);
    // A new measurement window starts with every change.
    appDiagnosticWindowEpoch.value++;
  }
}

final appLyricsDiagnosticsProvider =
    NotifierProvider<AppLyricsDiagnosticsNotifier, AppLyricsDiagnostics>(
      AppLyricsDiagnosticsNotifier.new,
    );

/// Provides [AppLyricsDiagnostics] to the Now Playing subtree. Outside it,
/// everything is normal, so overlays and other routes are never affected.
class AppLyricsDiagnosticScope extends ConsumerWidget {
  const AppLyricsDiagnosticScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _Scope(value: ref.watch(appLyricsDiagnosticsProvider), child: child);

  static AppLyricsDiagnostics of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_Scope>()?.value ??
      const AppLyricsDiagnostics();
}

class _Scope extends InheritedWidget {
  const _Scope({required this.value, required super.child});

  final AppLyricsDiagnostics value;

  @override
  bool updateShouldNotify(_Scope oldWidget) => oldWidget.value != value;
}

/// A [ShaderMask] that is built only while [masked]. Diagnostic (developer
/// only): with a lyrics or background effect switched off, its mask layer is
/// not built, and the child draws unmasked.
///
/// The child keeps one [GlobalKey] either way, so switching the mask on or off
/// reparents the child rather than rebuilding it. A rebuilt child would lose
/// its scroll position.
class AppDiagnosticShaderMask extends StatefulWidget {
  const AppDiagnosticShaderMask({
    super.key,
    required this.masked,
    required this.shaderCallback,
    required this.child,
    this.blendMode = BlendMode.dstIn,
  });

  final bool masked;
  final ShaderCallback shaderCallback;
  final BlendMode blendMode;
  final Widget child;

  @override
  State<AppDiagnosticShaderMask> createState() =>
      _AppDiagnosticShaderMaskState();
}

class _AppDiagnosticShaderMaskState extends State<AppDiagnosticShaderMask> {
  final _child = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final content = KeyedSubtree(key: _child, child: widget.child);
    return widget.masked
        ? ShaderMask(
            blendMode: widget.blendMode,
            shaderCallback: widget.shaderCallback,
            child: content,
          )
        : content;
  }
}
