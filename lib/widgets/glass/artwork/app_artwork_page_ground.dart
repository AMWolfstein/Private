import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:sistrum/widgets/glass/artwork/app_artwork_ground.dart';

/// How an anchored artwork is painted into its page's ground: cover-fit,
/// optionally rounded, under [gradient] (stops and colours top to bottom).
@immutable
class AppGroundLayout {
  const AppGroundLayout({
    this.alignment = Alignment.center,
    this.radius = 0,
    this.stops = const [],
    this.colors = const [],
  });

  final Alignment alignment;
  final double radius;
  final List<double> stops;
  final List<Color> colors;

  @override
  bool operator ==(Object other) =>
      other is AppGroundLayout &&
      other.alignment == alignment &&
      other.radius == radius &&
      listEquals(other.stops, stops) &&
      listEquals(other.colors, colors);

  @override
  int get hashCode => Object.hash(
    alignment,
    radius,
    Object.hashAll(stops),
    Object.hashAll(colors),
  );
}

/// Marks the artwork a page's header glass draws from. Its box is the
/// ground's rect on screen; [fade] follows an artist header's collapse.
class AppGroundAnchor extends SingleChildRenderObjectWidget {
  const AppGroundAnchor({
    super.key,
    required this.layout,
    this.fade = 0,
    super.child,
  });

  final AppGroundLayout layout;
  final double fade;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderGroundAnchor(_AppPageGroundState.of(context), layout, fade);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderGroundAnchor)
      ..host = _AppPageGroundState.of(context)
      ..groundLayout = layout
      ..fade = fade;
  }
}

class _RenderGroundAnchor extends RenderProxyBox {
  _RenderGroundAnchor(this._host, this._layout, this._fade);

  _AppPageGroundState? _host;
  set host(_AppPageGroundState? value) {
    if (identical(value, _host)) return;
    _host?._release(this);
    _host = value;
    if (attached) _host?._claim(this);
  }

  AppGroundLayout _layout;
  AppGroundLayout get groundLayout => _layout;
  set groundLayout(AppGroundLayout value) {
    if (value == _layout) return;
    _layout = value;
    _host?._changed(this);
  }

  double _fade;
  set fade(double value) {
    if (value == _fade) return;
    _fade = value;
    _host?._fade(this, value);
  }

  Rect? get globalRect => attached && hasSize
      ? MatrixUtils.transformRect(getTransformTo(null), Offset.zero & size)
      : null;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _host?._claim(this);
  }

  @override
  void detach() {
    _host?._release(this);
    super.detach();
  }

  @override
  void performLayout() {
    final previous = hasSize ? size : null;
    super.performLayout();
    if (size != previous) _host?._changed(this);
  }
}

/// Lays the page's pre-blurred ground over its anchored artwork at
/// [opacity], so a header softens as it scrolls without a live blur. Place it
/// to fill the [AppGroundAnchor]'s box, above the artwork and its gradient
/// (the ground already holds both). Paints nothing without a ground.
class AppGroundVeil extends StatelessWidget {
  const AppGroundVeil({super.key, required this.opacity});

  final double opacity;

  @override
  Widget build(BuildContext context) {
    final controller = AppArtworkGroundScope.pageOf(context);
    if (controller == null || opacity <= 0) return const SizedBox.shrink();
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _GroundVeilPainter(controller, opacity.clamp(0.0, 1.0)),
      ),
    );
  }
}

class _GroundVeilPainter extends CustomPainter {
  _GroundVeilPainter(this.controller, this.opacity)
    : super(repaint: controller);

  final AppGroundController controller;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    controller.markPainted();
    final image = controller.to?.image;
    if (image == null || size.isEmpty) return;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint()
        ..color = Color.fromRGBO(0, 0, 0, opacity)
        ..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_GroundVeilPainter oldDelegate) =>
      !identical(controller, oldDelegate.controller) ||
      opacity != oldDelegate.opacity;
}

/// Builds the ground for a detail page (album or artist) from [source] and
/// the page's [AppGroundAnchor]; header controls draw from it.
class AppPageGround extends StatefulWidget {
  const AppPageGround({
    super.key,
    required this.source,
    required this.surface,
    required this.sigma,
    required this.enabled,
    required this.cover,
    required this.child,
  });

  /// The cover's path or URL; identifies the artwork.
  final String? source;

  /// The page colour around the artwork.
  final Color surface;
  final double sigma;

  /// False while glass is off: no ground is built.
  final bool enabled;
  final ImageProvider? cover;
  final Widget child;

  @override
  State<AppPageGround> createState() => _AppPageGroundState();
}

