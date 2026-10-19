import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/models/settings.dart';
import 'package:spotiflac_android/providers/library_browse_provider.dart';
import 'package:spotiflac_android/providers/library_search_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/screens/mornye_library_screen.dart';
import 'package:spotiflac_android/screens/library_tracks_folder_screen.dart';
import 'package:spotiflac_android/screens/favorite_artists_screen.dart';
import 'package:spotiflac_android/screens/local_genres_screen.dart';
import 'package:spotiflac_android/providers/library_collections_provider.dart';
import 'package:spotiflac_android/services/album_completeness.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';

class _Settings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings(localLibraryEnabled: false);
}

class _Collections extends LibraryCollectionsNotifier {
  @override
  LibraryCollectionsState build() => LibraryCollectionsState(isLoaded: true);
}

LibraryBrowseEntry _album(int index) => LibraryBrowseEntry(
  source: 'downloaded',
  key: 'album-$index',
  name: 'Album $index',
  artist: 'Artist $index',
  samplePath: '',
  trackCount: 1,
);

void main() {
  testWidgets(
    'Mornye albums filter incomplete and unknown tags without losing search',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final requests = <LibraryBrowseRequest>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith(_Settings.new),
            libraryCollectionsProvider.overrideWith(_Collections.new),
            libraryBrowsePageLoaderProvider.overrideWithValue((page) async {
              final request = page.browse;
              requests.add(request);
              final filter = request.completeness;
              return LibraryBrowsePage([
                LibraryBrowseEntry.fromRow({
                  'queue_source': 'downloaded',
                  'album_key': 'album',
                  'album_name': filter == unknownAlbumCompletenessFilter
                      ? 'Unknown'
                      : 'Album',
                  'artist_name': 'Artist',
                  'track_count': 8,
                  if (filter != null) ...{
                    'album_completeness': filter == incompleteAlbumFilter
                        ? 'incomplete'
                        : 'unknown',
                    'album_present_tracks': 8,
                    'album_expected_tracks': filter == incompleteAlbumFilter
                        ? 12
                        : null,
                  },
                }, isArtist: false),
              ]);
            }),
          ],
          child: MaterialApp(
            theme: MornyeTheme.build(Brightness.dark),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: MornyeLibraryScreen(
                page: MornyeLibraryPage.albums,
                onOpenSection: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Incomplete albums'));
      await tester.pumpAndSettle();
      expect(requests.last.completeness, incompleteAlbumFilter);
      expect(find.text('8/12'), findsOneWidget);
      expect(find.byTooltip('8/12 tracks · 4 missing'), findsOneWidget);
      await tester.tap(find.byTooltip('Search your library'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'My album');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(requests.last.search, 'My album');
      expect(requests.last.completeness, incompleteAlbumFilter);
      await tester.tap(find.byTooltip('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Album completeness unknown'));
      await tester.pumpAndSettle();
      expect(requests.last.completeness, unknownAlbumCompletenessFilter);
      expect(find.text('?'), findsOneWidget);
      await tester.tap(find.byTooltip('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      expect(requests.last.completeness, isNull);
      expect(find.text('?'), findsNothing);
      expect(find.text('8/12'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'Library overview browses albums, artists, and search ($brightness)',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final opened = <String>[];
        final requests = <LibraryBrowseRequest>[];
        final searches = <LibrarySearchRequest>[];
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              settingsProvider.overrideWith(_Settings.new),
              libraryCollectionsProvider.overrideWith(_Collections.new),
              libraryBrowsePageLoaderProvider.overrideWithValue((page) async {
                final request = page.browse;
                requests.add(request);
                return LibraryBrowsePage([_album(0), _album(1)]);
              }),
              librarySearchProvider.overrideWith((ref, request) async {
                searches.add(request);
                return [];
              }),
            ],
            child: MaterialApp(
              theme: MornyeTheme.build(brightness),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: MornyeLibraryScreen(onOpenSection: opened.add),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Recently Added'), findsNothing);
        expect(find.byType(SliverGrid), findsNothing);
        expect(requests, isEmpty);
        expect(find.text('Playlists'), findsOneWidget);
        expect(find.text('Songs'), findsOneWidget);
        expect(find.text('Genres'), findsOneWidget);
        expect(
          tester.getTopLeft(find.text('Genres')).dy,
          greaterThan(tester.getTopLeft(find.text('Songs')).dy),
        );
        expect(
          tester.getTopLeft(find.text('Genres')).dy,
          lessThan(tester.getTopLeft(find.text('Loved Songs')).dy),
        );
        await tester.tap(find.text('Genres'));
        await tester.pumpAndSettle();
        expect(find.byType(LocalGenresScreen), findsOneWidget);
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        expect(find.text('Loved Songs'), findsOneWidget);
        expect(find.text('Favorite Artists'), findsOneWidget);
        expect(
          tester.getTopLeft(find.text('Songs')).dy,
          lessThan(tester.getTopLeft(find.text('Loved Songs')).dy),
        );
        expect(
          tester.getTopLeft(find.text('Loved Songs')).dy,
          lessThan(tester.getTopLeft(find.text('Favorite Artists')).dy),
        );
        await tester.ensureVisible(find.text('Loved Songs'));
        await tester.tap(find.text('Loved Songs'));
        await tester.pumpAndSettle();
        expect(find.byType(LibraryTracksFolderScreen), findsOneWidget);
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Favorite Artists'));
        await tester.tap(find.text('Favorite Artists'));
        await tester.pumpAndSettle();
        expect(find.byType(FavoriteArtistsScreen), findsOneWidget);
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Songs'));
        await tester.tap(find.text('Playlists'));
        expect(opened, ['all', 'playlists']);

        await tester.tap(find.byTooltip('Search your library'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'green lilac');
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        expect(searches, hasLength(4));
        expect(find.byType(TextField), findsOneWidget);
        await tester.tap(find.byTooltip('Clear'));
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Artists'));
        await tester.pumpAndSettle();
        expect(requests.last.artists, isTrue);
        await tester.tap(find.text('Artist 0'));
        await tester.pumpAndSettle();
        expect(requests.last.artists, isFalse);
        expect(requests.last.artist, 'Artist 0');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Library search is local and album pages load on scroll', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final requests = <LibraryBrowseRequest>[];
    final offsets = <int>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(_Settings.new),
          libraryBrowsePageLoaderProvider.overrideWithValue((page) async {
            final request = page.browse;
            requests.add(request);
            offsets.add(page.offset);
            return LibraryBrowsePage(
              List.generate(request.limit, (i) => _album(page.offset + i)),
            );
          }),
        ],
        child: MaterialApp(
          theme: MornyeTheme.build(Brightness.dark),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MornyeLibraryScreen(
              page: MornyeLibraryPage.albums,
              onOpenSection: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scroll = tester.widget<CustomScrollView>(
      find.byType(CustomScrollView),
    );
    scroll.controller!.jumpTo(scroll.controller!.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(requests.last.limit, 40);
    expect(offsets, [0, 40]);
    expect(
      tester
          .widget<SliverGrid>(find.byType(SliverGrid))
          .delegate
          .estimatedChildCount,
      80,
    );
    scroll.controller!.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Search your library'));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.enterText(find.byType(TextField), 'My album');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(requests.last.search, 'My album');
    expect(requests.last.limit, 40);
    expect(offsets.last, 0);
    expect(tester.takeException(), isNull);
  });
}
