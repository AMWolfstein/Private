import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/theme/app_theme.dart';
import 'package:sistrum/utils/layout/adaptive_layout.dart';
import 'package:sistrum/widgets/primitives/app_switch.dart';
import 'package:sistrum/widgets/glass/thumb/app_glass_surface.dart';
import 'package:sistrum/widgets/glass/chrome/app_chrome_controls.dart';

void main() {
  testWidgets('glass and controls share tablet layout coordinates', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2;
    tester.view.padding = const FakeViewPadding(bottom: 40);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    MediaQueryData? contentMetrics;

    Future<void> pumpAt(Size size) async {
      tester.view.physicalSize = size * 2;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.build(Brightness.dark),
            builder: (context, child) => AdaptiveUiScaler(child: child!),
            home: Scaffold(
              body: Column(
                children: [
                  AppGlass(
                    blurEnabled: true,
                    child: Builder(
                      builder: (context) {
                        contentMetrics = MediaQuery.of(context);
                        return const SizedBox(width: 200, height: 50);
                      },
                    ),
                  ),
                  AppSegmentedControl(
                    labels: const ['One', 'Two'],
                    selectedIndex: 0,
                    onChanged: (_) {},
                  ),
                  AppSwitch(value: true, onChanged: (_) {}),
                  AppTabBar(
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.home),
                        label: 'Home',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.music_note),
                        label: 'Library',
                      ),
                    ],
                    selectedIndex: 0,
                    onSelected: (_) {},
                    blurEnabled: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    // Full-screen tablet in both orientations, compact tablet, then a pop-up
    // window and back. Glass follows normal layout, without window-pixel hacks.
    for (final size in [
      const Size(1400, 876),
      const Size(876, 1400),
      const Size(700, 1000),
      const Size(430, 850),
      const Size(1400, 876),
    ]) {
      await pumpAt(size);
      final scale = adaptiveUiScaleForSize(size);
      expect(contentMetrics!.size, size / scale);
      expect(contentMetrics!.devicePixelRatio, 2 * scale);
      expect(contentMetrics!.padding.bottom, closeTo(20 / scale, 0.01));
      for (final type in [AppGlass, AppTabBar, AppSwitch]) {
        final glass = find.byType(type);
        expect(glass, findsWidgets);
        for (final element in glass.evaluate()) {
          final metrics = MediaQuery.of(element);
          expect(metrics.size, size / scale, reason: '$type at $size');
          expect(metrics.devicePixelRatio, 2 * scale, reason: '$type at $size');
          expect(metrics.textScaler, contentMetrics!.textScaler);
          expect(metrics.highContrast, contentMetrics!.highContrast);
          expect(metrics.disableAnimations, contentMetrics!.disableAnimations);
        }
      }
      final content = tester.getRect(find.byType(AppGlass).first);
      expect(content.width, closeTo(200 * scale, 0.01));
      expect(content.height, closeTo(50 * scale, 0.01));
      expect(tester.takeException(), isNull);
    }
  });
}
