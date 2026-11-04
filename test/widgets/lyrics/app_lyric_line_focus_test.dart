import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/widgets/lyrics/app_lyric_line_focus.dart';

const _duration = Duration(milliseconds: 420);

Future<void> _line(WidgetTester tester, double sigma) => tester.pumpWidget(
  Directionality(
    textDirection: TextDirection.ltr,
    child: AppLyricLineFocus(
      sigma: sigma,
      restSigma: 2.4,
      duration: _duration,
      child: const Text('line'),
    ),
  ),
);

/// The sigmas of the blurs drawn this frame.
List<double> _drawnSigmas(WidgetTester tester) => [
  for (final blur in tester.widgetList<AppLyricBlur>(find.byType(AppLyricBlur)))
    if (blur.enabled) blur.sigma,
];

/// Checks every frame of a change: no drawn blur is below [floor].
Future<void> _expectNoSmallBlur(WidgetTester tester, double floor) async {
  for (var ms = 0; ms <= 480; ms += 16) {
    await tester.pump(const Duration(milliseconds: 16));
    for (final sigma in _drawnSigmas(tester)) {
      expect(sigma, greaterThanOrEqualTo(floor), reason: 'at $ms ms');
    }
  }
}

void main() {
  testWidgets('a line leaving focus never draws a small blur', (tester) async {
    await _line(tester, 0);
    expect(_drawnSigmas(tester), isEmpty);
    await _line(tester, 2.4);
    await _expectNoSmallBlur(tester, 2.4);
    expect(_drawnSigmas(tester), [2.4]);
    expect(find.text('line'), findsOneWidget);
  });

  testWidgets('a line coming into focus keeps its blur and fades sharp', (
    tester,
  ) async {
    await _line(tester, 4.8);
    await _line(tester, 0);
    await tester.pump(const Duration(milliseconds: 200));
    // Mid-change: a sharp copy and a copy at the line's rest blur.
    expect(find.text('line'), findsNWidgets(2));
    expect(_drawnSigmas(tester), [4.8]);
    await tester.pumpAndSettle();
    expect(_drawnSigmas(tester), isEmpty);
    expect(find.text('line'), findsOneWidget);
  });

  testWidgets('between two blurs the sigma animates', (tester) async {
    await _line(tester, 2.4);
    await _line(tester, 4.8);
    await tester.pump(const Duration(milliseconds: 200));
    final sigma = _drawnSigmas(tester).single;
    expect(sigma, greaterThan(2.4));
    expect(sigma, lessThan(4.8));
    await tester.pumpAndSettle();
    expect(_drawnSigmas(tester), [4.8]);
  });

  testWidgets('the line keeps its state through a crossfade', (tester) async {
    await _line(tester, 3.6);
    final before = tester.element(find.text('line'));
    await _line(tester, 0);
    await tester.pumpAndSettle();
    expect(tester.element(find.text('line')), same(before));
  });
}
