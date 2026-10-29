import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/widgets/glass/app_glass_thumb.dart';
import 'package:sistrum/widgets/glass/app_level_slider.dart';
import 'package:sistrum/widgets/primitives/app_slider.dart';

import 'support/glass_controls.dart';

void main() {
  group('AppSlider', () {
    const key = ValueKey('slider');

    testWidgets('draws its thumb where the slider paints it', (tester) async {
      for (final direction in TextDirection.values) {
        for (final (value, divisions) in [
          (0.0, 10),
          (0.3, 10),
          (1.0, 10),
          (0.0, null),
          (0.3, null),
          (1.0, null),
        ]) {
          await pumpGlassControl(
            tester,
            (_) => AppSlider(
              key: key,
              value: value,
              divisions: divisions,
              onChanged: (_) {},
            ),
            direction: direction,
          );
          final drawn = tester
              .widget<AppGlassThumb>(find.byType(AppGlassThumb))
              .center;
          // The slider paints in its own layer at the overlay's origin.
          final painted = AppSlider.debugPaintedThumbCenter!;
          expect(
            drawn,
            offsetMoreOrLessEquals(painted, epsilon: 0.01),
            reason: '$direction $value $divisions',
          );
          // The key still addresses the Material slider.
          expect(tester.widget<Slider>(find.byKey(key)).value, value);
        }
      }
    });

    testWidgets('has no lens at rest and glass only while dragged', (
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
          label: '$value',
          onChangeStart: (_) => events.add('start'),
          onChanged: (next) => setState(() => value = next),
          onChangeEnd: (_) => events.add('end'),
        ),
      );
      expect(glassLenses(), 0);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(key)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      for (var i = 0; i < 5; i++) {
        await gesture.moveBy(const Offset(12, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(glassPills(), 1);
      expect(value, greaterThan(0.5));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(events, ['start', 'end']);
      expect(glassPills(), 0);
      expect(glassLenses(), 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('is a plain Slider when the gates are off or disabled', (
      tester,
    ) async {
      await pumpGlassControl(
        tester,
        (_) => AppSlider(key: key, value: 0.5, onChanged: (_) {}),
        glass: false,
      );
      expect(find.byType(AppGlassThumb), findsNothing);
      expect(SliderTheme.of(tester.element(find.byKey(key))).thumbShape, null);
      await pumpGlassControl(
        tester,
        (_) => const AppSlider(key: key, value: 0.5, onChanged: null),
      );
      expect(find.byType(AppGlassThumb), findsNothing);
    });

    testWidgets('reports the same values with and without glass', (
      tester,
    ) async {
      Future<List<String>> run(bool glass) async {
        var value = 0.0;
        final events = <String>[];
        await pumpGlassControl(
          tester,
          (setState) => AppSlider(
            key: key,
            value: value,
            divisions: 10,
            onChangeStart: (v) => events.add('start $v'),
            onChanged: (next) {
              events.add('change $next');
              setState(() => value = next);
            },
            onChangeEnd: (v) => events.add('end $v'),
          ),
          glass: glass,
        );
        await tester.drag(find.byKey(key), const Offset(120, 0));
        await tester.pumpAndSettle();
        await tester.tapAt(tester.getCenter(find.byKey(key)));
        await tester.pumpAndSettle();
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(key)),
        );
        await gesture.moveBy(const Offset(60, 0));
        await tester.pump();
        await gesture.cancel();
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
        return events;
      }

      final plain = await run(false);
      expect(plain, isNotEmpty);
      expect(await run(true), plain);
      expect(tester.takeException(), isNull);
    });
  });

  group('AppLevelSlider', () {
    testWidgets('horizontal knob turns to glass only while touched', (
      tester,
    ) async {
      var value = 0.0;
      await pumpGlassControl(
        tester,
        (setState) => AppLevelSlider(
          value: value,
          min: -12,
          max: 12,
          origin: 0,
          onChanged: (next) => setState(() => value = next),
        ),
      );
      expect(find.byType(AppGlassThumb), findsOneWidget);
      expect(glassLenses(), 0);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(AppLevelSlider)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(glassPills(), 1);
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(value, greaterThan(0));
      expect(glassPills(), 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('vertical faders keep the painted knob', (tester) async {
      await pumpGlassControl(
        tester,
        (_) => SizedBox(
          height: 200,
          child: AppLevelSlider(
            value: 0,
            min: -15,
            max: 15,
            vertical: true,
            onChanged: (_) {},
          ),
        ),
      );
      expect(find.byType(AppGlassThumb), findsNothing);
    });
  });
}
