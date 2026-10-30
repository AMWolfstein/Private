import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/l10n/app_localizations.dart';
import 'package:sistrum/screens/library/section_tab/library_section_tab.dart';
import 'package:sistrum/widgets/primitives/app_alert_dialog.dart';

import 'support/library_section_harness.dart';

void main() {
  setUp(() => installLibrarySongsDatabase(songs: ['Alpha', 'Beta']));

  testWidgets('ReplayGain on a selection asks first and cancel keeps it', (
    tester,
  ) async {
    await pumpLibrarySection(tester, section: 'all');
    final l10n = AppLocalizations.of(
      tester.element(find.byType(LibrarySectionTab)),
    );
    await tester.longPress(find.text('Alpha'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.selectionReplayGainCount(2)));
    await tester.pumpAndSettle();
    expect(find.byType(AppAlertDialog), findsOneWidget);

    await tester.tap(find.text(l10n.dialogCancel));
    // The selection overlay returns after the dialog's exit animation.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.byType(AppAlertDialog), findsNothing);
    expect(find.text(l10n.selectionReplayGainCount(2)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
