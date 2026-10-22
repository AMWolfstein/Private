import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/models/settings.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/screens/settings/about_page.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';
import 'package:spotiflac_android/widgets/mornye_performance_hud.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('frame statistics use percentiles and the real refresh budget', () {
    final build = [for (var i = 1; i <= 100; i++) i / 10];
    final raster = [for (var i = 1; i <= 100; i++) 2.0];
    // At 120 Hz the budget is 8.33 ms: build frames 8.4 ms and up are janky.
    final stats = MornyeFrameStats.from(
      buildMs: build,
      rasterMs: raster,
      refreshRate: 120,
    );
    expect(stats.frames, 100);
    expect(stats.build.average, closeTo(5.05, 1e-9));
    expect(stats.build.p90, 9.0);
    expect(stats.build.p99, 9.9);
    expect(stats.raster.format(), '2.0/2.0/2.0');
    expect(stats.jankPercent, 17);
    final at60 = MornyeFrameStats.from(
      buildMs: build,
      rasterMs: raster,
      refreshRate: 60,
    );
    expect(at60.jankPercent, 0);
    expect(
      stats.summary(glass: 'quality=full(liquid) level=3'),
      'mornye-hud quality=full(liquid) level=3 hz=120 frames=100 '
      'build=5.0/9.0/9.9 raster=2.0/2.0/2.0 jank=17.0%',
    );
    expect(
      MornyeFrameStats.from(
        buildMs: [],
        rasterMs: [],
        refreshRate: 60,
      ).summary(glass: 'g'),
      'mornye-hud g hz=60 frames=0 build=0.0/0.0/0.0 raster=0.0/0.0/0.0 '
      'jank=0.0%',
    );
  });

  Future<ProviderContainer> pumpHost(
    WidgetTester tester, {
    bool unlocked = false,
    bool hud = false,
  }) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialSettingsProvider.overrideWithValue(
            AppSettings(
              developerOptionsUnlocked: unlocked,
              performanceHudEnabled: hud,
            ),
          ),
        ],
        child: MaterialApp(
          theme: MornyeTheme.build(Brightness.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MornyePerformanceHudHost(child: child!),
          home: const AboutPage(),
        ),
      ),
    );
    await tester.pump();
    return ProviderScope.containerOf(tester.element(find.byType(AboutPage)));
  }

  final hud = find.byType(MornyePerformanceHud);

  testWidgets('HUD off costs nothing: no overlay and no timings callback', (
    tester,
  ) async {
    await pumpHost(tester, hud: true);
    // Enabled but not unlocked stays off.
    expect(hud, findsNothing);
    expect(MornyePerformanceHud.debugRegisteredCallbacks, 0);
    expect(find.text('Developer options'), findsNothing);
  });

  testWidgets('seven taps on the version reveal the HUD toggle', (
    tester,
  ) async {
    final container = await pumpHost(tester);
    final version = find.byKey(const ValueKey('about-version'));
    for (var tap = 1; tap < AboutPage.developerTaps; tap++) {
      await tester.tap(version);
      await tester.pump();
      expect(container.read(settingsProvider).developerOptionsUnlocked, false);
    }
    await tester.tap(version);
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).developerOptionsUnlocked, true);
    expect(find.text('Developer options enabled'), findsOneWidget);
    expect(find.text('Performance HUD'), findsOneWidget);
    expect(hud, findsNothing);
    expect(MornyePerformanceHud.debugRegisteredCallbacks, 0);

    await tester.tap(find.text('Performance HUD'));
    await tester.pump();
    expect(hud, findsOneWidget);
    expect(MornyePerformanceHud.debugRegisteredCallbacks, 1);
    expect(find.textContaining('quality=auto(liquid) level=3'), findsOneWidget);
    expect(find.text('Reset'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);

    await tester.tap(find.text('Performance HUD'));
    await tester.pump();
    expect(hud, findsNothing);
    expect(MornyePerformanceHud.debugRegisteredCallbacks, 0);
  });

  testWidgets('Copy puts the one-line summary on the clipboard', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final container = await pumpHost(tester, unlocked: true, hud: true);
    expect(hud, findsOneWidget);
    await tester.tap(find.text('Reset'));
    await tester.pump();
    await tester.tap(find.text('Copy'));
    await tester.pump();
    expect(copied, startsWith('mornye-hud quality=auto(liquid) level=3 hz='));
    expect(copied, contains('jank='));

    // Hiding the developer options also removes the overlay.
    container
        .read(settingsProvider.notifier)
        .setDeveloperOptionsUnlocked(false);
    await tester.pump();
    expect(hud, findsNothing);
    expect(MornyePerformanceHud.debugRegisteredCallbacks, 0);
    expect(container.read(settingsProvider).performanceHudEnabled, false);
  });
}
