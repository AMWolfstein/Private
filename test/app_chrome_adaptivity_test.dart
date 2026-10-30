import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/navigation/shell_navigation.dart';
import 'package:sistrum/theme/app_theme.dart';
import 'package:sistrum/widgets/glass/thumb/app_glass_surface.dart';
import 'package:sistrum/widgets/glass/chrome/app_chrome_adaptivity.dart';

void main() {
  Future<AppChromeAdaptivity> pumpBackdrop(
    WidgetTester tester, {
    required bool enabled,
  }) async {
    final adaptivity = AppChromeAdaptivity();
    addTearDown(adaptivity.dispose);
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(400, 800),
            padding: EdgeInsets.only(bottom: 120),
          ),
          child: AppChromeBackdrop(
            adaptivity: adaptivity,
            enabled: enabled,
            child: ListView.builder(
              itemCount: 80,
              itemBuilder: (_, index) =>
                  SizedBox(height: 64, child: Text('Row $index')),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return adaptivity;
  }

  final area = find.byKey(const ValueKey('sistrum-bar-adaptive-area'));

  testWidgets('closed gate mounts no view and no sampler', (tester) async {
    await pumpBackdrop(tester, enabled: false);
    expect(find.byType(LiquidGlassView), findsNothing);
    expect(area, findsNothing);
    expect(find.text('Row 0'), findsOneWidget);
  });

  testWidgets('sampling is held at rest and live only while scrolling', (
    tester,
  ) async {
    final adaptivity = await pumpBackdrop(tester, enabled: true);
    final view = tester.widget<LiquidGlassView>(find.byType(LiquidGlassView));
    expect(view.adaptiveSampling, isNotNull);
    expect(view.adaptiveSampling!.frameLimit, 6);
    expect(view.realTimeCapture, isFalse);
    expect(view.batch, isFalse);
    expect(view.useImpellerBackdrop, isTrue);
    // The area covers the bar footprint at the bottom edge only.
    expect(tester.getRect(area), const Rect.fromLTWH(0, 680, 400, 120));

    // Mounting takes one look, then holds: no realtime capture at rest.
    final controller = adaptivity.controller;
    expect(controller.enabled, isFalse);
    final mounted = controller.refreshGeneration;
    expect(mounted, greaterThan(0));
    await tester.pump(AppChromeAdaptivity.followUpDelay);
    expect(controller.enabled, isFalse);
    expect(controller.refreshGeneration, mounted + 1);

    final gesture = await tester.startGesture(const Offset(200, 400));
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();
    expect(controller.enabled, isTrue);
    await gesture.moveBy(const Offset(0, -80));
    await tester.pump();
    expect(controller.enabled, isTrue);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(controller.enabled, isFalse);
    final settled = controller.refreshGeneration;
    expect(settled, greaterThan(mounted + 1));
    // A follow-up look catches artwork that fades in after the scroll.
    await tester.pump(AppChromeAdaptivity.followUpDelay);
    expect(controller.refreshGeneration, settled + 1);
    expect(controller.enabled, isFalse);
  });

  testWidgets('a visible page change takes one look', (tester) async {
    final adaptivity = await pumpBackdrop(tester, enabled: false);
    final before = adaptivity.controller.refreshGeneration;
    ShellNavigationService.pageChanges.value++;
    expect(adaptivity.controller.refreshGeneration, before + 1);
    expect(adaptivity.controller.enabled, isFalse);
    await tester.pump(AppChromeAdaptivity.followUpDelay);
  });

  test('a page override wins over the sampled verdict', () {
    expect(
      appChromeBrightness(
        pageOverride: Brightness.dark,
        sampled: Brightness.light,
      ),
      Brightness.dark,
    );
    expect(
      appChromeBrightness(pageOverride: null, sampled: Brightness.dark),
      Brightness.dark,
    );
    expect(appChromeBrightness(pageOverride: null, sampled: null), isNull);
  });

  testWidgets('adaptive chrome drops the light glass floor only in scope', (
    tester,
  ) async {
    Color fill({required bool active, Brightness b = Brightness.light}) {
      final decorated = tester.widgetList<DecoratedBox>(
        find.descendant(
          of: find.byKey(ValueKey('glass-$active-$b')),
          matching: find.byType(DecoratedBox),
        ),
      );
      return decorated
          .map((box) => box.decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.color)
          .whereType<Color>()
          .first;
    }

    Widget glass(bool active, Brightness b) => Theme(
      data: AppTheme.build(b),
      child: AppAdaptiveChromeScope(
        active: active,
        child: SizedBox(
          key: ValueKey('glass-$active-$b'),
          width: 60,
          height: 60,
          child: const AppGlass.navigation(
            blurEnabled: true,
            strongTint: true,
            tintOpacity: 0.49,
            child: SizedBox.expand(),
          ),
        ),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appGlassLevelProvider.overrideWithValue(AppGlassLevel.lite),
        ],
        child: MaterialApp(
          home: Column(
            children: [
              for (final b in Brightness.values)
                for (final active in [false, true]) glass(active, b),
            ],
          ),
        ),
      ),
    );
    final light = fill(active: false);
    final clear = fill(active: true);
    expect(light.a, greaterThan(0.5));
    // Balanced bar fill: 0.49 x 0.64 under the level's 15% veil.
    expect(clear.a, closeTo(0.42, 0.01));
    // Dark glass already follows its backdrop; the scope leaves it alone.
    expect(
      fill(active: true, b: Brightness.dark),
      fill(active: false, b: Brightness.dark),
    );
  });
}
