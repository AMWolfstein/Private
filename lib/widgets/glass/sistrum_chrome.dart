import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/theme/sistrum_theme.dart';
import 'package:sistrum/widgets/glass/sistrum_selection_pill.dart';
import 'package:sistrum/theme/sistrum_glass_levels.dart';
import 'package:sistrum/widgets/glass/sistrum_artwork_glass.dart';
import 'package:sistrum/widgets/glass/sistrum_backdrop_groups.dart';
import 'package:sistrum/widgets/glass/sistrum_liquid_backdrop.dart';
import 'package:sistrum/widgets/glass/sistrum_squircle_border.dart';
import 'package:sistrum/widgets/animation_utils.dart';

class SistrumSegmentedControl extends ConsumerWidget {
  const SistrumSegmentedControl({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final height = (MediaQuery.textScalerOf(context).scale(15) + 36).clamp(
      56.0,
      double.infinity,
    );
    final contrastBlocked = ref.watch(
      sistrumGlassContrastBlockedProvider(MediaQuery.highContrastOf(context)),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SizedBox(
        height: height,
        child: SistrumGlass.navigation(
          blurEnabled: ref.watch(sistrumBlurEnabledProvider),
          radius: height / 2,
          // Sits on the plain settings page: tint, no backdrop at rest.
          samplesBackdrop: false,
          child: SistrumSelectionPill(
            contrastBlocked: contrastBlocked,
            // Touch-only glass: a held lens also under lite, never Level 1.
            liquidInteraction:
                ref.watch(sistrumBlurEnabledProvider) &&
                !sistrumGlassClarity(
                  ref.watch(sistrumGlassClarityLevelProvider),
                ).plainBlur,
            labels: labels,
            selectedIndex: selectedIndex,
            onChanged: onChanged,
            itemBuilder: (context, index, selected) => Center(
              child: Text(
                labels[index],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared material for panels, menus, dialogs and floating sheets.
class SistrumGlassPanel extends ConsumerWidget {
  const SistrumGlassPanel({
    super.key,
    required this.child,
    this.radius = 32,
    this.firstInGroup = true,
    this.lastInGroup = true,
    this.strongTint = false,
    this.tintOpacity,
    this.tintColor,
    this.blurEnabled = true,
    this.highlightBorder = false,
    this.smoothCorners = false,
    this.highlightIntensity = 1,
    this.glassProgress = 1,
    this.clarityLevel,
  }) : _composedBackdrop = false;

  const SistrumGlassPanel.overlay({
    super.key,
    required this.child,
    this.radius = 32,
    this.firstInGroup = true,
    this.lastInGroup = true,
    this.tintOpacity = 0.78,
    this.tintColor,
    this.blurEnabled = true,
    this.highlightBorder = false,
    this.smoothCorners = false,
    this.highlightIntensity = 1,
    this.glassProgress = 1,
  }) : strongTint = true,
       clarityLevel = null,
       _composedBackdrop = true;

  final Widget child;
  final double radius;
  final bool firstInGroup;
  final bool lastInGroup;
  final bool strongTint;
  final double? tintOpacity;
  final Color? tintColor;
  final bool blurEnabled;
  final bool highlightBorder;
  final bool smoothCorners;
  final double highlightIntensity;
  final double glassProgress;

  /// Renders this panel at a fixed clarity level instead of the saved one,
  /// e.g. the Appearance preview while its slider is being dragged.
  final int? clarityLevel;
  final bool _composedBackdrop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final glass = SistrumGlass.navigation(
      radius: radius,
      firstInGroup: firstInGroup,
      lastInGroup: lastInGroup,
      strongTint: strongTint,
      tintOpacity: tintOpacity,
      tintColor: tintColor,
      blurEnabled: blurEnabled && ref.watch(sistrumBlurEnabledProvider),
      highlightBorder: highlightBorder,
      smoothCorners: smoothCorners,
      highlightIntensity: highlightIntensity,
      glassProgress: glassProgress,
      clarityLevel: clarityLevel,
      // Tile ink must paint above the glass tint rather than beneath it.
      child: Material(type: MaterialType.transparency, child: child),
    );
    // One overlay gets its own key: the package composes blur and refraction
    // into one backdrop read, including while the route moves. Sharing that
    // key with the page or another overlapping menu would lose their glass.
    // Over a known ground there is no read to share.
    return _composedBackdrop &&
            SistrumArtworkGroundScope.maybeOf(context) == null
        ? LiquidGlassBatch(child: glass)
        : glass;
  }
}

/// Bounded glass: Impeller lenses refract a blurred backdrop, while frosted
/// surfaces are blur passes. Either joins the enclosing batch (the shell's
/// chrome batch only for SistrumChromeMember chrome), so its read is shared. Foreground content stays above glass.
class SistrumGlass extends ConsumerWidget {
  const SistrumGlass({
    super.key,
    required this.child,
    required this.blurEnabled,
    this.radius = 32,
    this.strongTint = false,
    this.tintOpacity,
    this.tintColor,
    this.highlightBorder = false,
    this.refractionDepth = 0.30,
    this.smoothCorners = false,
    this.highlightIntensity = 1,
    this.glassProgress = 1,
  }) : firstInGroup = true,
       lastInGroup = true,
       samplesBackdrop = true,
       allowLens = true,
       clarityLevel = null;

  const SistrumGlass.navigation({
    super.key,
    required this.child,
    required this.blurEnabled,
    this.radius = 32,
    this.firstInGroup = true,
    this.lastInGroup = true,
    this.strongTint = false,
    this.tintOpacity,
    this.tintColor,
    this.samplesBackdrop = true,
    this.highlightBorder = false,
    this.refractionDepth = 0.30,
    this.smoothCorners = false,
    this.highlightIntensity = 1,
    this.glassProgress = 1,
    this.clarityLevel,
    this.allowLens = true,
  });

  // One shared filter per clarity level; never rebuilt per frame.
  static final _blurs = [
    for (final level in kSistrumGlassLevels)
      ImageFilter.blur(sigmaX: level.blurSigma, sigmaY: level.blurSigma),
  ];

  final Widget child;
  final bool blurEnabled;
  final double radius;
  final bool firstInGroup;
  final bool lastInGroup;
  final bool strongTint;
  final double? tintOpacity;
  final Color? tintColor;

  /// Paint the edge above the fill so tinted popovers retain a visible rim.
  final bool highlightBorder;
  final double refractionDepth;
  final bool smoothCorners;
  final double highlightIntensity;

  /// Reveal glass through its tint, without isolating the backdrop in opacity.
  final double glassProgress;

  /// Plain-page surfaces keep their tint without filtering a uniform backdrop.
  final bool samplesBackdrop;

  /// Overrides the saved clarity level for this surface only.
  final int? clarityLevel;

  /// False keeps a liquid-level surface on lite glass, e.g. header chrome
  /// while animations are disabled.
  final bool allowLens;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final clarity = sistrumGlassClarity(
      clarityLevel ?? ref.watch(sistrumGlassClarityLevelProvider),
    );
    final level = ref.watch(sistrumGlassLevelProvider);
    final reveal = glassProgress.clamp(0.0, 1.0);
    final translucent =
        reveal > 0 &&
        blurEnabled &&
        level != SistrumGlassLevel.flat &&
        !ref.watch(
          sistrumGlassContrastBlockedProvider(
            MediaQuery.highContrastOf(context),
          ),
        );
    final dark = scheme.brightness == Brightness.dark;
    final outlines = ref.watch(sistrumGlassOutlinesProvider);
    final shape = BorderRadius.vertical(
      top: firstInGroup ? Radius.circular(radius) : Radius.zero,
      bottom: lastInGroup ? Radius.circular(radius) : Radius.zero,
    );
    final artworkTint = Theme.of(
      context,
    ).extension<SistrumTheme>()?.chromeSurface;
    var tintSource =
        tintColor ?? (dark ? scheme.surfaceContainerHigh : Colors.white);
    var opacity = tintOpacity ?? (strongTint ? 0.80 : 0.60);
    if (tintColor == null && artworkTint != null) {
      // The artwork color is already known; retain its hue with a richer tint
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
    // Keep this in the existing fill so whitening adds no backdrop pass.
    // Chrome whose palette follows its sampled backdrop needs no such floor:
    // over dark content it turns dark instead.
    final clearChrome =
        !dark &&
        tintColor == null &&
        artworkTint == null &&
        SistrumAdaptiveChromeScope.isActive(context);
    var baseTint = tintSource.withValues(
      alpha: dark
          ? opacity * 0.82
          : clearChrome
          ? opacity * clarity.barFill
          : (opacity * 0.88).clamp(0.50, 1.0),
    );
    if (dark) {
      // Bound bright artwork with paint instead of filtering backdrop luma.
      baseTint = Color.alphaBlend(
        baseTint,
        Colors.black.withValues(alpha: 0.35),
      );
    }
    // The level's veil of surface colour; Crystal shows the page through.
    final tint = translucent
        ? Color.alphaBlend(
            scheme.surfaceContainerHigh.withValues(alpha: clarity.tint),
            baseTint,
          )
        : scheme.surfaceContainerHigh;
    final insideGlass =
        context.dependOnInheritedWidgetOfExactType<_GlassBackdropScope>() !=
        null;
    final sampleBackdrop = translucent && samplesBackdrop && !insideGlass;
    final single = firstInGroup && lastInGroup;
    // Level 1 is always a plain blur; lenses need full glass and Impeller.
    final lensAllowed =
        !clarity.plainBlur &&
        allowLens &&
        level == SistrumGlassLevel.liquid &&
        ref.watch(sistrumShaderFiltersSupportedProvider);
    // Over known artwork (the player, album and artist headers) glass draws
    // from that artwork's ground and reads no backdrop.
    final ground = sampleBackdrop && single
        ? SistrumArtworkGroundScope.maybeOf(context)
        : null;
    final useLens = ground == null && sampleBackdrop && single && lensAllowed;
    // Every other single surface is a blur plus LiquidGlassLite's painted
    // rim (Level 1, lite glass, or full glass without a lens).
    final liteRim =
        ground == null && sampleBackdrop && !useLens && single && outlines;
    final clearFill = (dark ? const Color(0xff999999) : Colors.white)
        .withValues(alpha: dark ? 0.17 : 0.46);
    final fill = Color.lerp(
      scheme.surfaceContainerHigh,
      // Plain-page surfaces match sampled ones; nested ones keep the tint.
      translucent && !strongTint && !insideGlass
          ? Color.lerp(tint, clearFill, clarity.clearFill)
          : tint,
      reveal,
    );
    final squircle = smoothCorners && firstInGroup && lastInGroup;
    final surface = DecoratedBox(
      decoration: squircle
          ? ShapeDecoration(color: fill, shape: SistrumSquircleBorder(radius))
          : BoxDecoration(color: fill, borderRadius: shape),
      // Child controls paint on this surface; never re-blur their parent.
      child: _GlassBackdropScope(child: child),
    );
    final shadows = firstInGroup && lastInGroup
        ? [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.14 : 0.08),
              blurRadius: 8,
              blurStyle: BlurStyle.outer,
              offset: const Offset(0, 2),
            ),
          ]
        : null;
    // Page glass under the shell's chrome batch keeps a read of its own.
    final ownRead = sistrumOutsideChromeBatch(context);
    final backdrop = ground != null
        ? SistrumArtworkGlassSurface(
            controller: ground,
            lens: lensAllowed,
            fill: fill!,
            opaqueFill: scheme.surfaceContainerHigh,
            radius: radius,
            squircle: squircle,
            refractionDepth: refractionDepth,
            refractionWidth: 20,
            dispersion: clarity.dispersion,
            child: _GlassBackdropScope(child: child),
          )
        : useLens
        ? _maybeExclude(
            ownRead,
            SistrumLiquidBackdrop(
              borderRadius: shape,
              dispersion: clarity.dispersion,
              blurSigma: clarity.blurSigma,
              refractionDepth: refractionDepth * reveal,
              smoothCorners: squircle,
              highlightIntensity: highlightIntensity * reveal,
              child: surface,
            ),
          )
        : sampleBackdrop
        ? SistrumBackdropBlur(
            filter: _blurs[clarity.level - 1],
            // Shares the enclosing batch's read, as a lens would.
            backdropId: sistrumBlurBackdropId(
              context,
              impeller: ref.watch(sistrumShaderFiltersSupportedProvider),
            ),
            child: liteRim
                ? LiquidGlassLite(
                    shape: sistrumGlassShape(
                      radius: radius,
                      smoothCorners: squircle,
                    ),
                    specular: sistrumGlassSpecular(
                      outlines: true,
                      dark: dark,
                      intensity: highlightIntensity * reveal,
                    ),
                    glow: sistrumGlassGlow(
                      outlines: true,
                      intensity: highlightIntensity * reveal,
                    ),
                    // The grouped filter above is the frost; the lite only
                    // paints its rim and reads nothing.
                    blur: 0,
                    child: surface,
                  )
                : surface,
          )
        : surface;
    return DecoratedBox(
      decoration: squircle
          ? ShapeDecoration(
              shape: SistrumSquircleBorder(radius),
              shadows: shadows,
            )
          : BoxDecoration(borderRadius: shape, boxShadow: shadows),
      child: CustomPaint(
        // The optical lens already draws its own rim. Avoid a second dark
        // contact stroke on top, particularly visible against light pages.
        foregroundPainter:
            outlines && ((!useLens && !liteRim) || highlightBorder)
            ? _SistrumGlassRim(
                shape: shape,
                firstInGroup: firstInGroup,
                lastInGroup: lastInGroup,
                illuminated:
                    translucent && ((!useLens && !liteRim) || highlightBorder),
                emphasized: highlightBorder,
                dark: dark,
                smoothCorners: squircle,
                highlightIntensity: highlightIntensity * reveal,
              )
            : null,
        child: squircle
            ? ClipPath.shape(
                shape: SistrumSquircleBorder(radius),
                child: backdrop,
              )
            : ClipRRect(borderRadius: shape, child: backdrop),
      ),
    );
  }
}

Widget _maybeExclude(bool exclude, Widget child) =>
    exclude ? LiquidGlassBatch.exclude(child: child) : child;

/// Marks chrome whose light/dark palette follows a sampled backdrop, so its
/// light glass can drop the readability floor and look clear at rest.
class SistrumAdaptiveChromeScope extends InheritedWidget {
  const SistrumAdaptiveChromeScope({
    super.key,
    required this.active,
    required super.child,
  });

  final bool active;

  static bool isActive(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<SistrumAdaptiveChromeScope>()
          ?.active ??
      false;

  @override
  bool updateShouldNotify(SistrumAdaptiveChromeScope oldWidget) =>
      active != oldWidget.active;
}

class _GlassBackdropScope extends InheritedWidget {
  const _GlassBackdropScope({required super.child});

  @override
  bool updateShouldNotify(_GlassBackdropScope oldWidget) => false;
}

/// Subtle edge definition without another offscreen layer or backdrop read.
class _SistrumGlassRim extends CustomPainter {
  const _SistrumGlassRim({
    required this.shape,
    required this.firstInGroup,
    required this.lastInGroup,
    required this.illuminated,
    required this.emphasized,
    required this.dark,
    required this.smoothCorners,
    required this.highlightIntensity,
  });

  final BorderRadius shape;
  final bool firstInGroup;
  final bool lastInGroup;
  final bool illuminated;
  final bool emphasized;
  final bool dark;
  final bool smoothCorners;
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
    void stroke(double inset, Paint paint) {
      if (smoothCorners) {
        canvas.drawPath(
          SistrumSquircleBorder(
            (shape.topLeft.x - inset).clamp(0, double.infinity),
          ).getOuterPath(bounds.deflate(inset)),
          paint,
        );
      } else {
        canvas.drawRRect(outline.deflate(inset), paint);
      }
    }

    stroke(
      0.25,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5
        // A thin contact edge must not paint a shadow under the whole glass.
        ..color = Colors.black.withValues(alpha: dark ? 0.5 : 0.16),
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
  bool shouldRepaint(covariant _SistrumGlassRim oldDelegate) =>
      shape != oldDelegate.shape ||
      firstInGroup != oldDelegate.firstInGroup ||
      lastInGroup != oldDelegate.lastInGroup ||
      illuminated != oldDelegate.illuminated ||
      emphasized != oldDelegate.emphasized ||
      smoothCorners != oldDelegate.smoothCorners ||
      highlightIntensity != oldDelegate.highlightIntensity ||
      dark != oldDelegate.dark;
}

class SistrumNavigationIcon extends StatelessWidget {
  const SistrumNavigationIcon({
    super.key,
    required this.icon,
    required this.badgeCount,
  });

  final IconData icon;
  final int badgeCount;

  @override
  Widget build(BuildContext context) => AnimatedBadge(
    count: badgeCount,
    child: Badge(
      isLabelVisible: badgeCount > 0,
      label: Text('$badgeCount'),
      child: SistrumSelectionForeground(child: Icon(icon)),
    ),
  );
}

class SistrumTabBar extends ConsumerWidget {
  const SistrumTabBar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.blurEnabled,
    this.liquidGlass = true,
    this.hiddenIconIndices = const {},
    this.contentOpacity = const AlwaysStoppedAnimation(1),
  });

  final List<NavigationDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool blurEnabled;
  final bool liquidGlass;
  final Set<int> hiddenIconIndices;

  /// Fade only the foreground so the backdrop can keep sampling the page.
  final Animation<double> contentOpacity;

  /// The floating layout also supplies the coordinates for collapsing icons.
  static bool usesLiquidGlass(
    BuildContext context, {
    required bool blurEnabled,
    required bool liquidGlass,
    required bool contrastBlocked,
  }) =>
      blurEnabled &&
      liquidGlass &&
      !MediaQuery.disableAnimationsOf(context) &&
      !contrastBlocked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final contrastBlocked = ref.watch(
      sistrumGlassContrastBlockedProvider(MediaQuery.highContrastOf(context)),
    );
    final clarity = sistrumGlassClarity(
      ref.watch(sistrumGlassClarityLevelProvider),
    );
    final floating = usesLiquidGlass(
      context,
      blurEnabled: blurEnabled,
      liquidGlass: liquidGlass,
      contrastBlocked: contrastBlocked,
    );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: floating ? 8 : 0),
      child: SistrumSelectionPill(
        contrastBlocked: contrastBlocked,
        selectionColor: scheme.primary,
        maskItemForeground: false,
        liquidInteraction: floating && !clarity.plainBlur,
        labels: [for (final destination in destinations) destination.label],
        selectedIndex: selectedIndex,
        onChanged: onSelected,
        padding: EdgeInsets.symmetric(
          horizontal: floating ? 6 : 5,
          vertical: 5,
        ),
        interactionBuilder: (context, progress, child) => Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              // Only the capsule projects forward. Icons, labels and touch
              // coordinates stay fixed, and collapse never fades the backdrop.
              child: Transform.scale(
                scaleX: 1 + 0.025 * progress,
                scaleY: 1 + 0.06 * progress,
                child: SistrumGlass.navigation(
                  blurEnabled: blurEnabled,
                  strongTint: true,
                  tintOpacity: SistrumTheme.navigationOpacity(context),
                  refractionDepth: 0.45 + 0.15 * progress,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            // The selection lens can swell beyond the capsule's clip.
            FadeTransition(opacity: contentOpacity, child: child),
          ],
        ),
        itemBuilder: (context, index, selected) => ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 54),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: floating ? 0 : 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconTheme(
                  data: IconThemeData(
                    size: 25,
                    color: selected ? scheme.primary : scheme.onSurface,
                  ),
                  child: Opacity(
                    opacity: hiddenIconIndices.contains(index) ? 0 : 1,
                    child: destinations[index].icon is SistrumNavigationIcon
                        ? destinations[index].icon
                        : SistrumSelectionForeground(
                            child: destinations[index].icon,
                          ),
                  ),
                ),
                const SizedBox(height: 2),
                SistrumSelectionForeground(
                  child: Text(
                    destinations[index].label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: floating ? 11 : null,
                      fontWeight: FontWeight.w600,
                      color: selected ? scheme.primary : scheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
