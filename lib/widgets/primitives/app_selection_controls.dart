import 'package:flutter/material.dart';
import 'package:sistrum/widgets/animation/animation_indicators.dart';

/// A row of equal segments with one sliding selection pill behind the
/// selected segment. Tapping a segment selects it.
class AppSelectionPill extends StatelessWidget {
  const AppSelectionPill({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
    required this.itemBuilder,
    this.padding = const EdgeInsets.all(4),
    this.selectionColor,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final Widget Function(BuildContext context, int index, bool selected)
  itemBuilder;
  final EdgeInsetsGeometry padding;

  /// Colour of the selection pill; defaults to a neutral tint of the
  /// foreground colour.
  final Color? selectionColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final count = labels.length;
    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220);
    final pill = (selectionColor ?? scheme.onSurface).withValues(alpha: 0.12);
    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segment = count == 0 ? 0.0 : constraints.maxWidth / count;
          return SizedBox(
            height: constraints.hasBoundedHeight ? constraints.maxHeight : null,
            child: Stack(
              children: [
                if (count > 0)
                  AnimatedPositionedDirectional(
                    duration: motion,
                    curve: Curves.easeOutCubic,
                    start: segment * selectedIndex,
                    top: 0,
                    bottom: 0,
                    width: segment,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: pill,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                Row(
                  children: [
                    for (var i = 0; i < count; i++)
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: () => onChanged(i),
                          child: Semantics(
                            button: true,
                            selected: i == selectedIndex,
                            child: itemBuilder(context, i, i == selectedIndex),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A compact segmented control (labels in equal segments).
class AppSegmentedControl extends StatelessWidget {
  const AppSegmentedControl({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final height = (MediaQuery.textScalerOf(context).scale(15) + 36).clamp(
      56.0,
      double.infinity,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SizedBox(
        height: height,
        child: AppSelectionPill(
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
    );
  }
}

/// Bottom navigation icon carrying an unread-style count badge.
class AppNavigationIcon extends StatelessWidget {
  const AppNavigationIcon({
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
      child: Icon(icon),
    ),
  );
}

/// The shell's tab bar: one segment per destination with the selected
/// destination's pill behind it.
class AppTabBar extends StatelessWidget {
  const AppTabBar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    this.hiddenIconIndices = const {},
  });

  final List<NavigationDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Set<int> hiddenIconIndices;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppSelectionPill(
      selectionColor: scheme.primary,
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      labels: [for (final destination in destinations) destination.label],
      selectedIndex: selectedIndex,
      onChanged: onSelected,
      itemBuilder: (context, index, selected) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 54),
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
                child: destinations[index].icon,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              destinations[index].label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: selected ? scheme.primary : scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
