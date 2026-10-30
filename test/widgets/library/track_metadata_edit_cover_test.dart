import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/l10n/app_localizations.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/widgets/library/track_metadata_edit_sheet.dart';

import '../../support/library_section_harness.dart';

void main() {
  testWidgets('a track without embedded art says so and offers to pick one', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsProvider.overrideWith(LibrarySectionSettings.new)],
        child: MaterialApp(
          theme: AppTheme.build(Brightness.dark),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: EditMetadataSheet(
              colorScheme: const ColorScheme.dark(),
              initialValues: const {'title': 'Song'},
              filePath: '/music/song.flac',
              durationMs: 60000,
            ),
          ),
        ),
      ),
    );
    // The cover lookup does real file work and a platform call that is absent
    // in tests. Poll in real time until the loading bar goes away.
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
      if (find.byType(LinearProgressIndicator).evaluate().isEmpty) break;
    }
    final l10n = AppLocalizations.of(
      tester.element(find.byType(EditMetadataSheet)),
    );

    expect(find.text(l10n.editMetadataFieldCover), findsOneWidget);
    expect(find.text(l10n.trackCoverNoEmbeddedArt), findsOneWidget);
    expect(find.text(l10n.trackCoverPick), findsOneWidget);
    // Nothing is selected yet, so there is no cover to clear.
    expect(find.byTooltip(l10n.trackCoverClearSelected), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
