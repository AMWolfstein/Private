import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mornye/models/settings.dart';
import 'package:mornye/providers/performance_provider.dart';
import 'package:mornye/providers/settings_provider.dart';
import 'package:mornye/widgets/performance_runtime.dart';
import 'support/fixed_settings.dart';

void main() {
  for (final enabled in [false, true]) {
    testWidgets('HUD is opt-in and pointer-transparent (enabled=$enabled)', (
      tester,
    ) async {
      var taps = 0;
      final c = PerformanceController(androidOverride: false);
      c.configure(enabled, false, 10000, 3000);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith(
              () => FixedSettingsNotifier(
                AppSettings(
                  performanceMonitoring: enabled,
                  performanceHud: enabled,
                ),
              ),
            ),
            performanceControllerProvider.overrideWithValue(c),
          ],
          child: MaterialApp(
            home: PerformanceRuntime(
              child: Scaffold(
                body: Stack(
                  children: [
                    Positioned(
                      top: 0,
                      right: 0,
                      child: SizedBox(
                        width: 220,
                        height: 200,
                        child: TextButton(
                          onPressed: () => taps++,
                          child: const Text('Original action'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        find.textContaining('Build P95'),
        enabled ? findsOneWidget : findsNothing,
      );
      await tester.tapAt(
        const Offset(750, 30),
      ); // Inside HUD and original button.
      await tester.pump();
      expect(taps, 1);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  }
}
