import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:sistrum/core/theme/app_icons.dart';
import 'package:sistrum/widgets/glass/thumb/app_glass_surface.dart';

/// Shared sheet actions follow the selected design on every platform.
class AppActionButton extends StatelessWidget {
  const AppActionButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.style,
    this.outlined = false,
    this.glass = true,
    this.isDestructive = false,
    this.fontSize = 17,
  });

  final VoidCallback? onPressed;
  final Widget icon;
  final Widget label;
  final ButtonStyle? style;
  final bool outlined;
  final bool glass;
  final bool isDestructive;
  final double fontSize;

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
      color: prominent ? scheme.primary : Colors.transparent,
      disabledColor: !prominent && !glass
          ? Colors.transparent
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
    // Outlined buttons are Tinted Lite glass like every other floating control.
    return prominent || !glass
        ? action
        : AppGlass(
            radius: 28,
            blurEnabled: true,
            dropShadow: false,
            mode: AppGlassMode.liquid,
            child: action,
          );
  }
}
