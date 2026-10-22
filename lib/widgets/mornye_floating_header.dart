import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:spotiflac_android/providers/runtime_profile_provider.dart';
import 'package:spotiflac_android/theme/cover_palette.dart';
import 'package:spotiflac_android/theme/mornye_glass_levels.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';
import 'package:spotiflac_android/widgets/mornye_artwork_glass.dart';
import 'package:spotiflac_android/widgets/mornye_backdrop_groups.dart';
import 'package:spotiflac_android/widgets/mornye_chrome.dart';

/// How a pinned header floats over its page.
enum MornyeHeaderMaterial {
  /// Glass off (or Auto under high contrast): the old opaque toolbar.
  opaque,

  /// Transparent toolbar; blurred lite controls (lite glass, Level 1,
  /// reduced motion or no shader filters).
  frosted,

  /// Transparent toolbar; liquid-glass lens controls.
  glass,
}

/// Liquid header and bar chrome (lenses, the bar's adaptive sampler) needs
/// the shader renderer, full glass above Level 1, motion and no contrast
/// request.
bool mornyeLiquidChromeEnabled(BuildContext context, WidgetRef ref) =>
    ref.watch(mornyeShaderFiltersSupportedProvider) &&
    ref.watch(mornyeLiquidGlassProvider) &&
    !mornyeGlassClarity(ref.watch(mornyeGlassClarityLevelProvider)).plainBlur &&
    !MediaQuery.disableAnimationsOf(context) &&
    !ref.watch(
      mornyeGlassContrastBlockedProvider(MediaQuery.highContrastOf(context)),
    );

MornyeHeaderMaterial mornyeHeaderMaterial(BuildContext context, WidgetRef ref) {
  final translucent =
      ref.watch(mornyeGlassLevelProvider) != MornyeGlassLevel.flat &&
      !ref.watch(
        mornyeGlassContrastBlockedProvider(MediaQuery.highContrastOf(context)),
      );
  if (!translucent) return MornyeHeaderMaterial.opaque;
  return mornyeLiquidChromeEnabled(context, ref)
      ? MornyeHeaderMaterial.glass
      : MornyeHeaderMaterial.frosted;
}

/// Status-bar icons for a header whose backdrop has [brightness]. Set
/// explicitly: a transparent AppBar would otherwise be estimated as dark.
SystemUiOverlayStyle mornyeHeaderOverlayStyle(Brightness brightness) =>
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: brightness == Brightness.dark
          ? Brightness.light
          : Brightness.dark,
      statusBarBrightness: brightness,
    );

/// Header backdrop verdict for artwork: dark below the package's split.
Brightness? mornyeArtworkBrightness(double? lightness) => lightness == null
    ? null
    : lightness < 0.6
    ? Brightness.dark
    : Brightness.light;

/// Fades a backing band in behind the toolbar while content is scrolled under
/// it, so the collapsed title and controls never sit bare over artwork.
///
/// [visible] defaults to the enclosing sliver app bar's scrolled-under state.
class MornyeHeaderBacking extends ConsumerWidget {
  const MornyeHeaderBacking({super.key, this.visible, this.color});

  final bool? visible;

  /// Defaults to the page's scaffold background.
  final Color? color;

  static const _duration = Duration(milliseconds: 180);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final material = mornyeHeaderMaterial(context, ref);
    if (material == MornyeHeaderMaterial.opaque) return const SizedBox.shrink();
    final shown =
        visible ??
        context
            .dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>()
            ?.isScrolledUnder ??
        false;
    final sigma = ref.watch(mornyeHeaderBandBlurDisabledProvider)
        ? 0.0
        : mornyeGlassClarity(
            ref.watch(mornyeGlassClarityLevelProvider),
          ).blurSigma;
    final base = color ?? Theme.of(context).scaffoldBackgroundColor;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: shown ? 1 : 0),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : _duration,
      builder: (context, amount, _) {
        if (amount == 0) return const SizedBox.shrink();
        // Hold the tint across the toolbar and feather only its last third.
        // Opacity would isolate the blur from the page, so fade by value.
        final edge = LiquidGlassScrollEdge(
          key: const ValueKey('mornye-header-backing'),
          edge: LiquidGlassEdge.top,
          color: base.withValues(alpha: 0.72 * amount),
          blur: sigma * amount,
          curve: const Interval(0.68, 1, curve: Curves.easeIn),
          blurCurve: const Interval(0.68, 1, curve: Curves.easeIn),
        );
        // The header controls float over the band and must see it, so the
        // band reads on its own, outside the chrome batch.
        return LiquidGlassBatch.exclude(
          child: sigma == 0
              ? edge
              : MornyeBackdropReadMarker(backdropId: null, child: edge),
        );
      },
    );
  }
}

