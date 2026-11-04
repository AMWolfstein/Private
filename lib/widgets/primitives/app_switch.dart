import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoColors;

/// One switch style for settings, extension controls and editing sheets.
/// Sistrum keeps its wide oval thumb.
class AppSwitch extends StatefulWidget {
  const AppSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.adaptive = false,
    this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool adaptive;
  final String? semanticLabel;

  @override
  State<AppSwitch> createState() => _AppSwitchState();
}

class _AppSwitchState extends State<AppSwitch> {
  // Geometry of the track and thumb. The box is 48dp tall so the switch
  // stays a full-size tap target.
  static const _box = Size(71, 48);
  static const _track = Size(63, 28);
  static const _thumb = Size(37, 24);
  static const _trackPadding = 2.0;

  double? _dragPosition;

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    final onChanged = widget.onChanged;
    final scheme = Theme.of(context).colorScheme;
    final active = CupertinoColors.systemGreen.resolveFrom(context);
    final enabled = onChanged != null;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    final inactive = scheme.brightness == Brightness.dark
        ? const Color(0xff39393d)
        : const Color(0xff8e8e93);

    final position = _dragPosition ?? (value ? 1.0 : 0.0);
    final thumbDuration = _dragPosition == null ? duration : Duration.zero;
    final control = AnimatedContainer(
      duration: duration,
      width: _track.width,
      height: _track.height,
      padding: const EdgeInsets.all(_trackPadding),
      decoration: BoxDecoration(
        color: position >= 0.5 ? active : inactive,
        borderRadius: BorderRadius.circular(14),
      ),
      child: AnimatedAlign(
        duration: thumbDuration,
        curve: Curves.easeOutCubic,
        alignment: AlignmentDirectional(-1 + position * 2, 0),
        child: Container(
          width: _thumb.width,
          height: _thumb.height,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );

    return Semantics(
      label: widget.semanticLabel,
      toggled: value,
      enabled: enabled,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? () => onChanged(!value) : null,
            borderRadius: BorderRadius.circular(22),
            // InkWell supplies keyboard and accessible activation.
            child: ExcludeSemantics(
              child: GestureDetector(
                onHorizontalDragStart: enabled
                    ? (_) => setState(() => _dragPosition = value ? 1 : 0)
                    : null,
                onHorizontalDragUpdate: enabled
                    ? (event) {
                        final direction =
                            Directionality.of(context) == TextDirection.rtl
                            ? -1.0
                            : 1.0;
                        setState(
                          () => _dragPosition =
                              ((_dragPosition ?? (value ? 1 : 0)) +
                                      event.delta.dx * direction / 22)
                                  .clamp(0, 1),
                        );
                      }
                    : null,
                onHorizontalDragEnd: enabled
                    ? (_) {
                        final next = (_dragPosition ?? (value ? 1 : 0)) >= 0.5;
                        setState(() => _dragPosition = null);
                        if (next != value) onChanged(next);
                      }
                    : null,
                onHorizontalDragCancel: enabled
                    ? () => setState(() => _dragPosition = null)
                    : null,
                child: SizedBox(
                  width: _box.width,
                  height: _box.height,
                  child: Center(child: control),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
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
