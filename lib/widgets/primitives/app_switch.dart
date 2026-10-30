import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoColors;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/widgets/glass/thumb/app_glass_thumb.dart';

/// One switch style for settings, extension controls and editing sheets.
/// Sistrum keeps its wide oval thumb even when glass or motion is disabled.
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
  final bool adaptive;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return _AppSwitch(
      value: value,
      onChanged: onChanged,
      semanticLabel: semanticLabel,
    );
  }
}

class _AppSwitch extends ConsumerStatefulWidget {
  const _AppSwitch({
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  @override
  ConsumerState<_AppSwitch> createState() => _AppSwitchState();
}

class _AppSwitchState extends ConsumerState<_AppSwitch> {
  // Geometry shared by the painted thumb and the glass overlay. The box is
  // 48dp tall so the switch stays a full-size tap target.
  static const _box = Size(71, 48);
  static const _track = Size(63, 28);
  static const _thumb = Size(37, 24);
  static const _trackPadding = 2.0;

  double? _dragPosition;
  bool _dragCancelled = false;

  /// Whether the current touch shows glass, decided once at touch-down.
  bool? _touchGlass;

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

    // Glass follows the shared thumb gate, upstream Sistrum 9247b99a's
    // enabled/motion/contrast/liquid checks, and needs an enabled control.
    final glassAllowed = enabled && appGlassThumbsEnabled(context, ref);
    final glass = _touchGlass ?? glassAllowed;
    final position = _dragPosition ?? (value ? 1.0 : 0.0);
    final thumbDuration = _dragPosition == null ? duration : Duration.zero;
    final track = AnimatedContainer(
      duration: duration,
      width: _track.width,
      height: _track.height,
      padding: const EdgeInsets.all(_trackPadding),
      decoration: BoxDecoration(
        color: position >= 0.5 ? active : inactive,
        borderRadius: BorderRadius.circular(14),
      ),
      child: glass
          ? null
          : AnimatedAlign(
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
    final Widget control = glass
        ? SizedBox.fromSize(
            size: _box,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                track,
                // The thumb is drawn over the box so the swollen glass is not
                // clipped by the track; it glides exactly like the painted one.
                Positioned.fill(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: position),
                    duration: thumbDuration,
                    curve: Curves.easeOutCubic,
                    builder: (context, animated, _) {
                      final travel =
                          _track.width - _trackPadding * 2 - _thumb.width;
                      var x =
                          (_box.width - _track.width) / 2 +
                          _trackPadding +
                          _thumb.width / 2 +
                          animated * travel;
                      if (Directionality.of(context) == TextDirection.rtl) {
                        x = _box.width - x;
                      }
                      return AppGlassThumb(
                        center: Offset(x, _box.height / 2),
                        held: _touchGlass == true,
                        restSize: _thumb,
                        activeSize: const Size(58, 38.33),
                        style: appGlassThumbStyle(
                          outlines: ref.watch(appGlassOutlinesProvider),
                          dispersion: 1,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          )
        : track;

    void release() {
      if (_touchGlass != null) setState(() => _touchGlass = null);
    }

    return Listener(
      onPointerDown: (_) {
        _dragCancelled = false;
        if (_touchGlass == null) setState(() => _touchGlass = glassAllowed);
      },
      onPointerUp: (_) => release(),
      onPointerCancel: (_) {
        _dragCancelled = true;
        release();
      },
      child: Semantics(
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
              // InkWell supplies keyboard and accessible activation. The
              // thumb uses only paint/layout, even on a page of switches.
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
                          final next =
                              (_dragPosition ?? (value ? 1 : 0)) >= 0.5;
                          setState(() => _dragPosition = null);
                          if (!_dragCancelled && next != value) onChanged(next);
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
