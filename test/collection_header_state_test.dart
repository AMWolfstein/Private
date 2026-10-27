import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/models/track.dart';
import 'package:sistrum/providers/library_collections_provider.dart';
import 'package:sistrum/providers/local_library_provider.dart';
import 'package:sistrum/providers/music_player_provider.dart';
import 'package:sistrum/screens/library_tracks_folder_screen.dart';
import 'package:sistrum/screens/local_album_screen.dart';
import 'package:sistrum/services/library_database.dart';
import 'package:sistrum/theme/sistrum_theme.dart';
import 'package:sistrum/widgets/album_detail_header.dart';
import 'package:sistrum/widgets/album_track_tile.dart';
import 'package:sistrum/widgets/animation_utils.dart';
import 'package:sistrum/widgets/collection_scaffold.dart';
import 'package:sistrum/widgets/local_song_row.dart';

class _Library extends LocalLibraryNotifier {
  @override
  LocalLibraryState build() => LocalLibraryState();
}

class _Collections extends LibraryCollectionsNotifier {
  _Collections({this.loaded = true, this.withSong = true});
  final bool loaded, withSong;
  @override
  LibraryCollectionsState build() => LibraryCollectionsState(
    isLoaded: loaded,
    loved: withSong
        ? [
            CollectionTrackEntry(
              key: 'local:1',
              addedAt: DateTime(2026),
              track: const Track(
                id: '1',
                name: 'Song',
                artistName: 'Artist',
                albumName: 'Album',
                source: 'local',
                duration: 120,
              ),
            ),
          ]
        : [],
  );
  void finish() => state = LibraryCollectionsState(isLoaded: true);
}

class _Player extends MusicPlayerController {
  final toggles = <bool>[];
  @override
  Future<void> togglePlayPause(bool isPlaying) async {
    toggles.add(isPlaying);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final brightness in Brightness.values) {
    Widget host(
      Widget page, {
      _Collections? collections,
      List<Override> overrides = const [],
    }) => ProviderScope(
      overrides: [
        localLibraryProvider.overrideWith(_Library.new),
        libraryCollectionsProvider.overrideWith(
          () => collections ?? _Collections(),
        ),
        ...overrides,
      ],
      child: MaterialApp(
        theme: SistrumTheme.build(brightness),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: page,
      ),
    );
    testWidgets(
      'album selection owns the header and closes without leaving ($brightness)',
      (tester) async {
        tester.view.physicalSize = const Size(430, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          host(
            LocalAlbumScreen(
              albumName: 'Album',
              artistName: 'Artist',
              tracks: [
                LocalLibraryItem(
                  id: '1',
                  trackName: 'Song',
                  artistName: 'Artist',
                  albumName: 'Album',
                  filePath: 'content://music/1',
                  scannedAt: DateTime(2026),
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byType(AlbumTrackTile));
        await tester.pumpAndSettle();
        await tester.longPress(find.byType(AlbumTrackTile));
        await tester.pumpAndSettle();
        AlbumDetailHeader header() =>
            tester
                    .widget<CollectionScaffold>(find.byType(CollectionScaffold))
                    .appBar
                as AlbumDetailHeader;
        expect(header().actions, isNull);
        expect(header().appBarTitle, isNotNull);
        final close = header().leading! as HeaderCircleButton;
        expect(close.icon, Icons.close);
        close.onPressed!();
        await tester.pumpAndSettle();
        expect(header().appBarTitle, isNull);
        expect(find.byType(LocalAlbumScreen), findsOneWidget);
      },
    );
    testWidgets(
      'Loved waits for hydration before showing empty ($brightness)',
      (tester) async {
        final collections = _Collections(loaded: false, withSong: false);
        await tester.pumpWidget(
          host(
            const LibraryTracksFolderScreen(
              mode: LibraryTracksFolderMode.loved,
            ),
            collections: collections,
          ),
        );
        await tester.pump();
        expect(find.byType(TrackListSkeleton), findsOneWidget);
        collections.finish();
        await tester.pumpAndSettle();
        expect(find.byType(TrackListSkeleton), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      'Loved row pauses the current song without restarting ($brightness)',
      (tester) async {
        tester.view.physicalSize = const Size(430, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final player = _Player();
        await tester.pumpWidget(
          host(
            const LibraryTracksFolderScreen(
              mode: LibraryTracksFolderMode.loved,
            ),
            overrides: [
              currentMediaItemProvider.overrideWithBuild(
                (ref, notifier) =>
                    Stream.value(const MediaItem(id: '1', title: 'Song')),
              ),
              playbackPlayingProvider.overrideWith((ref) => true),
              musicPlayerControllerProvider.overrideWithValue(player),
            ],
          ),
        );
        await tester.pumpAndSettle();
        final row = tester.widget<LocalSongRow>(find.byType(LocalSongRow));
        expect(row.isPlaying, isTrue);
        row.onPlay();
        await tester.pump();
        expect(player.toggles, [true]);
        final header =
            tester
                    .widget<CollectionScaffold>(find.byType(CollectionScaffold))
                    .appBar
                as AlbumDetailHeader;
        expect(header.leading, isNull);
        expect(header.appBarTitle, isNull);
      },
    );
  }
}
