import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/l10n/app_localizations.dart';
import 'package:sistrum/screens/library/library_section_tab.dart';

import 'support/library_section_harness.dart';

void main() {
  setUp(() => installLibrarySongsDatabase(songs: ['Alpha', 'Beta']));

  testWidgets('each song row exposes a play control with its name', (
    tester,
  ) async {
    await pumpLibrarySection(tester, section: 'all');
    final l10n = AppLocalizations.of(
      tester.element(find.byType(LibrarySectionTab)),
    );
    expect(
      find.byTooltip(l10n.a11yPlayTrackByArtist('Alpha', 'Artist')),
      findsOneWidget,
    );
    expect(
      find.byTooltip(l10n.a11yPlayTrackByArtist('Beta', 'Artist')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
