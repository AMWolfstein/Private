import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';

/// A lyric line's defocus: [child] blurred by [sigma], or sharp at 0.
///
/// Changes animate over [duration] without the blur ever passing through a
/// small sigma. Impeller blurs at full resolution up to about 4 physical
/// pixels and downsamples above that, so the old sigma ramp (0 to 2.4 dp and
/// back) cost a full-resolution blur of the two lines that changed focus on
/// every line change; the device measured raster P95 21.8 ms with the blur
/// and 8.2 ms without it.
///
/// - Between two blurred states the sigma animates (all at least the nearest
///   line's sigma).
/// - Into or out of focus the line crossfades between a sharp copy and a copy
///   blurred at a constant sigma: the one it rests at, or [restSigma] when it
///   has never been blurred.
///
/// While a line crossfades its content is built twice; the second copy is
/// hidden from semantics and hit testing.
class AppLyricLineFocus extends StatefulWidget {
  const AppLyricLineFocus({
    super.key,
    required this.sigma,
    required this.restSigma,
    required this.duration,
    this.curve = Curves.easeInOutCubic,
    required this.child,
  });

  /// The target blur, 0 for a sharp line.
  final double sigma;

  /// The blur of a line that leaves focus before it was ever blurred.
  final double restSigma;
  final Duration duration;
  final Curve curve;
  final Widget child;

  @override
  State<AppLyricLineFocus> createState() => _AppLyricLineFocusState();
}

class _AppLyricLineFocusState extends State<AppLyricLineFocus>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1,
  )..addListener(() => setState(() {}));

  // How blurred the line is, 0 sharp to 1 blurred, and the blur it uses.
  late double _amountFrom = _amountOf(widget.sigma);
  late double _amountTo = _amountFrom;
  late double _levelFrom = _levelOf(widget.sigma, null);
  late double _levelTo = _levelFrom;

  static double _amountOf(double sigma) => sigma > 0 ? 1 : 0;

  double _levelOf(double sigma, double? current) =>
      sigma > 0 ? sigma : (current ?? widget.restSigma);

  double get _t => widget.curve.transform(_controller.value);
  double get _amount => _amountFrom + (_amountTo - _amountFrom) * _t;
  double get _level => _levelFrom + (_levelTo - _levelFrom) * _t;

  @override
  void didUpdateWidget(AppLyricLineFocus oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = widget.duration;
    if (widget.sigma == oldWidget.sigma &&
        widget.restSigma == oldWidget.restSigma) {
      return;
    }
    final amount = _amount;
    final level = _level;
    _amountFrom = amount;
    _levelFrom = level;
    _amountTo = _amountOf(widget.sigma);
    _levelTo = _levelOf(widget.sigma, level > 0 ? level : null);
    if (widget.duration == Duration.zero) {
      _amountFrom = _amountTo;
      _levelFrom = _levelTo;
      _controller.value = 1;
    } else {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final amount = _amount.clamp(0.0, 1.0);
    final level = _level;
    // The copy that keeps the line's state is the one nearer its rest; the
    // two swap roles at the midpoint, where they draw the same picture.
    final primaryBlurred = amount >= 0.5;
    final crossfading = amount > 0 && amount < 1;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Opacity(
          key: const ValueKey('primary'),
          opacity: primaryBlurred ? amount : 1 - amount,
          child: AppLyricBlur(
            sigma: level,
            enabled: primaryBlurred && level > 0,
            child: widget.child,
          ),
        ),
        if (crossfading)
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: Opacity(
                  opacity: primaryBlurred ? 1 - amount : amount,
                  child: AppLyricBlur(
                    sigma: level,
                    enabled: !primaryBlurred && level > 0,
                    child: widget.child,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// One blur of a lyric line; [sigma] is public for tests.
class AppLyricBlur extends StatelessWidget {
  const AppLyricBlur({
    super.key,
    required this.sigma,
    required this.enabled,
    required this.child,
  });

  final double sigma;
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) => ImageFiltered(
    enabled: enabled,
    imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
    child: child,
  );
}
