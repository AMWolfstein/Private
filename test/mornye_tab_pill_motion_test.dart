import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:spotiflac_android/providers/runtime_profile_provider.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';
import 'package:spotiflac_android/widgets/mornye_chrome.dart';
import 'package:spotiflac_android/widgets/mornye_selection_pill.dart';

void main() {
  Future<List<int>> pumpBar(WidgetTester tester, {bool glass = true}) async {
    final changes = <int>[];
    tester.view.physicalSize = const Size(400, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          mornyeShaderFiltersSupportedProvider.overrideWithValue(glass),
          mornyeLiquidGlassProvider.overrideWithValue(true),
        ],
        child: MaterialApp(
          theme: MornyeTheme.build(Brightness.light),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: MornyeTabBar(
                blurEnabled: true,
                selectedIndex: 0,
                onSelected: changes.add,
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
                  NavigationDestination(
                    icon: Icon(Icons.apps),
                    label: 'Browse',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.podcasts),
                    label: 'Radio',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.library_music),
                    label: 'Library',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return changes;
  }

  /// Horizontal and vertical scale of the selection pill. The first
  /// transform belongs to the bar capsule; the pill follows it.
  (double, double) pillScale(WidgetTester tester) {
    final transform = tester.widget<Transform>(
      find
          .descendant(
            of: find.byType(MornyeSelectionPill),
            matching: find.byType(Transform),
          )
          .at(1),
    );
    return (transform.transform.storage[0], transform.transform.storage[5]);
  }

  testWidgets('held glass squashes and stretches while dragged', (
    tester,
  ) async {
    final changes = await pumpBar(tester);
    expect(pillScale(tester), (1.0, 1.0));
    // The bar's own capsule is a lens; the pill adds one only while held.
    final rest = find.byType(LiquidGlassLens).evaluate().length;

    final pill = find.byType(MornyeSelectionPill);
    final start = tester.getTopLeft(pill) + const Offset(40, 30);
    final gesture = await tester.startGesture(start);
    // Fully held: only the press growth, no deformation yet.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final (heldX, heldY) = pillScale(tester);
    expect(heldX, closeTo(1.28, 0.001));
    expect(heldY, closeTo(1.24, 0.001));
    expect(find.byType(LiquidGlassLens), findsNWidgets(rest + 1));

    // Accelerate towards the far tab; the held pill deforms on both axes.
    var deformed = false;
    var step = 2.0;
    for (var frame = 0; frame < 16; frame++) {
      await gesture.moveBy(Offset(step, 0));
      step *= 1.3;
      await tester.pump(const Duration(milliseconds: 16));
      final (x, y) = pillScale(tester);
      if ((x - heldX).abs() > 0.005 && (y - heldY).abs() > 0.005) {
        deformed = true;
        // Opposite directions: wider and flatter, or narrower and taller.
        expect((x - heldX).sign, -(y - heldY).sign);
      }
    }
    expect(deformed, isTrue);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(pillScale(tester), (1.0, 1.0));
    expect(find.byType(LiquidGlassLens), findsNWidgets(rest));
    expect(changes, isNotEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no lens or deformation without the glass gate', (tester) async {
    final changes = await pumpBar(tester, glass: false);
    final pill = find.byType(MornyeSelectionPill);
    final gesture = await tester.startGesture(
      tester.getTopLeft(pill) + const Offset(40, 30),
    );
    for (var frame = 0; frame < 10; frame++) {
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump(const Duration(milliseconds: 16));
      expect(pillScale(tester), (1.0, 1.0));
      expect(find.byType(LiquidGlassLens), findsNothing);
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(changes, isNotEmpty);
  });
}
