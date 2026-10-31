part of 'now_playing_lyrics_transition_test.dart';

void _registerNowPlayingLyricsTransition4() {
  for (final reducedMotion in [false, true]) {
    testWidgets(
      'lyrics hide controls after five idle seconds and restore on tap (reduced motion: $reducedMotion)',
      (tester) async {
        const lyric = 'First lyric with several words on this line';
        metadataOverrides['lyrics'] = '[00:00.00]$lyric\n[01:00.00]Second line';
        await _pumpNowPlaying(
          tester,
          theme: AppTheme.build(Brightness.dark),
          size: const Size(393, 852),
          playback: PlaybackState(playing: true),
          wrapPlayer: (player) => Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(disableAnimations: reducedMotion),
              child: player,
            ),
          ),
        );
        mediaItems.add(_item('many'));
        await _settlePlayer(tester);
        final lyricsButton = find.byIcon(CupertinoIcons.quote_bubble);
        final queueButton = find.byIcon(CupertinoIcons.list_bullet);
        final play = find.widgetWithIcon(
          AppPlaybackButton,
          CupertinoIcons.pause_fill,
        );
        final volume = find.byType(AppVolumeControl);
        await tester.tap(lyricsButton);
        await tester.pump();
        await _completeLyrics(tester);
        await tester.pump(const Duration(milliseconds: 4900));
        expect(play.hitTestable(), findsOneWidget);
        final list = find.byType(ListView);
        final originalHeight = tester.getSize(list).height;
        final originalTop = tester.getTopLeft(find.text(lyric)).dy;
        await tester.pump(const Duration(milliseconds: 100));
        for (var frame = 0; frame < 10; frame++) {
          await tester.pump(const Duration(milliseconds: 40));
          expect(
            tester.getTopLeft(find.text(lyric)).dy,
            closeTo(originalTop, 1),
          );
        }
        await _settlePlayer(tester);
        expect(play.hitTestable(), findsNothing);
        expect(volume.hitTestable(), findsNothing);
        expect(lyricsButton.hitTestable(), findsNothing);
        expect(queueButton.hitTestable(), findsNothing);
        expect(tester.getSize(list).height, originalHeight);
        expect(
          find.byKey(const ValueKey('player-track-header')).hitTestable(),
          findsOneWidget,
        );

        Future<void> reveal() async {
          final bounds = tester.getRect(list);
          await tester.tapAt(Offset(bounds.right - 6, bounds.top + 10));
          for (var frame = 0; frame < 10; frame++) {
            await tester.pump(const Duration(milliseconds: 40));
            expect(
              tester.getTopLeft(find.text(lyric)).dy,
              closeTo(originalTop, 1),
            );
          }
          await _settlePlayer(tester);
          expect(play.hitTestable(), findsOneWidget);
          expect(lyricsButton.hitTestable(), findsOneWidget);
        }

        await reveal();
        final slider = find.descendant(
          of: volume,
          matching: find.byType(Slider),
        );
        final touch = await tester.startGesture(tester.getCenter(slider));
        await tester.pump(const Duration(seconds: 5));
        expect(volume.hitTestable(), findsOneWidget);
        await touch.up();
        await tester.pump(const Duration(milliseconds: 4900));
        expect(volume.hitTestable(), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 100));
        await _settlePlayer(tester);
        expect(volume.hitTestable(), findsNothing);

        await reveal();
        await tester.tap(queueButton.hitTestable());
        await _settlePlayer(tester);
        await tester.pump(const Duration(seconds: 6));
        expect(play.hitTestable(), findsOneWidget);
        expect(queueButton.hitTestable(), findsOneWidget);
        await tester.tap(queueButton.hitTestable());
        await _settlePlayer(tester);
        await tester.pump(const Duration(seconds: 6));
        expect(play.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final landscape in [false, true]) {
    testWidgets(
      'paused lyrics keep controls visible and resume gets five seconds (landscape: $landscape)',
      (tester) async {
        final playback = StreamController<PlaybackState>();
        addTearDown(playback.close);
        await _pumpNowPlaying(
          tester,
          theme: AppTheme.build(Brightness.dark),
          size: landscape ? const Size(852, 393) : const Size(393, 852),
          playbackEvents: playback.stream,
        );
        playback.add(PlaybackState(playing: false));
        mediaItems.add(_item('many'));
        await _settlePlayer(tester);
        final lyricsButton = find.byIcon(CupertinoIcons.quote_bubble);
        await tester.tap(lyricsButton);
        await _settlePlayer(tester);
        await tester.pump(const Duration(seconds: 6));
        expect(lyricsButton.hitTestable(), findsOneWidget);

        playback.add(PlaybackState(playing: true));
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 4900));
        expect(lyricsButton.hitTestable(), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 100));
        await _settlePlayer(tester);
        expect(lyricsButton.hitTestable(), findsNothing);

        playback.add(PlaybackState(playing: false));
        await _settlePlayer(tester);
        expect(lyricsButton.hitTestable(), findsOneWidget);
        await tester.pump(const Duration(seconds: 6));
        expect(lyricsButton.hitTestable(), findsOneWidget);

        // Pausing during the countdown must cancel the pending hide too.
        playback.add(PlaybackState(playing: true));
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 3));
        playback.add(PlaybackState(playing: false));
        await _settlePlayer(tester);
        await tester.pump(const Duration(seconds: 6));
        expect(lyricsButton.hitTestable(), findsOneWidget);

        playback.add(PlaybackState(playing: true));
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 4900));
        expect(lyricsButton.hitTestable(), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 100));
        await _settlePlayer(tester);
        expect(lyricsButton.hitTestable(), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'accessible navigation keeps lyric controls available while idle',
    (tester) async {
      await _pumpNowPlaying(
        tester,
        theme: AppTheme.build(Brightness.dark),
        size: const Size(393, 852),
        playback: PlaybackState(playing: true),
        wrapPlayer: (player) => Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(accessibleNavigation: true),
            child: player,
          ),
        ),
      );
      mediaItems.add(_item('many'));
      await _settlePlayer(tester);
      await tester.tap(find.byIcon(CupertinoIcons.quote_bubble));
      await _settlePlayer(tester);
      await tester.pump(const Duration(seconds: 6));
      expect(find.byType(AppVolumeControl).hitTestable(), findsOneWidget);
      expect(
        find.byIcon(CupertinoIcons.quote_bubble).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Sistrum player background does not reveal the page below', (
    tester,
  ) async {
    final background = ValueNotifier<Color>(Colors.white);
    addTearDown(background.dispose);
    final capture = GlobalKey();
    await _pumpNowPlaying(
      tester,
      theme: AppTheme.build(Brightness.light),
      size: const Size(393, 780),
      wrapPlayer: (player) => RepaintBoundary(
        key: capture,
        child: ValueListenableBuilder<Color>(
          valueListenable: background,
          child: player,
          builder: (context, color, child) => Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: color),
              child!,
            ],
          ),
        ),
      ),
    );
    mediaItems.add(_item('first'));
    await _settlePlayer(tester);

    Future<List<int>?> edgePixel() => tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(capture),
      );
      final image = await boundary.toImage();
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final offset = (image.width + 1) * 4;
      final pixel = List<int>.generate(4, (i) => bytes.getUint8(offset + i));
      image.dispose();
      return pixel;
    });

    final onWhite = await edgePixel();
    background.value = Colors.red;
    await _settlePlayer(tester);
    expect(await edgePixel(), onWhite);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Sistrum player menu floats above its button and retains dark colors',
    (tester) async {
      await _pumpNowPlaying(
        tester,
        theme: AppTheme.build(Brightness.light),
        size: const Size(393, 780),
      );
      mediaItems.add(_item('first'));
      await _settlePlayer(tester);
      final moreButton = find.byIcon(CupertinoIcons.ellipsis).hitTestable();
      final anchor = tester.getRect(moreButton);
      await tester.tap(moreButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final panel = find.byType(AppPlayerActionsSheet);
      final enteringWidth = tester.getSize(panel).width;
      await _settlePlayer(tester);
      expect(tester.getSize(panel).width, enteringWidth);
      expect(tester.getRect(panel).bottom, lessThan(anchor.top));
      expect(tester.getRect(panel).width, 280);
      expect(find.byType(BottomSheet), findsNothing);
      expect(Theme.of(tester.element(panel)).brightness, Brightness.dark);
      expect(
        tester.widget<Text>(find.text('Go to Album')).style?.color,
        Colors.white,
      );
      expect(find.byIcon(CupertinoIcons.square_stack), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.moon_zzz), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.gear_alt), findsNothing);
      expect(
        find.text(
          AppLocalizations.of(tester.element(panel)).collectionAddToPlaylist,
        ),
        findsOneWidget,
      );
      expect(find.text('Go to Artist'), findsOneWidget);
      expect(find.text('Favorite'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(tester.widget<Text>(find.text('Go to Album')).style?.fontSize, 16);
      await tester.ensureVisible(find.text('Sleep timer'));
      await tester.tap(find.text('Sleep timer'));
      await _settlePlayer(tester);
      expect(
        Theme.of(tester.element(find.text('15 minutes'))).brightness,
        Brightness.dark,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Sistrum title opens artist and album destinations with subtitles',
    (tester) async {
      await _pumpNowPlaying(
        tester,
        theme: AppTheme.build(Brightness.dark),
        size: const Size(393, 780),
      );
      mediaItems.add(_item('first'));
      await _settlePlayer(tester);
      await tester.tap(find.text('First').hitTestable());
      await _settlePlayer(tester);
      expect(find.text('Go to Artist'), findsOneWidget);
      expect(find.text('Go to Album'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppPlayerNavigationMenu),
          matching: find.text('Artist'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(AppPlayerNavigationMenu),
          matching: find.text('Album'),
        ),
        findsOneWidget,
      );
      await tester.tapAt(const Offset(5, 770));
      await _settlePlayer(tester);
      expect(find.byType(AppPlayerNavigationMenu), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
