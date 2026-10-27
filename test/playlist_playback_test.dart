import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/models/settings.dart';
import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/providers/library_collections_provider.dart';
import 'package:spotiflac_android/providers/local_library_provider.dart';
import 'package:spotiflac_android/providers/music_player_provider.dart';
import 'package:spotiflac_android/providers/playback_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/screens/library_tracks_folder_screen.dart';
import 'package:spotiflac_android/services/music_player_service.dart';
import 'support/material_test_theme.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';
import 'package:spotiflac_android/widgets/track_card.dart';
import 'package:spotiflac_android/widgets/album_detail_header.dart';

final _tracks = [
  for (final name in ['First', 'Unavailable', 'Selected', 'Last'])
    Track(
      id: name,
      name: name,
      artistName: 'Artist',
      albumName: 'Album',
      duration: 180,
    ),
];

class _Settings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings(
    localLibraryEnabled: true,
    localLibraryShowDuplicates: true,
  );
}

class _Handler extends Fake implements MusicPlayerHandler {}

class _Player extends MusicPlayerController {
  bool available = true;
  bool? shuffle;

  @override
  Future<void> setShuffle(bool enabled) async => shuffle = enabled;
  List<PlayableMedia> queue = [];
  int? index;

  @override
  Future<MusicPlayerHandler?> ensureInitialized() async =>
      available ? _Handler() : null;

  @override
  Future<void> playAll(
    List<PlayableMedia> items, {
    int initialIndex = 0,
  }) async {
    queue = items;
    index = initialIndex;
  }
}

class _Playback extends PlaybackController {
  final List<List<String>> resolvedRequests = [];
  final Map<String, String?> paths = {
    'First': 'content://library/first',
    'Selected': 'content://library/selected',
    'Last': 'content://library/last',
  };

