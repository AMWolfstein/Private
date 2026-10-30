import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/models/local_library_item.dart';
import 'package:sistrum/models/unified_library_item.dart';
import 'package:sistrum/widgets/library/batch_track_actions.dart';
import 'package:sistrum/theme/app_theme.dart';
import 'package:sistrum/utils/logger.dart';
import 'package:sistrum/widgets/primitives/app_alert_dialog.dart';
import 'package:sistrum/widgets/selection/batch_progress_dialog.dart';
import 'package:sistrum/services/library/library_database.dart';

UnifiedLibraryItem _item(String path) => UnifiedLibraryItem(
  LocalLibraryItem(
    id: path,
    trackName: path,
    artistName: 'Artist',
    albumName: 'Album',
    filePath: path,
    scannedAt: DateTime(2026),
  ),
);

void main() {
  const channel = MethodChannel('com.amwolfstein.sistrum/backend');
  late BuildContext pageContext;
  late GlobalKey<NavigatorState> navigator;

  Future<void> mount(WidgetTester tester) async {
    navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          navigatorKey: navigator,
          theme: AppTheme.build(Brightness.dark),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              pageContext = context;
              return const Scaffold(body: Text('Songs'));
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> confirmRemoval(WidgetTester tester) async {
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(pageContext);
    await tester.tap(
      find.widgetWithText(AppDialogAction, l10n.trackRemoveReplayGain),
    );
    // The pending write and progress indicator deliberately do not settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('CUE-only batches return unchanged without confirmation', (
    tester,
  ) async {
    await mount(tester);
    var opened = false;
    var exited = false;
    for (final remove in [false, true]) {
      final changed = await runBatchReplayGain(
        pageContext,
        [
          _item('/music/album.cue#track01'),
          _item('content://music/document/album#track02'),
        ],
        remove: remove,
        onConfirmOpen: () => opened = true,
        database: LibraryDatabase.instance,
        onExitSelectionMode: () => exited = true,
      );
      expect(changed, isFalse);
    }
    await tester.pumpAndSettle();
    expect(opened, isFalse);
    expect(exited, isFalse);
    expect(find.byType(AppAlertDialog), findsNothing);
  });

  testWidgets('mixed batch counts only physical files and logs failed writes', (
    tester,
  ) async {
    await mount(tester);
    final calls = <String>[];
    final firstWrite = Completer<Map<String, Object?>>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'editFileMetadata') {
        calls.add((call.arguments as Map)['file_path'] as String);
        if (calls.length == 1) return firstWrite.future;
        return {'success': false};
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final pending = runBatchReplayGain(
      pageContext,
      [
        _item('/music/album.cue#track01'),
        _item('content://music/document/album#track02'),
        _item('physical.flac'),
        // A real filename containing #trackNN is not a CUE virtual row.
        _item('physical#track1.flac'),
      ],
      remove: true,
      database: LibraryDatabase.instance,
      onExitSelectionMode: () {},
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        AppLocalizations.of(pageContext).replayGainRemoveConfirmMessage(2),
      ),
      findsOneWidget,
    );
    await confirmRemoval(tester);
    expect(find.text('1 / 2'), findsOneWidget);
    expect(calls, ['physical.flac']);
    firstWrite.complete({'success': false});
    await tester.pump();
    await tester.pumpAndSettle();
    expect(await pending, isFalse);
    expect(calls, ['physical.flac', 'physical#track1.flac']);
    expect(
      find.text(
        AppLocalizations.of(pageContext).replayGainRemoveBatchSuccess(0, 2),
      ),
      findsOneWidget,
    );
    expect(
      LogBuffer().entries
          .where((entry) => entry.tag == 'BatchActions')
          .map((entry) => entry.message),
      contains(contains('ReplayGain did not change physical.flac')),
    );
  });

  testWidgets(
    'Back cancels after current write and completion preserves Settings',
    (tester) async {
      await mount(tester);
      final write = Completer<Map<String, Object?>>();
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'editFileMetadata') {
          calls.add((call.arguments as Map)['file_path'] as String);
          return write.future;
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final pending = runBatchReplayGain(
        pageContext,
        [_item('first.flac'), _item('second.flac')],
        remove: true,
        database: LibraryDatabase.instance,
        onExitSelectionMode: () {},
      );
      await confirmRemoval(tester);
      expect(calls, ['first.flac']);
      expect(find.byType(BatchProgressDialog), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(BatchProgressDialog), findsNothing);
      navigator.currentState!.push<void>(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('Settings')),
        ),
      );
      await tester.pumpAndSettle();
      write.complete({'success': false});
      await tester.pump();
      await tester.pumpAndSettle();
      expect(await pending, isFalse);
      expect(calls, ['first.flac']);
      expect(find.text('Settings'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
