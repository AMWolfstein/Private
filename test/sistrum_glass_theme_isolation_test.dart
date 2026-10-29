import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/models/theme_settings.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/providers/theme_provider.dart';
import 'package:sistrum/widgets/shell/sistrum_theme_wrapper.dart';

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
    final clarity = ref.watch(sistrumGlassClarityLevelProvider);
    final outlines = ref.watch(sistrumGlassOutlinesProvider);
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
        child: SistrumThemeWrapper(
          builder: (light, dark, mode) => MaterialApp(
            theme: light,
            darkTheme: dark,
            themeMode: mode,
            themeAnimationDuration: const Duration(milliseconds: 300),
            home: const Column(
              children: [_ThemeDependent(), _GlassDependent()],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(_GlassDependent)),
    );
    final notifier = container.read(themeProvider.notifier);
    final settings = container.read(settingsProvider.notifier);
    final themeBuilds = _themeBuilds;
    final glassBuilds = _glassBuilds;

    // Simulate level changes: unpersisted steps, then the persisted end.
    for (var level = 1; level <= 5; level++) {
      await settings.setGlassClarityLevel(level, persist: false);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await settings.setGlassClarityLevel(5);
    await notifier.setSistrumGlassOutlines(false);
    await tester.pumpAndSettle();

    expect(_themeBuilds, themeBuilds);
    expect(_glassBuilds, greaterThan(glassBuilds));
    expect(container.read(sistrumGlassClarityLevelProvider), 5);
    expect(container.read(sistrumGlassOutlinesProvider), isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(
      (jsonDecode(prefs.getString('app_settings')!)
          as Map)['glassClarityLevel'],
      5,
    );

    // The counter does observe real theme changes.
    await notifier.setSistrumAccent(SistrumAccent.blue);
    await tester.pumpAndSettle();
    expect(_themeBuilds, greaterThan(themeBuilds));
    expect(tester.takeException(), isNull);
  });
}