  @override
  Future<List<String?>> resolveTrackFilePaths(List<Track> tracks) async {
    resolvedRequests.add(tracks.map((track) => track.id).toList());
    return [for (final track in tracks) paths[track.id]];
  }
}

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
          for (final track in _tracks)
            CollectionTrackEntry(
              key: track.id,
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

class _RemovalCollections extends _Collections {
  _RemovalCollections(this._record);
  final void Function(String, List<String>) _record;

  @override
  LibraryCollectionsState build() {
    final initial = super.build();
    final tracks = initial.playlists.single.tracks;
    return initial.copyWith(loved: tracks);
  }

  Future<int> _remove(String kind, Iterable<String> keys) async {
    final selected = keys.toSet();
    _record(kind, selected.toList());
    List<CollectionTrackEntry> keep(List<CollectionTrackEntry> entries) =>
        entries.where((entry) => !selected.contains(entry.key)).toList();
    state = switch (kind) {
      'loved' => state.copyWith(loved: keep(state.loved)),
      _ => state.copyWith(
        playlists: [
          state.playlists.single.copyWith(
            tracks: keep(state.playlists.single.tracks),
          ),
        ],
      ),
    };
    return selected.length;
  }

  @override
  Future<int> removeLovedTracks(Iterable<String> keys) =>
      _remove('loved', keys);

  @override
  Future<int> removeTracksFromPlaylist(String id, Iterable<String> keys) =>
      _remove('playlist', keys);
}

class _FailingRemovalCollections extends _Collections {
  final error = StateError('remove failed');

  @override
  Future<int> removeLovedTracks(Iterable<String> keys) async => throw error;

  @override
  Future<int> removeTracksFromPlaylist(
    String id,
    Iterable<String> keys,
  ) async => throw error;
}

class _SingleLovedCollections extends _Collections {
  @override
  LibraryCollectionsState build() => LibraryCollectionsState(
    isLoaded: true,
    loved: [
      CollectionTrackEntry(
        key: 'First',
        track: _tracks.first,
        addedAt: DateTime(2026),
      ),
    ],
  );

  void clearLoved() => state = state.copyWith(loved: []);
  void restoreLoved() => state = build();
}

class _Library extends LocalLibraryNotifier {
  @override
  LocalLibraryState build() => LocalLibraryState();
}

class _PlaylistLibrary extends LocalLibraryNotifier {
  @override
  LocalLibraryState build() => LocalLibraryState();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final (tickersEnabled, withArtwork) in [
    (true, false),
    (false, false),
    (true, true),
    (false, true),
  ]) {
    testWidgets(
      'single loved song stays painted (tickers: $tickersEnabled, artwork: $withArtwork)',
      (tester) async {
        tester.view.physicalSize = const Size(432, 960);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final collections = _SingleLovedCollections();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              settingsProvider.overrideWith(_Settings.new),
              musicPlayerControllerProvider.overrideWithValue(_Player()),
              playbackProvider.overrideWith(_Playback.new),
              libraryCollectionsProvider.overrideWith(() => collections),
              localLibraryProvider.overrideWith(_PlaylistLibrary.new),
              localLibraryCoverProvider.overrideWith(
                (ref, request) async => withArtwork
                    ? File('assets/images/logo.png').absolute.path
                    : null,
              ),
              localLibraryFirstCoverProvider.overrideWith(
                (ref, request) async => null,
              ),
            ],
            child: MaterialApp(
              theme: MornyeTheme.build(Brightness.dark),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: withArtwork && tickersEnabled
                  ? Builder(
                      builder: (context) => Scaffold(
                        body: TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const LibraryTracksFolderScreen(
                                mode: LibraryTracksFolderMode.loved,
                              ),
                            ),
                          ),
                          child: const Text('Open Loved'),
                        ),
                      ),
                    )
                  : TickerMode(
                      enabled: tickersEnabled,
                      child: const LibraryTracksFolderScreen(
                        mode: LibraryTracksFolderMode.loved,
                      ),
                    ),
            ),
          ),
        );
        if (withArtwork && tickersEnabled) {
          await tester.tap(find.text('Open Loved'));
        }
        await tester.pumpAndSettle();
        expect(find.text('First').hitTestable(), findsOneWidget);
        final row = tester.getRect(find.byType(TrackCard));
        expect(row.isFinite, isTrue);
        expect(row.height, inExclusiveRange(0, 140));
        expect(
          tester
              .widgetList<Opacity>(
                find.ancestor(
                  of: find.text('First'),
                  matching: find.byType(Opacity),
                ),
              )
              .every((widget) => widget.opacity == 1),
          isTrue,
        );
        expect(tester.takeException(), isNull);
        collections.clearLoved();
        await tester.pumpAndSettle();
        collections.restoreLoved();
        await tester.pumpAndSettle();
        expect(find.text('First').hitTestable(), findsOneWidget);
        expect(
          tester
              .widgetList<Opacity>(
                find.ancestor(
                  of: find.text('First'),
                  matching: find.byType(Opacity),
                ),
              )
              .every((widget) => widget.opacity == 1),
          isTrue,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final mode in LibraryTracksFolderMode.values) {
    for (final mornye in [true]) {
      testWidgets(
        'selection dispatches one ${mode.name} removal (Mornye: $mornye)',
        (tester) async {
          final calls = <(String, List<String>)>[];
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                settingsProvider.overrideWith(_Settings.new),
                musicPlayerControllerProvider.overrideWithValue(_Player()),
                playbackProvider.overrideWith(_Playback.new),
                libraryCollectionsProvider.overrideWith(
                  () => _RemovalCollections(
                    (kind, keys) => calls.add((kind, keys)),
                  ),
                ),
                localLibraryProvider.overrideWith(_Library.new),
                localLibraryCoverProvider.overrideWith(
                  (ref, request) async => null,
                ),
                localLibraryFirstCoverProvider.overrideWith(
                  (ref, request) async => null,
                ),
              ],
              child: MaterialApp(
                theme: mornye
                    ? MornyeTheme.build(Brightness.dark)
                    : AppTheme.light(),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: LibraryTracksFolderScreen(
                  mode: mode,
                  playlistId: mode == LibraryTracksFolderMode.playlist
                      ? 'playlist'
                      : null,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (mornye) {
            expect(find.text('Shuffle'), findsOneWidget);
            expect(find.byTooltip('Shuffle'), findsNothing);
          }
          await tester.ensureVisible(find.text('First'));
          await tester.longPress(find.text('First'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Unavailable'));
          await tester.tap(find.text('Unavailable'));
          await tester.pumpAndSettle();
          await tester.tap(find.byIcon(Icons.remove_circle_outline));
          await tester.pumpAndSettle();
          expect(calls, hasLength(1));
          expect(calls.single.$1, mode.name);
          expect(calls.single.$2, ['First', 'Unavailable']);
          expect(find.text('First'), findsNothing);
          expect(find.text('Unavailable'), findsNothing);
          expect(find.byIcon(Icons.remove_circle_outline), findsNothing);
          final l10n = AppLocalizations.of(
            tester.element(find.byType(LibraryTracksFolderScreen)),
          );
          expect(find.text(l10n.collectionRemovedTracks(2)), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('a failed removal reports the error and closes the bar', (
    tester,
  ) async {
    final collections = _FailingRemovalCollections();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(_Settings.new),
          musicPlayerControllerProvider.overrideWithValue(_Player()),
          playbackProvider.overrideWith(_Playback.new),
          libraryCollectionsProvider.overrideWith(() => collections),
          localLibraryProvider.overrideWith(_Library.new),
          localLibraryCoverProvider.overrideWith((ref, request) async => null),
          localLibraryFirstCoverProvider.overrideWith(
            (ref, request) async => null,
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const LibraryTracksFolderScreen(
            mode: LibraryTracksFolderMode.playlist,
            playlistId: 'playlist',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('First'));
    await tester.longPress(find.text('First'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.remove_circle_outline));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(LibraryTracksFolderScreen));
    expect(find.text(context.friendlyError(collections.error)), findsOneWidget);
    // The row stays, but the bar closes so it cannot cover the error message.
    expect(find.text('First'), findsOneWidget);
    expect(find.byIcon(Icons.remove_circle_outline), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final mornye in [true]) {
    testWidgets('playlist row queues its neighbors (Mornye: $mornye)', (
      tester,
    ) async {
      final player = _Player();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith(_Settings.new),
            musicPlayerControllerProvider.overrideWithValue(player),
            playbackProvider.overrideWith(_Playback.new),
            libraryCollectionsProvider.overrideWith(_Collections.new),
            localLibraryProvider.overrideWith(_PlaylistLibrary.new),
            localLibraryCoverProvider.overrideWith(
              (ref, request) async => null,
            ),
            localLibraryFirstCoverProvider.overrideWith(
              (ref, request) async => null,
            ),
          ],
          child: MaterialApp(
            theme: mornye
                ? MornyeTheme.build(Brightness.dark)
                : AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const LibraryTracksFolderScreen(
              mode: LibraryTracksFolderMode.playlist,
              playlistId: 'playlist',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final row = find.ancestor(
        of: find.text('Selected'),
        matching: find.byType(TrackCard),
      );
      await tester.scrollUntilVisible(row, 200);
      await tester.tap(
        find.descendant(of: row, matching: find.byIcon(Icons.play_arrow)),
      );
      await tester.pumpAndSettle();

      expect(player.queue.map((item) => item.title), [
        'First',
        'Selected',
        'Last',
      ]);
      expect(player.index, 1);
      final actions = find.byType(AlbumPlayActions);
      await tester.ensureVisible(actions);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: actions,
          matching: mornye ? find.text('Shuffle') : find.byTooltip('Shuffle'),
        ),
      );
      await tester.pumpAndSettle();
      expect(player.shuffle, isTrue);
      expect(
        player.queue.map((item) => item.title),
        unorderedEquals(['First', 'Selected', 'Last']),
      );

      expect(tester.takeException(), isNull);
    });
  }

  late ProviderContainer container;
  late _Player player;
  late _Playback playback;
  setUp(() {
    player = _Player();
    playback = _Playback();
    container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(_Settings.new),
        musicPlayerControllerProvider.overrideWithValue(player),
        playbackProvider.overrideWith(() => playback),
      ],
    );
    addTearDown(container.dispose);
  });

  test(
    'starting at the last track does not rotate earlier tracks after it',
    () async {
      await container
          .read(playbackProvider.notifier)
          .playTrackList(_tracks, startIndex: 3);
      expect(player.queue.map((item) => item.title), [
        'First',
        'Selected',
        'Last',
      ]);
      expect(player.index, player.queue.length - 1);
    },
  );

  test(
    'missing and virtual CUE tracks do not shift the selected track',
    () async {
      playback.paths['Unavailable'] = '/album.cue#track02';
      await container
          .read(playbackProvider.notifier)
          .playTrackList(_tracks, startIndex: 2);
      expect(player.queue.map((item) => item.title), [
        'First',
        'Selected',
        'Last',
      ]);
      expect(player.index, 1);
    },
  );

  test('repeated tracks retain the selected occurrence', () async {
    await container.read(playbackProvider.notifier).playTrackList([
      _tracks.first,
      _tracks.last,
      _tracks.first,
      _tracks[2],
    ], startIndex: 2);
    expect(player.queue.map((item) => item.title), [
      'First',
      'Last',
      'First',
      'Selected',
    ]);
    expect(player.index, 2);
  });

  test('unavailable selection starts the next playable track', () async {
    await container
        .read(playbackProvider.notifier)
        .playTrackList(_tracks, startIndex: 1);
    expect(player.queue[player.index!].title, 'Selected');
  });

  test('empty playlist leaves existing playback alone', () async {
    await container.read(playbackProvider.notifier).playTrackList([]);
    expect(player.index, isNull);
  });

  test(
    'no playable files reports an error without replacing playback',
    () async {
      playback.paths.clear();
      await expectLater(
        container.read(playbackProvider.notifier).playTrackList(_tracks),
        throwsA(isA<Exception>()),
      );
      expect(player.index, isNull);
    },
  );

  test(
    'old external preference cannot redirect local queue playback',
    () async {
      final calls = <MethodCall>[];
      const channel = MethodChannel('com.amwolfstein.sistrum/backend');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final legacy = AppSettings.fromJson({'playerMode': 'external'});
      expect(legacy.toJson().containsKey('playerMode'), false);
      await container
          .read(playbackProvider.notifier)
          .playTrackList(_tracks, startIndex: 2);
      expect(player.queue[player.index!].title, 'Selected');
      expect(player.queue.length, 3);
      expect(calls, isEmpty);
    },
  );
}
