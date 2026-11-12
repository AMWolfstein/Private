import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mornye/l10n/app_localizations.dart';
import 'package:mornye/models/track.dart';
import 'package:mornye/providers/download_queue_provider.dart';
import 'package:mornye/providers/library_collections_provider.dart';
import 'package:mornye/providers/library_search_provider.dart';
import 'package:mornye/providers/local_library_provider.dart';
import 'package:mornye/providers/music_player_provider.dart';
import 'package:mornye/providers/settings_provider.dart';
import 'package:mornye/services/library_search.dart';
import 'package:mornye/theme/app_theme.dart';
import 'package:mornye/widgets/library_search_results.dart';
import 'package:mornye/widgets/now_playing_indicator.dart';
import 'package:mornye/widgets/track_list_tile.dart';

import 'support/fixed_settings.dart';

/// The playing track, a different track, and a track another provider lists
/// under the same catalog id.
const _tracks = [
  Track(
    id: 'catalog-1',
    name: 'Current song',
    artistName: 'Example artist',
    albumName: 'Example album',
    duration: 180,
    trackNumber: 1,
  ),
  Track(
    id: 'catalog-2',
    name: 'Other song',
    artistName: 'Example artist',
    albumName: 'Example album',
    duration: 180,
    trackNumber: 2,
  ),
  Track(
    id: 'catalog-1',
    name: 'Same id song',
    artistName: 'Another artist',
    albumName: 'Another album',
    duration: 180,
    trackNumber: 3,
    source: 'other-provider',
  ),
];

/// The downloaded file of the first track is playing.
final _identity = CurrentTrackIdentity(
  recordIds: const {'/music/current.flac', 'download-row'},
  catalogIds: const {'catalog-1'},
  matchKey: catalogTrackKey(_tracks.first).matchKey,
);

class _Collections extends LibraryCollectionsNotifier {
  @override
  LibraryCollectionsState build() => LibraryCollectionsState(
    isLoaded: true,
    playlists: [
      UserPlaylistCollection(
        id: 'playlist',
        name: 'Playlist',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        tracks: [
          for (final (index, track) in _tracks.indexed)
            CollectionTrackEntry(
              key: 'entry-$index',
              track: track,
              addedAt: DateTime(2026),
            ),
        ],
      ),
    ],
  );

  @override
  Future<void> ensurePlaylistLoaded(String playlistId) async {}
}

class _Library extends LocalLibraryNotifier {
  @override
  LocalLibraryState build() => LocalLibraryState();
}

class _History extends DownloadHistoryNotifier {
  @override
  DownloadHistoryState build() => DownloadHistoryState();
}

List<Override> _overrides({MediaItem? current, required bool identified}) => [
  settingsProvider.overrideWith(FixedSettingsNotifier.new),
  libraryCollectionsProvider.overrideWith(_Collections.new),
  localLibraryProvider.overrideWith(_Library.new),
  downloadHistoryProvider.overrideWith(_History.new),
  downloadHistoryVisibleBatchExistsProvider.overrideWith(
    (ref, request) => const {},
  ),
  localLibraryCoverProvider.overrideWith((ref, request) async => null),
  localLibraryFirstCoverProvider.overrideWith((ref, request) async => null),
  currentMediaItemProvider.overrideWithBuild(
    (ref, notifier) => Stream.value(current),
  ),
  currentTrackIdentityProvider.overrideWith(
    (ref) async => identified ? _identity : null,
  ),
  playbackPlayingProvider.overrideWith((ref) => true),
  playbackLoadingProvider.overrideWith((ref) => false),
];

Widget _app(
  Widget home, {
  bool mornye = false,
  MediaItem? current,
  bool identified = true,
  List<Override> overrides = const [],
}) => ProviderScope(
  overrides: [
    ..._overrides(current: current, identified: identified),
    ...overrides,
  ],
  child: MaterialApp(
    theme: AppTheme.build(Brightness.light),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  ),
);

/// Pumps in bounded steps: a playing indicator loops, so the tree never
/// settles.
Future<void> _pumpFor(
  WidgetTester tester, [
  Duration duration = const Duration(seconds: 1),
]) async {
  const step = Duration(milliseconds: 50);
  for (var elapsed = Duration.zero; elapsed < duration; elapsed += step) {
    await tester.pump(step);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('TrackListTile', () {
    Widget list() => Scaffold(
      body: ListView(
        children: [
          for (final track in _tracks)
            TrackListTile(
              track: track,
              isInHistory: true,
              onDownload: ({bool forceQualityPicker = false}) {},
              leading: Text('${track.trackNumber}'),
            ),
        ],
      ),
    );

    testWidgets('marks nothing when no file is identified', (tester) async {
      await tester.pumpWidget(_app(list(), identified: false));
      await _pumpFor(tester);
      expect(find.byType(NowPlayingIndicator), findsNothing);
    });
  });

  group('Library folder', () {});

  group('Library search', () {
    // Downloaded and local rows number their records independently, so the
    // same id can name two files.
    const hits = [
      LibrarySearchHit(
        kind: LibrarySearchKind.songs,
        id: '7',
        title: 'Current song',
        source: 'downloaded',
        samplePath: '/music/current.flac',
      ),
      LibrarySearchHit(
        kind: LibrarySearchKind.songs,
        id: '8',
        title: 'Other song',
        source: 'downloaded',
        samplePath: '/music/other.flac',
      ),
      LibrarySearchHit(
        kind: LibrarySearchKind.songs,
        id: '7',
        title: 'Same id song',
        source: 'local',
        samplePath: '/music/same-id.flac',
      ),
    ];

    Widget results() => Scaffold(
      body: CustomScrollView(
        slivers: [LibrarySearchResults(query: 'Song', onOpenArtist: (_) {})],
      ),
    );

    const current = MediaItem(
      id: '7',
      title: 'Current song',
      extras: {'source': '/music/current.flac'},
    );
    final searchOverrides = [
      librarySearchProvider.overrideWith(
        (ref, request) async =>
            request.kind == LibrarySearchKind.songs ? hits : [],
      ),
    ];

    testWidgets('Mornye rows show no current-track state', (tester) async {
      await tester.pumpWidget(
        _app(
          results(),
          mornye: true,
          current: current,
          overrides: searchOverrides,
        ),
      );
      await _pumpFor(tester);
      expect(find.byType(NowPlayingIndicator), findsNothing);
    });
  });
}
