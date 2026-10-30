import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:sistrum/core/theme/app_theme.dart';

/// A single tonal selection inside a sheet, without a second glass layer.
class AppChoiceChip extends StatelessWidget {
  const AppChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.visualDensity,
    this.singleChoice = false,
    this.icon,
    this.count,
  });

  final Widget label;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final VisualDensity? visualDensity;
  final bool singleChoice;
  final Widget? icon;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = onSelected == null
        ? scheme.onSurfaceVariant
        // The accent is too light for small text on the tinted fill in light
        // Sistrum (about 3:1); dark keeps the accent, which already passes.
        : selected && scheme.brightness == Brightness.light
        ? scheme.onSurface
        : selected
        ? scheme.primary
        : scheme.onSurface;
    return Semantics(
      selected: selected,
      button: true,
      inMutuallyExclusiveGroup: singleChoice,
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        // Keeps the chip a 48dp tap target even with short labels.
        minimumSize: const Size(48, 48),
        borderRadius: BorderRadius.circular(24),
        color: selected
            ? scheme.primary.withValues(alpha: 0.12)
            : AppTheme.controlFill(context),
        disabledColor: AppTheme.controlFill(context, enabled: false),
        onPressed: onSelected == null ? null : () => onSelected!(!selected),
        child: DefaultTextStyle(
          style: Theme.of(context).textTheme.bodyMedium!.copyWith(
            color: foreground,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[icon!, const SizedBox(width: 8)],
              if (selected) ...[
                Icon(CupertinoIcons.check_mark, size: 18, color: foreground),
                const SizedBox(width: 8),
              ],
              Flexible(child: label),
              if (count != null) ...[const SizedBox(width: 6), Text('$count')],
            ],
          ),
        ),
      ),
    );
  }
}
