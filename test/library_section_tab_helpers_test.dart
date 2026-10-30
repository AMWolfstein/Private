import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/l10n/app_localizations.dart';
import 'package:sistrum/screens/library/section_tab/library_section_tab.dart';

import 'support/library_section_harness.dart';

void main() {
  testWidgets('the count header reports the browse counts for the songs', (
    tester,
  ) async {
    installLibrarySongsDatabase(songs: ['Alpha', 'Beta', 'Gamma']);
    await pumpLibrarySection(tester, section: 'all');
    final l10n = AppLocalizations.of(
      tester.element(find.byType(LibrarySectionTab)),
    );
    expect(find.text(l10n.queueTrackCount(3)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
