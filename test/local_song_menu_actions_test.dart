import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/models/settings.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/providers/local_library_provider.dart';
import 'package:spotiflac_android/providers/music_player_provider.dart';
import 'package:spotiflac_android/services/library_database.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';
import 'package:spotiflac_android/widgets/local_song_menu.dart';
import 'package:spotiflac_android/widgets/local_song_row.dart';
import 'package:spotiflac_android/widgets/mornye_context_menu.dart';

class _Settings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings();
}

class _Local extends LocalLibraryNotifier {
  final removed = <String>[];
  @override
  LocalLibraryState build() => LocalLibraryState();
  @override
  Future<void> removePhysicalFiles(Iterable<String> paths) async =>
      removed.addAll(paths);
  @override
  Future<void> removeItem(String id) async => removed.add(id);
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
    TextDirection direction = TextDirection.ltr,
    LocalLibraryItem? item,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
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
          theme: MornyeTheme.build(Brightness.dark),
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
        await tester.runAsync(() => tester.tap(find.byIcon(Icons.more_horiz)));
        await tester.pumpAndSettle();
        final panel = tester.getRect(find.byType(MornyeContextMenu));
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

  testWidgets('restored queue actions use the selected local song', (
    tester,
  ) async {
    await mount(tester);
    for (final label in ['Play next', 'Add to queue']) {
      await tester.runAsync(() => tester.tap(find.byIcon(Icons.more_horiz)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.runAsync(() => pendingAction!);
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
    await tester.runAsync(() => tester.tap(find.byIcon(Icons.more_horiz)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy file path'));
    await tester.runAsync(() => pendingAction!);
    await tester.pumpAndSettle();
    expect(copied, song.filePath);
    for (final confirm in [false, true]) {
      await tester.runAsync(() => tester.tap(find.byIcon(Icons.more_horiz)));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Remove from device'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from device'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      await tester.tap(find.text(confirm ? 'Delete' : 'Cancel'));
      await tester.runAsync(() => pendingAction!);
      await tester.pumpAndSettle();
      expect(File(song.filePath).existsSync(), !confirm);
    }
    expect(library.removed, [song.filePath]);
  });
  testWidgets(
    'CUE split can be cancelled and deleting its row preserves the backing sheet',
    (tester) async {
      const channel = MethodChannel('com.zarz.spotiflac/backend');
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
      await tester.runAsync(() => tester.tap(find.byIcon(Icons.more_horiz)));
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(
        tester.element(find.byType(LocalSongRow)),
      );
      expect(find.text(l10n.trackReplayGain), findsNothing);
      expect(find.text(l10n.audioAnalysisTitle), findsNothing);
      await tester.ensureVisible(find.text(l10n.cueSplitTitle));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.cueSplitTitle));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(find.text(l10n.cueSplitConfirmTitle), findsOneWidget);
      await tester.tap(find.text(l10n.dialogCancel));
      await tester.runAsync(() => pendingAction!);
      await tester.pumpAndSettle();
      expect(calls, ['parseCueSheet']);
      await tester.runAsync(() => tester.tap(find.byIcon(Icons.more_horiz)));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(l10n.trackRemoveFromDevice));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.trackRemoveFromDevice));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.dialogDelete));
      await tester.runAsync(() => pendingAction!);
      await tester.pumpAndSettle();
      expect(library.removed, ['cue-row']);
      expect(file.existsSync(), isTrue);
    },
  );
}
