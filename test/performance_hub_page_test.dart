import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mornye/l10n/l10n.dart';
import 'package:mornye/providers/performance_provider.dart';
import 'package:mornye/providers/settings_provider.dart';
import 'package:mornye/screens/settings/performance_hub_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/fixed_settings.dart';

void main() {
  testWidgets(
    'production Hub is accessible with monitoring off and controls update settings',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        ProviderScope(
          overrides: [settingsProvider.overrideWith(FixedSettingsNotifier.new)],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const PerformanceHubPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PerformanceHubPage)),
      );
      final controller = container.read(performanceControllerProvider);
      expect(find.text('Performance Hub'), findsOneWidget);
      expect(controller.registered, false);
      expect(container.read(settingsProvider).performanceHud, false);
      await tester.tap(find.text('Enable Performance Monitoring'));
      await tester.pumpAndSettle();
      expect(container.read(settingsProvider).performanceMonitoring, true);
      expect(controller.registered, true);
      await tester.tap(find.text('Enable Performance Monitoring'));
      await tester.pumpAndSettle();
      expect(controller.registered, false);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
