import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/l10n/app_localizations.dart';
import 'package:sistrum/screens/library/section_tab/library_section_tab.dart';
import 'package:sistrum/widgets/primitives/app_alert_dialog.dart';

import '../../../support/library_section_harness.dart';

void main() {
  setUp(() => installLibrarySongsDatabase(songs: const []));

  testWidgets(
    'create playlist refuses a blank name and keeps the dialog open',
    (tester) async {
      await pumpLibrarySection(tester, section: 'playlists');
      final l10n = AppLocalizations.of(
        tester.element(find.byType(LibrarySectionTab)),
      );
      await tester.tap(find.text(l10n.collectionCreatePlaylist));
      await tester.pumpAndSettle();
      expect(find.byType(AppAlertDialog), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), '   ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text(l10n.collectionPlaylistNameRequired), findsOneWidget);
      expect(find.byType(AppAlertDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancelling create playlist closes the dialog', (tester) async {
    await pumpLibrarySection(tester, section: 'playlists');
    final l10n = AppLocalizations.of(
      tester.element(find.byType(LibrarySectionTab)),
    );
    await tester.tap(find.text(l10n.collectionCreatePlaylist));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.dialogCancel));
    await tester.pumpAndSettle();
    expect(find.byType(AppAlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
