import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/services/library/covers/cover_palette.dart';
import 'package:sistrum/core/theme/app_glass_levels.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/widgets/glass/artwork/app_artwork_ground.dart';
import 'package:sistrum/widgets/glass/debug/app_artist_glass_isolation.dart';
import 'package:sistrum/widgets/glass/thumb/app_glass_surface.dart';
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
  /// Flat level, low-end device or high contrast: the opaque toolbar.
  opaque,

  /// Transparent toolbar; Tinted Lite glass controls.
  tinted,
}

AppHeaderMaterial appHeaderMaterial(BuildContext context, WidgetRef ref) {
  final translucent =
      ref.watch(appGlassLevelProvider) != AppGlassLevel.flat &&
      !ref.watch(
        appGlassContrastBlockedProvider(MediaQuery.highContrastOf(context)),
      );
  return translucent ? AppHeaderMaterial.tinted : AppHeaderMaterial.opaque;
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
  const AppHeaderBacking({
    super.key,
    this.visible,
    this.color,
    this.groundVeil = false,
  });

  final bool? visible;

  /// The header sits over the page's artwork ground, which already softens the
  /// artwork beneath it. The band then draws no live blur; its tint alone holds
  /// the toolbar. Without an artwork ground it keeps the live blur.
  final bool groundVeil;

  /// Defaults to the page's scaffold background.
  final Color? color;

  static const _duration = Duration(milliseconds: 180);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final material = appHeaderMaterial(context, ref);
    // Over a live video, tells the header controls whether this band fully
    // covers them with its blur (see AppLiveVideoBand).
    final bandCovers = AppLiveVideoBand.notifierOf(context);
    void report(bool covers) {
      if (bandCovers == null || bandCovers.value == covers) return;
      // After the frame: the controls are not rebuilt in the middle of one.
      // A band gone by then (its page closed) has nothing to report, and its
      // notifier may be gone with it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) bandCovers.value = covers;
      });
    }

    if (material == AppHeaderMaterial.opaque) {
      report(false);
      return const SizedBox.shrink();
    }
    final shown =
        visible ??
        context
            .dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>()
            ?.isScrolledUnder ??
        false;
    // Over an artwork ground the artwork beneath is already softened by the
    // ground veil, so the band needs no live read of the page.
    final onGround =
        groundVeil && AppArtworkGroundScope.pageOf(context) != null;
    // The Artist diagnostic (developer only) draws this band as Tint alone.
    final sigma =
        onGround ||
            ref.watch(appHeaderBandBlurDisabledProvider) ||
            AppArtistGlassIsolationScope.disabledOf(context)
        ? 0.0
        : kAppGlassStyle.blurSigma;
    final base = color ?? Theme.of(context).scaffoldBackgroundColor;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: shown ? 1 : 0),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : _duration,
      builder: (context, amount, _) {
        report(sigma > 0 && amount >= 1 && AppLiveVideoBackdrop.of(context));
        if (amount == 0) return const SizedBox.shrink();
        // Hold the tint across the toolbar and feather only its last third.
        // The blur fades with it, so the band never shows a hard edge.
        final band = DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0, 0.68, 1],
              colors: [
                base.withValues(alpha: 0.72 * amount),
                base.withValues(alpha: 0.72 * amount),
                base.withValues(alpha: 0),
              ],
            ),
          ),
          child: const SizedBox.expand(),
        );
        final backing = sigma == 0
            ? band
            : ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: sigma * amount,
                    sigmaY: sigma * amount,
                  ),
                  child: band,
                ),
              );
        return KeyedSubtree(
          key: const ValueKey('sistrum-header-backing'),
          child: backing,
        );
      },
    );
  }
}

/// Toolbar controls (the leading circle, the actions). On album and artist
/// pages they draw from the header artwork's ground.
class AppHeaderControls extends StatelessWidget {
  const AppHeaderControls({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // On album and artist pages the controls draw from the header artwork.
    final page = AppArtworkGroundScope.pageOf(context);
    final grounded = page == null
        ? child
        : AppArtworkGroundScope(controller: page, child: child);
    // Over a playing video they read the live page instead, through one
    // backdrop shared by the leading and trailing controls.
    final shared = AppLiveVideoBackdrop.keyOf(context);
    return shared == null
        ? grounded
        : BackdropGroup(backdropKey: shared, child: grounded);
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
        foregroundColor: AppTheme.accentColor(Theme.of(context).brightness),
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
      // A lone action is a circle, like the back button; several share a capsule.
      children.add(
        run.length == 1
            ? AppHeaderCircle(child: run.first)
            : _HeaderCapsule(children: run),
      );
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
    return Center(
      widthFactor: 1,
      child: _HeaderGlass(
        child: SizedBox(
          height: kAppHeaderControlSize,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: _HeaderIconTheme(
              foregroundColor: AppTheme.accentColor(
                Theme.of(context).brightness,
              ),
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

/// The header controls' shared glass: HeaderCircleButton's tint and a
/// capsule radius, drawn as Tinted Lite.
class _HeaderGlass extends ConsumerWidget {
  const _HeaderGlass({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = HeaderPalette.of(context);
    final dark = scheme.brightness == Brightness.dark;
    return AppGlass(
      mode: AppGlassMode.liquid,
      dropShadow: false,
      radius: kAppHeaderControlSize / 2,
      tintColor: dark ? Colors.black : Colors.white,
      tintOpacity: dark ? 0.45 : 0.55,
      blurEnabled: ref.watch(appBlurEnabledProvider),
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
  State<AppHeaderBrightness> createState() => _AppHeaderBrightnessState();
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
