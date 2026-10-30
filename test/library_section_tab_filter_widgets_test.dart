import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/l10n/app_localizations.dart';
import 'package:sistrum/screens/library/section_tab/library_section_tab.dart';

import 'support/library_section_harness.dart';

void main() {
  setUp(() => installLibrarySongsDatabase(songs: ['Alpha', 'Beta']));

  testWidgets('the Filters button opens the filter sheet with its sections', (
    tester,
  ) async {
    await pumpLibrarySection(tester, section: 'all');
    final l10n = AppLocalizations.of(
      tester.element(find.byType(LibrarySectionTab)),
    );
    await tester.tap(find.text(l10n.libraryFilterTitle));
    await tester.pumpAndSettle();

    final sheet = find.byType(BottomSheet);
    expect(sheet, findsOneWidget);
    expect(
      find.descendant(
        of: sheet,
        matching: find.text(l10n.libraryFilterQuality),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text(l10n.libraryFilterReset)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Reset in the filter sheet keeps it open and the list intact', (
    tester,
  ) async {
    await pumpLibrarySection(tester, section: 'all');
    final l10n = AppLocalizations.of(
      tester.element(find.byType(LibrarySectionTab)),
    );
    await tester.tap(find.text(l10n.libraryFilterTitle));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text(l10n.libraryFilterReset),
      ),
    );
    await tester.pumpAndSettle();
    // Reset only clears the sheet's pending choices; applying is still needed.
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text(l10n.queueTrackCount(2)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
