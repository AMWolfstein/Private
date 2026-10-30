import 'package:flutter/material.dart';
import 'package:sistrum/utils/layout/adaptive_layout.dart';

/// Background fill for grouped cards, matching the Settings group look. Blends a
/// translucent overlay over the surface so it stays visible on AMOLED (pure
/// black) dark themes as well as normal light/dark themes.
Color settingsGroupColor(BuildContext context) {
  final colorScheme = Theme.of(context).colorScheme;
  return colorScheme.surfaceContainer;
}

class SettingsGroup extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry? margin;

  const SettingsGroup({super.key, required this.children, this.margin});

  @override
  Widget build(BuildContext context) {
    final cardColor = settingsGroupColor(context);

    final decoration = BoxDecoration(
      color: cardColor,
      borderRadius: BorderRadius.circular(28),
      border: null,
    );
    final child = Material(
      color: Colors.transparent,
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );

    // Explicit caller margin wins as-is. Otherwise center on wide surfaces
    // using the incoming constraint (not screen width) so groups nested in an
    // already clamped box, e.g. a bottom sheet, are not over-inset.
    if (margin != null) {
      return Container(
        margin: margin,
        decoration: decoration,
        clipBehavior: Clip.antiAlias,
        child: child,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) => Container(
        margin: EdgeInsets.symmetric(
          horizontal:
              16 +
              (constraints.hasBoundedWidth
                  ? wideInsetForWidth(constraints.maxWidth)
                  : 0),
          vertical: 4,
        ),
        decoration: decoration,
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}

/// The grouped list appearance with rows built only near the viewport.
class SliverSettingsGroup extends StatelessWidget {
  const SliverSettingsGroup({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.margin,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) => SliverPadding(
    padding: margin,
    sliver: SliverList.builder(
      itemCount: itemCount,
      itemBuilder: (context, index) {
        final first = index == 0;
        final last = index == itemCount - 1;
        final radius = BorderRadius.vertical(
          top: first ? const Radius.circular(28) : Radius.zero,
          bottom: last ? const Radius.circular(28) : Radius.zero,
        );
        final row = Material(
          color: settingsGroupColor(context),
          clipBehavior: Clip.antiAlias,
          borderRadius: radius,
          child: itemBuilder(context, index),
        );
        return row;
      },
    ),
  );
}
