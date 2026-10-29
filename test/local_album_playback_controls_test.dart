import 'dart:async';

import 'package:audio_service/audio_service.dart' show MediaItem;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/models/local_library_item.dart';
import 'package:sistrum/providers/music_player_provider.dart';
import 'package:sistrum/providers/playback_provider.dart';
import 'package:sistrum/screens/library/local_album_screen.dart';
import 'support/material_test_theme.dart';
import 'package:sistrum/theme/sistrum_theme.dart';
import 'package:sistrum/widgets/header/album_detail_header.dart';
import 'package:sistrum/widgets/library/album_track_tile.dart';

class _Playing extends Notifier<bool> {
  @override
  bool build() => false;

  void emit(bool playing) => state = playing;
}

final _playingProvider = NotifierProvider<_Playing, bool>(_Playing.new);

class _Player extends MusicPlayerController {
  _Player(this._emit);

  final void Function(bool) _emit;
  final _toggles = <bool>[];
  final shuffleWrites = <bool>[];

  @override
  Future<void> setShuffle(bool enabled) async => shuffleWrites.add(enabled);

  @override
  Future<void> togglePlayPause(bool isPlaying) async {
    _toggles.add(isPlaying);
    _emit(!isPlaying);
  }
}

class _Playback extends PlaybackController {
  _Playback(this._start);

  final void Function(LocalLibraryItem) _start;
  final _started = <String>[];

  @override
  Future<void> playLocalLibraryQueue(
    List<LocalLibraryItem> items, {
    required LocalLibraryItem startItem,
  }) async {
    _started.add(startItem.id);
    _start(startItem);
  }
}

