import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/l10n/app_localizations.dart';
import 'package:sistrum/screens/library/library_section_tab.dart';
import 'package:sistrum/widgets/primitives/app_alert_dialog.dart';

import 'support/library_section_harness.dart';

void main() {
  testWidgets('an empty Albums section explains itself and offers Home', (
    tester,
  ) async {
    installLibrarySongsDatabase(songs: const []);
    await pumpLibrarySection(tester, section: 'albums');
    final l10n = AppLocalizations.of(
      tester.element(find.byType(LibrarySectionTab)),
    );
    expect(find.text(l10n.queueEmptyAlbums), findsOneWidget);
    expect(find.text(l10n.queueEmptyAlbumsSubtitle), findsOneWidget);
    expect(find.text(l10n.navHome), findsOneWidget);
    // Albums are not created by hand, so there is no create action here.
    expect(find.text(l10n.collectionCreatePlaylist), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty Playlists section opens the create dialog on tap', (
    tester,
  ) async {
    installLibrarySongsDatabase(songs: const []);
    await pumpLibrarySection(tester, section: 'playlists');
    final l10n = AppLocalizations.of(
      tester.element(find.byType(LibrarySectionTab)),
    );
    expect(find.text(l10n.collectionNoPlaylistsYet), findsOneWidget);
    expect(find.text(l10n.navHome), findsNothing);
    await tester.tap(find.text(l10n.collectionCreatePlaylist));
    await tester.pumpAndSettle();
    expect(find.byType(AppAlertDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
