import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/widgets/performance/perf_hud_geometry.dart';

void main() {
  const screen = Size(400, 800);
  const panel = Size(180, 60);
  const safe = EdgeInsets.fromLTRB(0, 24, 0, 48);

  test('the default corner is upper right, below the status bar', () {
    final offset = defaultPerfHudOffset(
      panel: panel,
      screen: screen,
      safe: safe,
    );
    expect(offset.dx, 400 - 8 - 180);
    expect(offset.dy, 24 + 8);
  });

  test('dragging past an edge clamps the panel inside the safe area', () {
    final low = clampPerfHudOffset(
      offset: const Offset(-500, -500),
      panel: panel,
      screen: screen,
      safe: safe,
    );
    expect(low, const Offset(8, 24 + 8));

    final high = clampPerfHudOffset(
      offset: const Offset(900, 900),
      panel: panel,
      screen: screen,
      safe: safe,
    );
    expect(high, Offset(400 - 8 - 180, 800 - 48 - 8 - 60));
  });

  test('a position inside the safe area is left unchanged', () {
    const inside = Offset(100, 200);
    expect(
      clampPerfHudOffset(
        offset: inside,
        panel: panel,
        screen: screen,
        safe: safe,
      ),
      inside,
    );
  });

  test('a panel larger than the area pins to its top-left corner', () {
    final offset = clampPerfHudOffset(
      offset: const Offset(300, 300),
      panel: const Size(500, 900),
      screen: screen,
      safe: safe,
    );
    expect(offset, const Offset(8, 24 + 8));
  });

  test('cutouts and system insets move the clamp bounds', () {
    const cutout = EdgeInsets.fromLTRB(40, 60, 0, 0);
    final offset = clampPerfHudOffset(
      offset: const Offset(0, 0),
      panel: panel,
      screen: screen,
      safe: cutout,
    );
    expect(offset, const Offset(40 + 8, 60 + 8));
  });
}
