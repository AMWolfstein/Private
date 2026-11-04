import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:sistrum/core/theme/app_icons.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/widgets/primitives/app_surface.dart';

/// Shared sheet actions follow the selected design on every platform.
class AppActionButton extends StatelessWidget {
  const AppActionButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.style,
    this.outlined = false,
    this.tonal = false,
    this.isDestructive = false,
    this.fontSize = 17,
    this.filled = true,
  });

  final VoidCallback? onPressed;
  final Widget icon;
  final Widget label;
  final ButtonStyle? style;
  final bool outlined;
  final bool tonal;
  final bool isDestructive;
  final double fontSize;

  /// Outlined buttons sit on a solid raised surface; false leaves them bare.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final prominent = isDestructive || !outlined;
    final foreground = onPressed == null
        ? scheme.onSurfaceVariant.withValues(alpha: 0.5)
        : prominent
        ? scheme.onPrimary
        : scheme.primary;
    final action = CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      // Keeps short actions a 48dp tap target.
      minimumSize: const Size(48, 48),
      borderRadius: BorderRadius.circular(28),
      color: prominent
          ? scheme.primary
          : tonal
          ? AppTheme.controlFill(context)
          : Colors.transparent,
      disabledColor: tonal && !prominent
          ? AppTheme.controlFill(context, enabled: false)
          : scheme.surfaceContainerHighest,
      onPressed: onPressed,
      child: DefaultTextStyle(
        style: Theme.of(context).textTheme.bodyLarge!.copyWith(
          color: foreground,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
        ),
        child: IconTheme(
          data: IconThemeData(color: foreground, size: 20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon case Icon(:final icon?))
                Icon(appIconFor(icon), size: 20)
              else
                icon,
              const SizedBox(width: 8),
              Flexible(child: label),
            ],
          ),
        ),
      ),
    );
    if (prominent || tonal || !filled) return action;
    return AppSurface(
      radius: 28,
      color: scheme.surfaceContainerHigh,
      child: action,
    );
  }
}
