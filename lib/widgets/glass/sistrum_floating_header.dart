import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/services/cover_palette.dart';
import 'package:sistrum/theme/sistrum_glass_levels.dart';
import 'package:sistrum/theme/sistrum_theme.dart';
import 'package:sistrum/widgets/glass/sistrum_artwork_glass.dart';
import 'package:sistrum/widgets/glass/sistrum_backdrop_groups.dart';
import 'package:sistrum/widgets/glass/sistrum_chrome.dart';
import 'package:sistrum/widgets/header/profile_avatar.dart';

/// Every pinned header control (back circle, action capsule, profile photo)
/// is this tall; the player keeps its own controls.
const double kSistrumHeaderControlSize = 48;

/// Space between a header control and the visible screen edge.
const double kSistrumHeaderEdgeGap = 4;

/// Glyph size of every header icon.
const double kSistrumHeaderIconSize = 22;

/// How a pinned header floats over its page.
enum SistrumHeaderMaterial {
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
bool sistrumLiquidChromeEnabled(BuildContext context, WidgetRef ref) =>
    ref.watch(sistrumShaderFiltersSupportedProvider) &&
    ref.watch(sistrumLiquidGlassProvider) &&
    !sistrumGlassClarity(
      ref.watch(sistrumGlassClarityLevelProvider),
    ).plainBlur &&
    !MediaQuery.disableAnimationsOf(context) &&
    !ref.watch(
      sistrumGlassContrastBlockedProvider(MediaQuery.highContrastOf(context)),
    );

SistrumHeaderMaterial sistrumHeaderMaterial(
  BuildContext context,
  WidgetRef ref,
) {
  final translucent =
      ref.watch(sistrumGlassLevelProvider) != SistrumGlassLevel.flat &&
      !ref.watch(
        sistrumGlassContrastBlockedProvider(MediaQuery.highContrastOf(context)),
      );
  if (!translucent) return SistrumHeaderMaterial.opaque;
  return sistrumLiquidChromeEnabled(context, ref)
      ? SistrumHeaderMaterial.glass
      : SistrumHeaderMaterial.frosted;
}

/// Status-bar icons for a header whose backdrop has [brightness]. Set
/// explicitly: a transparent AppBar would otherwise be estimated as dark.
SystemUiOverlayStyle sistrumHeaderOverlayStyle(Brightness brightness) =>
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: brightness == Brightness.dark
          ? Brightness.light
          : Brightness.dark,
      statusBarBrightness: brightness,
    );

/// Header backdrop verdict for artwork: dark below the package's split.
Brightness? sistrumArtworkBrightness(double? lightness) => lightness == null
    ? null
    : lightness < 0.6
    ? Brightness.dark
    : Brightness.light;

/// Fades a backing band in behind the toolbar while content is scrolled under
/// it, so the collapsed title and controls never sit bare over artwork.
///
/// [visible] defaults to the enclosing sliver app bar's scrolled-under state.
class SistrumHeaderBacking extends ConsumerWidget {
  const SistrumHeaderBacking({super.key, this.visible, this.color});

  final bool? visible;

  /// Defaults to the page's scaffold background.
  final Color? color;

  static const _duration = Duration(milliseconds: 180);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final material = sistrumHeaderMaterial(context, ref);
    if (material == SistrumHeaderMaterial.opaque) {
      return const SizedBox.shrink();
    }
    final shown =
        visible ??
        context
            .dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>()
            ?.isScrolledUnder ??
        false;
    final sigma = ref.watch(sistrumHeaderBandBlurDisabledProvider)
        ? 0.0
        : sistrumGlassClarity(
            ref.watch(sistrumGlassClarityLevelProvider),
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
          key: const ValueKey('sistrum-header-backing'),
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
              : SistrumBackdropReadMarker(backdropId: null, child: edge),
        );
      },
    );
  }
}

