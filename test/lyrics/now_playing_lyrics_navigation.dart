part of 'now_playing_lyrics_transition_test.dart';

const backendChannel = MethodChannel('com.amwolfstein.sistrum/backend');

const secureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

late StreamController<MediaItem?> mediaItems;

late List<double> volumeWrites;

late Map<String, dynamic> metadataOverrides;

late List<String> metadataReads;

late List<({String? raw, Completer<ParsedLyrics> completion})> lyricsRequests;

MediaItem _item(String id) => MediaItem(
  id: id,
  title: id == 'first' ? 'First' : 'Second',
  artist: 'Artist',
  album: 'Album',
  duration: const Duration(minutes: 3),
  extras: {'source': 'content://library/$id.flac'},
);

Rect _seekTrackBounds(WidgetTester tester) {
  final track = find.descendant(
    of: find.descendant(
      of: find.byType(PlaybackSeekSlider),
      matching: find.byType(Slider),
    ),
    matching: find.byWidgetPredicate(
      (widget) => widget is LeafRenderObjectWidget,
    ),
  );
  final box = tester.renderObject<RenderBox>(track);
  final theme = SliderTheme.of(tester.element(track));
  final rect = theme.trackShape!.getPreferredRect(
    parentBox: box,
    sliderTheme: theme,
    isEnabled: true,
  );
  return Rect.fromPoints(
    box.localToGlobal(rect.topLeft),
    box.localToGlobal(rect.bottomRight),
  );
}

NowPlayingScreen _playerScreen() => NowPlayingScreen(
  metadataControllerFactory: () => PlayerMetadataController(
    parseLyrics: (raw) {
      final completion = Completer<ParsedLyrics>();
      lyricsRequests.add((raw: raw, completion: completion));
      return completion.future;
    },
  ),
);

Future<void> _pumpNowPlaying(
  WidgetTester tester, {
  ThemeData? theme,
  PlayerView playerView = PlayerView.normal,
  Size size = const Size(1080, 1920),
  PlaybackState? playback,
  Stream<PlaybackState>? playbackEvents,
  Widget Function(Widget)? wrapPlayer,
  MusicPlayerController? controller,
  int glassLevel = 3,
  List<MediaItem> queue = const [],
}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(kPlayerViewKey, playerView.name);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appScreensProvider.overrideWithValue(const AppScreenBuilders()),
        initialThemeSettingsProvider.overrideWithValue(
          ThemeSettings(playerView: playerView),
        ),
        initialSettingsProvider.overrideWithValue(
          // The immersive drift repeats forever, so it would keep these
          // player animations from settling.
          AppSettings(
            glassClarityLevel: glassLevel,
            animatedAlbumArtwork: false,
          ),
        ),
        if (controller != null)
          musicPlayerControllerProvider.overrideWithValue(controller),
        currentMediaItemProvider.overrideWithBuild(
          (ref, notifier) => mediaItems.stream,
        ),
        playerCollectionTrackProvider.overrideWith(
          (ref, item) async => Track(
            id: item.id,
            name: item.title,
            artistName: item.artist ?? '',
            albumName: item.album ?? '',
            duration: item.duration?.inSeconds ?? 0,
            source: 'local',
          ),
        ),
        libraryCollectionsProvider.overrideWith(_TestCollections.new),
        playbackStateProvider.overrideWith(
          (ref) =>
              playbackEvents ??
              (playback == null
                  ? const Stream.empty()
                  : Stream.value(playback)),
        ),
        playQueueProvider.overrideWith((ref) => Stream.value(queue)),
        systemVolumeProvider.overrideWith((ref) => Stream.value(0.5)),
        systemVolumeWriterProvider.overrideWith(
          (ref) =>
              (value) async => volumeWrites.add(value),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: theme,
        home: wrapPlayer?.call(_playerScreen()) ?? _playerScreen(),
      ),
    ),
  );
}

Future<void> _completeLyrics(WidgetTester tester) async {
  await tester.pump();
  // Start the actual encode/native DTO/hydration pipeline in the real async
  // zone: futures started under FakeAsync cannot finish isolate messages.
  while (lyricsRequests.isNotEmpty) {
    final pending = List.of(lyricsRequests);
    lyricsRequests.clear();
    await tester.runAsync(() async {
      for (final request in pending) {
        try {
          request.completion.complete(
            await LyricsParser.parseAsyncNative(request.raw),
          );
        } catch (error, stack) {
          request.completion.completeError(error, stack);
        }
      }
    });
    await tester.pump();
  }
}

