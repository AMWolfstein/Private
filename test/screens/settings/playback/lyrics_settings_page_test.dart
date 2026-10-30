import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/l10n/app_localizations.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/screens/settings/playback/lyrics_settings_page.dart';
import 'package:sistrum/widgets/primitives/app_switch.dart';

import '../../../support/library_section_harness.dart';

void main() {
  testWidgets('the lyrics page offers text size and keep-screen-on', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsProvider.overrideWith(LibrarySectionSettings.new)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const LyricsSettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(LyricsSettingsPage)),
    );

    expect(find.text(l10n.lyricsTextSize), findsOneWidget);
    expect(find.text(l10n.lyricsKeepScreenOn), findsOneWidget);
    expect(find.byType(AppSwitch), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
