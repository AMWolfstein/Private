import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/models/settings.dart';
import 'package:sistrum/models/track.dart';
import 'package:sistrum/providers/library_browse_provider.dart';
import 'package:sistrum/providers/library_collections_provider.dart';
import 'package:sistrum/providers/local_artist_provider.dart';
import 'package:sistrum/providers/local_library_provider.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/providers/playback_provider.dart';
import 'package:sistrum/providers/music_player_provider.dart';
import 'package:sistrum/screens/local_album_screen.dart';
import 'package:sistrum/screens/local_artist_screen.dart';
import 'package:sistrum/screens/library_tracks_folder_screen.dart';
import 'package:sistrum/services/library/library_database.dart';
import 'package:sistrum/theme/sistrum_theme.dart';
import 'package:sistrum/utils/clickable_metadata.dart';
import 'package:sistrum/widgets/album_detail_header.dart';
import 'package:sistrum/widgets/collection_scaffold.dart';
import 'package:sistrum/widgets/sistrum_artist_header.dart';

class _Settings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings();
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
              localArtistPlayCountsLoaderProvider.overrideWithValue(
                (keys) async => {},
              ),
              listeningFlushProvider.overrideWithValue(() async {}),
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
                (request) async => LibraryBrowsePage([
                  for (
                    var i = request.offset;
                    i < (request.offset == 0 ? 40 : 41);
                    i++
                  )
                    LibraryBrowseEntry(
                      source: 'local',
                      key: 'album$i',
                      name: i == 0 ? 'Album' : 'Album $i',
                      artist: 'Artist',
                      samplePath: '',
                      trackCount: 41,
                    ),
                ]),
              ),
            ],
            child: MaterialApp(
              theme: SistrumTheme.build(brightness),
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
          find.byType(SistrumArtistHeader),
          findsNothing,
        ); // Slivers are composed directly.
        expect(find.byType(SistrumArtistSurface), findsOneWidget);
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
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('artist-popular-dot-3')),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Popular'), findsOneWidget);
        expect(find.text('Show more'), findsNothing);
        expect(find.textContaining(RegExp(r'^\d+ / \d+$')), findsNothing);
        for (var page = 0; page < 4; page++) {
          expect(
            find.byKey(ValueKey('artist-popular-dot-$page')),
            findsOneWidget,
          );
        }
        expect(
          find.byKey(const ValueKey('artist-popular-dot-4')),
          findsNothing,
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('artist-popular-dot-3')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('artist-popular-dot-3')));
        await tester.pumpAndSettle();
        final dot = tester.widget<Semantics>(
          find
              .ancestor(
                of: find.byKey(const ValueKey('artist-popular-dot-3')),
                matching: find.byType(Semantics),
              )
              .first,
        );
        expect(dot.properties.selected, true);
        // The 8dp dot sits in a full 48dp touch target.
        final dotBox = tester.getSize(
          find.byKey(const ValueKey('artist-popular-dot-3')),
        );
        expect(dotBox.width, greaterThanOrEqualTo(48));
        expect(dotBox.height, greaterThanOrEqualTo(48));
        await tester.scrollUntilVisible(
          find.text('Albums'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(find.byType(ListView).last);
        await tester.drag(find.byType(ListView).last, const Offset(-7000, 0));
        await tester.pumpAndSettle();
        final shelf = tester.widget<ListView>(find.byType(ListView).last);
        expect(shelf.childrenDelegate.estimatedChildCount, 41);
        expect(find.text('Show more'), findsNothing);

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
              theme: SistrumTheme.build(Brightness.light),
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
        expect(find.byType(SistrumArtistSurface), findsOneWidget);
        await tester.ensureVisible(find.byTooltip('Add to Loved'));
        await tester.tap(find.byTooltip('Add to Loved'));
        await tester.pumpAndSettle();
        expect(collections.loved.single.id, '1');
        expect(find.byTooltip('Add to playlist'), findsOneWidget);
        // 1.6x on 360dp: the compact pills drop to icon-only and keep their
        // accessible names instead of ellipsizing "Play" and "Shuffle".
        expect(find.text('Shuffle'), findsNothing);
        expect(find.byTooltip('Shuffle'), findsOneWidget);
        expect(find.byTooltip('Play'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
