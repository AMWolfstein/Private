import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/l10n/app_localizations.dart';
import 'package:sistrum/screens/settings/library_settings_scan_widgets.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  // A running scan animates indefinitely, so pump fixed frames instead.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(Scaffold).first));

void main() {
  testWidgets('the hero card reports an active scan', (tester) async {
    await _pump(
      tester,
      const LibraryHeroCard(
        itemCount: 12,
        isScanning: true,
        scanIsFinalizing: false,
        scanIsPaused: false,
        scanProgress: 0.5,
        scanTotalFiles: 10,
        scannedFiles: 5,
      ),
    );
    expect(find.text(_l10n(tester).libraryScanning), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the hero card reports a paused scan', (tester) async {
    await _pump(
      tester,
      const LibraryHeroCard(
        itemCount: 12,
        isScanning: true,
        scanIsFinalizing: false,
        scanIsPaused: true,
        scanProgress: 0.5,
        scanTotalFiles: 10,
        scannedFiles: 5,
      ),
    );
    expect(find.text(_l10n(tester).libraryScanPaused), findsOneWidget);
  });

  testWidgets('a running scan offers pause and cancel', (tester) async {
    var pauses = 0;
    var cancels = 0;
    await _pump(
      tester,
      ScanProgressTile(
        isFinalizing: false,
        isPaused: false,
        progress: 0.2,
        currentFile: '/music/a.flac',
        scannedFiles: 2,
        totalFiles: 10,
        onPause: () => pauses++,
        onResume: () {},
        onCancel: () => cancels++,
      ),
    );
    final l10n = _l10n(tester);
    await tester.tap(find.text(l10n.actionPause));
    await tester.pump();
    await tester.tap(find.text(l10n.actionCancel));
    await tester.pump();
    expect(pauses, 1);
    expect(cancels, 1);
  });

  testWidgets('a paused scan offers resume', (tester) async {
    var resumes = 0;
    await _pump(
      tester,
      ScanProgressTile(
        isFinalizing: false,
        isPaused: true,
        progress: 0.2,
        scannedFiles: 2,
        totalFiles: 10,
        onPause: () {},
        onResume: () => resumes++,
        onCancel: () {},
      ),
    );
    await tester.tap(find.text(_l10n(tester).actionResume));
    await tester.pump();
    expect(resumes, 1);
  });

  testWidgets('the selected auto-scan option shows a check and reports taps', (
    tester,
  ) async {
    var taps = 0;
    await _pump(
      tester,
      AutoScanOption(
        icon: Icons.schedule,
        title: 'Every hour',
        selected: true,
        onTap: () => taps++,
      ),
    );
    expect(find.text('Every hour'), findsOneWidget);
    expect(find.byIcon(Icons.schedule), findsOneWidget);
    await tester.tap(find.text('Every hour'));
    await tester.pump();
    expect(taps, 1);
  });
}
