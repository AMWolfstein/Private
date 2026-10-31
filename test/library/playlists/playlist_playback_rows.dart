part of 'playlist_playback_test.dart';

late ProviderContainer container;

late _Player _player;

late _Playback _playback;

void _registerPlaylistPlaybackRows() {
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
              theme: AppTheme.build(Brightness.dark),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: withArtwork && tickersEnabled
                  ? Builder(
                      builder: (context) => Scaffold(
                        body: TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  const LibraryCollectionTracksScreen(
                                    mode: LibraryCollectionMode.loved,
                                  ),
                            ),
                          ),
                          child: const Text('Open Loved'),
                        ),
                      ),
                    )
                  : TickerMode(
                      enabled: tickersEnabled,
                      child: const LibraryCollectionTracksScreen(
                        mode: LibraryCollectionMode.loved,
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

  for (final mode in LibraryCollectionMode.values) {
    for (final sistrum in [true]) {
      testWidgets(
        'selection dispatches one ${mode.name} removal (Sistrum: $sistrum)',
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
                theme: sistrum
                    ? AppTheme.build(Brightness.dark)
                    : MaterialTestTheme.light(),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: LibraryCollectionTracksScreen(
                  mode: mode,
                  playlistId: mode == LibraryCollectionMode.playlist
                      ? 'playlist'
                      : null,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (sistrum) {
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
            tester.element(find.byType(LibraryCollectionTracksScreen)),
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
          theme: MaterialTestTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const LibraryCollectionTracksScreen(
            mode: LibraryCollectionMode.playlist,
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
    final context = tester.element(find.byType(LibraryCollectionTracksScreen));
    expect(find.text(context.friendlyError(collections.error)), findsOneWidget);
    // The row stays, but the bar closes so it cannot cover the error message.
    expect(find.text('First'), findsOneWidget);
    expect(find.byIcon(Icons.remove_circle_outline), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final sistrum in [true]) {
    testWidgets('playlist row queues its neighbors (Sistrum: $sistrum)', (
      tester,
    ) async {
      final fakePlayer = _Player();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith(_Settings.new),
            musicPlayerControllerProvider.overrideWithValue(fakePlayer),
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
            theme: sistrum
                ? AppTheme.build(Brightness.dark)
                : MaterialTestTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const LibraryCollectionTracksScreen(
              mode: LibraryCollectionMode.playlist,
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

      expect(fakePlayer.queue.map((item) => item.title), [
        'First',
        'Selected',
        'Last',
      ]);
      expect(fakePlayer.index, 1);
      final actions = find.byType(AlbumPlayActions);
      await tester.ensureVisible(actions);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: actions,
          matching: sistrum ? find.text('Shuffle') : find.byTooltip('Shuffle'),
        ),
      );
      await tester.pumpAndSettle();
      expect(fakePlayer.shuffle, isTrue);
      expect(
        fakePlayer.queue.map((item) => item.title),
        unorderedEquals(['First', 'Selected', 'Last']),
      );

      expect(tester.takeException(), isNull);
    });
  }
  setUp(() {
    _player = _Player();
    _playback = _Playback();
    container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(_Settings.new),
        musicPlayerControllerProvider.overrideWithValue(_player),
        playbackProvider.overrideWith(() => _playback),
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
      expect(_player.queue.map((item) => item.title), [
        'First',
        'Selected',
        'Last',
      ]);
      expect(_player.index, _player.queue.length - 1);
    },
  );

  test(
    'missing and virtual CUE tracks do not shift the selected track',
    () async {
      _playback.paths['Unavailable'] = '/album.cue#track02';
      await container
          .read(playbackProvider.notifier)
          .playTrackList(_tracks, startIndex: 2);
      expect(_player.queue.map((item) => item.title), [
        'First',
        'Selected',
        'Last',
      ]);
      expect(_player.index, 1);
    },
  );

  test('repeated tracks retain the selected occurrence', () async {
    await container.read(playbackProvider.notifier).playTrackList([
      _tracks.first,
      _tracks.last,
      _tracks.first,
      _tracks[2],
    ], startIndex: 2);
    expect(_player.queue.map((item) => item.title), [
      'First',
      'Last',
      'First',
      'Selected',
    ]);
    expect(_player.index, 2);
  });

  test('unavailable selection starts the next playable track', () async {
    await container
        .read(playbackProvider.notifier)
        .playTrackList(_tracks, startIndex: 1);
    expect(_player.queue[_player.index!].title, 'Selected');
  });

  test(
    'library _playback keeps the resolved row identity and audio facts',
    () async {
      const track = Track(
        id: 'Selected',
        name: 'Selected',
        artistName: 'Artist',
        albumName: 'Album',
        coverUrl: 'https://remote.example/cover.jpg',
        duration: 180,
      );
      await container.read(playbackProvider.notifier).playTrackList([
        track,
      ], startIndex: 0);

      final media = _player.queue.single;
      expect(media.id, 'Selected');
      expect(media.source, 'content://library/selected');
      expect(media.bitDepth, 24);
      expect(media.sampleRate, 96000);
      expect(media.bitrate, 1411);
      expect(media.format, 'flac');
      expect(media.genre, 'Jazz');
      // Remote artwork is never adopted as local _playback artwork.
      expect(media.artUri, isNull);
    },
  );
}
