import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g1455/g1455.dart' show GlassSwitch;
import 'package:sistrum/widgets/primitives/app_switch.dart';

import '../../support/glass_controls.dart';

void main() {
  group('AppSwitch (g1455 GlassSwitch)', () {
    const key = ValueKey('switch');

    testWidgets('a tap reports the new value and the knob follows it', (
      tester,
    ) async {
      var value = false;
      final reported = <bool>[];
      await pumpGlassControl(
        tester,
        (setState) => AppSwitch(
          key: key,
          value: value,
          onChanged: (next) {
            reported.add(next);
            setState(() => value = next);
          },
        ),
      );
      expect(tester.widget<GlassSwitch>(find.byType(GlassSwitch)).value, false);
      await tester.tap(find.byType(GlassSwitch));
      await tester.pumpAndSettle();
      expect(reported, [true]);
      expect(tester.widget<GlassSwitch>(find.byType(GlassSwitch)).value, true);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a null onChanged disables it and reports nothing', (
      tester,
    ) async {
      await pumpGlassControl(
        tester,
        (_) => const AppSwitch(value: true, onChanged: null),
      );
      expect(
        tester.widget<GlassSwitch>(find.byType(GlassSwitch)).onChanged,
        isNull,
      );
      await tester.tap(find.byType(GlassSwitch), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('mirrors in RTL and still reports a tap', (tester) async {
      final reported = <bool>[];
      await pumpGlassControl(
        tester,
        (_) => AppSwitch(value: false, onChanged: reported.add),
        direction: TextDirection.rtl,
      );
      await tester.tap(find.byType(GlassSwitch));
      await tester.pumpAndSettle();
      expect(reported, [true]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the value comes from the parent, not from the last tap', (
      tester,
    ) async {
      await pumpGlassControl(
        tester,
        (_) => AppSwitch(key: key, value: true, onChanged: (_) {}),
      );
      await tester.tap(find.byType(GlassSwitch));
      await tester.pumpAndSettle();
      // The parent never rebuilt with the new value, so the switch stays on.
      expect(tester.widget<GlassSwitch>(find.byType(GlassSwitch)).value, true);
    });
  });
}
