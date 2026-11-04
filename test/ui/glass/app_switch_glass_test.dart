import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/widgets/primitives/app_switch.dart';
import 'package:sistrum/widgets/glass/thumb/app_glass_thumb.dart';

import '../../support/glass_controls.dart';

void main() {
  group('AppSwitch', () {
    Widget switchFor(
      StateSetter setState,
      bool Function() value,
      void Function(bool) set,
      List<bool> changes,
    ) => Center(
      child: AppSwitch(
        value: value(),
        onChanged: (next) {
          changes.add(next);
          setState(() => set(next));
        },
      ),
    );

    testWidgets('has no glass at rest and glass only while touched', (
      tester,
    ) async {
      var value = false;
      final changes = <bool>[];
      await pumpGlassControl(
        tester,
        (setState) =>
            switchFor(setState, () => value, (v) => value = v, changes),
      );
      expect(find.byType(AppGlassThumb), findsOneWidget);
      expect(glassPills(), 0);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(AppSwitch)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(glassPills(), 1);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(changes, [true]);
      expect(glassPills(), 0);
      expect(tester.takeException(), isNull);
    });

    for (final (name, level, touchGlass) in [
      ('Tinted Lite shows touch-only glass', AppGlassLevel.tinted, true),
      ('flat level has none', AppGlassLevel.flat, false),
    ]) {
      testWidgets(name, (tester) async {
        var value = false;
        final changes = <bool>[];
        await pumpGlassControl(
          tester,
          (setState) =>
              switchFor(setState, () => value, (v) => value = v, changes),
          level: level,
        );
        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(AppSwitch)),
        );
        await tester.pump(const Duration(milliseconds: 50));
        expect(glassPills(), touchGlass ? 1 : 0);
        await gesture.up();
        await tester.pumpAndSettle();
        expect(changes, [true]);
      });
    }

    for (final (name, glass, reduceMotion, highContrast) in [
      ('glass off', false, false, false),
      ('reduced motion', true, true, false),
      ('high contrast', true, false, true),
    ]) {
      testWidgets('falls back to the painted switch: $name', (tester) async {
        var value = false;
        final changes = <bool>[];
        await pumpGlassControl(
          tester,
          (setState) =>
              switchFor(setState, () => value, (v) => value = v, changes),
          glass: glass,
          reduceMotion: reduceMotion,
          highContrast: highContrast,
        );
        expect(find.byType(AppGlassThumb), findsNothing);
        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(AppSwitch)),
        );
        await tester.pump(const Duration(milliseconds: 50));
        expect(glassPills(), 0);
        await gesture.up();
        await tester.pumpAndSettle();
        expect(changes, [true]);
      });
    }

    testWidgets('disabled switch never shows glass', (tester) async {
      await pumpGlassControl(
        tester,
        (_) => const Center(child: AppSwitch(value: true, onChanged: null)),
      );
      expect(find.byType(AppGlassThumb), findsNothing);
      final opacity = tester.widget<Opacity>(
        find.descendant(
          of: find.byType(AppSwitch),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacity.opacity, 0.5);
    });

    for (final glass in [true, false]) {
      testWidgets('tap, drag and cancel report the same changes (glass: '
          '$glass)', (tester) async {
        var value = false;
        final changes = <bool>[];
        await pumpGlassControl(
          tester,
          (setState) =>
              switchFor(setState, () => value, (v) => value = v, changes),
          glass: glass,
        );
        final center = tester.getCenter(find.byType(AppSwitch));

        await tester.tap(find.byType(AppSwitch));
        await tester.pumpAndSettle();
        expect(changes, [true]);

        // Dragging back past halfway turns it off once, on release.
        var gesture = await tester.startGesture(center);
        for (var i = 0; i < 6; i++) {
          await gesture.moveBy(const Offset(-6, 0));
          await tester.pump();
        }
        expect(changes, [true]);
        await gesture.up();
        await tester.pumpAndSettle();
        expect(changes, [true, false]);

        // A drag that ends on the side it started changes nothing.
        gesture = await tester.startGesture(center);
        for (var i = 0; i < 6; i++) {
          await gesture.moveBy(const Offset(-6, 0));
          await tester.pump();
        }
        await gesture.up();
        await tester.pumpAndSettle();
        expect(changes, [true, false]);

        // A cancelled drag past halfway changes nothing.
        gesture = await tester.startGesture(center);
        for (var i = 0; i < 6; i++) {
          await gesture.moveBy(const Offset(6, 0));
          await tester.pump();
        }
        await gesture.cancel();
        await tester.pumpAndSettle();
        expect(changes, [true, false]);
        expect(glassPills(), 0);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('glass thumb mirrors in RTL', (tester) async {
      Future<double> thumbX(TextDirection direction) async {
        await pumpGlassControl(
          tester,
          (_) => Center(child: AppSwitch(value: true, onChanged: (_) {})),
          direction: direction,
        );
        return tester
            .widget<AppGlassThumb>(find.byType(AppGlassThumb))
            .center
            .dx;
      }

      final ltr = await thumbX(TextDirection.ltr);
      final rtl = await thumbX(TextDirection.rtl);
      expect(ltr, greaterThan(71 / 2));
      expect(rtl, closeTo(71 - ltr, 0.001));
    });
  });
}
