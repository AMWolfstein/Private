import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/core/models/automix_options.dart';
import 'package:sistrum/core/models/settings.dart';
import 'package:sistrum/core/models/theme_settings.dart';
import 'package:sistrum/providers/settings/settings_provider.dart';
import 'package:sistrum/screens/settings/playback/playback_settings_page.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/widgets/primitives/app_bottom_sheet.dart';

import '../support/material_test_theme.dart';

void main() {
  testWidgets(
    'manual duration saves at end of drag and USB disables DSP controls',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [
          initialSettingsProvider.overrideWithValue(
            const AppSettings(
              autoMix: true,
              autoMixDuration: 5,
              autoMixEffect: AutoMixEffect.custom,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(child: AutoMixSettings()),
            ),
          ),
        ),
      );
      final slider = tester.widget<Slider>(find.byType(Slider).first);
      slider.onChanged!(45);
      await tester.pump();
      expect(container.read(settingsProvider).autoMixDuration, 5);
      expect(find.text('Mix duration: 45 s'), findsOneWidget);
      slider.onChangeEnd!(45);
      await tester.pump();
      expect(container.read(settingsProvider).autoMixDuration, 45);
      container.read(settingsProvider.notifier).setUsbBitPerfect(true);
      await tester.pump();
      for (final slider in tester.widgetList<Slider>(find.byType(Slider))) {
        expect(slider.onChanged, isNull);
      }
      await tester.tap(find.text('Transition effect'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final sistrum in [true]) {
    testWidgets(
      'effect picker follows app theme and saves selection ($sistrum)',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = const Size(350, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final container = ProviderContainer(
          overrides: [
            initialSettingsProvider.overrideWithValue(
              const AppSettings(autoMix: true),
            ),
          ],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: sistrum
                  ? AppTheme.build(Brightness.dark, accent: AppAccent.blue)
                  : MaterialTestTheme.light(seedColor: Colors.blue),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const AppSettingsTheme(
                child: Scaffold(
                  body: SingleChildScrollView(child: AutoMixSettings()),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Transition effect'));
        await tester.pumpAndSettle();
        expect(find.byType(AppBottomSheet), findsOneWidget);
        expect(find.byType(AppSheetOption), findsNWidgets(6));
        final context = tester.element(find.byType(AppBottomSheet));
        expect(context.isAppTheme, sistrum);
        final selected = tester
            .widgetList<AppSheetOption>(find.byType(AppSheetOption))
            .singleWhere((option) => option.trailing != null);
        expect((selected.title as Text).data, 'Auto');
        expect(
          (selected.trailing as Icon).color,
          Theme.of(context).colorScheme.primary,
        );
        final custom = find.descendant(
          of: find.byType(AppBottomSheet),
          matching: find.text('Custom'),
        );
        await tester.ensureVisible(custom);
        await tester.pumpAndSettle();
        await tester.tap(custom);
        await tester.pumpAndSettle();
        expect(
          container.read(settingsProvider).autoMixEffect,
          AutoMixEffect.custom,
        );
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.text('Custom'), findsOneWidget);
        expect(find.byType(Slider), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