/// Toolbar controls (the leading circle, the actions) share the shell's
/// chrome read with the bottom bar. Glass inside page content must not join:
/// it paints before the content below it, which the batch could then no
/// longer see.
class SistrumHeaderControls extends StatelessWidget {
  const SistrumHeaderControls({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // On album and artist pages the controls draw from the header artwork.
    final page = SistrumArtworkGroundScope.pageOf(context);
    return SistrumChromeMember(
      child: page == null
          ? child
          : SistrumArtworkGroundScope(controller: page, child: child),
    );
  }
}

/// A glass circle around a header [IconButton], matching HeaderCircleButton.
class SistrumHeaderCircle extends ConsumerWidget {
  const SistrumHeaderCircle({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final button = _HeaderIconTheme(child: child);
    if (sistrumHeaderMaterial(context, ref) == SistrumHeaderMaterial.opaque) {
      return button;
    }
    return SistrumHeaderControls(
      child: Center(
        widthFactor: 1,
        child: _HeaderGlass(
          child: SizedBox.square(
            dimension: kSistrumHeaderControlSize,
            child: Center(child: button),
          ),
        ),
      ),
    );
  }
}

/// Trailing header actions: runs of [IconButton]s and menu buttons share one
/// glass capsule, followed by the profile photo at the trailing end.
class SistrumHeaderActions extends ConsumerWidget {
  const SistrumHeaderActions({
    super.key,
    this.actions = const [],
    this.showProfile = true,
  });

  final List<Widget> actions;

  /// Appends [HeaderProfileButton], which hides itself inside Settings.
  final bool showProfile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (sistrumHeaderMaterial(context, ref) == SistrumHeaderMaterial.opaque) {
      return _HeaderIconTheme(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...actions,
            if (showProfile) HeaderProfileButton(gap: actions.isEmpty ? 0 : 8),
          ],
        ),
      );
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
      if (action is IconButton || action is PopupMenuButton) {
        run.add(action);
        continue;
      }
      flush();
      if (children.isNotEmpty) children.add(const SizedBox(width: 8));
      children.add(action);
    }
    flush();
    if (showProfile) {
      children.add(HeaderProfileButton(gap: children.isEmpty ? 0 : 8));
    }
    return SistrumHeaderControls(
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
          height: kSistrumHeaderControlSize,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: _HeaderIconTheme(
              foregroundColor: scheme.onSurface,
              child: Row(mainAxisSize: MainAxisSize.min, children: children),
            ),
          ),
        ),
      ),
    );
  }
}

/// Header icon buttons and menus: 48dp targets with 22dp glyphs.
class _HeaderIconTheme extends StatelessWidget {
  const _HeaderIconTheme({required this.child, this.foregroundColor});

  final Widget child;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) => IconButtonTheme(
    data: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size.square(kSistrumHeaderControlSize),
        iconSize: kSistrumHeaderIconSize,
        foregroundColor: foregroundColor,
      ),
    ),
    child: IconTheme.merge(
      data: const IconThemeData(size: kSistrumHeaderIconSize),
      child: child,
    ),
  );
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
    return SistrumGlass.navigation(
      radius: kSistrumHeaderControlSize / 2,
      tintColor: dark ? Colors.black : Colors.white,
      tintOpacity: dark ? 0.45 : 0.55,
      blurEnabled: ref.watch(sistrumBlurEnabledProvider),
      allowLens: sistrumLiquidChromeEnabled(context, ref),
      child: child,
    );
  }
}

/// Repaints header controls for a backdrop of [brightness] (artwork behind a
/// transparent toolbar). The theme is built once per brightness, not per
/// scroll frame.
class SistrumHeaderBrightness extends StatefulWidget {
  const SistrumHeaderBrightness({
    super.key,
    required this.brightness,
    required this.child,
  });

  /// Null keeps the surrounding theme.
  final Brightness? brightness;
  final Widget child;

  @override
  State<SistrumHeaderBrightness> createState() =>
      _SistrumHeaderBrightnessState();
}

class _SistrumHeaderBrightnessState extends State<SistrumHeaderBrightness> {
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
      _theme = SistrumTheme.fromContext(context, brightness: brightness);
    }
    return Theme(
      data: _theme!,
      child: HeaderPalette(scheme: _theme!.colorScheme, child: widget.child),
    );
  }
}
