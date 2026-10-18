import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/models/settings.dart';
import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/providers/library_browse_provider.dart';
import 'package:spotiflac_android/providers/library_collections_provider.dart';
import 'package:spotiflac_android/providers/local_artist_provider.dart';
import 'package:spotiflac_android/providers/local_library_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/providers/playback_provider.dart';
import 'package:spotiflac_android/providers/music_player_provider.dart';
import 'package:spotiflac_android/screens/local_album_screen.dart';
import 'package:spotiflac_android/screens/local_artist_screen.dart';
import 'package:spotiflac_android/screens/library_tracks_folder_screen.dart';
import 'package:spotiflac_android/services/library_database.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';
import 'package:spotiflac_android/utils/clickable_metadata.dart';
import 'package:spotiflac_android/widgets/album_detail_header.dart';
import 'package:spotiflac_android/widgets/collection_scaffold.dart';
import 'package:spotiflac_android/widgets/mornye_artist_header.dart';

class _Settings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings(localLibraryEnabled: true);
}

class _Library extends LocalLibraryNotifier {
  @override
  LocalLibraryState build() => LocalLibraryState();
}

LocalLibraryItem _item(int i) => LocalLibraryItem(
  id: '$i',
  trackName: 'Song $i',
  artistName: 'Artist',
  albumName: 'Album',
  filePath: 'content://music/$i',
  scannedAt: DateTime(2026),
);
Track _track(int i) => Track(
  id: '$i',
  name: 'Song $i',
  artistName: 'Artist',
  albumName: 'Album',
  duration: 120,
  source: 'local',
);

class _Collections extends LibraryCollectionsNotifier {
  final loved = <Track>[];
  @override
  LibraryCollectionsState build() => LibraryCollectionsState(
    isLoaded: true,
    playlists: [
      UserPlaylistCollection(
        id: 'mix',
        name: 'My mix',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        tracks: [
          CollectionTrackEntry(
            key: 'local:1',
            track: _track(1),
            addedAt: DateTime(2026),
          ),
        ],
      ),
    ],
  );
  @override
  Future<void> ensurePlaylistLoaded(String id) async {}
  @override
  Future<({bool removed, int count})> toggleLovedTracks(
    Iterable<Track> tracks,
  ) async {
    loved.addAll(tracks);
    return (removed: false, count: loved.length);
  }
}

class _Player extends MusicPlayerController {
  @override
  Future<void> setShuffle(bool value) async {}
}

class _Playback extends PlaybackController {
  final queues = <List<String>>[];
  @override
  Future<void> playLocalLibraryQueue(
    List<LocalLibraryItem> items, {
    required LocalLibraryItem startItem,
  }) async {
    queues.add(items.map((t) => t.id).toList());
  }

  @override
  Future<void> playTrackList(List<Track> tracks, {int startIndex = 0}) async {
    queues.add(tracks.map((t) => t.id).toList());
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final brightness in Brightness.values) {
    testWidgets(
      'artist names open the portrait detail and play all local pages ($brightness)',
      (tester) async {
        tester.view.physicalSize = const Size(430, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final playback = _Playback();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              settingsProvider.overrideWith(_Settings.new),
              localLibraryProvider.overrideWith(_Library.new),
              libraryCollectionsProvider.overrideWith(_Collections.new),
              musicPlayerControllerProvider.overrideWithValue(_Player()),
              playbackProvider.overrideWith(() => playback),
              localArtistTrackLoaderProvider.overrideWithValue(
                (request) async => QueueLibraryDbPage(
                  rows: [
                    for (
                      var i = request.offset;
                      i < (request.offset == 0 ? 40 : 41);
                      i++
                    )
                      {'source': 'local', 'item': _item(i).toJson()},
                  ],
                  nextCursor: QueueLibraryDbCursor([request.offset + 40]),
                ),
              ),
              libraryBrowsePageLoaderProvider.overrideWithValue(
                (request) async => const LibraryBrowsePage([
                  LibraryBrowseEntry(
                    source: 'local',
                    key: 'album',
                    name: 'Album',
                    artist: 'Artist',
                    samplePath: '',
                    trackCount: 41,
                  ),
                ]),
              ),
            ],
            child: MaterialApp(
              theme: MornyeTheme.build(brightness),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const Scaffold(
                body: Center(child: ClickableArtistName(artistName: 'Artist')),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Artist'));
        await tester.pumpAndSettle();
        expect(find.byType(LocalArtistScreen), findsOneWidget);
        expect(
          find.byType(MornyeArtistHeader),
          findsNothing,
        ); // Slivers are composed directly.
        expect(find.byType(MornyeArtistSurface), findsOneWidget);
        expect(find.text('Album'), findsWidgets);
        expect(find.byIcon(CupertinoIcons.star), findsOneWidget);
        expect(
          tester.getCenter(find.byKey(const ValueKey('artist-play'))).dx,
          closeTo(215, 1),
        );
        await tester.tap(find.byKey(const ValueKey('artist-play')));
        await tester.pumpAndSettle();
        expect(playback.queues.single.length, 41);
        expect(playback.queues.single.last, '40');
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final playlist in [false, true]) {
    testWidgets(
      'album and playlist use immersive membership actions at narrow large text ($playlist)',
      (tester) async {
        tester.view.physicalSize = const Size(360, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final collections = _Collections();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              libraryCollectionsProvider.overrideWith(() => collections),
              localLibraryProvider.overrideWith(_Library.new),
              settingsProvider.overrideWith(_Settings.new),
              musicPlayerControllerProvider.overrideWithValue(_Player()),
              playbackProvider.overrideWith(_Playback.new),
            ],
            child: MaterialApp(
              theme: MornyeTheme.build(Brightness.light),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(1.6)),
                child: child!,
              ),
              home: playlist
                  ? const LibraryTracksFolderScreen(
                      mode: LibraryTracksFolderMode.playlist,
                      playlistId: 'mix',
                    )
                  : LocalAlbumScreen(
                      albumName: 'Album',
                      artistName: 'Artist',
                      tracks: [_item(1)],
                    ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final header =
            tester
                    .widget<CollectionScaffold>(find.byType(CollectionScaffold))
                    .appBar
                as AlbumDetailHeader;
        expect(header.immersive, true);
        expect(header.squareArtwork, true);
        expect(find.byType(MornyeArtistSurface), findsOneWidget);
        await tester.ensureVisible(find.byTooltip('Add to Loved'));
        await tester.tap(find.byTooltip('Add to Loved'));
        await tester.pumpAndSettle();
        expect(collections.loved.single.id, '1');
        expect(find.byTooltip('Add to playlist'), findsOneWidget);
        expect(find.byTooltip('Shuffle'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
