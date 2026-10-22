import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/providers/runtime_profile_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/providers/theme_provider.dart';
import 'package:spotiflac_android/screens/settings/appearance_settings_page.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';
import 'package:spotiflac_android/theme/mornye_theme_wrapper.dart';
import 'package:spotiflac_android/widgets/mornye_chrome.dart';

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
    final level = ref.watch(mornyeGlassClarityLevelProvider);
    return SizedBox(height: 1, child: Text('$level'));
  }
}

void main() {
  final slider = find.byKey(const ValueKey('mornye-glass-clarity'));
  final preview = find.byWidgetPredicate(
    (widget) => widget is MornyeGlassPanel && widget.clarity != null,
  );

  setUp(() {
    _levelCalls.clear();
    _outsideBuilds = 0;
  });

  Future<(ProviderContainer, SharedPreferences)> open(
    WidgetTester tester,
  ) async {
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
        ],
        child: MornyeThemeWrapper(
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
                  child: MornyeSettingsTheme(child: AppearanceSettingsPage()),
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
      expect(container.read(mornyeGlassClarityLevelProvider), 3);
    }
    expect(seen, containsAll([2.0, 4.0, 5.0]));
    expect(_outsideBuilds, outsideBuilds);
    expect(_levelCalls, isEmpty);
    expect(savedLevel(prefs), isNull);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(_levelCalls, [(5, true)]);
    expect(container.read(mornyeGlassClarityLevelProvider), 5);
    expect(savedLevel(prefs), 5);
    expect(_outsideBuilds, outsideBuilds + 1);
    expect(tester.widget<Slider>(slider).value, 5);
    expect(tester.widget<Slider>(slider).label, 'Crystal');
    expect(tester.widget<MornyeGlassPanel>(preview).clarity, isNotNull);
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
}
