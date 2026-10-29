import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/services/library/cover_palette.dart';
import 'package:sistrum/theme/app_glass_levels.dart';
import 'package:sistrum/theme/app_theme.dart';
import 'package:sistrum/widgets/glass/app_artwork_ground.dart';
import 'package:sistrum/widgets/glass/app_backdrop_groups.dart';
import 'package:sistrum/widgets/glass/app_glass_surface.dart';
import 'package:sistrum/widgets/header/profile_avatar.dart';

/// Every pinned header control (back circle, action capsule, profile photo)
/// is this tall; the player keeps its own controls.
const double kAppHeaderControlSize = 48;

/// Space between a header control and the visible screen edge.
const double kAppHeaderEdgeGap = 4;

/// Glyph size of every header icon.
const double kAppHeaderIconSize = 22;

/// How a pinned header floats over its page.
enum AppHeaderMaterial {
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
bool appLiquidChromeEnabled(BuildContext context, WidgetRef ref) =>
    ref.watch(appShaderFiltersSupportedProvider) &&
    ref.watch(appLiquidGlassProvider) &&
    !appGlassClarity(
      ref.watch(appGlassClarityLevelProvider),
    ).plainBlur &&
    !MediaQuery.disableAnimationsOf(context) &&
    !ref.watch(
      appGlassContrastBlockedProvider(MediaQuery.highContrastOf(context)),
    );

AppHeaderMaterial appHeaderMaterial(
  BuildContext context,
  WidgetRef ref,
) {
  final translucent =
      ref.watch(appGlassLevelProvider) != AppGlassLevel.flat &&
      !ref.watch(
        appGlassContrastBlockedProvider(MediaQuery.highContrastOf(context)),
      );
  if (!translucent) return AppHeaderMaterial.opaque;
  return appLiquidChromeEnabled(context, ref)
      ? AppHeaderMaterial.glass
      : AppHeaderMaterial.frosted;
}

/// Status-bar icons for a header whose backdrop has [brightness]. Set
/// explicitly: a transparent AppBar would otherwise be estimated as dark.
SystemUiOverlayStyle appHeaderOverlayStyle(Brightness brightness) =>
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: brightness == Brightness.dark
          ? Brightness.light
          : Brightness.dark,
      statusBarBrightness: brightness,
    );

/// Header backdrop verdict for artwork: dark below the package's split.
Brightness? appArtworkBrightness(double? lightness) => lightness == null
    ? null
    : lightness < 0.6
    ? Brightness.dark
    : Brightness.light;

/// Fades a backing band in behind the toolbar while content is scrolled under
/// it, so the collapsed title and controls never sit bare over artwork.
///
/// [visible] defaults to the enclosing sliver app bar's scrolled-under state.
class AppHeaderBacking extends ConsumerWidget {
  const AppHeaderBacking({super.key, this.visible, this.color});

  final bool? visible;

  /// Defaults to the page's scaffold background.
  final Color? color;

  static const _duration = Duration(milliseconds: 180);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final material = appHeaderMaterial(context, ref);
    if (material == AppHeaderMaterial.opaque) {
      return const SizedBox.shrink();
    }
    final shown =
        visible ??
        context
            .dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>()
            ?.isScrolledUnder ??
        false;
    final sigma = ref.watch(appHeaderBandBlurDisabledProvider)
        ? 0.0
        : appGlassClarity(
            ref.watch(appGlassClarityLevelProvider),
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
              : AppBackdropReadMarker(backdropId: null, child: edge),
        );
      },
    );
  }
}

/// Toolbar controls (the leading circle, the actions) share the shell's
/// chrome read with the bottom bar. Glass inside page content must not join:
/// it paints before the content below it, which the batch could then no
/// longer see.
class AppHeaderControls extends StatelessWidget {
  const AppHeaderControls({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // On album and artist pages the controls draw from the header artwork.
    final page = AppArtworkGroundScope.pageOf(context);
    return AppChromeMember(
      child: page == null
          ? child
          : AppArtworkGroundScope(controller: page, child: child),
    );
  }
}

/// A glass circle around a header [IconButton], matching HeaderCircleButton.
class AppHeaderCircle extends ConsumerWidget {
  const AppHeaderCircle({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final button = _HeaderIconTheme(child: child);
    if (appHeaderMaterial(context, ref) == AppHeaderMaterial.opaque) {
      return button;
    }
    return AppHeaderControls(
      child: Center(
        widthFactor: 1,
        child: _HeaderGlass(
          child: SizedBox.square(
            dimension: kAppHeaderControlSize,
            child: Center(child: button),
          ),
        ),
      ),
    );
  }
}

/// Trailing header actions: runs of [IconButton]s and menu buttons share one
/// glass capsule, followed by the profile photo at the trailing end.
class AppHeaderActions extends ConsumerWidget {
  const AppHeaderActions({
    super.key,
    this.actions = const [],
    this.showProfile = true,
  });

  final List<Widget> actions;

  /// Appends [HeaderProfileButton], which hides itself inside Settings.
  final bool showProfile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (appHeaderMaterial(context, ref) == AppHeaderMaterial.opaque) {
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
    return AppHeaderControls(
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
          height: kAppHeaderControlSize,
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
        minimumSize: const Size.square(kAppHeaderControlSize),
        iconSize: kAppHeaderIconSize,
        foregroundColor: foregroundColor,
      ),
    ),
    child: IconTheme.merge(
      data: const IconThemeData(size: kAppHeaderIconSize),
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
    return AppGlass.navigation(
      radius: kAppHeaderControlSize / 2,
      tintColor: dark ? Colors.black : Colors.white,
      tintOpacity: dark ? 0.45 : 0.55,
      blurEnabled: ref.watch(appBlurEnabledProvider),
      allowLens: appLiquidChromeEnabled(context, ref),
      child: child,
    );
  }
}

/// Repaints header controls for a backdrop of [brightness] (artwork behind a
/// transparent toolbar). The theme is built once per brightness, not per
/// scroll frame.
class AppHeaderBrightness extends StatefulWidget {
  const AppHeaderBrightness({
    super.key,
    required this.brightness,
    required this.child,
  });

  /// Null keeps the surrounding theme.
  final Brightness? brightness;
  final Widget child;

  @override
  State<AppHeaderBrightness> createState() =>
      _AppHeaderBrightnessState();
}

class _AppHeaderBrightnessState extends State<AppHeaderBrightness> {
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
      _theme = AppTheme.fromContext(context, brightness: brightness);
    }
    return Theme(
      data: _theme!,
      child: HeaderPalette(scheme: _theme!.colorScheme, child: widget.child),
    );
  }
}
