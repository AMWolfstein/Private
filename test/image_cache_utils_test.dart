import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/utils/image_cache_utils.dart';

Future<int> _cacheWidth(
  WidgetTester tester, {
  required double width,
  required double dpr,
  double widthMultiplier = 1,
  int? min,
  int? max,
}) async {
  late int result;
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: Size(width, 800), devicePixelRatio: dpr),
      child: Builder(
        builder: (context) {
          result = coverCacheWidthForViewport(
            context,
            widthMultiplier: widthMultiplier,
            min: min ?? 320,
            max: max ?? 2048,
          );
          return const SizedBox();
        },
      ),
    ),
  );
  return result;
}

void main() {
  testWidgets('the cache width is the logical width times the density', (
    tester,
  ) async {
    expect(await _cacheWidth(tester, width: 390, dpr: 3), 1170);
  });

  testWidgets('a narrow viewport never goes below the minimum', (tester) async {
    expect(await _cacheWidth(tester, width: 100, dpr: 1), 320);
  });

  testWidgets('a very wide viewport is capped at the maximum', (tester) async {
    expect(await _cacheWidth(tester, width: 1000, dpr: 4), 2048);
  });

  testWidgets('the width multiplier scales before the density', (tester) async {
    expect(
      await _cacheWidth(tester, width: 400, dpr: 2, widthMultiplier: 0.5),
      400,
    );
  });
}
