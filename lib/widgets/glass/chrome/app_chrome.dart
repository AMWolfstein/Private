import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/widgets/glass/artwork/app_artwork_ground.dart';
import 'package:sistrum/widgets/glass/thumb/app_glass_surface.dart';

/// Shared material for panels, menus, dialogs and floating sheets.
class AppGlassPanel extends ConsumerWidget {
  const AppGlassPanel({
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

  const AppGlassPanel.overlay({
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
    final glass = AppGlass.navigation(
      radius: radius,
      firstInGroup: firstInGroup,
      lastInGroup: lastInGroup,
      strongTint: strongTint,
      tintOpacity: tintOpacity,
      tintColor: tintColor,
      blurEnabled: blurEnabled && ref.watch(appBlurEnabledProvider),
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
    return _composedBackdrop && AppArtworkGroundScope.maybeOf(context) == null
        ? LiquidGlassBatch(child: glass)
        : glass;
  }
}
