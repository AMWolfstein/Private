import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/core/models/app_glass.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/providers/settings/settings_provider.dart';
import 'package:sistrum/providers/settings/theme_provider.dart';
import 'package:sistrum/screens/settings/appearance/appearance_settings_page.dart';
import 'package:sistrum/services/glass/app_glass_auto_probe.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/app.dart';
import 'package:sistrum/widgets/glass/chrome/app_chrome.dart';

final _levelCalls = <(int, bool)>[];
var _outsideBuilds = 0;

class _CountingSettings extends SettingsNotifier {
  @override
  Future<void> setGlassClarityLevel(int level, {bool persist = true}) {
    _levelCalls.add((level, persist));
    return super.setGlassClarityLevel(level, persist: persist);
  }
}

/// Stands in for glass elsewhere in the app, e.g. the bottom bar.
class _OutsideGlass extends ConsumerWidget {
  const _OutsideGlass();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    _outsideBuilds++;
    final level = ref.watch(appGlassClarityLevelProvider);
    return SizedBox(height: 1, child: Text('$level'));
  }
}

void main() {
  final slider = find.byKey(const ValueKey('sistrum-glass-clarity'));
  final preview = find.byWidgetPredicate(
    (widget) => widget is AppGlassPanel && widget.clarityLevel != null,
  );

  setUp(() {
    _levelCalls.clear();
    _outsideBuilds = 0;
  });

  Future<(ProviderContainer, SharedPreferences)> open(
    WidgetTester tester, {
    AppGlassAutoResult? autoResult,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialThemeSettingsProvider.overrideWithValue(
            loadBootstrapThemeSettings(prefs),
          ),
          settingsProvider.overrideWith(_CountingSettings.new),
          initialGlassAutoResultProvider.overrideWithValue(autoResult),
        ],
        child: AppThemeWrapper(
          builder: (light, dark, mode) => MaterialApp(
            theme: light,
            darkTheme: dark,
            themeMode: mode,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Column(
              children: [
                _OutsideGlass(),
                Expanded(
                  child: AppSettingsTheme(child: AppearanceSettingsPage()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(slider));
    return (container, prefs);
  }

  int? savedLevel(SharedPreferences prefs) {
    final raw = prefs.getString('app_settings');
    return raw == null
        ? null
        : (jsonDecode(raw) as Map<String, dynamic>)['glassClarityLevel']
              as int?;
  }

  testWidgets('the slider snaps to five named levels', (tester) async {
    await open(tester);
    final widget = tester.widget<Slider>(slider);
    expect(widget.min, 1);
    expect(widget.max, 5);
    expect(widget.divisions, 4);
    expect(widget.value, 3);
    expect(widget.label, 'Balanced');
    expect(find.text('Tinted'), findsOneWidget);
    expect(find.text('Clear'), findsOneWidget);
  });

  testWidgets('dragging previews locally and commits once on release', (
    tester,
  ) async {
    final (container, prefs) = await open(tester);
    final outsideBuilds = _outsideBuilds;
    final rect = tester.getRect(slider);
    final gesture = await tester.startGesture(rect.centerLeft);
    await tester.pump();
    final seen = <double>{};
    for (var step = 0; step < 12; step++) {
      await gesture.moveBy(Offset(rect.width / 12, 0));
      await tester.pump();
      final value = tester.widget<Slider>(slider).value;
      // Every intermediate value is one of the five stops.
      expect(value, value.roundToDouble());
      seen.add(value);
      // Only the preview follows the thumb.
      expect(tester.widget<AppGlassPanel>(preview).clarityLevel, value.round());
      expect(container.read(appGlassClarityLevelProvider), 3);
    }
    expect(seen, containsAll([2.0, 4.0, 5.0]));
    expect(_outsideBuilds, outsideBuilds);
    expect(_levelCalls, isEmpty);
    expect(savedLevel(prefs), isNull);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(_levelCalls, [(5, true)]);
    expect(container.read(appGlassClarityLevelProvider), 5);
    expect(savedLevel(prefs), 5);
    expect(_outsideBuilds, outsideBuilds + 1);
    expect(tester.widget<Slider>(slider).value, 5);
    expect(tester.widget<Slider>(slider).label, 'Crystal');
    expect(tester.widget<AppGlassPanel>(preview).clarityLevel, 5);
    expect(tester.takeException(), isNull);
  });

  testWidgets('external level changes update the slider when idle', (
    tester,
  ) async {
    final (container, _) = await open(tester);
    await container
        .read(settingsProvider.notifier)
        .setGlassClarityLevel(1, persist: false);
    await tester.pump();
    expect(tester.widget<Slider>(slider).value, 1);
    expect(tester.widget<Slider>(slider).label, 'Frosted');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a measured Auto step is explained; Level 1 locks the slider', (
    tester,
  ) async {
    final (container, _) = await open(
      tester,
      autoResult: const AppGlassAutoResult(
        build: 'b',
        step: AppGlassAutoStep.liteFrosted,
        done: true,
      ),
    );
    expect(
      find.text('Measured on this device: Auto uses Lite · Frosted.'),
      findsOneWidget,
    );
    final widget = tester.widget<Slider>(slider);
    // The saved level stays visible; glass renders at Level 1.
    expect(widget.value, 3);
    expect(widget.onChanged, isNull);
    expect(container.read(appGlassClarityLevelProvider), 1);
    expect(
      find.text(
        'Auto measured this device and uses Frosted. Choose Lite or Full to '
        'set clarity.',
      ),
      findsOneWidget,
    );

    // An explicit choice restores the slider and drops the note.
    container
        .read(settingsProvider.notifier)
        .setGlassQuality(AppGlassQuality.lite);
    await tester.pump();
    expect(tester.widget<Slider>(slider).onChanged, isNotNull);
    expect(container.read(appGlassClarityLevelProvider), 3);
    expect(
      find.byKey(const ValueKey('sistrum-glass-auto-measured')),
      findsNothing,
    );
  });

  testWidgets('a measured lite step keeps the slider', (tester) async {
    await open(
      tester,
      autoResult: const AppGlassAutoResult(
        build: 'b',
        step: AppGlassAutoStep.lite,
        done: true,
      ),
    );
    expect(
      find.text('Measured on this device: Auto uses Lite.'),
      findsOneWidget,
    );
    expect(tester.widget<Slider>(slider).onChanged, isNotNull);
  });
}
