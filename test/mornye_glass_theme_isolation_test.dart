import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotiflac_android/models/theme_settings.dart';
import 'package:spotiflac_android/providers/runtime_profile_provider.dart';
import 'package:spotiflac_android/providers/theme_provider.dart';
import 'package:spotiflac_android/theme/mornye_theme_wrapper.dart';

int _themeBuilds = 0;
int _glassBuilds = 0;

class _ThemeDependent extends StatelessWidget {
  const _ThemeDependent();

  @override
  Widget build(BuildContext context) {
    _themeBuilds++;
    return ColoredBox(color: Theme.of(context).colorScheme.surface);
  }
}

class _GlassDependent extends ConsumerWidget {
  const _GlassDependent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    _glassBuilds++;
    final clarity = ref.watch(mornyeGlassClarityProvider);
    final outlines = ref.watch(mornyeGlassOutlinesProvider);
    return Text('$clarity $outlines', textDirection: TextDirection.ltr);
  }
}

void main() {
  setUp(() {
    _themeBuilds = 0;
    _glassBuilds = 0;
  });

  testWidgets('glass preferences do not rebuild Theme.of dependents', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        child: MornyeThemeWrapper(
          builder: (light, dark, mode) => MaterialApp(
            theme: light,
            darkTheme: dark,
            themeMode: mode,
            themeAnimationDuration: const Duration(milliseconds: 300),
            home: const Column(children: [_ThemeDependent(), _GlassDependent()]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(_GlassDependent)),
    );
    final notifier = container.read(themeProvider.notifier);
    final themeBuilds = _themeBuilds;
    final glassBuilds = _glassBuilds;

    // Simulate a slider drag: many unpersisted ticks, then the persisted end.
    for (var step = 0; step <= 10; step++) {
      await notifier.setMornyeGlassClarity(step / 10, persist: false);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await notifier.setMornyeGlassClarity(1);
    await notifier.setMornyeGlassOutlines(false);
    await tester.pumpAndSettle();

    expect(_themeBuilds, themeBuilds);
    expect(_glassBuilds, greaterThan(glassBuilds));
    expect(container.read(mornyeGlassClarityProvider), 1);
    expect(container.read(mornyeGlassOutlinesProvider), isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble(kMornyeGlassClarityKey), 1);

    // The counter does observe real theme changes.
    await notifier.setMornyeAccent(MornyeAccent.blue);
    await tester.pumpAndSettle();
    expect(_themeBuilds, greaterThan(themeBuilds));
    expect(tester.takeException(), isNull);
  });
}
