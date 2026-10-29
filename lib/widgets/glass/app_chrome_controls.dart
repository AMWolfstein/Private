
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/theme/app_glass_levels.dart';
import 'package:sistrum/theme/app_theme.dart';
import 'package:sistrum/widgets/animation_indicators.dart';
import 'package:sistrum/widgets/glass/app_glass_surface.dart';
import 'package:sistrum/widgets/glass/app_selection_pill.dart';

class AppSegmentedControl extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final height = (MediaQuery.textScalerOf(context).scale(15) + 36).clamp(
      56.0,
      double.infinity,
    );
    final contrastBlocked = ref.watch(
      appGlassContrastBlockedProvider(MediaQuery.highContrastOf(context)),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SizedBox(
        height: height,
        child: AppGlass.navigation(
          blurEnabled: ref.watch(appBlurEnabledProvider),
          radius: height / 2,
          // Sits on the plain settings page: tint, no backdrop at rest.
          samplesBackdrop: false,
          child: AppSelectionPill(
            contrastBlocked: contrastBlocked,
            // Touch-only glass: a held lens also under lite, never Level 1.
            liquidInteraction:
                ref.watch(appBlurEnabledProvider) &&
                !appGlassClarity(
                  ref.watch(appGlassClarityLevelProvider),
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
      child: AppSelectionForeground(child: Icon(icon)),
    ),
  );
}

class AppTabBar extends ConsumerWidget {
  const AppTabBar({
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
      appGlassContrastBlockedProvider(MediaQuery.highContrastOf(context)),
    );
    final clarity = appGlassClarity(
      ref.watch(appGlassClarityLevelProvider),
    );
    final floating = usesLiquidGlass(
      context,
      blurEnabled: blurEnabled,
      liquidGlass: liquidGlass,
      contrastBlocked: contrastBlocked,
    );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: floating ? 8 : 0),
      child: AppSelectionPill(
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
                child: AppGlass.navigation(
                  blurEnabled: blurEnabled,
                  strongTint: true,
                  tintOpacity: AppTheme.navigationOpacity(context),
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
                    child: destinations[index].icon is AppNavigationIcon
                        ? destinations[index].icon
                        : AppSelectionForeground(
                            child: destinations[index].icon,
                          ),
                  ),
                ),
                const SizedBox(height: 2),
                AppSelectionForeground(
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
