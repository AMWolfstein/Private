import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:spotiflac_android/providers/runtime_profile_provider.dart';
import 'package:spotiflac_android/widgets/mornye_glass_thumb.dart';

/// An iOS-style slider: a thin rounded track and a white shadowed knob.
///
/// Unlike [CupertinoSlider], the active track can grow from an [origin]
/// inside the range (gain, balance) and the slider can stand [vertical], with
/// [min] at the bottom. A vertical slider only claims vertical drags, so a
/// row of them still scrolls sideways.
///
/// A horizontal slider's knob turns into liquid glass while touched when the
/// glass gate allows it; dense vertical faders keep the painted knob.
class MornyeLevelSlider extends ConsumerStatefulWidget {
  const MornyeLevelSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.origin,
    this.vertical = false,
    this.step,
    this.semanticLabel,
    this.semanticFormatterCallback,
    this.knobRadius = CupertinoThumbPainter.radius,
  });

  final double value, min, max;

  /// Smaller knobs keep a dense row of vertical faders from touching.
  final double knobRadius;
  final ValueChanged<double>? onChanged;

  /// Where the active track starts; [min] when null.
  final double? origin;
  final bool vertical;

  /// Accessibility increment; a hundredth of the range when null.
  final double? step;
  final String? semanticLabel;
  final String Function(double value)? semanticFormatterCallback;

  static const _trackThickness = 4.0;

  @override
  ConsumerState<MornyeLevelSlider> createState() => _MornyeLevelSliderState();
}

class _MornyeLevelSliderState extends ConsumerState<MornyeLevelSlider> {
  static const _activeKnobSize = Size(58, 38.33);
  static const _shadow = LiquidGlassShadow(inset: 3);

  /// Whether the current touch shows glass, decided at touch-down.
  bool? _touchGlass;

  double get value => widget.value;
  double get min => widget.min;
  double get max => widget.max;
  bool get vertical => widget.vertical;
  double get knobRadius => widget.knobRadius;
  ValueChanged<double>? get onChanged => widget.onChanged;

  double get _origin => (widget.origin ?? min).clamp(min, max);

  void _update(Offset local, Size size) {
    final extent = (vertical ? size.height : size.width) - knobRadius * 2;
    if (extent <= 0) return;
    var fraction = ((vertical ? local.dy : local.dx) - knobRadius) / extent;
    if (vertical) fraction = 1 - fraction;
    final next = min + fraction.clamp(0.0, 1.0) * (max - min);
    // A light tick when the knob reaches or crosses the origin.
    final at = _origin;
    if ((value - at).sign != (next - at).sign && value != next) {
      HapticFeedback.selectionClick();
    }
    onChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onChanged != null;
    final active = enabled ? scheme.primary : CupertinoColors.inactiveGray;
    final track = CupertinoColors.systemFill.resolveFrom(context);
    final increment = widget.step ?? (max - min) / 100;
    String format(double v) =>
        widget.semanticFormatterCallback?.call(v) ?? v.toStringAsFixed(1);
    final glassAllowed =
        enabled && !vertical && mornyeGlassThumbsEnabled(context, ref);
    final glass = _touchGlass ?? glassAllowed;
    final outlines = glass && ref.watch(mornyeGlassOutlinesProvider);
    void release() {
      if (_touchGlass != null) setState(() => _touchGlass = null);
    }

    return Semantics(
      slider: true,
      enabled: enabled,
      label: widget.semanticLabel,
      value: format(value),
      increasedValue: format((value + increment).clamp(min, max)),
      decreasedValue: format((value - increment).clamp(min, max)),
      onIncrease: enabled
          ? () => onChanged!((value + increment).clamp(min, max))
          : null,
      onDecrease: enabled
          ? () => onChanged!((value - increment).clamp(min, max))
          : null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // A 48 dp touch target across the track.
          final size = Size(
            vertical && !constraints.hasBoundedWidth
                ? 48
                : constraints.maxWidth,
            vertical ? constraints.maxHeight : 48,
          );
          void update(Offset local) => _update(local, size);
          final fraction = ((value - min) / (max - min)).clamp(0.0, 1.0);
          final Widget gestures = GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: enabled ? (d) => update(d.localPosition) : null,
            onHorizontalDragStart: enabled && !vertical
                ? (d) => update(d.localPosition)
                : null,
            onHorizontalDragUpdate: enabled && !vertical
                ? (d) => update(d.localPosition)
                : null,
            onVerticalDragStart: enabled && vertical
                ? (d) => update(d.localPosition)
                : null,
            onVerticalDragUpdate: enabled && vertical
                ? (d) => update(d.localPosition)
                : null,
            child: CustomPaint(
              size: size,
              painter: _LevelPainter(
                fraction: fraction,
                origin: (_origin - min) / (max - min),
                vertical: vertical,
                active: active,
                track: track,
                knobRadius: knobRadius,
                paintKnob: !glass,
              ),
            ),
          );
          if (!glass) return gestures;
          final r = knobRadius;
          return Listener(
            onPointerDown: (_) {
              if (_touchGlass == null) {
                setState(() => _touchGlass = glassAllowed);
              }
            },
            onPointerUp: (_) => release(),
            onPointerCancel: (_) => release(),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                gestures,
                Positioned.fill(
                  child: MornyeGlassThumb(
                    center: Offset(
                      r + fraction * (size.width - r * 2),
                      size.height / 2,
                    ),
                    held: _touchGlass == true,
                    restSize: Size.square(r * 2),
                    activeSize: _activeKnobSize,
                    style: mornyeGlassThumbStyle(outlines: outlines),
                    shadow: _shadow,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _LevelPainter extends CustomPainter {
  const _LevelPainter({
    required this.fraction,
    required this.origin,
    required this.vertical,
    required this.active,
    required this.track,
    required this.knobRadius,
    this.paintKnob = true,
  });

  final double fraction, origin, knobRadius;
  final bool vertical;

  /// False while the knob is drawn as a glass thumb above the painter.
  final bool paintKnob;
  final Color active, track;

  @override
  void paint(Canvas canvas, Size size) {
    final r = knobRadius;
    const t = MornyeLevelSlider._trackThickness;
    final length = (vertical ? size.height : size.width) - r * 2;
    Offset at(double f) => vertical
        ? Offset(size.width / 2, r + (1 - f) * length)
        : Offset(r + f * length, size.height / 2);
    Rect span(double a, double b) {
      final p = at(a), q = at(b);
      return vertical
          ? Rect.fromLTRB(p.dx - t / 2, q.dy, p.dx + t / 2, p.dy)
          : Rect.fromLTRB(p.dx, p.dy - t / 2, q.dx, p.dy + t / 2);
    }

    const radius = Radius.circular(t / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(span(0, 1), radius),
      Paint()..color = track,
    );
    final low = fraction < origin ? fraction : origin;
    final high = fraction < origin ? origin : fraction;
    if (high > low) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(span(low, high), radius),
        Paint()..color = active,
      );
    }
    if (paintKnob) {
      const CupertinoThumbPainter().paint(
        canvas,
        Rect.fromCircle(center: at(fraction), radius: r),
      );
    }
  }

  @override
  bool shouldRepaint(_LevelPainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.origin != origin ||
      oldDelegate.vertical != vertical ||
      oldDelegate.active != active ||
      oldDelegate.track != track ||
      oldDelegate.knobRadius != knobRadius ||
      oldDelegate.paintKnob != paintKnob;
}