/// Toolbar controls (the leading circle, the actions) share the shell's
/// chrome read with the bottom bar. Glass inside page content must not join:
/// it paints before the content below it, which the batch could then no
/// longer see.
class MornyeHeaderControls extends StatelessWidget {
  const MornyeHeaderControls({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // On album and artist pages the controls draw from the header artwork.
    final page = MornyeArtworkGroundScope.pageOf(context);
    return MornyeChromeMember(
      child: page == null
          ? child
          : MornyeArtworkGroundScope(controller: page, child: child),
    );
  }
}

/// A glass circle around a header [IconButton], matching HeaderCircleButton.
class MornyeHeaderCircle extends ConsumerWidget {
  const MornyeHeaderCircle({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (mornyeHeaderMaterial(context, ref) == MornyeHeaderMaterial.opaque) {
      return child;
    }
    return MornyeHeaderControls(
      child: Center(
        widthFactor: 1,
        child: _HeaderGlass(
          child: SizedBox.square(dimension: 44, child: Center(child: child)),
        ),
      ),
    );
  }
}

/// Trailing header actions: runs of [IconButton]s share one glass capsule.
/// Other actions (the profile avatar, menus) keep their own shape.
class MornyeHeaderActions extends ConsumerWidget {
  const MornyeHeaderActions({super.key, required this.actions});

  final List<Widget> actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (mornyeHeaderMaterial(context, ref) == MornyeHeaderMaterial.opaque) {
      return Row(mainAxisSize: MainAxisSize.min, children: actions);
    }
    final children = <Widget>[];
    var run = <Widget>[];
    void flush() {
      if (run.isEmpty) return;
      if (children.isNotEmpty) children.add(const SizedBox(width: 8));
      children.add(_HeaderCapsule(children: run));
      run = <Widget>[];
    }

    for (final action in actions) {
      if (action is IconButton) {
        run.add(action);
        continue;
      }
      flush();
      if (children.isNotEmpty) children.add(const SizedBox(width: 8));
      children.add(action);
    }
    flush();
    return MornyeHeaderControls(
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

class _HeaderCapsule extends StatelessWidget {
  const _HeaderCapsule({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = HeaderPalette.of(context);
    return Center(
      widthFactor: 1,
      child: _HeaderGlass(
        child: SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: IconButtonTheme(
              data: IconButtonThemeData(
                style: IconButton.styleFrom(
                  minimumSize: const Size.square(44),
                  foregroundColor: scheme.onSurface,
                ),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: children),
            ),
          ),
        ),
      ),
    );
  }
}

/// The header controls' shared glass: HeaderCircleButton's tint, a capsule
/// radius, and the frosted blur instead of a lens when liquid is not allowed.
class _HeaderGlass extends ConsumerWidget {
  const _HeaderGlass({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = HeaderPalette.of(context);
    final dark = scheme.brightness == Brightness.dark;
    return MornyeGlass.navigation(
      radius: 22,
      tintColor: dark ? Colors.black : Colors.white,
      tintOpacity: dark ? 0.45 : 0.55,
      blurEnabled: ref.watch(mornyeBlurEnabledProvider),
      allowLens: mornyeLiquidChromeEnabled(context, ref),
      child: child,
    );
  }
}

/// Repaints header controls for a backdrop of [brightness] (artwork behind a
/// transparent toolbar). The theme is built once per brightness, not per
/// scroll frame.
class MornyeHeaderBrightness extends StatefulWidget {
  const MornyeHeaderBrightness({
    super.key,
    required this.brightness,
    required this.child,
  });

  /// Null keeps the surrounding theme.
  final Brightness? brightness;
  final Widget child;

  @override
  State<MornyeHeaderBrightness> createState() => _MornyeHeaderBrightnessState();
}

class _MornyeHeaderBrightnessState extends State<MornyeHeaderBrightness> {
  ThemeData? _source;
  Brightness? _built;
  ThemeData? _theme;

  @override
  Widget build(BuildContext context) {
    final brightness = widget.brightness;
    final source = Theme.of(context);
    // The same Theme > HeaderPalette shape either way, so a verdict arriving
    // mid-scroll does not remount the app bar below.
    if (brightness == null || brightness == source.brightness) {
      return Theme(
        data: source,
        child: HeaderPalette(
          scheme: HeaderPalette.of(context),
          child: widget.child,
        ),
      );
    }
    if (!identical(source, _source) || brightness != _built) {
      _source = source;
      _built = brightness;
      _theme = MornyeTheme.fromContext(context, brightness: brightness);
    }
    return Theme(
      data: _theme!,
      child: HeaderPalette(scheme: _theme!.colorScheme, child: widget.child),
    );
  }
}
