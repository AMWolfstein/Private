import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/core/models/settings.dart';
import 'package:sistrum/providers/library/library_browse_provider.dart';
import 'package:sistrum/providers/library/library_collections_provider.dart';
import 'package:sistrum/providers/library/library_sort_provider.dart';
import 'package:sistrum/providers/library/local_library_provider.dart';
import 'package:sistrum/providers/settings/settings_provider.dart';
import 'package:sistrum/screens/library/local_artist/local_artist_screen.dart';
import 'package:sistrum/screens/library/local_artist/local_artist_providers.dart';
import 'package:sistrum/services/library/database/library_database.dart';
import 'package:sistrum/widgets/header/app_artist_header.dart';

class _Library extends LocalLibraryNotifier {
  @override
  LocalLibraryState build() => LocalLibraryState();
  void indexed() =>
      state = state.copyWith(loadedIndexVersion: state.loadedIndexVersion + 1);
}

class _Settings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings();
}

class _Collections extends LibraryCollectionsNotifier {
  @override
  LibraryCollectionsState build() => LibraryCollectionsState(isLoaded: true);
}

void main() {
  testWidgets(
    'artist feature and portrait follow new indexed albums independent of Sort',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      var newer = false;
      var singlesOnly = false;
      final requests = <LibraryBrowseRequest>[];
      LibraryBrowseEntry album(
        String name,
        String cover, {
        bool single = false,
      }) => LibraryBrowseEntry(
        source: 'local',
        key: name,
        name: name,
        artist: 'Artist',
        cover: cover,
        samplePath: '',
        trackCount: 2,
        totalTracks: single ? 1 : 10,
        releaseDate: newer ? '2027' : '2026',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith(_Settings.new),
            localLibraryProvider.overrideWith(_Library.new),
            libraryCollectionsProvider.overrideWith(_Collections.new),
            libraryBrowsePageLoaderProvider.overrideWithValue((request) async {
              requests.add(request.browse);
              if (request.browse.credit == LibraryArtistCredit.appearsOn) {
                return const LibraryBrowsePage([]);
              }
              if (request.browse.releaseKind == LibraryReleaseKind.singles) {
                return LibraryBrowsePage(
                  singlesOnly
                      ? [album('Newest single', '/single.jpg', single: true)]
                      : [],
                );
              }
              if (singlesOnly) return const LibraryBrowsePage([]);
              return LibraryBrowsePage([
                newer
                    ? album('New album', '/new.jpg')
                    : album('Old album', '/old.jpg'),
              ]);
            }),
            localArtistTrackLoaderProvider.overrideWithValue(
              (_) async =>
                  const LibraryBrowseDbPage(rows: [], nextCursor: null),
            ),
            localArtistPlayCountsLoaderProvider.overrideWithValue(
              (_) async => {},
            ),
            listeningFlushProvider.overrideWithValue(() async {}),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const LocalArtistScreen(
              artistName: 'Artist',
              coverPath: '/stale-route.jpg',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(LocalArtistScreen)),
      );
      expect(
        tester
            .widget<AppArtistSurface>(find.byType(AppArtistSurface))
            .imageSource,
        '/old.jpg',
      );
      expect(find.text('Old album'), findsWidgets);
      container.read(librarySortProvider.notifier).select('size-asc');
      await tester.pumpAndSettle();
      expect(requests.every((r) => r.sort == 'artist-releases-newest'), isTrue);
      newer = true;
      (container.read(localLibraryProvider.notifier) as _Library).indexed();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AppArtistSurface>(find.byType(AppArtistSurface))
            .imageSource,
        '/new.jpg',
      );
      expect(find.text('New album'), findsWidgets);
      expect(find.text('Old album'), findsNothing);
      singlesOnly = true;
      (container.read(localLibraryProvider.notifier) as _Library).indexed();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AppArtistSurface>(find.byType(AppArtistSurface))
            .imageSource,
        '/single.jpg',
      );
      expect(find.text('Newest single'), findsWidgets);
      expect(find.text('New album'), findsNothing);

      expect(
        requests
            .where((r) => r.limit == 1)
            .every(
              (r) =>
                  const [
                    LibraryReleaseKind.albums,
                    LibraryReleaseKind.singles,
                  ].contains(r.releaseKind) &&
                  r.credit == LibraryArtistCredit.albumArtist,
            ),
        isTrue,
      );
      expect(
        requests.any((r) => r.releaseKind == LibraryReleaseKind.singles),
        isTrue,
      );
      expect(
        requests.any((r) => r.credit == LibraryArtistCredit.appearsOn),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
