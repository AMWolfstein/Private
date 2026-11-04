import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g1455/g1455.dart' show GlassFinish, GlassSurface;
import 'package:sistrum/core/theme/app_glass_levels.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/widgets/glass/artwork/app_artwork_ground.dart';
import 'package:sistrum/widgets/glass/artwork/app_artwork_glass.dart';
import 'package:sistrum/widgets/glass/debug/app_artist_glass_isolation.dart';
import 'package:sistrum/widgets/glass/debug/app_lyrics_diagnostics.dart';
import 'package:sistrum/widgets/glass/thumb/app_glass_look.dart';

/// The rendering mode of one glass surface (Glass Engine V2).
///
/// [auto] picks a mode from the context: GROUND over a known artwork ground,
/// TINT where glass is off (flat level, high contrast, low-end devices) or
/// nested in other glass, and FROSTED otherwise. It never picks LIQUID: a
/// a surface opts in with [liquid] where its backdrop is captured by the host.
/// [ground] falls back to FROSTED when no artwork ground is known; [liquid]
/// and [frosted] are what they name, and [tint] never samples.
enum AppGlassMode { auto, ground, frosted, liquid, tint }

/// Sistrum's finish for LIQUID surfaces: the refraction is the Tinted Lite
/// blur and the surface fill above it sets the colour, as it did over the
/// blur. Surfaces read the current look's with [appLiquidGlassFinish].
final GlassFinish kAppLiquidGlassFinish = appLiquidGlassFinish(
  AppGlassLook.sistrum,
);

/// Glass Engine V2 surface: GROUND, FROSTED, LIQUID or TINT.
///
/// - GROUND: over known artwork (the player, album and artist headers) it
///   draws the artwork's pre-blurred ground and reads no backdrop.
/// - LIQUID ([AppGlassMode.liquid]): the backdrop is refracted through a `GlassSurface`
///   from the `g1455` package, under the host's one capture. Small chrome only.
/// - FROSTED: a backdrop blur clipped to the glass bounds. The default.
/// - TINT: an opaque or translucent fill with no sampling, for flat levels,
///   low-end devices and surfaces nested inside another glass surface.
///
/// A surface inside another glass surface draws its fill only, so nested
/// glass never samples twice. Foreground content stays above the glass.
class AppGlass extends ConsumerWidget {
  const AppGlass({
    super.key,
    required this.child,
    required this.blurEnabled,
    this.radius = 32,
    this.firstInGroup = true,
    this.lastInGroup = true,
    this.strongTint = false,
    this.tintOpacity,
    this.tintColor,
    this.highlightBorder = false,
    this.highlightIntensity = 1,
    this.glassProgress = 1,
    this.samplesBackdrop = true,
    this.dropShadow = true,
    this.mode = AppGlassMode.auto,
  });

  final Widget child;
  final bool blurEnabled;
  final double radius;
  final bool firstInGroup;
  final bool lastInGroup;
  final bool strongTint;
  final double? tintOpacity;
  final Color? tintColor;

  /// The rendering mode; [AppGlassMode.auto] unless a surface needs a fixed
  /// one. See [AppGlassMode].
  final AppGlassMode mode;

  /// Paint the rim above the fill so tinted popovers keep a visible edge.
  final bool highlightBorder;
  final double highlightIntensity;

  /// Reveal glass through its tint, without isolating the backdrop in opacity.
  final double glassProgress;

  /// Plain-page surfaces keep their tint without filtering a uniform backdrop.
  final bool samplesBackdrop;

