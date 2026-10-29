import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:sistrum/widgets/glass/app_selection_shared.dart';

/// Paint only icons and labels with the sliding selection color. Badge fills
/// and counters can remain outside this widget and retain their own contrast.
class AppSelectionForeground extends StatefulWidget {
  const AppSelectionForeground({super.key, required this.child});

  final Widget child;

  @override
  State<AppSelectionForeground> createState() =>
      _AppSelectionForegroundState();
}

class _AppSelectionForegroundState extends State<AppSelectionForeground> {
  ui.FragmentProgram? _program;
  ui.FragmentShader? _shader;

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AppSelectionForegroundScope>();
    if (scope == null) return widget.child;
    if (_program != scope.program) {
      _shader?.dispose();
      _program = scope.program;
      _shader = _program?.fragmentShader();
    }
    late Rect local;
    late double width;
    late double rowHeight;
    return _SelectionShaderMask(
      maskIntersects: (bounds) {
        // A transparent srcATop source leaves the foreground unchanged.
        if (scope.color.a == 0) return false;
        final row =
            scope.rowKey.currentContext!.findRenderObject()! as RenderBox;
        final box = context.findRenderObject()! as RenderBox;
        width = row.size.width / scope.count;
        rowHeight = row.size.height;
        final left = (scope.alignment + 1) * (row.size.width - width) / 2;
        final lens = Rect.fromCenter(
          center: Offset(left + width / 2, rowHeight / 2),
          width: width * scope.scaleX,
          height: rowHeight * scope.scaleY,
        );
        local = Rect.fromPoints(
          box.globalToLocal(row.localToGlobal(lens.topLeft)),
          box.globalToLocal(row.localToGlobal(lens.bottomRight)),
        );
        // Keep generous AA room, including inverse foreground scaling.
        final padX = 2 * math.max(1.0, local.width / width);
        final padY = 2 * math.max(1.0, local.height / rowHeight);
        return bounds.right >= local.left - padX &&
            bounds.left <= local.right + padX &&
            // The gradient fallback is vertically unbounded.
            (_shader == null ||
                (bounds.bottom >= local.top - padY &&
                    bounds.top <= local.bottom + padY));
      },
      shaderCallback: (bounds) {
        // Use the same rounded, expanding bounds as the glass, including the
        // inverse scale of each icon. A one-tab rectangular mask cuts through
        // the foreground before it reaches the held lens's curved edge.
        final shader = _shader;
        if (shader != null) {
          shader
            ..setFloat(0, local.left)
            ..setFloat(1, local.top)
            ..setFloat(2, local.width)
            ..setFloat(3, local.height)
            ..setFloat(4, local.width / width)
            ..setFloat(5, local.height / rowHeight)
            ..setFloat(6, math.min(kAppSelectionPillRadius, math.min(width, rowHeight) / 2))
            ..setFloat(7, scope.color.r)
            ..setFloat(8, scope.color.g)
            ..setFloat(9, scope.color.b)
            ..setFloat(10, scope.color.a);
          return shader;
        }
        return ui.Gradient.linear(
          Offset(local.left, 0),
          Offset(local.right, 0),
          [scope.color, scope.color],
          null,
          TileMode.decal,
        );
      },
      child: widget.child,
    );
  }
}

class _SelectionShaderMask extends ShaderMask {
  const _SelectionShaderMask({
    required this.maskIntersects,
    required super.shaderCallback,
    required super.child,
  }) : super(blendMode: BlendMode.srcATop);

  final bool Function(Rect) maskIntersects;

  @override
  RenderShaderMask createRenderObject(BuildContext context) =>
      _SelectionRenderShaderMask(
        maskIntersects: maskIntersects,
        shaderCallback: shaderCallback,
      );

  @override
  void updateRenderObject(BuildContext context, RenderShaderMask renderObject) {
    super.updateRenderObject(context, renderObject);
    (renderObject as _SelectionRenderShaderMask).maskIntersects =
        maskIntersects;
  }
}

class _SelectionRenderShaderMask extends RenderShaderMask {
  _SelectionRenderShaderMask({
    required this.maskIntersects,
    required super.shaderCallback,
  }) : super(blendMode: BlendMode.srcATop);

  bool Function(Rect) maskIntersects;

  @override
  void paint(PaintingContext context, Offset offset) {
    final foreground = child;
    if (foreground != null && !maskIntersects(foreground.paintBounds)) {
      // Drop any layer retained from a previous intersecting frame.
      layer = null;
      context.paintChild(foreground, offset);
    } else {
      // The predicate prepared this paint's geometry for shaderCallback.
      super.paint(context, offset);
    }
  }
}
