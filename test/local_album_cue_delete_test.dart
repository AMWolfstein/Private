import 'dart:io';

import 'package:audio_service/audio_service.dart' show MediaItem;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/local_library_provider.dart';
import 'package:sistrum/providers/music_player_provider.dart';
import 'package:sistrum/screens/local_album_screen.dart';
import 'package:sistrum/services/library/library_database.dart';
import 'package:sistrum/theme/sistrum_theme.dart';
import 'package:sistrum/widgets/album_track_tile.dart';
import 'package:sistrum/widgets/destructive_selection_button.dart';
import 'support/pump_until.dart';

class _Local extends LocalLibraryNotifier {
  final removedIds = <String>[];
  final removedPaths = <String>[];

  @override
  LocalLibraryState build() => LocalLibraryState();

  @override
  Future<void> removeItems(Iterable<String> ids) async =>
      removedIds.addAll(ids);

  @override
  Future<void> removePhysicalFiles(Iterable<String> paths) async =>
      removedPaths.addAll(paths);
}

class _Player extends MusicPlayerController {
  @override
  Future<void> setShuffle(bool enabled) async {}

  @override
  Future<void> togglePlayPause(bool isPlaying) async {}
}

void main() {
  testWidgets('album selection delete never removes a CUE sheet file', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final directory = Directory.systemTemp.createTempSync('album_cue_delete_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final cueFile = File('${directory.path}/album.cue')
      ..writeAsStringSync('FILE "album.flac" WAVE');
    final audioFile = File('${directory.path}/album.flac')
      ..writeAsBytesSync([102, 76, 97, 67]);
    final songFile = File('${directory.path}/song.flac')
      ..writeAsBytesSync([102, 76, 97, 67]);

    // A legacy row that points at the sheet but has no `cue+` format: the
    // screen must still keep the shared file on disk.
    final cueRow = LocalLibraryItem(
      id: 'cue-sheet',
      trackName: 'Cue Album',
      artistName: 'Artist',
      albumName: 'Album',
      filePath: cueFile.path,
      format: 'flac',
      trackNumber: 1,
      scannedAt: DateTime(2026),
    );
    final songRow = LocalLibraryItem(
      id: 'song',
      trackName: 'Song',
      artistName: 'Artist',
      albumName: 'Album',
      filePath: songFile.path,
      format: 'flac',
      trackNumber: 2,
      scannedAt: DateTime(2026),
    );
    final library = _Local();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localLibraryProvider.overrideWith(() => library),
          currentMediaItemProvider.overrideWithBuild(
            (ref, notifier) => const Stream<MediaItem?>.empty(),
          ),
          playbackPlayingProvider.overrideWith((ref) => false),
          musicPlayerControllerProvider.overrideWithValue(_Player()),
        ],
        child: MaterialApp(
          theme: SistrumTheme.build(Brightness.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: LocalAlbumScreen(
            albumName: 'Album',
            artistName: 'Artist',
            tracks: [cueRow, songRow],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(LocalAlbumScreen)),
    );

    final tile = find.byWidgetPredicate(
      (widget) => widget is AlbumTrackTile && widget.trackName == 'Cue Album',
    );
    await tester.ensureVisible(tile);
    await tester.longPress(tile);
    await tester.pumpAndSettle();
    expect(find.byType(DestructiveSelectionButton), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(DestructiveSelectionButton),
        matching: find.text(l10n.collectionDeleteCount(1)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.dialogDelete));
    await tester.pumpAndSettle();

    expect(library.removedIds, ['cue-sheet']);
    expect(library.removedPaths, isEmpty);
    expect(cueFile.existsSync(), isTrue);
    expect(audioFile.existsSync(), isTrue);
    expect(songFile.existsSync(), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a partial album delete drops only the deleted row', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final directory = Directory.systemTemp.createTempSync('album_partial_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final firstFile = File('${directory.path}/first.flac')
      ..writeAsBytesSync([102, 76, 97, 67]);
    final secondFile = File('${directory.path}/second.flac')
      ..writeAsBytesSync([102, 76, 97, 67]);
    LocalLibraryItem row(String id, String name, int number, File file) =>
        LocalLibraryItem(
          id: id,
          trackName: name,
          artistName: 'Artist',
          albumName: 'Album',
          filePath: file.path,
          format: 'flac',
          trackNumber: number,
          scannedAt: DateTime(2026),
        );
    final rows = [
      row('first', 'First', 1, firstFile),
      row('second', 'Second', 2, secondFile),
    ];
    final library = _Local();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localLibraryProvider.overrideWith(() => library),
          currentMediaItemProvider.overrideWithBuild(
            (ref, notifier) => const Stream<MediaItem?>.empty(),
          ),
          playbackPlayingProvider.overrideWith((ref) => false),
          musicPlayerControllerProvider.overrideWithValue(_Player()),
        ],
        child: MaterialApp(
          theme: SistrumTheme.build(Brightness.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: LocalAlbumScreen(
            albumName: 'Album',
            artistName: 'Artist',
            tracks: rows,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(LocalAlbumScreen)),
    );

    await tester.longPress(
      find.byWidgetPredicate(
        (widget) => widget is AlbumTrackTile && widget.trackName == 'First',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(DestructiveSelectionButton),
        matching: find.text(l10n.collectionDeleteCount(1)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.dialogDelete));
    await tester.pumpAndSettle();
    // Deleting a real file finishes on the platform event loop, not the fake
    // test clock, so wait for the recorded cleanup before asserting.
    await pumpUntilTrue(
      tester,
      () => library.removedPaths.isNotEmpty,
      description: 'the recorded file cleanup',
    );
    await tester.pumpAndSettle();

    expect(firstFile.existsSync(), isFalse);
    expect(secondFile.existsSync(), isTrue);
    expect(library.removedPaths, [firstFile.path]);
    // The page is still open and only the deleted row disappeared.
    expect(find.byType(LocalAlbumScreen), findsOneWidget);
    expect(find.text('First'), findsNothing);
    expect(find.text('Second'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
