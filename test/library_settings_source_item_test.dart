import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/l10n/app_localizations.dart';
import 'package:sistrum/screens/settings/library/library_settings_source_item.dart';
import 'package:sistrum/services/library/database/library_database.dart';

LibrarySourceSettingsItem _item({
  LocalLibrarySource? source,
  required void Function() onScan,
  void Function()? onRemove,
}) => LibrarySourceSettingsItem(
  source:
      source ??
      const LocalLibrarySource(
        id: 'src',
        path: '/storage/Music/Albums',
        displayName: '/storage/Music/Albums',
      ),
  failures: null,
  isScanning: false,
  isFinalizing: false,
  isPaused: false,
  scannedFiles: 0,
  totalFiles: 0,
  progress: 0,
  onEnabledChanged: (_) {},
  onScan: onScan,
  onFullScan: () {},
  onRemove: onRemove ?? () {},
);

Future<void> _pump(WidgetTester tester, Widget item) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SizedBox(width: 390, child: item)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a source shows the last folder name as its title', (
    tester,
  ) async {
    await _pump(tester, _item(onScan: () {}));
    expect(find.text('Albums'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the source opens its actions and Scan runs a scan', (
    tester,
  ) async {
    var scans = 0;
    await _pump(tester, _item(onScan: () => scans++));
    await tester.tap(find.text('Albums'));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );
    await tester.tap(find.text(l10n.libraryScan));
    await tester.pumpAndSettle();
    expect(scans, 1);
  });

  testWidgets('a disabled source cannot be scanned', (tester) async {
    var scans = 0;
    await _pump(
      tester,
      _item(
        source: const LocalLibrarySource(
          id: 'src',
          path: '/storage/Music/Albums',
          displayName: '/storage/Music/Albums',
          enabled: false,
        ),
        onScan: () => scans++,
      ),
    );
    await tester.tap(find.text('Albums'));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );
    await tester.tap(find.text(l10n.libraryScan));
    await tester.pumpAndSettle();
    expect(scans, 0);
  });

  testWidgets('Remove reports the removal for the caller to confirm', (
    tester,
  ) async {
    var removals = 0;
    await _pump(tester, _item(onScan: () {}, onRemove: () => removals++));
    await tester.tap(find.text('Albums'));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );
    await tester.tap(find.text(l10n.libraryRemoveFolder));
    await tester.pumpAndSettle();
    expect(removals, 1);
  });
}
