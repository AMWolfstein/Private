import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:mornye/models/settings.dart';
import 'package:mornye/providers/runtime_profile_provider.dart';
import 'package:mornye/providers/settings_provider.dart';
import 'package:mornye/theme/mornye_theme.dart';
import 'package:mornye/widgets/mornye_chrome.dart';
import 'package:mornye/widgets/mornye_liquid_backdrop.dart';
import 'package:mornye/widgets/mornye_selection_pill.dart';

class _Settings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings();
}

Future<void> _pumpGlass(WidgetTester tester, double clarity) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith(_Settings.new),
        deviceSupportsBackdropBlurProvider.overrideWithValue(true),
        deviceSupportsLiquidGlassProvider.overrideWithValue(true),
      ],
      child: MaterialApp(
        theme: MornyeTheme.build(Brightness.light, glassClarity: clarity),
        home: const Scaffold(
          body: MornyeGlass.navigation(
            blurEnabled: true,
            child: SizedBox(width: 200, height: 50),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUp(() => MornyeGlassRules.debugShaderFilterSupport = true);
  tearDown(() => MornyeGlassRules.debugShaderFilterSupport = null);

  // Clear end of the slider: sigma steps down to 2 and the dispersion keeps
  // scaling with clarity. 0.75 is the default and must not change.
  const expectations = <(double clarity, double sigma, double dispersion)>[
    (0.75, 6, 0.99),
    (0.9, 2, 1.188),
    (0.95, 2, 1.254),
    (1.0, 2, 1.32),
  ];
  for (final (clarity, sigma, dispersion) in expectations) {
    testWidgets('clarity $clarity maps to sigma and dispersion', (
      tester,
    ) async {
      await _pumpGlass(tester, clarity);
      final lens = tester.widget<LiquidGlassLens>(
        find.byType(LiquidGlassLens).first,
      );
      final backdrop = tester.widget<MornyeLiquidBackdrop>(
        find.byType(MornyeLiquidBackdrop).first,
      );
      expect(backdrop.clarity, clarity);
      expect(backdrop.blurSigma, sigma);
      expect(lens.style.dispersion, closeTo(dispersion, 1e-9));
    });
  }

  testWidgets('the held lens is forced to clarity 1 and no blur', (
    tester,
  ) async {
    // The pill is built at a low clarity; its held lens must still ignore it.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsProvider.overrideWith(_Settings.new)],
        child: MaterialApp(
          theme: MornyeTheme.build(Brightness.light, glassClarity: 0.75),
          home: Center(
            child: SizedBox(
              width: 300,
              height: 56,
              child: MornyeSelectionPill(
                labels: const ['A', 'B', 'C'],
                selectedIndex: 0,
                liquidInteraction: true,
                padding: EdgeInsets.zero,
                onChanged: (_) {},
                itemBuilder: (_, index, _) => const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // At rest the held lens is present but draws no lens.
    expect(
      find.descendant(
        of: find.byType(MornyeSelectionPill),
        matching: find.byType(LiquidGlassLens),
      ),
      findsNothing,
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(MornyeSelectionPill)),
    );
    addTearDown(gesture.up);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 1));

    final backdrop = tester.widget<MornyeLiquidBackdrop>(
      find.descendant(
        of: find.byType(MornyeSelectionPill),
        matching: find.byType(MornyeLiquidBackdrop),
      ),
    );
    expect(backdrop.clarity, 1);
    expect(backdrop.blurSigma, 0);
    expect(backdrop.interaction, isTrue);
    expect(backdrop.progress, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
}
