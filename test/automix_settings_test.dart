import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mornye/l10n/l10n.dart';
import 'package:mornye/models/automix_options.dart';
import 'package:mornye/models/settings.dart';
import 'package:mornye/models/theme_settings.dart';
import 'package:mornye/providers/settings_provider.dart';
import 'package:mornye/widgets/automix_settings.dart';
import 'package:mornye/theme/app_theme.dart';
import 'package:mornye/widgets/app_bottom_sheet.dart';
import 'package:mornye/widgets/app_slider.dart';

void main() {
  testWidgets('effect picker follows app theme and saves selection', (
    tester,
  ) async {
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
          theme: AppTheme.build(Brightness.dark, accent: AppAccent.blue),
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
    expect(find.byType(AppSlider), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
