import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:sistrum/widgets/glass/artwork/app_artwork_ground.dart';

/// The render side of [AppArtworkGlassSurface]: the pre-blurred artwork
/// ground under the surface fill. It reads no backdrop.
class AppArtworkGlassRender extends SingleChildRenderObjectWidget {
  const AppArtworkGlassRender({
    super.key,
    required this.controller,
    required this.opaque,
    required this.fill,
    required this.scroll,
    super.child,
  });

  final AppGroundController controller;
  final bool opaque;
  final Color fill;

  /// Pages repaint while scrolling: the ground moves under fixed controls.
  final Listenable? scroll;

  @override
  RenderAppArtworkGlass createRenderObject(BuildContext context) =>
      RenderAppArtworkGlass(
        controller: controller,
        opaque: opaque,
        fill: fill,
        scroll: scroll,
      );

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as RenderAppArtworkGlass)
      ..controller = controller
      ..opaque = opaque
      ..fill = fill
      ..scroll = scroll;
  }
}

class RenderAppArtworkGlass extends RenderProxyBox {
  RenderAppArtworkGlass({
    required AppGroundController controller,
    required bool opaque,
    required Color fill,
    Listenable? scroll,
  }) : _controller = controller,
       _opaque = opaque,
       _fill = fill,
       _scroll = scroll;

  AppGroundController _controller;
  AppGroundController get controller => _controller;
  set controller(AppGroundController value) {
    if (identical(value, _controller)) return;
    if (attached) _controller.removeListener(markNeedsPaint);
    _controller = value;
    if (attached) _controller.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  bool _opaque;
  bool get opaque => _opaque;
  set opaque(bool value) {
    if (value == _opaque) return;
    _opaque = value;
    markNeedsPaint();
  }

  Color _fill;
  set fill(Color value) {
    if (value == _fill) return;
    _fill = value;
    markNeedsPaint();
  }

  Listenable? _scroll;
  set scroll(Listenable? value) {
    if (identical(value, _scroll)) return;
    if (attached) _scroll?.removeListener(markNeedsPaint);
    _scroll = value;
    if (attached) _scroll?.addListener(markNeedsPaint);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _controller.addListener(markNeedsPaint);
    _scroll?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _controller.removeListener(markNeedsPaint);
    _scroll?.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    final local = offset & size;
    if (!_opaque) _paintGround(canvas, offset);
    canvas.drawRect(local, Paint()..color = _fill);
    super.paint(context, offset);
  }

  void _paintGround(Canvas canvas, Offset offset) {
    final controller = _controller..markPainted();
    final local = offset & size;
    final from = controller.from;
    final to = controller.to;
    final groundRect = controller.rect;
    final edge = controller.edge ?? _fill.withValues(alpha: 1);
    if (from == null ||
        to == null ||
        groundRect == null ||
        groundRect.isEmpty) {
      canvas.drawRect(local, Paint()..color = edge);
    } else {
      final panel = MatrixUtils.transformRect(
        getTransformTo(null),
        Offset.zero & size,
      );
      canvas.drawRect(local, Paint()..color = edge);
      _drawPlain(canvas, offset, panel, groundRect, from.image, 1);
      if (!identical(from, to)) {
        _drawPlain(canvas, offset, panel, groundRect, to.image, controller.mix);
      }
    }
    if (controller.fade > 0) {
      canvas.drawRect(
        local,
        Paint()
          ..color = controller.fadeColor.withValues(
            alpha: controller.fadeColor.a * controller.fade,
          ),
      );
    }
  }

  void _drawPlain(
    Canvas canvas,
    Offset offset,
    Rect panel,
    Rect ground,
    ui.Image image,
    double opacity,
  ) {
    final mapping = appGroundMapping(
      panel: panel,
      ground: ground,
      image: Size(image.width.toDouble(), image.height.toDouble()),
      local: size,
    );
    if (mapping == null || opacity <= 0) return;
    canvas.drawImageRect(
      image,
      mapping.source,
      mapping.target.shift(offset),
      Paint()
        ..filterQuality = FilterQuality.low
        ..color = Color.fromRGBO(0, 0, 0, opacity),
    );
  }
}

/// Where a panel at [panel] (on screen) meets a ground at [ground]: the
/// [image] pixels under it and where they land in the panel's [local] size.
/// Null when the panel is off the ground.
({Rect source, Rect target})? appGroundMapping({
  required Rect panel,
  required Rect ground,
  required Size image,
  required Size local,
}) {
  final shared = panel.intersect(ground);
  if (shared.width <= 0 || shared.height <= 0) return null;
  final sx = image.width / ground.width;
  final sy = image.height / ground.height;
  final px = local.width / panel.width;
  final py = local.height / panel.height;
  return (
    source: Rect.fromLTRB(
      (shared.left - ground.left) * sx,
      (shared.top - ground.top) * sy,
      (shared.right - ground.left) * sx,
      (shared.bottom - ground.top) * sy,
    ),
    target: Rect.fromLTRB(
      (shared.left - panel.left) * px,
      (shared.top - panel.top) * py,
      (shared.right - panel.left) * px,
      (shared.bottom - panel.top) * py,
    ),
  );
}