class _AppPageGroundState extends State<AppPageGround>
    with SingleTickerProviderStateMixin {
  late final AppGroundController _controller = AppGroundController(
    vsync: this,
    rectOf: () => _anchor?.globalRect,
  )..onNeeded = _rebuildReleased;
  _RenderGroundAnchor? _anchor;
  Object? _built;
  double? _builtWidth;
  double? _builtHeight;
  // Inputs whose ground build already failed. A page that cannot compose its
  // ground must not re-decode on every collapse frame; the fallback material
  // renders until the width, source or layout changes.
  Object? _failedInput;
  int _generation = 0;
  bool _scheduled = false;

  static _AppPageGroundState? of(BuildContext context) =>
      context.findAncestorStateOfType<_AppPageGroundState>();

  void _rebuildReleased() {
    _built = null;
    _failedInput = null;
    _schedule();
  }

  void _claim(_RenderGroundAnchor anchor) {
    _anchor = anchor;
    _controller.setFade(anchor._fade, widget.surface);
    _schedule();
  }

  void _release(_RenderGroundAnchor anchor) {
    if (identical(_anchor, anchor)) _anchor = null;
  }

  void _changed(_RenderGroundAnchor anchor) {
    if (identical(_anchor, anchor)) _schedule();
  }

  void _fade(_RenderGroundAnchor anchor, double fade) {
    if (identical(_anchor, anchor)) _controller.setFade(fade, widget.surface);
  }

  @override
  void didUpdateWidget(AppPageGround oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedule();
  }

  void _schedule() {
    if (_scheduled || !mounted) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) unawaited(_build());
    });
  }

  Future<void> _build() async {
    final anchor = _anchor;
    if (!widget.enabled || anchor == null || !anchor.hasSize) {
      if (!widget.enabled && _controller.hasGround) _controller.release();
      if (!widget.enabled) {
        _built = null;
        _builtWidth = null;
        _builtHeight = null;
        _failedInput = null;
      }
      return;
    }
    // PERF-605: the artist header's anchor shrinks on every collapse frame.
    // The height of the built ground grows monotonically per width, so a
    // collapse never rebuilds it; the veil and header controls sample the
    // ground scaled into the anchor's current rect.
    final width = anchor.size.width;
    final height =
        (_builtWidth == width &&
            _builtHeight != null &&
            _builtHeight! >= anchor.size.height)
        ? _builtHeight!
        : anchor.size.height;
    final layout = anchor.groundLayout;
    final key = (
      widget.source,
      width,
      height,
      layout,
      widget.sigma,
      widget.surface,
    );
    final input = (widget.source, width, layout, widget.sigma, widget.surface);
    if (input == _failedInput) return;
    // Built, or being built: a ground is made once per input.
    if (key == _built) return;
    _built = key;
    _builtWidth = width;
    _builtHeight = height;
    final generation = ++_generation;
    final surface = widget.surface;
    final size = Size(width, height);
    final image = await AppGroundBuilder.build(
      label: 'page',
      size: size,
      cover: widget.cover,
      sigma: widget.sigma,
      paint: (canvas, size, cover) {
        final rect = Offset.zero & size;
        canvas.drawRect(rect, Paint()..color = surface);
        if (cover != null) {
          canvas.save();
          if (layout.radius > 0) {
            canvas.clipRRect(
              RRect.fromRectAndRadius(rect, Radius.circular(layout.radius)),
            );
          }
          AppGroundBuilder.paintCover(
            canvas,
            cover,
            rect,
            alignment: layout.alignment,
          );
          canvas.restore();
        }
        if (layout.colors.length >= 2) {
          canvas.drawRect(
            rect,
            Paint()
              ..shader = LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: layout.stops.length == layout.colors.length
                    ? layout.stops
                    : null,
                colors: layout.colors,
              ).createShader(rect),
          );
        }
      },
    );
    if (image == null) {
      // A failed build must not pin the key, or the monotonic height would
      // block every retry until the width changes. It is remembered per input
      // so a failing page falls back instead of decoding on every frame.
      if (generation == _generation) {
        _built = null;
        _builtWidth = null;
        _builtHeight = null;
        _failedInput = input;
      }
      return;
    }
    _failedInput = null;
    if (!mounted || generation != _generation) {
      image.dispose();
      return;
    }
    _controller.show(AppGround(image, edge: surface));
  }

  @override
  void dispose() {
    _generation++;
    _builtWidth = null;
    _builtHeight = null;
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppArtworkGroundScope(
    controller: _controller,
    page: true,
    child: widget.child,
  );
}
