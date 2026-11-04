import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Gap kept between the HUD and the edges of the safe area.
const double kPerfHudMargin = 8;

/// Clamps a panel's top-left [offset] so the whole panel stays inside the
/// safe area of [screen]. If the panel is larger than the area, its top-left
/// corner is pinned to the area's top-left.
Offset clampPerfHudOffset({
  required Offset offset,
  required Size panel,
  required Size screen,
  required EdgeInsets safe,
  double margin = kPerfHudMargin,
}) {
  final minX = safe.left + margin;
  final maxX = screen.width - safe.right - margin - panel.width;
  final minY = safe.top + margin;
  final maxY = screen.height - safe.bottom - margin - panel.height;
  return Offset(
    _clampRange(offset.dx, minX, maxX),
    _clampRange(offset.dy, minY, maxY),
  );
}

/// The default corner: upper right, below the status bar and cutouts.
Offset defaultPerfHudOffset({
  required Size panel,
  required Size screen,
  required EdgeInsets safe,
  double margin = kPerfHudMargin,
}) => clampPerfHudOffset(
  offset: Offset(
    screen.width - safe.right - margin - panel.width,
    safe.top + margin,
  ),
  panel: panel,
  screen: screen,
  safe: safe,
  margin: margin,
);

double _clampRange(double value, double min, double max) {
  if (max < min) return min;
  return math.min(math.max(value, min), max);
}
