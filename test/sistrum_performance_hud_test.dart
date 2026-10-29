import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/models/settings.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/screens/settings/about_page.dart';
import 'package:sistrum/widgets/glass/sistrum_glass_auto_probe.dart';
import 'package:sistrum/theme/sistrum_theme.dart';
import 'package:sistrum/widgets/glass/sistrum_performance_hud.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SistrumPerformanceHud.debugResetPlacement();
  });

  test('frame statistics use percentiles and the real refresh budget', () {
    final build = [for (var i = 1; i <= 100; i++) i / 10];
    final raster = [for (var i = 1; i <= 100; i++) 2.0];
    // At 120 Hz the budget is 8.33 ms: build frames 8.4 ms and up are janky.
    final stats = SistrumFrameStats.from(
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
    final at60 = SistrumFrameStats.from(
      buildMs: build,
      rasterMs: raster,
      refreshRate: 60,
    );
    expect(at60.jankPercent, 0);
    expect(
      stats.summary(glass: 'quality=full(liquid) level=3'),
      'sistrum-hud quality=full(liquid) level=3 hz=120 frames=100 '
      'build=5.0/9.0/9.9 raster=2.0/2.0/2.0 jank=17.0%',
    );
    expect(
      SistrumFrameStats.from(
        buildMs: [],
        rasterMs: [],
        refreshRate: 60,
      ).summary(glass: 'g'),
      'sistrum-hud g hz=60 frames=0 build=0.0/0.0/0.0 raster=0.0/0.0/0.0 '
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
          theme: SistrumTheme.build(Brightness.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => SistrumPerformanceHudHost(child: child!),
          home: const AboutPage(),
        ),
      ),
    );
    await tester.pump();
    return ProviderScope.containerOf(tester.element(find.byType(AboutPage)));
  }

  final hud = find.byType(SistrumPerformanceHud);

  testWidgets('HUD off costs nothing: no overlay and no timings callback', (
    tester,
  ) async {
    await pumpHost(tester, hud: true);
    // Enabled but not unlocked stays off.
    expect(hud, findsNothing);
    expect(SistrumPerformanceHud.debugRegisteredCallbacks, 0);
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
    expect(SistrumPerformanceHud.debugRegisteredCallbacks, 0);

    await tester.tap(find.text('Performance HUD'));
    await tester.pump();
    expect(hud, findsOneWidget);
    expect(SistrumPerformanceHud.debugRegisteredCallbacks, 1);
    expect(
      find.textContaining('quality=auto(liquid, measuring) level=3 reads='),
      findsOneWidget,
    );
    expect(find.text('Reset'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);

    await tester.tap(find.text('Performance HUD'));
    await tester.pump();
    expect(hud, findsNothing);
    expect(SistrumPerformanceHud.debugRegisteredCallbacks, 0);
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
    expect(
      copied,
      matches(
        RegExp(
          r'^sistrum-hud quality=auto\(liquid, measuring\) level=3 reads=\d+ '
          r'sampler=n/a bandblur=on ground=n/a hz=',
        ),
      ),
    );
    expect(copied, contains('jank='));

    // Hiding the developer options also removes the overlay.
    container
        .read(settingsProvider.notifier)
        .setDeveloperOptionsUnlocked(false);
    await tester.pump();
    expect(hud, findsNothing);
    expect(SistrumPerformanceHud.debugRegisteredCallbacks, 0);
    expect(container.read(settingsProvider).performanceHudEnabled, false);
  });

  /// The HUD over a page that counts taps anywhere.
  Future<(ProviderContainer, ValueNotifier<int>)> pumpOverPage(
    WidgetTester tester,
  ) async {
    final taps = ValueNotifier(0);
    addTearDown(taps.dispose);
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialSettingsProvider.overrideWithValue(
            const AppSettings(
              developerOptionsUnlocked: true,
              performanceHudEnabled: true,
            ),
          ),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(padding: const EdgeInsets.only(top: 24)),
            child: SistrumPerformanceHudHost(child: child!),
          ),
          home: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => taps.value++,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pump();
    return (
      ProviderScope.containerOf(tester.element(find.byType(SizedBox).first)),
      taps,
    );
  }

  final panel = find.byKey(const ValueKey('sistrum-performance-hud'));
  final handle = find.byKey(const ValueKey('sistrum-performance-hud-handle'));
  final pill = find.byKey(const ValueKey('sistrum-performance-hud-pill'));

  testWidgets('starts top-left, clear of the Home avatar, and drags', (
    tester,
  ) async {
    await pumpOverPage(tester);
    expect(tester.getTopLeft(panel), const Offset(8, 28));
    await tester.drag(handle, const Offset(120, 300));
    await tester.pump();
    expect(tester.getTopLeft(panel), const Offset(128, 328));
    // It never leaves the screen.
    await tester.drag(handle, const Offset(-900, -900));
    await tester.pump();
    expect(tester.getTopLeft(panel), Offset.zero);
    // Overshooting an edge stores the clamped position, so a normal drag from
    // the corner moves immediately instead of consuming the overshoot.
    await tester.drag(handle, const Offset(40, 60));
    await tester.pump();
    expect(tester.getTopLeft(panel), const Offset(40, 60));
  });

  testWidgets('statistics pass taps through; the buttons do not', (
    tester,
  ) async {
    final (_, taps) = await pumpOverPage(tester);
    await tester.tap(find.textContaining('frames @'));
    await tester.tap(find.textContaining('raster '));
    expect(taps.value, 2);
    await tester.tap(find.text('Reset'));
    await tester.tap(handle);
    expect(taps.value, 2);
  });

  testWidgets('minimizes to a pill that keeps its place and expands', (
    tester,
  ) async {
    final (_, taps) = await pumpOverPage(tester);
    await tester.drag(handle, const Offset(40, 100));
    await tester.pump();
    final at = tester.getTopLeft(panel);
    await tester.tap(
      find.byKey(const ValueKey('sistrum-performance-hud-minimize')),
    );
    await tester.pump();
    expect(pill, findsOneWidget);
    expect(find.text('Copy'), findsNothing);
    expect(find.textContaining('frames @'), findsNothing);
    expect(tester.getTopLeft(panel), at);
    expect(tester.getSize(pill).height, greaterThanOrEqualTo(36));
    // Timings are still collected while minimized.
    expect(SistrumPerformanceHud.debugRegisteredCallbacks, 1);
    await tester.drag(pill, const Offset(0, 50));
    await tester.pump();
    expect(tester.getTopLeft(panel), at + const Offset(0, 50));
    await tester.tap(pill);
    await tester.pump();
    expect(pill, findsNothing);
    expect(find.text('Copy'), findsOneWidget);
    expect(taps.value, 0);
  });

  testWidgets('A/B switches flip from the HUD and show in its line', (
    tester,
  ) async {
    final (container, _) = await pumpOverPage(tester);
    expect(find.textContaining('sampler=n/a bandblur=on'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('sistrum-performance-hud-sampler')),
    );
    await tester.tap(find.byKey(const ValueKey('sistrum-performance-hud-band')));
    await tester.pump();
    expect(container.read(settingsProvider).barSamplerDisabled, true);
    expect(container.read(settingsProvider).headerBandBlurDisabled, true);
    expect(find.textContaining('sampler=off bandblur=off'), findsOneWidget);
    expect(find.text('Sampler: off'), findsOneWidget);
    expect(find.text('Band blur: off'), findsOneWidget);
  });

  testWidgets('developer options carry the A/B switches and re-measuring', (
    tester,
  ) async {
    final container = await pumpHost(tester, unlocked: true);
    container
        .read(sistrumGlassAutoResultProvider.notifier)
        .record(
          const SistrumGlassAutoResult(
            build: 'b',
            step: SistrumGlassAutoStep.lite,
            done: true,
          ),
        );
    await tester.pump();
    final sampler = find.byKey(const ValueKey('developer-bar-sampler'));
    final band = find.byKey(const ValueKey('developer-header-band-blur'));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('developer-remeasure-glass')),
      200,
    );
    await tester.ensureVisible(sampler);
    await tester.pumpAndSettle();
    await tester.tap(sampler);
    await tester.pumpAndSettle();
    await tester.ensureVisible(band);
    await tester.pumpAndSettle();
    await tester.tap(band);
    await tester.pump();
    final settings = container.read(settingsProvider);
    expect(settings.barSamplerDisabled, true);
    expect(settings.headerBandBlurDisabled, true);
    expect(container.read(sistrumBarSamplerDisabledProvider), true);

    await tester.tap(find.byKey(const ValueKey('developer-remeasure-glass')));
    await tester.pump();
    expect(container.read(sistrumGlassAutoResultProvider), isNull);

    // Hiding the options restores both effects.
    container
        .read(settingsProvider.notifier)
        .setDeveloperOptionsUnlocked(false);
    expect(container.read(settingsProvider).barSamplerDisabled, false);
    expect(container.read(settingsProvider).headerBandBlurDisabled, false);
  });
}
