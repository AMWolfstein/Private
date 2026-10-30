import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/l10n/app_localizations.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/widgets/settings/music_haptics_settings.dart';

import 'support/library_section_harness.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(WidgetTester tester, {required bool enabled}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsProvider.overrideWith(LibrarySectionSettings.new)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: MusicHapticsSettings(enabled: enabled)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('both haptic sliders show the saved percentage', (tester) async {
    await pump(tester, enabled: true);
    // The default sensitivity and strength are both 50%.
    expect(find.textContaining('50%'), findsNWidgets(2));
    expect(find.byType(Slider).evaluate().length, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled haptics leave the sliders unable to change', (
    tester,
  ) async {
    await pump(tester, enabled: false);
    final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
    expect(sliders, hasLength(2));
    expect(sliders.every((slider) => slider.onChanged == null), isTrue);
  });
}