  /// The soft contact shadow under the surface. Buttons turn it off; the rim
  /// stays on every glass surface.
  final bool dropShadow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final style = kAppGlassStyle;
    final reveal = glassProgress.clamp(0.0, 1.0);
    final translucent =
        reveal > 0 &&
        blurEnabled &&
        ref.watch(appGlassLevelProvider) != AppGlassLevel.flat &&
        !ref.watch(
          appGlassContrastBlockedProvider(MediaQuery.highContrastOf(context)),
        );
    final dark = scheme.brightness == Brightness.dark;
    final look = ref.watch(appGlassLookProvider);
    final shape = BorderRadius.vertical(
      top: firstInGroup ? Radius.circular(radius) : Radius.zero,
      bottom: lastInGroup ? Radius.circular(radius) : Radius.zero,
    );
    final artworkTint = Theme.of(context).extension<AppTheme>()?.chromeSurface;
    var tintSource =
        tintColor ?? (dark ? scheme.surfaceContainerHigh : Colors.white);
    var opacity = tintOpacity ?? (strongTint ? 0.80 : 0.60);
    if (tintColor == null && artworkTint != null) {
      // The artwork colour is already known; keep its hue with a richer tint
      // instead of a saturation filter over changing page content.
      final hsl = HSLColor.fromColor(scheme.surfaceContainerHigh);
      final coverTint = hsl
          .withSaturation((hsl.saturation * 1.6).clamp(0, 1))
          .toColor();
      tintSource = dark
          ? coverTint
          : Color.lerp(Colors.white, coverTint, 0.15)!;
      opacity = opacity.clamp(0.60, 1.0);
    }
    // Light glass needs a white veil over saturated or dark artwork.
    var baseTint = tintSource.withValues(
      alpha: dark ? opacity * 0.82 : (opacity * 0.88).clamp(0.50, 1.0),
    );
    if (dark) {
      // Bound bright artwork with paint instead of filtering backdrop luma.
      baseTint = Color.alphaBlend(
        baseTint,
        Colors.black.withValues(alpha: 0.35),
      );
    }
    // The style's veil of surface colour over the tint.
    final tint = translucent
        ? Color.alphaBlend(
            scheme.surfaceContainerHigh.withValues(alpha: style.tint),
            baseTint,
          )
        : scheme.surfaceContainerHigh;
    final insideGlass =
        context.dependOnInheritedWidgetOfExactType<_GlassBackdropScope>() !=
        null;
    final sampleBackdrop = translucent && samplesBackdrop && !insideGlass;
    final single = firstInGroup && lastInGroup;
    // Over known artwork glass draws from that artwork's ground and reads no
    // backdrop.
    final ground = sampleBackdrop && single
        ? AppArtworkGroundScope.maybeOf(context)
        : null;
    final clearFill = (dark ? const Color(0xff999999) : Colors.white)
        .withValues(alpha: dark ? 0.17 : 0.46);
    final fill = Color.lerp(
      scheme.surfaceContainerHigh,
      // Plain-page surfaces match sampled ones; nested ones keep the tint.
      translucent && !strongTint && !insideGlass
          ? Color.lerp(tint, clearFill, style.clearFill)!
          : tint,
      reveal,
    )!;
    final surface = DecoratedBox(
      decoration: BoxDecoration(color: fill, borderRadius: shape),
      // Child controls paint on this surface; never re-blur their parent.
      child: _GlassBackdropScope(child: child),
    );
    final shadows = single && dropShadow
        ? [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.14 : 0.08),
              blurRadius: 8,
              blurStyle: BlurStyle.outer,
              offset: const Offset(0, 2),
            ),
          ]
        : null;
    // A LIQUID surface over a playing video reads the live backdrop instead
    // (see [AppLiveVideoBackdrop]).
    final liveVideoFallback =
        mode == AppGlassMode.liquid && AppLiveVideoBackdrop.of(context);
    // Header controls over a live video sit inside the header band once it
    // is fully shown, and the band already blurs the same video under them:
    // they are then nested glass and draw their fill only, so the page is
    // copied once for the band instead of once more for the controls.
    final insideLiveBand =
        liveVideoFallback &&
        BackdropGroup.of(context) != null &&
        AppLiveVideoBand.coversOf(context);
    // The Artist diagnostic (developer only) turns its glass into Tint.
    final effectiveMode =
        AppArtistGlassIsolationScope.disabledOf(context) ||
            !AppLyricsDiagnosticScope.of(context).glass ||
            insideLiveBand
        ? AppGlassMode.tint
        : liveVideoFallback
        ? AppGlassMode.frosted
        : mode;
    // The one place a surface's mode becomes a rendering. A known artwork
    // ground wins for GROUND, AUTO and LIQUID: it is the artwork itself, read
    // without a live backdrop. TINT, or a surface that reads nothing, draws
    // its fill; LIQUID refracts the host's capture; everything else blurs.
    final useGround =
        ground != null &&
        (effectiveMode == AppGlassMode.auto ||
            effectiveMode == AppGlassMode.ground ||
            effectiveMode == AppGlassMode.liquid);
    final body = useGround
        ? AppArtworkGlassSurface(
            controller: ground,
            fill: fill,
            opaqueFill: scheme.surfaceContainerHigh,
            child: _GlassBackdropScope(child: child),
          )
        : !sampleBackdrop || effectiveMode == AppGlassMode.tint
        ? surface
        : effectiveMode == AppGlassMode.liquid
        ? GlassSurface(
            borderRadius: shape,
            finish: appLiquidGlassFinish(look),
            labelled: false,
            child: surface,
          )
        : BackdropFilter(
            filter: appFrostFilter(look),
            // Header controls over a live video share one backdrop read: the
            // engine copies and blurs the page once for all of them, not once
            // per control (see [AppHeaderControls]).
            backdropGroupKey: liveVideoFallback
                ? BackdropGroup.of(context)?.backdropKey
                : null,
            child: surface,
          );
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: shape, boxShadow: shadows),
      child: CustomPaint(
        foregroundPainter: _AppGlassRim(
          shape: shape,
          firstInGroup: firstInGroup,
          lastInGroup: lastInGroup,
          illuminated: translucent,
          emphasized: highlightBorder,
          dark: dark,
          contactEdge: appGlassContactEdge(look, dark: dark),
          highlightIntensity: highlightIntensity * reveal,
        ),
        child: ClipRRect(borderRadius: shape, child: body),
      ),
    );
  }
}

