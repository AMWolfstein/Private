import 'package:flutter/material.dart';
import 'package:sistrum/widgets/app_action_button.dart';

/// Icon+label pill used in selection-mode bottom bars, with the active theme's
/// disabled tones and room for a two-line label.
class SelectionActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final ColorScheme colorScheme;

  const SelectionActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    {
      return Semantics(
        label: label,
        button: true,
        enabled: onPressed != null,
        onTap: onPressed,
        excludeSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: AppActionButton(
            outlined: true,
            tonal: true,
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
            fontSize: 15,
          ),
        ),
      );
    }
  }
}
