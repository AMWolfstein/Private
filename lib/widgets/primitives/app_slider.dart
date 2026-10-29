import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/widgets/glass/app_glass_thumb.dart';

/// A Material [Slider] whose thumb turns into liquid glass while touched.
///
/// When the glass gate is closed it is exactly a [Slider] with the given
/// arguments. When open, the thumb is a white pill drawn over the slider (no
/// lens at rest) that becomes a [LiquidGlassMotionPill] between
/// [onChangeStart] and [onChangeEnd]. Keyboard, semantics, divisions, the
/// value label and RTL stay the [Slider]'s own.
///
/// [key] is given to the inner [Slider], so finders and callers that address
/// the slider by key keep working.
class AppSlider extends ConsumerStatefulWidget {
  // The key belongs to the inner Slider (see the class comment).
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

  static const restThumbSize = Size(37, 24);
  static const _activeThumbSize = Size(58, 38.33);
  static const _shadow = LiquidGlassShadow(inset: 3);

  // Explicit so the drawn thumb can share the slider's track geometry.
  static const _overlayShape = RoundSliderOverlayShape();

  /// Where a glass-mode slider last painted its (hidden) thumb, in the
  /// slider's own layer; tests compare it with the drawn thumb.
  @visibleForTesting
  static Offset? debugPaintedThumbCenter;

  @override
  ConsumerState<AppSlider> createState() => _AppSliderState();
}

class _AppSliderState extends ConsumerState<AppSlider>
    with SingleTickerProviderStateMixin {
  // Mirrors the Slider's own position animation, so the drawn thumb and the
  // painted track fill move together (75 ms ease for discrete steps).
  late final AnimationController _position = AnimationController(
    vsync: this,
    value: _fraction(widget.value),
  );

  /// Whether the current interaction shows glass, decided at its start.
  bool? _touchGlass;

  double _fraction(double value) => widget.max > widget.min
      ? ((value - widget.min) / (widget.max - widget.min)).clamp(0.0, 1.0)
      : 0.0;

  @override
  void didUpdateWidget(AppSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = _fraction(widget.value);
    if (target == _position.value) return;
    if (widget.divisions != null) {
      _position.animateTo(
        target,
        duration: const Duration(milliseconds: 75),
        curve: Curves.easeInOut,
      );
    } else {
      _position.value = target;
    }
  }

  @override
  void dispose() {
    _position.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onChanged != null;
    final glassAllowed = enabled && appGlassThumbsEnabled(context, ref);
    final glass = _touchGlass ?? glassAllowed;
    final slider = Slider(
      key: widget._sliderKey,
      value: widget.value,
      min: widget.min,
      max: widget.max,
      divisions: widget.divisions,
      label: widget.label,
      semanticFormatterCallback: widget.semanticFormatterCallback,
      onChanged: widget.onChanged,
      onChangeStart: (value) {
        setState(() => _touchGlass = glassAllowed);
        widget.onChangeStart?.call(value);
      },
      onChangeEnd: (value) {
        setState(() => _touchGlass = null);
        widget.onChangeEnd?.call(value);
      },
    );
    if (!glass) return slider;

    final outlines = ref.watch(appGlassOutlinesProvider);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            thumbShape: const _HiddenPillThumbShape(),
            overlayShape: AppSlider._overlayShape,
            // The glass replaces Material's pressed halo.
            overlayColor: Colors.transparent,
          ),
          child: slider,
        ),
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Slider's track inset: half the wider of overlay and thumb.
              final inset =
                  AppSlider._overlayShape
                      .getPreferredSize(true, widget.divisions != null)
                      .width
                      .clamp(
                        AppSlider.restThumbSize.width,
                        double.infinity,
                      ) /
                  2;
              // Discrete sliders keep the thumb half a (rounded) track
              // height inside the ends, as Slider._calcThumbCenter does.
              final rounded = widget.divisions == null
                  ? 0.0
                  : SliderTheme.of(context).trackHeight ?? 4.0;
              final start = inset + rounded / 2;
              final width = constraints.maxWidth - inset * 2 - rounded;
              return AnimatedBuilder(
                animation: _position,
                builder: (context, _) {
                  var fraction = _position.value;
                  if (Directionality.of(context) == TextDirection.rtl) {
                    fraction = 1 - fraction;
                  }
                  return AppGlassThumb(
                    center: Offset(
                      start + fraction * width,
                      constraints.maxHeight / 2,
                    ),
                    held: _touchGlass == true,
                    restSize: AppSlider.restThumbSize,
                    activeSize: AppSlider._activeThumbSize,
                    style: appGlassThumbStyle(outlines: outlines),
                    shadow: AppSlider._shadow,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Reserves the pill's size for the track geometry but paints nothing: the
/// thumb is drawn by [AppGlassThumb] above the slider.
class _HiddenPillThumbShape extends SliderComponentShape {
  const _HiddenPillThumbShape();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      AppSlider.restThumbSize;

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    assert(() {
      AppSlider.debugPaintedThumbCenter = center;
      return true;
    }());
  }
}
