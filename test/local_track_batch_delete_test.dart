import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/l10n/app_localizations.dart';
import 'package:sistrum/models/unified_library_item.dart';
import 'package:sistrum/providers/local_library_provider.dart';
import 'package:sistrum/services/library/library_database_models.dart';
import 'package:sistrum/widgets/library/local_track_batch_actions.dart';
import 'package:sistrum/widgets/primitives/app_alert_dialog.dart';
import 'support/pump_until.dart';

class _Local extends LocalLibraryNotifier {
  final removedPaths = <String>[];
  final removedIds = <String>[];
  @override
  LocalLibraryState build() => LocalLibraryState();
  @override
  Future<void> removePhysicalFiles(Iterable<String> paths) async =>
      removedPaths.addAll(paths);
  @override
  Future<void> removeItems(Iterable<String> ids) async =>
      removedIds.addAll(ids);
}

void main() {
  late Directory directory;
  late _Local library;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('batch_delete_');
    library = _Local();
  });
  tearDown(() => directory.deleteSync(recursive: true));

  UnifiedLibraryItem unified(LocalLibraryItem item) =>
      UnifiedLibraryItem.fromLocalLibrary(item);

  testWidgets('batch delete removes CUE rows without deleting their files', (
    tester,
  ) async {
    final cueFile = File('${directory.path}/album.cue')
      ..writeAsStringSync('FILE "album.flac" WAVE');
    final audioFile = File('${directory.path}/album.flac')
      ..writeAsBytesSync([102, 76, 97, 67]);
    final songFile = File('${directory.path}/song.flac')
      ..writeAsBytesSync([102, 76, 97, 67]);
    final cueItem = LocalLibraryItem(
      id: 'cue-row',
      trackName: 'Part one',
      artistName: 'Artist',
      albumName: 'Album',
      filePath: '${cueFile.path}#track01',
      format: 'cue+flac',
      scannedAt: DateTime(2026),
    );
    final cueSheetItem = LocalLibraryItem(
      id: 'cue-sheet-row',
      trackName: 'Album',
      artistName: 'Artist',
      albumName: 'Album',
      filePath: cueFile.path,
      format: 'flac',
      scannedAt: DateTime(2026),
    );
    final songItem = LocalLibraryItem(
      id: 'song-row',
      trackName: 'Song',
      artistName: 'Artist',
      albumName: 'Album',
      filePath: songFile.path,
      format: 'flac',
      scannedAt: DateTime(2026),
    );
    var completed = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [localLibraryProvider.overrideWith(() => library)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => deleteLibraryTracks(
                  context,
                  ref,
                  [unified(cueItem), unified(cueSheetItem), unified(songItem)],
                  isActive: () => true,
                  onComplete: () => completed = true,
                ),
                child: const Text('Start'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(AppDialogAction, 'Delete'));
    // Give the real file I/O time to finish, flushing fake-zone continuations.
    await pumpUntilTrue(
      tester,
      () => completed,
      description: 'the batch delete to complete',
    );
    await tester.pumpAndSettle();

    expect(completed, isTrue);
    expect(library.removedIds, ['cue-row', 'cue-sheet-row']);
    expect(library.removedPaths, [songFile.path]);
    expect(cueFile.existsSync(), isTrue);
    expect(audioFile.existsSync(), isTrue);
    expect(songFile.existsSync(), isFalse);
  });
}
