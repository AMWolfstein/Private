import 'package:flutter/material.dart';
import 'package:mornye/widgets/app_icon.dart';

/// Expressive actions retain caller colors, disabled states and flexible labels.
class ExpressiveButton extends StatelessWidget {
  const ExpressiveButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.icon,
    this.style,
    this.outlined = false,
    this.tonal = false,
    this.text = false,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;
  final ButtonStyle? style;
  final bool outlined;
  final bool tonal;

  /// Low-emphasis action without a container, like [TextButton].
  final bool text;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon == null ? null : symbolIconWidget(this.icon!);
    if (icon != null) {
      // Keep the standard icon spacing and asymmetric padding.
      if (text) {
        return TextButton.icon(
          onPressed: onPressed,
          style: style,
          icon: icon,
          label: child,
        );
      }
      if (outlined) {
        return OutlinedButton.icon(
          onPressed: onPressed,
          style: style,
          icon: icon,
          label: child,
        );
      }
      if (tonal) {
        return FilledButton.tonalIcon(
          onPressed: onPressed,
          style: style,
          icon: icon,
          label: child,
        );
      }
      return FilledButton.icon(
        onPressed: onPressed,
        style: style,
        icon: icon,
        label: child,
      );
    }
    if (text) {
      return TextButton(onPressed: onPressed, style: style, child: child);
    }
    if (outlined) {
      return OutlinedButton(onPressed: onPressed, style: style, child: child);
    }
    if (tonal) {
      return FilledButton.tonal(
        onPressed: onPressed,
        style: style,
        child: child,
      );
    }
    return FilledButton(onPressed: onPressed, style: style, child: child);
  }
}
