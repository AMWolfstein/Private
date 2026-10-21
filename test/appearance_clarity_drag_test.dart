import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/models/theme_settings.dart';
import 'package:spotiflac_android/providers/runtime_profile_provider.dart';
import 'package:spotiflac_android/providers/theme_provider.dart';
import 'package:spotiflac_android/screens/settings/appearance_settings_page.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';
import 'package:spotiflac_android/theme/mornye_theme_wrapper.dart';
import 'package:spotiflac_android/widgets/mornye_chrome.dart';

final _clarityCalls = <(double, bool)>[];
var _outsideBuilds = 0;

class _CountingThemeNotifier extends ThemeNotifier {
  @override
  Future<void> setMornyeGlassClarity(double value, {bool persist = true}) {
    _clarityCalls.add((value, persist));
    return super.setMornyeGlassClarity(value, persist: persist);
  }
}

/// Stands in for glass elsewhere in the app, e.g. the bottom bar.
class _OutsideGlass extends ConsumerWidget {
  const _OutsideGlass();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    _outsideBuilds++;
    final clarity = ref.watch(mornyeGlassClarityProvider);
    return SizedBox(height: 1, child: Text('$clarity'));
  }
}

void main() {
  final slider = find.byKey(const ValueKey('mornye-glass-clarity'));
  final preview = find.byWidgetPredicate(
    (widget) => widget is MornyeGlassPanel && widget.clarity != null,
  );

  setUp(() {
    _clarityCalls.clear();
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
          themeProvider.overrideWith(_CountingThemeNotifier.new),
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

  double previewClarity(WidgetTester tester) =>
      tester.widget<MornyeGlassPanel>(preview).clarity!;

  testWidgets('dragging previews locally and commits once on release', (
    tester,
  ) async {
    final (container, prefs) = await open(tester);
    expect(previewClarity(tester), kDefaultMornyeGlassClarity);
    final outsideBuilds = _outsideBuilds;

    final rect = tester.getRect(slider);
    final gesture = await tester.startGesture(
      rect.centerLeft + const Offset(40, 0),
    );
    await tester.pump();
    final seen = <double>{};
    for (var step = 0; step < 12; step++) {
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      final value = tester.widget<Slider>(slider).value;
      seen.add(value);
      // Only the preview follows the thumb.
      expect(previewClarity(tester), value);
      expect(
        container.read(themeProvider).mornyeGlassClarity,
        kDefaultMornyeGlassClarity,
      );
      expect(
        container.read(mornyeGlassClarityProvider),
        kDefaultMornyeGlassClarity,
      );
    }
    expect(seen.length, greaterThan(3));
    expect(_outsideBuilds, outsideBuilds);
    expect(_clarityCalls, isEmpty);
    expect(prefs.getDouble(kMornyeGlassClarityKey), isNull);

    final last = tester.widget<Slider>(slider).value;
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_clarityCalls, [(last, true)]);
    expect(container.read(mornyeGlassClarityProvider), last);
    expect(prefs.getDouble(kMornyeGlassClarityKey), last);
    expect(_outsideBuilds, outsideBuilds + 1);
    // The slider keeps the committed value instead of snapping back.
    expect(tester.widget<Slider>(slider).value, last);
    expect(previewClarity(tester), last);
    expect(tester.takeException(), isNull);
  });

  testWidgets('external clarity changes update the slider when idle', (
    tester,
  ) async {
    final (container, _) = await open(tester);
    await container
        .read(themeProvider.notifier)
        .setMornyeGlassClarity(0.3, persist: false);
    await tester.pump();
    expect(tester.widget<Slider>(slider).value, 0.3);
    expect(previewClarity(tester), 0.3);
    expect(tester.takeException(), isNull);
  });
}