Future<int> _settlePlayer(
  WidgetTester tester, [
  Duration duration = const Duration(milliseconds: 100),
]) async {
  final deadline = tester.binding.clock.fromNowBy(const Duration(minutes: 10));
  var frames = 0;
  do {
    if (tester.binding.clock.now().isAfter(deadline)) {
      fail('Player animations did not settle');
    }
    // A track change may start another metadata read during a later frame.
    await _completeLyrics(tester);
    await tester.pump(duration);
    frames++;
  } while (tester.binding.hasScheduledFrame || lyricsRequests.isNotEmpty);
  return frames;
}

void _registerNowPlayingLyricsNavigation() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mediaItems = StreamController<MediaItem?>.broadcast();
    volumeWrites = [];
    metadataOverrides = {};
    metadataReads = [];
    lyricsRequests = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (_) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(backendChannel, (call) async {
          if (call.method == 'setScreenAwake') return null;
          if (call.method == 'runNativeDataJob') {
            final arguments = (call.arguments as Map).cast<String, dynamic>();
            final request =
                jsonDecode(arguments['request_json'] as String) as Map;
            expect(request['operation'], 'parse_lyrics');
            final raw = utf8.decode(arguments['bytes'] as List<int>);
            return jsonEncode(_lyricsDto(LyricsParser.parse(raw)));
          }
          if (call.method != 'readFileMetadata') {
            fail('Unexpected platform call: ${call.method}');
          }
          final arguments = (call.arguments as Map).cast<String, dynamic>();
          final path = arguments['file_path']?.toString() ?? '';
          metadataReads.add(path);
          final lyrics = path.endsWith('/timed.flac')
              ? '''<tt xmlns="http://www.w3.org/ns/ttml"><body><div><p begin="00:00.000" end="00:02.000"><span begin="00:00.000">Short</span></p></div></body></tt>'''
              : path.endsWith('/many.flac')
              ? '[00:00.00]First line\n[00:02.00]Second line\n[00:04.00]Third line\n[00:06.00]Fourth line'
              : path.endsWith('/second.flac')
              ? '[00:01.00]Second lyric'
              : '[00:01.00]First lyric';
          return jsonEncode({
            'title': path.endsWith('/second.flac') ? 'Second' : 'First',
            'lyrics': lyrics,
            ...metadataOverrides,
          });
        });
  });

  tearDown(() async {
    await mediaItems.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(backendChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
  });

  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('swiping up the mini player opens the player '
        '(Sistrum: $brightness)', (tester) async {
      await _pumpNowPlaying(
        tester,
        theme: AppTheme.build(brightness),
        size: const Size(393, 852),
        // Paused, so the Material progress bar lets the frames settle.
        wrapPlayer: (_) => const Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 90),
              child: MiniPlayer(),
            ),
          ),
        ),
      );
      mediaItems.add(_item('first'));
      await _settlePlayer(tester);
      final title = find.descendant(
        of: find.byType(MiniPlayer),
        matching: find.text('First'),
      );
      final player = find.byType(NowPlayingScreen);

      // A downward drag never opens the player.
      await tester.drag(title, const Offset(0, 120));
      await _settlePlayer(tester);
      expect(player, findsNothing);

      // A nudge, or a pull taken back down, leaves it closed.
      for (final moves in [
        [const Offset(0, -30)],
        [const Offset(0, -120), const Offset(0, 110)],
      ]) {
        final gesture = await tester.startGesture(tester.getCenter(title));
        for (final move in moves) {
          await gesture.moveBy(move);
        }
        await tester.pump(const Duration(milliseconds: 200));
        await gesture.up();
        await _settlePlayer(tester);
        expect(player, findsNothing);
      }

      // A slow pull that stops before release opens it.
      final gesture = await tester.startGesture(tester.getCenter(title));
      await gesture.moveBy(const Offset(0, -150));
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.up();
      await _settlePlayer(tester);
      expect(player, findsOneWidget);
      expect(tester.getTopLeft(player).dy, 0);
      Navigator.of(tester.element(player)).pop();
      await _settlePlayer(tester);
      expect(player, findsNothing);

      await tester.fling(title, const Offset(0, -60), 1500);
      await _settlePlayer(tester);
      expect(player, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('sharing reads document lyrics before opening the lyrics page', (
    tester,
  ) async {
    await _pumpNowPlaying(tester, theme: AppTheme.build(Brightness.dark));
    mediaItems.add(_item('first'));
    await _settlePlayer(tester);
    expect(metadataReads, isEmpty);

    await tester.tap(find.byIcon(CupertinoIcons.ellipsis).hitTestable());
    await _settlePlayer(tester);
    await tester.tap(find.text('Share lyrics'));
    await _settlePlayer(tester);

    expect(metadataReads, ['content://library/first.flac']);
    expect(find.byType(LyricsShareScreen), findsOneWidget);
    expect(find.text('First lyric'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a track change cancels a pending lyrics share', (tester) async {
    await _pumpNowPlaying(tester, theme: AppTheme.build(Brightness.dark));
    mediaItems.add(_item('first'));
    await _settlePlayer(tester);

    await tester.tap(find.byIcon(CupertinoIcons.ellipsis).hitTestable());
    await _settlePlayer(tester);
    await tester.tap(find.text('Share lyrics'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(lyricsRequests, isNotEmpty);

    mediaItems.add(_item('second'));
    await tester.pump();
    await _settlePlayer(tester);

    expect(find.byType(LyricsShareScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final sistrum in [true]) {
    testWidgets(
      'late duration refreshes the open Sistrum player (dark: $sistrum)',
      (tester) async {
        await _pumpNowPlaying(
          tester,
          theme: AppTheme.build(sistrum ? Brightness.dark : Brightness.light),
          playback: PlaybackState(
            processingState: AudioProcessingState.ready,
            updatePosition: const Duration(seconds: 30),
          ),
          wrapPlayer: (player) => Column(
            children: [
              Expanded(child: player),
              const HeroMode(enabled: false, child: MiniPlayer()),
            ],
          ),
        );
        final initial = _item('first').copyWith(duration: Duration.zero);
        mediaItems.add(initial);
        await _settlePlayer(tester);
        final originalState = tester.state(find.byType(NowPlayingScreen));
        expect(
          tester
              .widget<PlaybackSeekSlider>(find.byType(PlaybackSeekSlider))
              .duration,
          Duration.zero,
        );
        final readsBefore = metadataReads.length;

        mediaItems.add(initial.copyWith(duration: const Duration(minutes: 3)));
        await _settlePlayer(tester);
        expect(
          tester.state(find.byType(NowPlayingScreen)),
          same(originalState),
        );
        expect(
          tester
              .widget<PlaybackSeekSlider>(find.byType(PlaybackSeekSlider))
              .duration,
          const Duration(minutes: 3),
        );
        expect(metadataReads.length, readsBefore);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final view in PlayerView.values) {
    for (final page in ['player', 'lyrics', 'queue']) {
      testWidgets(
        'cover swipe changes the track in the Sistrum $page ($view)',
        (tester) async {
          final queue = [_item('first'), _item('second')];
          final controller = _QueueController(
            (index) => mediaItems.add(queue[index]),
          );
          await _pumpNowPlaying(
            tester,
            theme: AppTheme.build(Brightness.dark),
            size: const Size(393, 852),
            playerView: view,
            queue: queue,
            controller: controller,
            playback: PlaybackState(queueIndex: 0),
          );
          mediaItems.add(queue.first);
          await _settlePlayer(tester);
          if (page != 'player') {
            await tester.tap(
              find.byIcon(
                page == 'lyrics'
                    ? CupertinoIcons.quote_bubble
                    : CupertinoIcons.list_bullet,
              ),
            );
            await _settlePlayer(tester);
          }
          final cover = find.byKey(
            ValueKey(
              page == 'player'
                  ? 'full-player-artwork'
                  : 'compact-player-artwork',
            ),
          );
          final rect = tester.getRect(cover);
          final gesture = await tester.startGesture(rect.center);
          await gesture.moveBy(const Offset(-110, 0));
          await tester.pump();
          expect(tester.getRect(cover), rect);
          await gesture.up();
          await _settlePlayer(tester);
          expect(controller.selected, [1]);
          expect(find.text('Second').hitTestable(), findsOneWidget);
          await tester.drag(cover, const Offset(110, 0));
          await _settlePlayer(tester);
          expect(controller.selected, [1, 0]);
          expect(find.text('First').hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
