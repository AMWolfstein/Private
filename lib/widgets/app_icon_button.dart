import 'package:flutter/material.dart';
import 'package:mornye/widgets/app_icon.dart';

enum _AppIconButtonVariant { standard, filled, tonal }

/// Drop-in [IconButton] with the Material 3 Expressive shape and press motion.
///
/// Mornye, reduced motion and dense buttons ([padding], [constraints],
/// [visualDensity] or a sizing [style]) keep the exact [IconButton] layout.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color,
    this.iconSize,
    this.isSelected,
    this.selectedIcon,
    this.style,
    this.padding,
    this.constraints,
    this.visualDensity,
  }) : _variant = _AppIconButtonVariant.standard;

  const AppIconButton.filled({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color,
    this.iconSize,
    this.isSelected,
    this.selectedIcon,
    this.style,
    this.padding,
    this.constraints,
    this.visualDensity,
  }) : _variant = _AppIconButtonVariant.filled;

  const AppIconButton.filledTonal({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color,
    this.iconSize,
    this.isSelected,
    this.selectedIcon,
    this.style,
    this.padding,
    this.constraints,
    this.visualDensity,
  }) : _variant = _AppIconButtonVariant.tonal;

  final Widget icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;
  final double? iconSize;
  final bool? isSelected;
  final Widget? selectedIcon;
  final ButtonStyle? style;
  final EdgeInsetsGeometry? padding;
  final BoxConstraints? constraints;
  final VisualDensity? visualDensity;
  final _AppIconButtonVariant _variant;

  @override
  Widget build(BuildContext context) {
    final icon = symbolIconWidget(this.icon);
    final selectedIcon = this.selectedIcon == null
        ? null
        : symbolIconWidget(this.selectedIcon!);
    return switch (_variant) {
      _AppIconButtonVariant.standard => IconButton(
        icon: icon,
        selectedIcon: selectedIcon,
        onPressed: onPressed,
        tooltip: tooltip,
        color: color,
        iconSize: iconSize,
        isSelected: isSelected,
        style: style,
        padding: padding,
        constraints: constraints,
        visualDensity: visualDensity,
      ),
      _AppIconButtonVariant.filled => IconButton.filled(
        icon: icon,
        selectedIcon: selectedIcon,
        onPressed: onPressed,
        tooltip: tooltip,
        color: color,
        iconSize: iconSize,
        isSelected: isSelected,
        style: style,
        padding: padding,
        constraints: constraints,
        visualDensity: visualDensity,
      ),
      _AppIconButtonVariant.tonal => IconButton.filledTonal(
        icon: icon,
        selectedIcon: selectedIcon,
        onPressed: onPressed,
        tooltip: tooltip,
        color: color,
        iconSize: iconSize,
        isSelected: isSelected,
        style: style,
        padding: padding,
        constraints: constraints,
        visualDensity: visualDensity,
      ),
    };
  }
}
