import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/models/settings.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/providers/local_library_provider.dart';
import 'package:sistrum/providers/music_player_provider.dart';
import 'package:sistrum/screens/local_artist_screen.dart';
import 'package:sistrum/screens/track_metadata_edit_sheet.dart';
import 'package:sistrum/services/library_database.dart';
import 'package:sistrum/theme/sistrum_theme.dart';
import 'package:sistrum/widgets/local_song_menu.dart';
import 'package:sistrum/widgets/local_song_row.dart';
import 'package:sistrum/widgets/sistrum_context_menu.dart';

class _Settings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings();
}

class _Local extends LocalLibraryNotifier {
  final removedItemIds = <String>[];
  final removedPaths = <String>[];
  @override
  LocalLibraryState build() => LocalLibraryState();
  @override
  Future<void> removePhysicalFiles(Iterable<String> paths) async =>
      removedPaths.addAll(paths);
  @override
  Future<void> removeItem(String id) async => removedItemIds.add(id);
  @override
  Future<void> removeItems(Iterable<String> ids) async =>
      removedItemIds.addAll(ids);
}

class _Player extends MusicPlayerController {
  final nextIds = <String>[], queued = <String>[];
  @override
  Future<void> playNextLocal(LocalLibraryItem item) async =>
      nextIds.add(item.id);
  @override
  Future<void> addToQueueLocal(LocalLibraryItem item) async =>
      queued.add(item.id);
}

