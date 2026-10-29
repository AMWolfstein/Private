import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/models/settings.dart';
import 'package:sistrum/models/theme_settings.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/screens/settings/playback_settings_page.dart';
import 'package:sistrum/screens/settings/settings_search_catalog.dart';
import 'support/material_test_theme.dart';
import 'package:sistrum/theme/app_theme.dart';
import 'package:sistrum/widgets/settings/settings_item_rows.dart';

void main() {
  for (final sistrum in [true]) {
    testWidgets('personalization switch persists and is searchable ($sistrum)', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(
        overrides: [
          initialSettingsProvider.overrideWithValue(const AppSettings()),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: sistrum
                ? AppTheme.build(Brightness.dark, accent: AppAccent.blue)
                : MaterialTestTheme.light(),
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const PlaybackSettingsPage(),
          ),
        ),
      );
      final label = find.text('Personalized autoplay');
      await tester.scrollUntilVisible(
        label,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      // On by default; the reset action belongs to the enabled state.
      expect(container.read(settingsProvider).autoplayPersonalization, isTrue);
      expect(find.text('Reset recommendation learning'), findsOneWidget);
      // A stray tap only asks; cancelling keeps what was learned.
      await tester.tap(find.text('Reset recommendation learning'));
      await tester.pumpAndSettle();
      expect(find.text('Reset recommendation learning?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Reset recommendation learning?'), findsNothing);
      await tester.tap(label);
      await tester.pumpAndSettle();
      expect(container.read(settingsProvider).autoplayPersonalization, isFalse);
      expect(container.read(settingsProvider).autoplay, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(
        AppSettings.fromJson(
          jsonDecode(prefs.getString('app_settings')!) as Map<String, dynamic>,
        ).autoplayPersonalization,
        isFalse,
      );
      expect(find.text('Reset recommendation learning'), findsNothing);
      await tester.ensureVisible(label);
      await tester.pumpAndSettle();
      await tester.tap(label);
      await tester.pumpAndSettle();
      expect(container.read(settingsProvider).autoplayPersonalization, isTrue);
      final l10n = AppLocalizations.of(tester.element(label));
      expect(
        SettingsSearchCatalog(l10n).playback.any(
          (entry) => entry.matches(SettingsSearchQuery('machine learning')),
        ),
        isTrue,
      );
      await tester.pump();
      expect(
        tester
            .widget<SettingsSwitchItem>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is SettingsSwitchItem &&
                    widget.title == 'Personalized autoplay',
              ),
            )
            .enabled,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
