import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/l10n/app_localizations.dart';
import 'package:sistrum/providers/library_browse_provider.dart';
import 'package:sistrum/screens/home/home_tab.dart';
import 'package:sistrum/widgets/status/error_card.dart';

import '../../support/home_tab_harness.dart';

void main() {
  testWidgets('an empty library explains how to add music', (tester) async {
    await pumpHome(
      tester,
      loader: (request) async => const LibraryBrowsePage([]),
    );
    final l10n = AppLocalizations.of(tester.element(find.byType(HomeTab)));
    expect(find.text(l10n.libraryEmptyCollection), findsOneWidget);
    // No library folder is set up, so the hint points at folder selection.
    expect(find.text(l10n.homeChooseLibraryFolder), findsOneWidget);
    expect(find.text(l10n.settingsLocalLibrary), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed shelf shows a retry card that reloads it', (
    tester,
  ) async {
    var attempts = 0;
    await pumpHome(
      tester,
      loader: (request) async {
        attempts++;
        throw StateError('database unavailable');
      },
    );
    final l10n = AppLocalizations.of(tester.element(find.byType(HomeTab)));
    expect(find.text(l10n.libraryLoadFailed), findsWidgets);
    final before = attempts;
    await tester.tap(find.text(l10n.dialogRetry).first);
    await tester.pumpAndSettle();
    expect(attempts, greaterThan(before));
    expect(find.byType(ErrorCard), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