class _GlassBackdropScope extends InheritedWidget {
  const _GlassBackdropScope({required super.child});

  @override
  bool updateShouldNotify(_GlassBackdropScope oldWidget) => false;
}

/// The rim: a hairline edge, plus a light band on translucent glass.
class _AppGlassRim extends CustomPainter {
  const _AppGlassRim({
    required this.shape,
    required this.firstInGroup,
    required this.lastInGroup,
    required this.illuminated,
    required this.emphasized,
    required this.dark,
    required this.contactEdge,
    required this.highlightIntensity,
  });

  final BorderRadius shape;
  final bool firstInGroup;
  final bool lastInGroup;
  final bool illuminated;
  final bool emphasized;
  final bool dark;
  final Color contactEdge;
  final double highlightIntensity;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final bounds = Offset.zero & size;
    final outline = shape.toRRect(
      Rect.fromLTRB(
        0,
        firstInGroup ? 0 : -2,
        size.width,
        lastInGroup ? size.height : size.height + 2,
      ),
    );
    canvas.save();
    canvas.clipRect(bounds);
    void stroke(double inset, Paint paint) =>
        canvas.drawRRect(outline.deflate(inset), paint);

    stroke(
      0.25,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5
        // A thin contact edge must not paint a shadow under the whole glass.
        ..color = contactEdge,
    );
    if (illuminated) {
      stroke(
        0.8,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = emphasized ? 1 : 0.6
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [0, 0.14, 0.5, 0.86, 1],
            colors:
                [
                      firstInGroup
                          ? Color(emphasized ? 0x88ffffff : 0x40ffffff)
                          : Colors.transparent,
                      Color(emphasized ? 0x26ffffff : 0x0dffffff),
                      const Color(0x0a000000),
                      Color(emphasized ? 0x20ffffff : 0x0dffffff),
                      lastInGroup
                          ? Color(emphasized ? 0x55ffffff : 0x26ffffff)
                          : Colors.transparent,
                    ]
                    .map(
                      (color) =>
                          color.withValues(alpha: color.a * highlightIntensity),
                    )
                    .toList(),
          ).createShader(bounds),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AppGlassRim oldDelegate) =>
      shape != oldDelegate.shape ||
      firstInGroup != oldDelegate.firstInGroup ||
      lastInGroup != oldDelegate.lastInGroup ||
      illuminated != oldDelegate.illuminated ||
      emphasized != oldDelegate.emphasized ||
      highlightIntensity != oldDelegate.highlightIntensity ||
      dark != oldDelegate.dark ||
      contactEdge != oldDelegate.contactEdge;
}

/// Marks a subtree whose backdrop is a playing video. A texture is not
/// readable by a LIQUID capture (it leaves a hole), so glass there must read
/// the live backdrop with FROSTED instead.
///
/// [backdropKey] is the one shared read for the header controls there: every
/// backdrop read costs a copy of the whole screen per frame while the video
/// plays, so the controls (which never overlap) take one between them. It must
/// be a stable object: a new key every build would read as a changed layer.
class AppLiveVideoBackdrop extends InheritedWidget {
  const AppLiveVideoBackdrop({
    super.key,
    required this.live,
    this.backdropKey,
    required super.child,
  });

  final bool live;
  final BackdropKey? backdropKey;

  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<AppLiveVideoBackdrop>()
          ?.live ??
      false;

  /// The shared backdrop key under a live video, or null.
  static BackdropKey? keyOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AppLiveVideoBackdrop>();
    return scope != null && scope.live ? scope.backdropKey : null;
  }

  @override
  bool updateShouldNotify(AppLiveVideoBackdrop oldWidget) =>
      oldWidget.live != live || oldWidget.backdropKey != backdropKey;
}

/// Whether the header band over a live video is fully shown with its blur:
/// written by `AppHeaderBacking` after each frame, read by the header
/// controls' glass (see [AppGlass]). False everywhere else.
class AppLiveVideoBand extends InheritedNotifier<ValueNotifier<bool>> {
  const AppLiveVideoBand({
    super.key,
    required ValueNotifier<bool> covers,
    required super.child,
  }) : super(notifier: covers);

  static bool coversOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<AppLiveVideoBand>()
          ?.notifier
          ?.value ??
      false;

  /// The notifier itself, for the band that writes it; no dependency.
  static ValueNotifier<bool>? notifierOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppLiveVideoBand>()?.notifier;
}
