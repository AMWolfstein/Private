import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/l10n/app_localizations.dart';
import 'package:sistrum/screens/library/collections/library_collection_tracks_screen.dart';
import 'package:sistrum/screens/library/section_tab/library_section_tab.dart';

import 'support/library_section_harness.dart';

void main() {
  setUp(() => installLibrarySongsDatabase(songs: const []));

  testWidgets('a playlist row is a list tile with its track count', (
    tester,
  ) async {
    await pumpLibrarySection(
      tester,
      section: 'playlists',
      collections: playlistsNamed(['Road trip']),
    );
    final l10n = AppLocalizations.of(
      tester.element(find.byType(LibrarySectionTab)),
    );
    expect(find.byKey(const ValueKey('plrow_road trip')), findsOneWidget);
    expect(find.text(l10n.collectionPlaylistTracks(0)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a playlist row opens its track list', (tester) async {
    await pumpLibrarySection(
      tester,
      section: 'playlists',
      collections: playlistsNamed(['Road trip']),
    );
    await tester.tap(find.text('Road trip'));
    await tester.pumpAndSettle();
    expect(find.byType(LibraryCollectionTracksScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
