import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/services/library/covers/cover_palette.dart';
import 'package:sistrum/widgets/header/profile_avatar.dart';

/// Every pinned header control (back circle, action run, profile photo)
/// is this tall; the player keeps its own controls.
const double kAppHeaderControlSize = 48;

/// Space between a header control and the visible screen edge.
const double kAppHeaderEdgeGap = 4;

/// Glyph size of every header icon.
const double kAppHeaderIconSize = 22;

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

/// Fades a solid band in behind the toolbar while content is scrolled under
/// it, so the collapsed title and controls never sit bare over artwork.
///
/// [visible] defaults to the enclosing sliver app bar's scrolled-under state.
class AppHeaderBacking extends StatelessWidget {
  const AppHeaderBacking({super.key, this.visible, this.color});

  final bool? visible;

  /// Defaults to the page's scaffold background.
  final Color? color;

  static const _duration = Duration(milliseconds: 180);

  @override
  Widget build(BuildContext context) {
    final shown =
        visible ??
        context
            .dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>()
            ?.isScrolledUnder ??
        false;
    final base = color ?? Theme.of(context).scaffoldBackgroundColor;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: shown ? 1 : 0),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : _duration,
      builder: (context, amount, _) {
        if (amount == 0) return const SizedBox.shrink();
        return ColoredBox(
          key: const ValueKey('sistrum-header-backing'),
          color: base.withValues(alpha: amount),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

/// Toolbar controls share one plain layout; they sit directly on the page.
class AppHeaderControls extends StatelessWidget {
  const AppHeaderControls({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// A round header button around an [IconButton], matching HeaderCircleButton.
class AppHeaderCircle extends StatelessWidget {
  const AppHeaderCircle({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => AppHeaderControls(
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: appHeaderControlFill(context),
        shape: BoxShape.circle,
      ),
      child: _HeaderIconTheme(child: child),
    ),
  );
}

/// The solid fill of a header control: the tint that Mornye's glass circles
/// and capsules carry over a page, flattened to one opaque colour.
Color appHeaderControlFill(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return scheme.brightness == Brightness.dark
      ? Color.alphaBlend(Colors.black.withValues(alpha: 0.45), scheme.surface)
      : Color.alphaBlend(Colors.white.withValues(alpha: 0.55), scheme.surface);
}

/// A solid capsule that groups header actions, sized like the header controls.
class _HeaderCapsule extends StatelessWidget {
  const _HeaderCapsule({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: appHeaderControlFill(context),
      borderRadius: BorderRadius.circular(kAppHeaderControlSize / 2),
    ),
    child: SizedBox(
      height: kAppHeaderControlSize,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    ),
  );
}

/// Trailing header actions followed by the profile photo at the trailing
/// end.
class AppHeaderActions extends StatelessWidget {
  const AppHeaderActions({
    super.key,
    this.actions = const [],
    this.showProfile = true,
  });

  final List<Widget> actions;

  /// Appends [HeaderProfileButton], which hides itself inside Settings.
  final bool showProfile;

  @override
  Widget build(BuildContext context) {
    return _HeaderIconTheme(
      foregroundColor: AppTheme.accentColor(Theme.of(context).brightness),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (actions.isNotEmpty) _HeaderCapsule(children: actions),
          if (showProfile) HeaderProfileButton(gap: actions.isEmpty ? 0 : 8),
        ],
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
