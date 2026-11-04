import 'package:flutter/material.dart';
import 'package:g1455/g1455.dart' show GlassSlider;

/// A slider drawn with the g1455 [GlassSlider]: a thin coloured track and a
/// white pill thumb, refracting the host's capture (Glass Engine V2, AGENTS.md).
///
/// Sistrum's [min], [max], [divisions] and [label] map onto the glass
/// slider's unit range. [label] is the value bubble shown while a finger
/// drags; [semanticFormatterCallback] spells the value for a screen reader.
/// [key] is given to the glass slider, so callers that address it by key keep
/// working.
class AppSlider extends StatefulWidget {
  // The key belongs to the inner glass slider (see the class comment).
  // ignore: use_key_in_widget_constructors
  const AppSlider({
    Key? key,
    required this.value,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.label,
    this.semanticFormatterCallback,
  }) : _sliderKey = key;

  final Key? _sliderKey;
  final double value;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;
  final double min;
  final double max;
  final int? divisions;
  final String? label;
  final SemanticFormatterCallback? semanticFormatterCallback;

  @override
  State<AppSlider> createState() => _AppSliderState();
}

class _AppSliderState extends State<AppSlider> {
  bool _dragging = false;

  double _unit(double v) {
    final range = widget.max - widget.min;
    if (range <= 0) return 0;
    return ((v - widget.min) / range).clamp(0.0, 1.0).toDouble();
  }

  // The unit range maps back with float noise (0.5 / 1.5 * 1.5 is not 0.5);
  // settings store the value at nine decimals.
  double _value(double unit) {
    final value = widget.min + unit * (widget.max - widget.min);
    return (value * 1e9).round() / 1e9;
  }

  void _start(double unit) {
    setState(() => _dragging = true);
    widget.onChangeStart?.call(_value(unit));
  }

  void _end(double unit) {
    setState(() => _dragging = false);
    widget.onChangeEnd?.call(_value(unit));
  }

  @override
  Widget build(BuildContext context) {
    final unit = _unit(widget.value);
    final spoken = widget.semanticFormatterCallback?.call(widget.value);
    final slider = GlassSlider(
      key: widget._sliderKey,
      value: unit,
      divisions: widget.divisions,
      onChanged: widget.onChanged == null
          ? null
          : (u) => widget.onChanged!(_value(u)),
      onChangeStart: _start,
      onChangeEnd: _end,
      semanticLabel: spoken,
    );
    final label = widget.label;
    // One Stack in every state: the slider keeps its element through a drag,
    // so the gesture that ends it is never lost to a change of parent.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        slider,
        if (label != null && _dragging)
          Positioned.fill(
            child: IgnorePointer(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final scheme = Theme.of(context).colorScheme;
                  // The thumb's travel keeps its ends inside the slider.
                  const inset = 19.0;
                  final x = inset + (constraints.maxWidth - inset * 2) * unit;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: x,
                        top: -34,
                        child: FractionalTranslation(
                          translation: const Offset(-0.5, 0),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: scheme.inverseSurface,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              child: Text(
                                label,
                                style: TextStyle(
                                  color: scheme.onInverseSurface,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}
