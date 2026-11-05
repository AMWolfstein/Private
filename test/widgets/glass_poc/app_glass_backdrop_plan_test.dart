import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/widgets/glass_poc/app_glass_backdrop_plan.dart';

void main() {
  test('distant surfaces share one capture', () {
    const boxes = [Rect.fromLTWH(0, 0, 40, 40), Rect.fromLTWH(200, 0, 40, 40)];
    expect(
      appGlassBackdropGroups(
        paintBounds: boxes,
        samplingBounds: [for (final box in boxes) box.inflate(20)],
      ),
      [0, 0],
    );
  });

  test('blur/refraction reach prevents sharing without silhouette overlap', () {
    const boxes = [Rect.fromLTWH(0, 0, 100, 56), Rect.fromLTWH(0, 66, 100, 56)];
    expect(
      appGlassBackdropGroups(
        paintBounds: boxes,
        samplingBounds: [for (final box in boxes) box.inflate(30)],
      ),
      [0, 1],
    );
  });

  test(
    'overlapping and nested surfaces keep their previously painted input',
    () {
      const boxes = [
        Rect.fromLTWH(0, 0, 100, 100),
        Rect.fromLTWH(20, 20, 20, 20),
      ];
      expect(
        appGlassBackdropGroups(paintBounds: boxes, samplingBounds: boxes),
        [0, 1],
      );
    },
  );

  test('intervening content from another group cannot disappear', () {
    const boxes = [
      Rect.fromLTWH(0, 0, 40, 40),
      Rect.fromLTWH(20, 0, 40, 40),
      Rect.fromLTWH(50, 0, 40, 40),
    ];
    expect(appGlassBackdropGroups(paintBounds: boxes, samplingBounds: boxes), [
      0,
      1,
      2,
    ]);
  });

  test('an independent surface does not block unrelated later sharing', () {
    const boxes = [
      Rect.fromLTWH(0, 0, 40, 40),
      Rect.fromLTWH(20, 0, 40, 40),
      Rect.fromLTWH(200, 0, 40, 40),
    ];
    expect(appGlassBackdropGroups(paintBounds: boxes, samplingBounds: boxes), [
      0,
      1,
      0,
    ]);
  });

  test('foreground/effect outsets are respected', () {
    const first = Rect.fromLTWH(0, 0, 40, 40);
    const second = Rect.fromLTWH(45, 0, 40, 40);
    expect(
      appGlassBackdropGroups(
        paintBounds: [first.inflate(10), second],
        samplingBounds: [first, second],
      ),
      [0, 1],
    );
  });

  test('invalid sampling geometry is isolated', () {
    expect(
      appGlassBackdropGroups(
        paintBounds: const [Rect.fromLTWH(0, 0, 40, 40), Rect.zero],
        samplingBounds: const [Rect.fromLTWH(0, 0, 40, 40), Rect.zero],
      ),
      [0, 1],
    );
  });

  test(
    'all four can share only when their inputs exclude earlier surfaces',
    () {
      const boxes = [
        Rect.fromLTWH(0, 0, 40, 40),
        Rect.fromLTWH(200, 0, 80, 40),
        Rect.fromLTWH(0, 300, 280, 56),
        Rect.fromLTWH(0, 500, 280, 56),
      ];
      expect(
        appGlassBackdropGroups(
          paintBounds: boxes,
          samplingBounds: [for (final box in boxes) box.inflate(80)],
        ),
        [0, 0, 0, 0],
      );
    },
  );

  test('mismatched lists are rejected', () {
    expect(
      () => appGlassBackdropGroups(
        paintBounds: const [Rect.zero],
        samplingBounds: const [],
      ),
      throwsArgumentError,
    );
  });
}
