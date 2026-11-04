import 'package:flutter/material.dart';

/// A Material [Slider] with Sistrum's defaults. Keyboard, semantics,
/// divisions, the value label and RTL stay the [Slider]'s own.
///
/// [key] is given to the inner [Slider], so finders and callers that address
/// the slider by key keep working.
class AppSlider extends StatelessWidget {
  // The key belongs to the inner Slider.
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
  Widget build(BuildContext context) => Slider(
    key: _sliderKey,
    value: value,
    min: min,
    max: max,
    divisions: divisions,
    label: label,
    semanticFormatterCallback: semanticFormatterCallback,
    onChanged: onChanged,
    onChangeStart: onChangeStart,
    onChangeEnd: onChangeEnd,
  );
}
