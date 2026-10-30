import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/l10n/app_localizations.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/screens/settings/appearance/appearance_glass_clarity_slider.dart';
import 'package:sistrum/core/theme/app_theme.dart';

import '../../../support/library_section_harness.dart';

Future<void> _pump(WidgetTester tester, {required bool blurEnabled}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith(LibrarySectionSettings.new),
        appBlurEnabledProvider.overrideWithValue(blurEnabled),
      ],
      child: MaterialApp(
        theme: AppTheme.build(Brightness.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: SingleChildScrollView(child: AppGlassClaritySlider()),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('with glass available the clarity can be adjusted', (
    tester,
  ) async {
    await _pump(tester, blurEnabled: true);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(AppGlassClaritySlider)),
    );
    expect(find.text(l10n.appearanceGlassClarity), findsOneWidget);
    expect(
      find.byKey(const ValueKey('sistrum-glass-clarity-unavailable')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'with glass turned off the slider explains why it is unavailable',
    (tester) async {
      await _pump(tester, blurEnabled: false);
      expect(
        find.byKey(const ValueKey('sistrum-glass-clarity-unavailable')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