void main() {
  for (final sistrum in [true]) {
    testWidgets(
      'local album controls pause and resume without restarting ($sistrum)',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = const Size(430, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final media = StreamController<MediaItem?>();
        addTearDown(media.close);
        late final ProviderContainer container;
        void emitPlaying(bool playing) =>
            container.read(_playingProvider.notifier).emit(playing);
        final player = _Player(emitPlaying);
        final playback = _Playback((track) {
          media.add(
            MediaItem(
              id: track.id,
              title: track.trackName,
              extras: {'source': track.filePath},
            ),
          );
          emitPlaying(true);
        });
        final tracks = [
          LocalLibraryItem(
            id: 'cue',
            trackName: 'Virtual intro',
            artistName: 'Artist',
            albumName: 'Album',
            filePath: '/music/album.cue#track01',
            trackNumber: 1,
            releaseDate: '20240501',
            genre: 'Pop',
            scannedAt: DateTime(2026),
          ),
          for (final number in [1, 2])
            LocalLibraryItem(
              id: '$number',
              trackName: 'Song $number',
              artistName: 'Artist',
              albumName: 'Album',
              filePath: 'content://library/song-$number.flac',
              trackNumber: number + 1,
              scannedAt: DateTime(2026),
            ),
        ];
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              currentMediaItemProvider.overrideWithBuild(
                (ref, notifier) => media.stream,
              ),
              playbackPlayingProvider.overrideWith(
                (ref) => ref.watch(_playingProvider),
              ),
              musicPlayerControllerProvider.overrideWithValue(player),
              playbackProvider.overrideWith(() => playback),
            ],
            child: MaterialApp(
              theme: sistrum
                  ? SistrumTheme.build(Brightness.light)
                  : AppTheme.light(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: LocalAlbumScreen(
                albumName: 'Album',
                artistName: 'Artist',
                tracks: tracks,
              ),
            ),
          ),
        );
        container = ProviderScope.containerOf(
          tester.element(find.byType(LocalAlbumScreen)),
        );
        await tester.pumpAndSettle();
        expect(find.text('Pop'), findsOneWidget);
        expect(find.text('2024'), findsOneWidget);
        final header = find.byType(AlbumPlayActions);
        Finder row(int number) => find.byWidgetPredicate(
          (widget) =>
              widget is AlbumTrackTile && widget.trackName == 'Song $number',
        );
        Finder rowButton(int number) => find.descendant(
          of: row(number),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is IconButton &&
                (widget.tooltip == 'Play Song $number' ||
                    widget.tooltip == 'Pause Song $number'),
          ),
        );
        if (sistrum) {
          expect(find.text('Shuffle'), findsOneWidget);
          expect(find.byTooltip('Shuffle'), findsNothing);
          expect(find.byIcon(CupertinoIcons.heart), findsOneWidget);
          expect(find.byIcon(CupertinoIcons.text_badge_plus), findsOneWidget);
        }
        final pauseIcon = sistrum ? CupertinoIcons.pause_fill : Icons.pause;
        const playIcon = Icons.play_arrow;

        await tester.tap(
          find.descendant(of: header, matching: find.text('Play')),
        );
        await tester.pumpAndSettle();
        expect(playback._started, ['1']);
        expect(
          find.descendant(of: header, matching: find.text('Pause')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: header, matching: find.byIcon(pauseIcon)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: row(1), matching: find.byIcon(Icons.pause)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: row(2), matching: find.byIcon(playIcon)),
          findsOneWidget,
        );

        await tester.tap(
          find.descendant(of: header, matching: find.text('Pause')),
        );
        await tester.pumpAndSettle();
        expect(player._toggles, [true]);
        expect(
          find.descendant(of: header, matching: find.text('Play')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: row(1), matching: find.byTooltip('Play Song 1')),
          findsOneWidget,
        );

        await tester.ensureVisible(rowButton(1));
        await tester.tap(rowButton(1));
        await tester.pumpAndSettle();
        expect(player._toggles, [true, false]);
        expect(playback._started, ['1']);
        expect(
          find.descendant(of: row(1), matching: find.byTooltip('Pause Song 1')),
          findsOneWidget,
        );

        await tester.ensureVisible(rowButton(2));
        await tester.tap(rowButton(2));
        await tester.pumpAndSettle();
        expect(playback._started, ['1', '2']);
        expect(
          find.descendant(of: row(1), matching: find.byIcon(playIcon)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: row(2), matching: find.byIcon(Icons.pause)),
          findsOneWidget,
        );
        await tester.tap(rowButton(2));
        await tester.pumpAndSettle();
        expect(player._toggles, [true, false, true]);
        expect(playback._started, ['1', '2']);

        // A queue started from a playlist uses its file path as the media ID.
        media.add(
          MediaItem(
            id: tracks.firstWhere((track) => track.id == '1').filePath,
            title: 'Song 1',
          ),
        );
        emitPlaying(true);
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: row(1), matching: find.byIcon(Icons.pause)),
          findsOneWidget,
        );
        await tester.tap(rowButton(1));
        await tester.pumpAndSettle();
        expect(player._toggles.last, isTrue);
        expect(playback._started, ['1', '2']);

        // A matching row ID must not pause a different file in another album.
        media.add(
          const MediaItem(
            id: '1',
            title: 'Other',
            extras: {'source': '/other.flac'},
          ),
        );
        emitPlaying(true);
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: header, matching: find.text('Play')),
          findsOneWidget,
        );
        expect(find.byIcon(pauseIcon), findsNothing);
        await tester.ensureVisible(header);
        await tester.tap(
          find.descendant(of: header, matching: find.text('Play')),
        );
        await tester.pumpAndSettle();
        expect(playback._started, ['1', '2', '1']);
        await tester.ensureVisible(header);
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: header,
            matching: sistrum
                ? find.text('Shuffle')
                : find.byTooltip('Shuffle'),
          ),
        );
        await tester.pumpAndSettle();
        expect(player.shuffleWrites.last, isTrue);
        expect(playback._started, hasLength(4));
        expect(playback._started.last, isIn(['1', '2']));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
