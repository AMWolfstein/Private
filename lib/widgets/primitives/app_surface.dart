import 'package:flutter/material.dart';

/// Opaque rounded surface for panels, menus, dialogs, snack bars and
/// floating sheets. The fill is a solid theme colour; nothing behind it is
/// read or blurred.
class AppSurface extends StatelessWidget {
  const AppSurface({
    super.key,
    required this.child,
    this.radius = 32,
    this.color,
    this.outlined = false,
  });

  final Widget child;
  final double radius;

  /// Defaults to the theme's raised surface colour.
  final Color? color;

  /// Adds a hairline outline in the theme's outline colour.
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final borderRadius = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? scheme.surfaceContainerHigh,
        borderRadius: borderRadius,
        border: outlined ? Border.all(color: scheme.outlineVariant) : null,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Material(type: MaterialType.transparency, child: child),
      ),
    );
  }
}
