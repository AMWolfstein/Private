import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g1455/g1455.dart' show GlassSlider;
import 'package:sistrum/widgets/primitives/app_slider.dart';

import '../../support/glass_controls.dart';

void main() {
  group('AppSlider', () {
    const key = ValueKey('slider');

    testWidgets('maps its range onto the glass slider and back', (
      tester,
    ) async {
      final values = <double>[];
      await pumpGlassControl(
        tester,
        (setState) => AppSlider(
          key: key,
          value: 50,
          min: 0,
          max: 100,
          onChanged: values.add,
        ),
      );
      expect(tester.widget<GlassSlider>(find.byKey(key)).value, 0.5);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(key)),
      );
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(values, isNotEmpty);
      expect(values.every((v) => v >= 0 && v <= 100), isTrue);
      expect(values.last, greaterThan(50));
      expect(tester.takeException(), isNull);
    });

    testWidgets('reports start and end once around a drag, in range', (
      tester,
    ) async {
      var value = 0.5;
      final events = <String>[];
      await pumpGlassControl(
        tester,
        (setState) => AppSlider(
          key: key,
          value: value,
          divisions: 20,
          onChangeStart: (_) => events.add('start'),
          onChanged: (next) => setState(() => value = next),
          onChangeEnd: (_) => events.add('end'),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(key)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      for (var i = 0; i < 5; i++) {
        await gesture.moveBy(const Offset(12, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(value, greaterThan(0.5));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(events, ['start', 'end']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the value bubble only while a finger drags it', (
      tester,
    ) async {
      var value = 0.5;
      final probe = <String>[];
      await pumpGlassControl(
        tester,
        (setState) => AppSlider(
          key: key,
          value: value,
          label: 'Half',
          onChangeStart: (_) => probe.add('start'),
          onChangeEnd: (_) => probe.add('end'),
          onChanged: (next) => setState(() => value = next),
        ),
      );
      expect(find.text('Half'), findsNothing);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(key)),
      );
      // The glass slider starts a drag once the finger moves past its slop.
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(12, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.text('Half'), findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(probe, ['start', 'end']);
      expect(find.text('Half'), findsNothing);
    });

    testWidgets('a screen reader hears the formatted value', (tester) async {
      await pumpGlassControl(
        tester,
        (_) => AppSlider(
          key: key,
          value: 0.25,
          onChanged: (_) {},
          semanticFormatterCallback: (v) => '${(v * 100).round()} percent',
        ),
      );
      expect(
        tester.widget<GlassSlider>(find.byKey(key)).semanticLabel,
        '25 percent',
      );
    });

    testWidgets('a null onChanged disables the glass slider', (tester) async {
      await pumpGlassControl(
        tester,
        (_) => const AppSlider(key: key, value: 0.4, onChanged: null),
      );
      expect(tester.widget<GlassSlider>(find.byKey(key)).onChanged, isNull);
      expect(tester.takeException(), isNull);
    });
  });
}
