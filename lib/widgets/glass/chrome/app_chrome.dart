import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
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
    this.highlightIntensity = 1,
    this.glassProgress = 1,
  });

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
    this.highlightIntensity = 1,
    this.glassProgress = 1,
  }) : strongTint = true;

  final Widget child;
  final double radius;
  final bool firstInGroup;
  final bool lastInGroup;
  final bool strongTint;
  final double? tintOpacity;
  final Color? tintColor;
  final bool blurEnabled;
  final bool highlightBorder;
  final double highlightIntensity;
  final double glassProgress;

  @override
  Widget build(BuildContext context, WidgetRef ref) => AppGlass(
    radius: radius,
    firstInGroup: firstInGroup,
    lastInGroup: lastInGroup,
    strongTint: strongTint,
    tintOpacity: tintOpacity,
    tintColor: tintColor,
    blurEnabled: blurEnabled && ref.watch(appBlurEnabledProvider),
    highlightBorder: highlightBorder,
    highlightIntensity: highlightIntensity,
    glassProgress: glassProgress,
    // Tile ink must paint above the glass tint rather than beneath it.
    child: Material(type: MaterialType.transparency, child: child),
  );
}
