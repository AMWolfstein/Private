import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/models/track.dart';
import 'package:sistrum/providers/library_collections_provider.dart';
import 'package:sistrum/providers/local_library_provider.dart';
import 'package:sistrum/screens/library/library_collection_tracks_screen.dart';
import 'package:sistrum/theme/app_theme.dart';
import 'package:sistrum/widgets/header/album_detail_header.dart';
import 'package:sistrum/widgets/collection_scaffold.dart';
import 'package:sistrum/widgets/library/local_collection_actions.dart';
import 'package:sistrum/widgets/header/app_artist_header.dart';
import 'package:sistrum/widgets/glass/app_chrome.dart';
import 'package:sistrum/widgets/header/header_controls.dart';

const _track = Track(
  id: '1',
  name: 'Song',
  artistName: 'Artist',
  albumName: 'Album',
  source: 'local',
  duration: 120,
  coverUrl: '/music/song.png',
);
CollectionTrackEntry _entry() => CollectionTrackEntry(
  key: trackCollectionKey(_track),
  track: _track,
  addedAt: DateTime(2026),
);

class _Collections extends LibraryCollectionsNotifier {
  @override
  LibraryCollectionsState build() => LibraryCollectionsState(
    isLoaded: true,
    loved: [_entry()],
    playlists: [
      UserPlaylistCollection(
        id: 'mix',
        name: 'Mix',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        coverImagePath: '/music/custom.png',
        tracks: [_entry()],
      ),
    ],
  );
  @override
  Future<void> ensurePlaylistLoaded(String id) async {}
  @override
  Future<({bool removed, int count})> toggleLovedTracks(
    Iterable<Track> tracks,
  ) async {
    state = state.copyWith(loved: []);
    return (removed: true, count: 1);
  }
}

class _Library extends LocalLibraryNotifier {
  @override
  LocalLibraryState build() => LocalLibraryState();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final brightness in Brightness.values) {
    Widget host(Widget child) => ProviderScope(
      overrides: [
        libraryCollectionsProvider.overrideWith(_Collections.new),
        localLibraryProvider.overrideWith(_Library.new),
      ],
      child: MaterialApp(
        theme: AppTheme.build(brightness),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    );
    test('Sistrum primary content retains readable contrast ($brightness)', () {
      final scheme = AppTheme.build(brightness).colorScheme;
      final first = scheme.primary.computeLuminance();
      final second = scheme.onPrimary.computeLuminance();
      final contrast =
          ((first > second ? first : second) + .05) /
          ((first < second ? first : second) + .05);
      expect(contrast, greaterThanOrEqualTo(4.5));
    });
    testWidgets(
      'collection action circles are tonal and Loved has feedback ($brightness)',
      (tester) async {
        await tester.pumpWidget(
          host(
            Scaffold(
              body: LocalCollectionActions(
                tracks: const [_track],
                onPlay: () {},
                onShuffle: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final actions = tester.widget<AlbumPlayActions>(
          find.byType(AlbumPlayActions),
        );
        final loved = actions.leadingAction! as HeaderCircleButton;
        final playlist = actions.trailingAction! as HeaderCircleButton;
        expect(loved.tonal, isTrue);
        expect(playlist.tonal, isTrue);
        expect(
          loved.iconColor,
          AppTheme.build(brightness).colorScheme.error,
        );
        final l10n = tester.element(find.byType(LocalCollectionActions)).l10n;
        await tester.tap(find.byTooltip(l10n.trackOptionRemoveFromLoved));
        await tester.pumpAndSettle();
        expect(
          find.text(l10n.snackbarRemovedTracksFromLoved(1)),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
    for (final playlist in [false, true]) {
      testWidgets(
        'collection surface and header share artwork ($brightness, playlist: $playlist)',
        (tester) async {
          await tester.pumpWidget(
            host(
              LibraryCollectionTracksScreen(
                mode: playlist
                    ? LibraryCollectionMode.playlist
                    : LibraryCollectionMode.loved,
                playlistId: playlist ? 'mix' : null,
              ),
            ),
          );
          await tester.pumpAndSettle();
          final surface = tester.widget<AppArtistSurface>(
            find.byType(AppArtistSurface),
          );
          final header =
              tester
                      .widget<CollectionScaffold>(
                        find.byType(CollectionScaffold),
                      )
                      .appBar
                  as AlbumDetailHeader;
          expect(surface.imageSource, playlist ? '/music/custom.png' : null);
          expect(header.paletteSource, surface.imageSource);
          expect(tester.takeException(), isNull);
        },
      );
    }
    testWidgets(
      'segmented targets remain large at reduced text scale ($brightness)',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          host(
            Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(.5)),
                child: Scaffold(
                  body: Center(
                    child: AppSegmentedControl(
                      labels: const ['One', 'Two'],
                      selectedIndex: 0,
                      onChanged: (_) {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        semantics.dispose();
      },
    );
  }
}
