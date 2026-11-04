import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/core/models/settings.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/library/library_browse_provider.dart';
import 'package:sistrum/providers/library/library_collections_provider.dart';
import 'package:sistrum/providers/library/local_library_provider.dart';
import 'package:sistrum/providers/settings/settings_provider.dart';
import 'package:sistrum/screens/library/local_artist/local_artist_providers.dart';
import 'package:sistrum/screens/library/local_artist/local_artist_screen.dart';
import 'package:sistrum/services/library/database/library_database.dart';

class _Library extends LocalLibraryNotifier {
  @override
  LocalLibraryState build() => LocalLibraryState();
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
    'artist header band, scrolled under the photo, draws no live blur',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(430, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      LibraryBrowseEntry album(String name) => LibraryBrowseEntry(
        source: 'local',
        key: name,
        name: name,
        artist: 'Artist',
        cover: '/$name.jpg',
        samplePath: '',
        trackCount: 2,
        totalTracks: 10,
        releaseDate: '2026',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith(_Settings.new),
            localLibraryProvider.overrideWith(_Library.new),
            libraryCollectionsProvider.overrideWith(_Collections.new),
            libraryBrowsePageLoaderProvider.overrideWithValue((request) async {
              if (request.browse.credit == LibraryArtistCredit.appearsOn ||
                  request.browse.releaseKind == LibraryReleaseKind.singles) {
                return const LibraryBrowsePage([]);
              }
              return LibraryBrowsePage([
                for (var n = 1; n <= 12; n++) album('Album $n'),
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
              coverPath: '/cover.jpg',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(CustomScrollView).first,
        const Offset(0, -700),
      );
      await tester.pumpAndSettle();

      final band = find.byKey(const ValueKey('sistrum-header-backing'));
      expect(band, findsOneWidget);
      expect(
        find.descendant(of: band, matching: find.byType(BackdropFilter)),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