void main() {
  late Directory directory;
  late LocalLibraryItem song;
  late _Local library;
  late _Player player;
  Future<bool>? pendingAction;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    directory = Directory.systemTemp.createTempSync('song-actions-');
    final file = File('${directory.path}/song.flac')
      ..writeAsBytesSync([102, 76, 97, 67]);
    song = LocalLibraryItem(
      id: 'song',
      trackName: 'Song',
      artistName: 'Artist',
      albumName: 'Album',
      filePath: file.path,
      scannedAt: DateTime(2026),
    );
    library = _Local();
    player = _Player();
  });
  tearDown(() => directory.deleteSync(recursive: true));

  Future<void> mount(
    WidgetTester tester, {
    double top = 160,
    double height = 844,
    TextDirection direction = TextDirection.ltr,
    LocalLibraryItem? item,
    List<Future<bool>>? actions,
  }) async {
    tester.view.physicalSize = Size(390, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(_Settings.new),
          localLibraryProvider.overrideWith(() => library),
          musicPlayerControllerProvider.overrideWithValue(player),
        ],
        child: MaterialApp(
          theme: SistrumTheme.build(Brightness.dark),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Directionality(
            textDirection: direction,
            child: Scaffold(
              body: Stack(
                children: [
                  Positioned(
                    top: top,
                    left: 0,
                    right: 0,
                    child: Consumer(
                      builder: (context, ref, _) => LocalSongRow(
                        title: 'Song',
                        artist: 'Artist',
                        onPlay: () {},
                        onMenu: (anchor) {
                          pendingAction = showLocalSongMenu(
                            context,
                            ref,
                            item ?? song,
                            anchor: anchor,
                          );
                          actions?.add(pendingAction!);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Runs short real delays and frame pumps until [condition] holds.
  ///
  /// Menu actions await platform channels and real file system calls, whose
  /// continuations only run on the real event loop, so a plain pump loop never
  /// observes them.
  Future<void> pumpUntilCondition(
    WidgetTester tester,
    bool Function() condition, {
    String description = 'condition',
  }) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 10));
      if (condition()) return;
    }
    fail('Timed out waiting for $description');
  }

  /// Pumps until [finder] matches instead of guessing a fixed delay.
  Future<void> pumpUntil(WidgetTester tester, Finder finder) =>
      pumpUntilCondition(
        tester,
        () => finder.evaluate().isNotEmpty,
        description: '$finder',
      );

  /// Waits for a menu action that may need real async work and frames.
  Future<void> runAction(WidgetTester tester, Future<void> action) async {
    var done = false;
    Object? error;
    unawaited(
      action
          .then<void>(
            (_) {},
            onError: (Object e) {
              error = e;
            },
          )
          .whenComplete(() => done = true),
    );
    await pumpUntilCondition(
      tester,
      () => done,
      description: 'menu action to finish',
    );
    if (error != null) throw error!;
    await tester.pumpAndSettle();
  }

  /// Opens the song menu and lets its route settle.
  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pumpAndSettle();
  }

  for (final top in [100.0, 650.0]) {
    for (final direction in TextDirection.values) {
      testWidgets('song popover follows tapped button at $top ($direction)', (
        tester,
      ) async {
        await mount(tester, top: top, direction: direction);
        final button = tester.getRect(
          find.ancestor(
            of: find.byIcon(Icons.more_horiz),
            matching: find.byType(IconButton),
          ),
        );
        await openMenu(tester);
        final panel = tester.getRect(find.byType(SistrumContextMenu));
        expect(panel.left, greaterThanOrEqualTo(16));
        expect(panel.right, lessThanOrEqualTo(374));
        if (top < 400) {
          expect(panel.top, closeTo(button.bottom + 8, 1));
        } else {
          expect(panel.bottom, closeTo(button.top - 8, 1));
        }
        await tester.ensureVisible(find.text('Remove from device'));
        await tester.pumpAndSettle();
        expect(find.text('Remove from device').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('short viewport scrolls the menu instead of overflowing', (
    tester,
  ) async {
    await mount(tester, top: 210, height: 420);
    final button = tester.getRect(
      find.ancestor(
        of: find.byIcon(Icons.more_horiz),
        matching: find.byType(IconButton),
      ),
    );
    await openMenu(tester);
    final panel = tester.getRect(find.byType(SistrumContextMenu));
    expect(panel.height, lessThanOrEqualTo(button.top - 24 + 0.5));
    expect(find.text('Remove from device').hitTestable(), findsNothing);
    await tester.ensureVisible(find.text('Remove from device'));
    await tester.pumpAndSettle();
    expect(find.text('Remove from device').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('restored queue actions use the selected local song', (
    tester,
  ) async {
    await mount(tester);
    for (final label in ['Play next', 'Add to queue']) {
      await openMenu(tester);
      await tester.tap(find.text(label));
      await runAction(tester, pendingAction!);
      await tester.pumpAndSettle();
    }
    expect(player.nextIds, ['song']);
    expect(player.queued, ['song']);
  });

  testWidgets('copy path and cancel/confirm file deletion', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await mount(tester);
    await openMenu(tester);
    await tester.tap(find.text('Copy file path'));
    await runAction(tester, pendingAction!);
    await tester.pumpAndSettle();
    expect(copied, song.filePath);
    for (final confirm in [false, true]) {
      await openMenu(tester);
      await tester.ensureVisible(find.text('Remove from device'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from device'));
      await pumpUntil(tester, find.text(confirm ? 'Delete' : 'Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(confirm ? 'Delete' : 'Cancel'));
      await runAction(tester, pendingAction!);
      await tester.pumpAndSettle();
      expect(File(song.filePath).existsSync(), !confirm);
    }
    expect(library.removedPaths, [song.filePath]);
    expect(library.removedItemIds, isEmpty);
  });
  testWidgets(
    'CUE split can be cancelled and deleting its row preserves the backing sheet',
    (tester) async {
      const channel = MethodChannel('com.amwolfstein.sistrum/backend');
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call.method);
        if (call.method == 'parseCueSheet') {
          return {
            'audio_path': '/audio.flac',
            'album': 'Album',
            'artist': 'Artist',
            'tracks': [
              {'number': 1, 'title': 'Part one', 'start_sec': 0, 'end_sec': 30},
            ],
          };
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final file = File('${directory.path}/album.cue')
        ..writeAsStringSync('FILE "album.flac" WAVE');
      final audio = File('${directory.path}/album.flac')
        ..writeAsBytesSync([102, 76, 97, 67]);
      final cue = LocalLibraryItem(
        id: 'cue-row',
        trackName: 'Part one',
        artistName: 'Artist',
        albumName: 'Album',
        filePath: '${file.path}#track01',
        format: 'cue+flac',
        scannedAt: DateTime(2026),
      );
      await mount(tester, item: cue);
      await openMenu(tester);
      final l10n = AppLocalizations.of(
        tester.element(find.byType(LocalSongRow)),
      );
      expect(find.text(l10n.trackReplayGain), findsNothing);
      expect(find.text(l10n.audioAnalysisTitle), findsNothing);
      expect(find.text(l10n.trackEditMetadata), findsNothing);
      expect(find.text(l10n.trackCopyFilePath), findsNothing);
      await tester.ensureVisible(find.text(l10n.cueSplitTitle));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.cueSplitTitle));
      await pumpUntil(tester, find.text(l10n.cueSplitConfirmTitle));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.dialogCancel));
      await runAction(tester, pendingAction!);
      await tester.pumpAndSettle();
      expect(calls, ['parseCueSheet']);
      await openMenu(tester);
      await tester.ensureVisible(find.text(l10n.trackRemoveFromDevice));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.trackRemoveFromDevice));
      await pumpUntil(tester, find.text(l10n.dialogDelete));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.dialogDelete));
      await runAction(tester, pendingAction!);
      await tester.pumpAndSettle();
      expect(library.removedItemIds, ['cue-row']);
      expect(library.removedPaths, isEmpty);
      expect(file.existsSync(), isTrue);
      expect(audio.existsSync(), isTrue);
    },
  );

  testWidgets('a CUE sheet row is removed without deleting the sheet', (
    tester,
  ) async {
    final file = File('${directory.path}/album.cue')
      ..writeAsStringSync('FILE "album.flac" WAVE');
    final audio = File('${directory.path}/album.flac')
      ..writeAsBytesSync([102, 76, 97, 67]);
    final cue = LocalLibraryItem(
      id: 'cue-sheet-row',
      trackName: 'Album',
      artistName: 'Artist',
      albumName: 'Album',
      filePath: file.path,
      format: 'cue+flac',
      scannedAt: DateTime(2026),
    );
    await mount(tester, item: cue);
    await openMenu(tester);
    final l10n = AppLocalizations.of(tester.element(find.byType(LocalSongRow)));
    await tester.ensureVisible(find.text(l10n.trackRemoveFromDevice));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.trackRemoveFromDevice));
    await pumpUntil(tester, find.text(l10n.dialogDelete));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.dialogDelete));
    await runAction(tester, pendingAction!);
    await tester.pumpAndSettle();
    expect(library.removedItemIds, ['cue-sheet-row']);
    expect(library.removedPaths, isEmpty);
    expect(file.existsSync(), isTrue);
    expect(audio.existsSync(), isTrue);
  });

  testWidgets('a second Split tap does not start another job', (tester) async {
    const channel = MethodChannel('com.amwolfstein.sistrum/backend');
    final parseCalls = <String>[];
    final gate = Completer<Map<String, dynamic>>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'parseCueSheet') {
        parseCalls.add((call.arguments as Map)['cue_path'] as String);
        return gate.future;
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final file = File('${directory.path}/album.cue')
      ..writeAsStringSync('FILE "album.flac" WAVE');
    final cue = LocalLibraryItem(
      id: 'cue-row',
      trackName: 'Part one',
      artistName: 'Artist',
      albumName: 'Album',
      filePath: '${file.path}#track01',
      format: 'cue+flac',
      scannedAt: DateTime(2026),
    );
    final second = LocalLibraryItem(
      id: 'cue-row-2',
      trackName: 'Part two',
      artistName: 'Artist',
      albumName: 'Album',
      filePath: '${file.path}#track02',
      format: 'cue+flac',
      scannedAt: DateTime(2026),
    );
    final actions = <Future<bool>>[];
    await mount(tester, item: cue, actions: actions);
    final l10n = AppLocalizations.of(tester.element(find.byType(LocalSongRow)));

    Future<void> tapSplit(LocalLibraryItem item) async {
      await mount(tester, item: item, actions: actions);
      await openMenu(tester);
      await tester.ensureVisible(find.text(l10n.cueSplitTitle));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.cueSplitTitle));
      // The menu action reaches the platform channel on the real event loop.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    await tapSplit(cue);
    expect(parseCalls, [file.path]);

    // A sibling row of the same sheet joins the in-flight job instead of
    // starting a second split of the same backing file.
    await tapSplit(second);
    expect(parseCalls, [file.path]);
    expect(actions, hasLength(2));

    gate.complete({'error': 'unreadable'});
    await runAction(tester, Future.wait(actions));
    await tester.pumpAndSettle();

    // The finished job releases the gate, so a later tap starts a new split.
    await tapSplit(cue);
    await pumpUntilCondition(
      tester,
      () => parseCalls.length == 2,
      description: 'second parseCueSheet call',
    );
    expect(parseCalls, hasLength(2));
    await runAction(tester, Future.wait(actions));
    await tester.pumpAndSettle();
    expect(find.text(l10n.cueSplitFailed), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('share and metadata actions run from the song menu', (
    tester,
  ) async {
    const channel = MethodChannel('com.amwolfstein.sistrum/backend');
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call.method);
      switch (call.method) {
        case 'safExists':
          return true;
        case 'shareContentUri':
          return true;
        case 'readFileMetadata':
          return {'title': 'Remote Song', 'artist': 'Artist'};
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final remote = LocalLibraryItem(
      id: 'remote',
      trackName: 'Song',
      artistName: 'Artist',
      albumName: 'Album',
      filePath: 'content://library/song.flac',
      scannedAt: DateTime(2026),
    );
    await mount(tester, item: remote);
    final l10n = AppLocalizations.of(tester.element(find.byType(LocalSongRow)));

    await openMenu(tester);
    await tester.tap(find.text(l10n.trackMetadataShare));
    await runAction(tester, pendingAction!);
    await tester.pumpAndSettle();
    expect(calls, contains('shareContentUri'));

    await openMenu(tester);
    await tester.ensureVisible(find.text(l10n.trackEditMetadata));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.trackEditMetadata));
    await pumpUntil(tester, find.byType(EditMetadataSheet));
    // The sheet focuses a text field, whose blinking cursor never settles.
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Remote Song'), findsOneWidget);
    Navigator.of(tester.element(find.byType(EditMetadataSheet))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await runAction(tester, pendingAction!);
    expect(calls, contains('readFileMetadata'));
  });

  testWidgets('ReplayGain cancel reports no change', (tester) async {
    await mount(tester);
    final l10n = AppLocalizations.of(tester.element(find.byType(LocalSongRow)));
    for (final label in [l10n.trackReplayGain, l10n.trackRemoveReplayGain]) {
      await openMenu(tester);
      await tester.ensureVisible(find.text(label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await pumpUntil(tester, find.text(l10n.dialogCancel));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.dialogCancel));
      await runAction(tester, pendingAction!);
      await tester.pumpAndSettle();
      expect(await pendingAction!, isFalse);
    }
  });

  testWidgets('album and artist actions navigate from the song menu', (
    tester,
  ) async {
    await mount(tester);
    final l10n = AppLocalizations.of(tester.element(find.byType(LocalSongRow)));
    await openMenu(tester);
    await tester.tap(find.text(l10n.homeGoToAlbum));
    await runAction(tester, pendingAction!);
    await tester.pumpAndSettle();
    expect(
      find.text(l10n.clickableInformationUnavailable(l10n.trackAlbum)),
      findsOneWidget,
    );

    await openMenu(tester);
    await tester.tap(find.text(l10n.sistrumGoToArtist));
    await pumpUntil(tester, find.byType(LocalArtistScreen));
    expect(find.byType(LocalArtistScreen), findsOneWidget);
  });

  testWidgets('go to artist splits a featured credit', (tester) async {
    await mount(
      tester,
      item: LocalLibraryItem(
        id: 'song',
        trackName: 'Song',
        artistName: 'Artist feat. Guest',
        albumName: 'Album',
        filePath: song.filePath,
        scannedAt: DateTime(2026),
      ),
    );
    final l10n = AppLocalizations.of(tester.element(find.byType(LocalSongRow)));
    await openMenu(tester);
    await tester.ensureVisible(find.text(l10n.sistrumGoToArtist));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.sistrumGoToArtist));
    await pumpUntil(tester, find.byType(LocalArtistScreen));
    // A featured credit navigates to the primary artist, not the whole credit.
    expect(
      tester
          .widget<LocalArtistScreen>(find.byType(LocalArtistScreen))
          .artistName,
      'Artist',
    );
  });

  testWidgets('the metadata sheet cannot be dismissed while saving', (
    tester,
  ) async {
    const channel = MethodChannel('com.amwolfstein.sistrum/backend');
    final saving = Completer<Map<String, dynamic>>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      switch (call.method) {
        case 'editFileMetadata':
          return saving.future;
        case 'acquireMediaDirectory' || 'releaseMediaDirectory':
          return '';
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await mount(tester);
    final l10n = AppLocalizations.of(tester.element(find.byType(LocalSongRow)));
    await openMenu(tester);
    await tester.ensureVisible(find.text(l10n.trackEditMetadata));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.trackEditMetadata));
    await pumpUntil(tester, find.byType(EditMetadataSheet));
    await tester.pump(const Duration(milliseconds: 300));
    // The route's own drag must not bypass the PopScope guard.
    expect(
      tester.widget<BottomSheet>(find.byType(BottomSheet)).enableDrag,
      isFalse,
    );

    await tester.tap(find.text(l10n.dialogSave));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(EditMetadataSheet), findsOneWidget);

    saving.complete({'method': 'native'});
    await tester.pumpAndSettle();
    expect(find.byType(EditMetadataSheet), findsNothing);
    await runAction(tester, pendingAction!);
    expect(await pendingAction!, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('CUE split confirm explains the destination picker', (
    tester,
  ) async {
    const channel = MethodChannel('com.amwolfstein.sistrum/backend');
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call.method);
      if (call.method == 'parseCueSheet') {
        return {
          'audio_path': '/audio.flac',
          'album': 'Album',
          'artist': 'Artist',
          'tracks': [
            {'number': 1, 'title': 'Part one', 'start_sec': 0, 'end_sec': 30},
          ],
        };
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final file = File('${directory.path}/album.cue')
      ..writeAsStringSync('FILE "album.flac" WAVE');
    final cue = LocalLibraryItem(
      id: 'cue-row',
      trackName: 'Part one',
      artistName: 'Artist',
      albumName: 'Album',
      filePath: '${file.path}#track01',
      format: 'cue+flac',
      scannedAt: DateTime(2026),
    );
    await mount(tester, item: cue);
    final l10n = AppLocalizations.of(tester.element(find.byType(LocalSongRow)));
    await openMenu(tester);
    await tester.ensureVisible(find.text(l10n.cueSplitTitle));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.cueSplitTitle));
    await pumpUntil(tester, find.text(l10n.cueSplitConfirmTitle));
    await tester.pumpAndSettle();
    expect(find.text(l10n.cueSplitConfirmMessage('Album', 1)), findsOneWidget);
    await tester.tap(find.text(l10n.cueSplitButton));
    await runAction(tester, pendingAction!);
    await tester.pumpAndSettle();
    expect(calls, contains('pickSafTree'));
    expect(calls, isNot(contains('safCreateFromPath')));
  });
}
