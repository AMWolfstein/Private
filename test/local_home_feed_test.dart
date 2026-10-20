import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/models/settings.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/providers/local_library_provider.dart';
import 'package:spotiflac_android/providers/local_home_feed_provider.dart';
import 'package:spotiflac_android/providers/library_browse_provider.dart';
import 'package:spotiflac_android/providers/library_collections_provider.dart';
import 'package:spotiflac_android/screens/home_tab.dart';
import 'package:spotiflac_android/screens/local_artist_screen.dart';
import 'package:spotiflac_android/providers/local_artist_provider.dart';
import 'package:spotiflac_android/services/library_database.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';

class _Settings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings(localLibraryEnabled: true);
  void disable() => state = state.copyWith(localLibraryEnabled: false);
}

class _Library extends LocalLibraryNotifier {
  @override
  LocalLibraryState build() => LocalLibraryState();
  void scanFinished() => state = state.copyWith(loadedIndexVersion: 1);
}

class _Collections extends LibraryCollectionsNotifier {
  @override
  LibraryCollectionsState build() => LibraryCollectionsState(
    isLoaded: true,
    playlists: [
      UserPlaylistCollection(
        id: 'mix',
        name: 'My mix',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        tracks: [],
      ),
    ],
  );
}

final _item = LocalLibraryItem(
  id: 'song',
  trackName: 'Local song',
  artistName: 'Local artist',
  albumName: 'Local album',
  filePath: '',
  scannedAt: DateTime(2026),
);
LibraryBrowsePage _browse(LibraryBrowsePageRequest request) =>
    LibraryBrowsePage([
      LibraryBrowseEntry(
        source: 'local',
        key: 'album',
        name: request.browse.artists ? 'Local artist' : 'Local album',
        artist: 'Local artist',
        samplePath: '',
        trackCount: 4,
        releaseDate: '2026-10-18',
      ),
    ]);
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'bounded local tracks refresh after scans and stop reading when disabled',
    () async {
      var reads = 0;
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(_Settings.new),
          localLibraryProvider.overrideWith(_Library.new),
          localHomeTrackLoaderProvider.overrideWithValue(() async {
            reads++;
            return QueueLibraryDbPage(
              nextCursor: null,
              rows: [
                {
                  'source': 'local',
                  'item': {..._item.toJson(), 'filePath': '/music/song.opus'},
                },
                {'source': 'local', 'item': _item.toJson()},
              ],
            );
          }),
        ],
      );
      addTearDown(container.dispose);
      container.listen(localHomeTracksProvider, (_, _) {});
      expect((await container.read(localHomeTracksProvider.future)).length, 1);
      (container.read(localLibraryProvider.notifier) as _Library)
          .scanFinished();
      expect((await container.read(localHomeTracksProvider.future)).length, 1);
      expect(reads, 2);
      (container.read(settingsProvider.notifier) as _Settings).disable();
      expect(await container.read(localHomeTracksProvider.future), isEmpty);
      expect(reads, 2);
      for (final request in [
        localHomeBrowseRequest(),
        localHomeBrowseRequest(artists: true),
      ]) {
        expect(request.limit, 12);
        expect(request.artist, isNull);
        expect(request.search, isEmpty);
      }
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets(
      'local editorial home shelves and artist navigation ($brightness)',
      (tester) async {
        tester.view.physicalSize = const Size(360, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final requests = <LibraryBrowsePageRequest>[];
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              settingsProvider.overrideWith(_Settings.new),
              localLibraryProvider.overrideWith(_Library.new),
              libraryCollectionsProvider.overrideWith(_Collections.new),
              localHomeTracksProvider.overrideWith((ref) async => [_item]),
              libraryBrowsePageLoaderProvider.overrideWithValue((
                request,
              ) async {
                requests.add(request);
                return _browse(request);
              }),
              localArtistPlayCountsLoaderProvider.overrideWithValue(
                (keys) async => {},
              ),
              localArtistTrackLoaderProvider.overrideWithValue(
                (request) async =>
                    const QueueLibraryDbPage(rows: [], nextCursor: null),
              ),
            ],
            child: MaterialApp(
              theme: MornyeTheme.build(brightness),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.6)),
                child: child!,
              ),
              home: const HomeTab(mode: HomeTabMode.browse),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Latest Releases in Your Library'), findsOneWidget);
        expect(find.text('2026-10-18'), findsOneWidget);
        expect(find.text('Recently Added'), findsOneWidget);
        expect(find.text('Recent'), findsNothing);
        expect(find.text('No recent items yet'), findsNothing);
        expect(
          requests.map((r) => r.browse.sort),
          containsAll(['release-date-newest', 'latest', 'a-z']),
        );
        expect(
          requests.every((r) => r.browse.limit == 12 && r.includeLocal),
          isTrue,
        );
        await tester.scrollUntilVisible(
          find.text('My mix'),
          400,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('My mix'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('home-artist-album')),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.byKey(const ValueKey('home-artist-album')));
        await tester.pumpAndSettle();
        expect(find.byType(LocalArtistScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
