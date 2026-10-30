import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/l10n/app_localizations.dart';
import 'package:sistrum/screens/library/library_section_tab.dart';
import 'package:sistrum/widgets/library/library_track_selection_bar.dart';

import 'support/library_section_harness.dart';

void main() {
  setUp(() => installLibrarySongsDatabase(songs: ['Alpha', 'Beta', 'Gamma']));

  AppLocalizations l10nOf(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(LibrarySectionTab)));

  testWidgets('long press selects a song and the bar counts the selection', (
    tester,
  ) async {
    await pumpLibrarySection(tester, section: 'all');
    final l10n = l10nOf(tester);
    expect(find.byType(LibraryTrackSelectionBar), findsNothing);

    await tester.longPress(find.text('Alpha'));
    await tester.pumpAndSettle();
    expect(find.byType(LibraryTrackSelectionBar), findsOneWidget);
    expect(find.text(l10n.selectionSelected(1)), findsOneWidget);

    // Tapping another row adds it to the same selection.
    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();
    expect(find.text(l10n.selectionSelected(2)), findsOneWidget);

    // Tapping a selected row removes it; removing the last one ends the mode.
    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();
    expect(find.text(l10n.selectionSelected(1)), findsOneWidget);
    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();
    expect(find.byType(LibraryTrackSelectionBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('select all selects every song, and deselect clears them', (
    tester,
  ) async {
    await pumpLibrarySection(tester, section: 'all');
    final l10n = l10nOf(tester);
    await tester.longPress(find.text('Alpha'));
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.actionSelectAll));
    await tester.pumpAndSettle();
    expect(find.text(l10n.selectionSelected(3)), findsOneWidget);

    await tester.tap(find.text(l10n.actionDeselect));
    await tester.pumpAndSettle();
    expect(find.byType(LibraryTrackSelectionBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('playlist selection bar counts selected playlists and closes', (
    tester,
  ) async {
    await pumpLibrarySection(
      tester,
      section: 'playlists',
      collections: playlistsNamed(['One', 'Two']),
    );
    final l10n = l10nOf(tester);

    await tester.longPress(find.text('One'));
    await tester.pumpAndSettle();
    expect(find.text(l10n.selectionDeletePlaylistsCount(1)), findsOneWidget);

    await tester.tap(
      find.byTooltip(
        MaterialLocalizations.of(
          tester.element(find.byType(LibrarySectionTab)),
        ).closeButtonTooltip,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.selectionDeletePlaylistsCount(1)), findsNothing);
    expect(find.text('One'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
