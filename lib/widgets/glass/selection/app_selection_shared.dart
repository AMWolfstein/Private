import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Corner radius of the selection pill, shared by the pill and its foreground.
const kAppSelectionPillRadius = 32.0;

class AppSelectionForegroundScope extends InheritedWidget {
  const AppSelectionForegroundScope({
    super.key,
    required this.rowKey,
    required this.alignment,
    required this.count,
    required this.scaleX,
    required this.scaleY,
    required this.program,
    required this.color,
    required super.child,
  });

  final GlobalKey rowKey;
  final double alignment;
  final int count;
  final double scaleX;
  final double scaleY;
  final ui.FragmentProgram? program;
  final Color color;

  @override
  bool updateShouldNotify(AppSelectionForegroundScope oldWidget) =>
      alignment != oldWidget.alignment ||
      count != oldWidget.count ||
      scaleX != oldWidget.scaleX ||
      scaleY != oldWidget.scaleY ||
      program != oldWidget.program ||
      color != oldWidget.color ||
      rowKey != oldWidget.rowKey;
}
