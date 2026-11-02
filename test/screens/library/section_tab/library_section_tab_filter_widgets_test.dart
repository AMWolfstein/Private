import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/providers/library/library_sort_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/l10n/app_localizations.dart';
import 'package:sistrum/screens/library/section_tab/library_section_tab.dart';

import '../../../support/library_section_harness.dart';

void main() {
  setUp(() => installLibrarySongsDatabase(songs: ['Alpha', 'Beta']));

  testWidgets('Songs exposes header Sort without retired filter controls', (
    tester,
  ) async {
    await pumpLibrarySection(tester, section: 'all');
    final l10n = AppLocalizations.of(
      tester.element(find.byType(LibrarySectionTab)),
    );
    expect(find.text('Filters'), findsNothing);
    expect(find.textContaining('2026'), findsNothing);
    await tester.tap(find.byTooltip(l10n.librarySortTitle));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    for (final label in [
      'Quality',
      'Format',
      'Metadata',
      'Incomplete albums',
      'Album completeness unknown',
    ]) {
      expect(find.text(label), findsNothing);
    }
    expect(find.text(l10n.libraryFilterSortSizeLargest), findsOneWidget);
    expect(find.text(l10n.searchSortTitleAZ), findsOneWidget);
    await tester.tap(find.text(l10n.searchSortTitleAZ));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text(l10n.queueTrackCount(2)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Songs letter index reaches a song beyond the initial 300 rows', (
    tester,
  ) async {
    installLibrarySongsDatabase(
      songs: List.generate(
        650,
        (i) => i < 600
            ? 'Alpha ${i.toString().padLeft(3, '0')}'
            : 'Zulu ${i.toString().padLeft(3, '0')}',
      ),
      paginate: true,
    );
    await pumpLibrarySection(tester, section: 'all');
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LibrarySectionTab)),
    );
    container.read(librarySortProvider.notifier).select('a-z');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Z'));
    await tester.pumpAndSettle();
    expect(find.text('Zulu 600').hitTestable(), findsOneWidget);
    expect(find.textContaining('2026'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });
}
