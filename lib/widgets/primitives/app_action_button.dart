import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:sistrum/theme/app_icons.dart';
import 'package:sistrum/theme/app_theme.dart';
import 'package:sistrum/widgets/glass/app_chrome.dart';

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
    this.tonal = false,
    this.isDestructive = false,
    this.fontSize = 17,
  });

  final VoidCallback? onPressed;
  final Widget icon;
  final Widget label;
  final ButtonStyle? style;
  final bool outlined;
  final bool glass;
  final bool tonal;
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
      color: prominent
          ? scheme.primary
          : tonal
          ? AppTheme.controlFill(context)
          : Colors.transparent,
      disabledColor: !prominent && !tonal && !glass
          ? Colors.transparent
          : tonal && !prominent
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
    // These buttons sit inside glass sheets/groups; avoid another blur pass.
    return prominent || tonal || !glass
        ? action
        : AppGlass.navigation(radius: 28, blurEnabled: false, child: action);
  }
}
