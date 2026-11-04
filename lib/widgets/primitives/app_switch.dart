import 'package:flutter/material.dart';
import 'package:g1455/g1455.dart' show GlassSwitch;

/// One switch style for settings, extension controls and editing sheets: the
/// g1455 [GlassSwitch], which draws its own glass knob through the host's
/// capture (Glass Engine V2, AGENTS.md). Its value and [onChanged] are
/// Sistrum's; a null [onChanged] disables it.
class AppSwitch extends StatelessWidget {
  const AppSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.adaptive = false,
    this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  /// Kept for existing callers. The switch has one look on every platform.
  final bool adaptive;
  final String? semanticLabel;

  @override
  // The painted switch laid out in a 71x48 box. The glass switch's own tap
  // region is 44dp tall, so this box keeps every settings row the same size.
  Widget build(BuildContext context) => SizedBox(
    width: 71,
    height: 48,
    child: Center(
      child: GlassSwitch(
        value: value,
        onChanged: onChanged,
        semanticLabel: semanticLabel,
      ),
    ),
  );
}

class AppSwitchListTile extends StatelessWidget {
  const AppSwitchListTile({
    super.key,
    required this.value,
    required this.onChanged,
    required this.title,
    this.subtitle,
    this.contentPadding,
    this.adaptive = false,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget title;
  final Widget? subtitle;
  final EdgeInsetsGeometry? contentPadding;
  final bool adaptive;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: ListTile(
        title: title,
        subtitle: subtitle,
        contentPadding: contentPadding,
        enabled: onChanged != null,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        trailing: AppSwitch(value: value, onChanged: onChanged),
      ),
    );
  }
}
