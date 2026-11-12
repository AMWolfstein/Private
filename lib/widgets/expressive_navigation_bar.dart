import 'package:flutter/material.dart';

/// Side navigation for wide layouts: the collapsed Material 3 Expressive
/// rail, with labels under the icons and a pill indicator that springs
/// between destinations. Reduced motion keeps Flutter's [NavigationRail].
class ExpressiveNavigationRail extends StatelessWidget {
  const ExpressiveNavigationRail({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.backgroundColor,
  });

  final List<NavigationDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    // The rail needs ~300dp of height for four labeled destinations; on
    // short viewports it must scroll, not overflow.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(
            child: NavigationRail(
              selectedIndex: selectedIndex,
              onDestinationSelected: onDestinationSelected,
              labelType: NavigationRailLabelType.all,
              backgroundColor: backgroundColor,
              destinations: [
                for (final destination in destinations)
                  NavigationRailDestination(
                    icon: destination.icon,
                    selectedIcon: destination.selectedIcon,
                    label: Text(destination.label),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
