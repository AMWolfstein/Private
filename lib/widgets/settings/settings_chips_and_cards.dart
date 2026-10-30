import 'package:flutter/material.dart';
import 'package:sistrum/core/theme/app_icons.dart';
import 'package:sistrum/core/theme/app_tokens.dart';
import 'package:sistrum/widgets/glass/chrome/app_chrome.dart';

/// How a [SettingsChoiceChip] stacks its icon and label.
enum SettingsChipLayout {
  /// Icon beside the label. Fits wide chips in a grid.
  row,

  /// Icon above the label. Fits equal-width chips in a row.
  column,
}

/// Single-select chip used across the settings pages.
class SettingsChoiceChip extends StatelessWidget {
  const SettingsChoiceChip({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.icon,
    this.layout = SettingsChipLayout.row,
    this.expand = false,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final IconData? icon;
  final SettingsChipLayout layout;

  /// Wraps the chip in [Expanded] so a row of chips divides the width evenly.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final borderRadius = BorderRadius.circular(tokens.radiusCover);

    final unselectedColor = Colors.transparent;
    final foreground = isSelected
        ? colorScheme.primary
        : isSelected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;

    final labelText = Text(
      label,
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodyMedium?.copyWith(
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        color: foreground,
      ),
    );

    final Widget content;
    if (icon == null) {
      content = Center(child: labelText);
    } else if (layout == SettingsChipLayout.column) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(context.adaptiveIcon(icon!), color: foreground),
          SizedBox(height: tokens.gapXs + 2),
          labelText,
        ],
      );
    } else {
      content = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(context.adaptiveIcon(icon!), size: 18, color: foreground),
          SizedBox(width: tokens.gapSm),
          Flexible(child: labelText),
        ],
      );
    }

    final chip = Material(
      color: isSelected
          ? (colorScheme.surfaceContainerHighest)
          : unselectedColor,
      borderRadius: borderRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        child: ConstrainedBox(
          // Keeps every chip a comfortable tap target regardless of layout.
          constraints: BoxConstraints(minHeight: tokens.minTouchTarget),
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: tokens.gapMd,
              horizontal: tokens.gapMd,
            ),
            child: content,
          ),
        ),
      ),
    );

    // These chips are one choice in a group; announce which one is active.
    final semantics = Semantics(
      selected: isSelected,
      button: true,
      inMutuallyExclusiveGroup: true,
      child: chip,
    );

    return expand ? Expanded(child: semantics) : semantics;
  }
}

/// Tone of a [SettingsInfoCard].

/// Inline explanatory or warning callout inside a settings page.
class SettingsInfoCard extends StatelessWidget {
  const SettingsInfoCard({
    super.key,
    required this.message,
    this.icon,
    this.title,

    this.margin,
    this.glass = false,
  });

  final String message;
  final IconData? icon;
  final String? title;

  final EdgeInsetsGeometry? margin;

  /// Uses the shared glass surface in Sistrum without changing Material cards.
  final bool glass;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final background = colorScheme.surfaceContainerHighest.withValues(
      alpha: .5,
    );
    final foreground = colorScheme.onSurfaceVariant;
    final useGlass = glass;
    final textColor = useGlass ? colorScheme.onSurface : foreground;
    final content = Padding(
      padding: EdgeInsets.all(tokens.gapLg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(
              useGlass ? appIconFor(icon!) : icon,
              size: 20,
              color: useGlass ? colorScheme.primary : foreground,
            ),
            SizedBox(width: tokens.gapMd),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title != null) ...[
                  Text(
                    title!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: textColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: tokens.gapXs),
                ],
                Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(color: textColor),
                ),
                ...[],
              ],
            ),
          ),
        ],
      ),
    );
    return Padding(
      padding:
          margin ??
          EdgeInsets.symmetric(
            horizontal: tokens.gapLg,
            vertical: tokens.gapXs,
          ),
      child: useGlass
          ? AppGlassPanel.overlay(child: content)
          : DecoratedBox(
              decoration: BoxDecoration(
                color: background,
                borderRadius: tokens.borderRadiusCard,
              ),
              child: content,
            ),
    );
  }
}
