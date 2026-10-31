part of 'now_playing_lyrics_transition_test.dart';

void _registerNowPlayingLyricsTransition8() {
  testWidgets(
    'player view switches live without duplicate artwork or lost controls',
    (tester) async {
      await _pumpNowPlaying(
        tester,
        theme: AppTheme.build(Brightness.dark),
        size: const Size(393, 852),
        playerView: PlayerView.immersive,
      );
      mediaItems.add(_item('first'));
      await _settlePlayer(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(NowPlayingScreen)),
      );
      final full = find.byKey(const ValueKey('full-player-artwork'));
      final notifier = container.read(themeProvider.notifier);
      await notifier.setPlayerView(PlayerView.normal);
      await _settlePlayer(tester);
      expect(full, findsOneWidget);
      expect(tester.getRect(full).left, greaterThan(0));
      await notifier.setPlayerView(PlayerView.immersive);
      await tester.pump(const Duration(milliseconds: 80));
      await notifier.setPlayerView(PlayerView.normal);
      await tester.pump(const Duration(milliseconds: 80));
      await notifier.setPlayerView(PlayerView.immersive);
      await _settlePlayer(tester);
      expect(full, findsOneWidget);
      expect(tester.getRect(full).width, 393);
      expect(find.byType(PlaybackSeekSlider).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [
    const Size(393, 852),
    const Size(393, 620),
    const Size(852, 393),
  ]) {
    testWidgets(
      'saved immersive view fills artwork and keeps controls ($size)',
      (tester) async {
        await _pumpNowPlaying(
          tester,
          theme: AppTheme.build(Brightness.dark),
          size: size,
          playerView: PlayerView.immersive,
          playback: PlaybackState(playing: false),
        );
        mediaItems.add(_item('first'));
        await _settlePlayer(tester);
        final full = find.byKey(const ValueKey('full-player-artwork'));
        if (size.width < size.height) {
          final bounds = tester.getRect(full);
          expect(bounds.left, 0);
          expect(bounds.top, 0);
          expect(bounds.width, size.width);
          expect(
            bounds.height,
            closeTo(
              size.width / (size.width / (size.height * .56)).clamp(.5, 1.0),
              .01,
            ),
          );
          expect(
            find.descendant(
              of: find.byType(AppPlayerBackground),
              matching: full,
            ),
            findsOneWidget,
          );
        } else {
          expect(tester.getRect(full).width, lessThan(size.width));
        }
        expect(find.byType(PlaybackSeekSlider).hitTestable(), findsOneWidget);
        await tester.tap(
          find.byIcon(CupertinoIcons.quote_bubble).hitTestable(),
        );
        await _settlePlayer(tester);
        expect(find.text('First lyric').hitTestable(), findsOneWidget);
        if (size.width < size.height) {
          await tester.tap(
            find.byKey(const ValueKey('compact-player-artwork')),
          );
          await tester.pump(const Duration(milliseconds: 80));
          await tester.tap(
            find.byIcon(CupertinoIcons.quote_bubble).hitTestable(),
          );
          await tester.pump(const Duration(milliseconds: 80));
          await tester.tap(
            find.byKey(const ValueKey('compact-player-artwork')),
          );
          await _settlePlayer(tester);
          expect(tester.getRect(full).width, size.width);
          await tester.tap(
            find.byIcon(CupertinoIcons.list_bullet).hitTestable(),
          );
          await _settlePlayer(tester);
          expect(find.byType(AppPlayerQueue).hitTestable(), findsOneWidget);
          await tester.tap(
            find.byKey(const ValueKey('compact-player-artwork')),
          );
          await _settlePlayer(tester);
        }
        mediaItems.add(_item('second'));
        await _settlePlayer(tester);
        expect(find.text('Second').hitTestable(), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final view in PlayerView.values) {
    for (final drag in [false, true]) {
      testWidgets(
        'Sistrum minimizes into the current mini player ($view, drag: $drag)',
        (tester) async {
          await _pumpNowPlaying(
            tester,
            theme: AppTheme.build(Brightness.dark),
            playerView: view,
            size: const Size(393, 852),
            playback: PlaybackState(playing: true),
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
          final mini = find.byType(MiniPlayer);
          final miniCover = find.descendant(
            of: mini,
            matching: find.byType(Hero),
          );
          final destination = tester.getRect(miniCover);
          await tester.tap(
            find.descendant(of: mini, matching: find.text('First')),
          );
          await _settlePlayer(tester);
          final player = find.byType(NowPlayingScreen);
          final route =
              ModalRoute.of(tester.element(player))! as NowPlayingRoute;
          final fullCover = find.byKey(const ValueKey('full-player-artwork'));
          if (drag) {
            route.startDrag();
            route.updateDrag(
              DragUpdateDetails(
                globalPosition: const Offset(0, 300),
                delta: const Offset(0, 300),
                primaryDelta: 300,
              ),
              852,
            );
            await tester.pump();
          }
          final releasedCover = tester.getRect(fullCover);
          final releasedPanel = tester.getRect(
            find.byType(AppPlayerBackground),
          );
          if (drag) {
            route.endDrag(DragEndDetails(primaryVelocity: 0), 852);
          } else {
            Navigator.of(tester.element(player)).pop();
          }
          await tester.pump();
          final flyingCover = find.byKey(
            const ValueKey('player-minimize-artwork'),
          );
          final surface = find.byKey(const ValueKey('player-minimize-surface'));
          expect(tester.getRect(flyingCover), releasedCover);
          expect(tester.getRect(surface), releasedPanel);
          var previousDistance =
              (releasedCover.center - destination.center).distance;
          for (var frame = 0; frame < 5; frame++) {
            await tester.pump(const Duration(milliseconds: 25));
            final bounds = tester.getRect(flyingCover);
            final distance = (bounds.center - destination.center).distance;
            expect(distance, lessThan(previousDistance));
            expect(
              bounds.width,
              inExclusiveRange(destination.width, releasedCover.width),
            );
            previousDistance = distance;
          }
          await _settlePlayer(tester);
          expect(player, findsNothing);
          expect(tester.getRect(miniCover), destination);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final lyrics in [true, false]) {
    testWidgets(
      'one header travels to and from ${lyrics ? 'lyrics' : 'queue'} beside the cover',
      (tester) async {
        await _pumpNowPlaying(
          tester,
          theme: AppTheme.build(Brightness.dark),
          size: const Size(393, 852),
        );
        mediaItems.add(_item('first'));
        await _settlePlayer(tester);
        final toggle = find.byIcon(
          lyrics ? CupertinoIcons.quote_bubble : CupertinoIcons.list_bullet,
        );
        final header = find.byKey(const ValueKey('player-track-header'));
        final element = tester.element(header);
        final expandedBounds = tester.getRect(header);
        final play = find.widgetWithIcon(
          AppPlaybackButton,
          CupertinoIcons.play_fill,
        );
        final controlsBounds = tester.getRect(play);
        final favorite = find.byType(AppPlayerFavoriteButton);
        final favoriteState = tester.state(favorite);
        for (var visit = 0; visit < 2; visit++) {
          await tester.tap(toggle);
          await tester.pump();
          expect(tester.getRect(header), expandedBounds);
          var previous = expandedBounds;
          for (var frame = 0; frame < 3; frame++) {
            await tester.pump(const Duration(milliseconds: 80));
            final bounds = tester.getRect(header);
            expect(bounds.top, lessThan(previous.top));
            expect(bounds.left, greaterThan(previous.left));
            expect(header.hitTestable(), findsOneWidget);
            expect(tester.element(header), same(element));
            expect(tester.state(favorite), same(favoriteState));
            expect(tester.getRect(play), controlsBounds);
            previous = bounds;
          }
          await _settlePlayer(tester);
          final cover = tester.getRect(
            find.byKey(const ValueKey('compact-player-artwork')),
          );
          final compactBounds = tester.getRect(header);
          expect(compactBounds.left, cover.right + 12);
          expect(compactBounds.center.dy, cover.center.dy);
          final track = _seekTrackBounds(tester);
          expect(cover.left, closeTo(track.left, 0.01));
          final more = find.descendant(
            of: header,
            matching: find.byIcon(CupertinoIcons.ellipsis),
          );
          expect(tester.getRect(more).right, closeTo(track.right, 0.01));
          final moreButton = find.ancestor(
            of: more,
            matching: find.byType(IconButton),
          );
          expect(tester.getSize(moreButton), const Size(48, 48));
          await tester.tap(toggle);
          await tester.pump();
          expect(tester.getRect(header), compactBounds);
          previous = compactBounds;
          for (var frame = 0; frame < 3; frame++) {
            await tester.pump(const Duration(milliseconds: 80));
            final bounds = tester.getRect(header);
            expect(bounds.top, greaterThan(previous.top));
            expect(bounds.left, lessThan(previous.left));
            expect(header.hitTestable(), findsOneWidget);
            expect(tester.element(header), same(element));
            expect(tester.state(favorite), same(favoriteState));
            expect(tester.getRect(play), controlsBounds);
            previous = bounds;
          }
          await _settlePlayer(tester);
          expect(tester.getRect(header), expandedBounds);
          expect(
            find.byKey(const ValueKey('full-player-artwork')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  for (final playing in [false, true]) {
    testWidgets(
      'tapping the lyrics cover returns to its resting size (playing: $playing)',
      (tester) async {
        await _pumpNowPlaying(
          tester,
          theme: AppTheme.build(Brightness.dark),
          size: const Size(393, 852),
          playback: PlaybackState(
            playing: playing,
            processingState: AudioProcessingState.ready,
            updatePosition: const Duration(seconds: 2),
          ),
        );
        mediaItems.add(_item('first'));
        await _settlePlayer(tester);
        final artwork = find.byKey(const ValueKey('full-player-artwork'));
        final restingBounds = tester.getRect(artwork);
        final lyrics = find.byIcon(CupertinoIcons.quote_bubble);
        final compact = find.byKey(const ValueKey('compact-player-artwork'));
        await tester.tap(lyrics);
        await _settlePlayer(tester);
        final compactBounds = tester.getRect(compact);
        await tester.tap(compact);
        await tester.pump();
        expect(tester.getRect(artwork), compactBounds);
        var previous = compactBounds;
        for (var frame = 0; frame < 4; frame++) {
          await tester.pump(const Duration(milliseconds: 80));
          final bounds = tester.getRect(artwork);
          expect(bounds.width, greaterThan(previous.width));
          expect(bounds.width, lessThanOrEqualTo(restingBounds.width));
          expect(tester.getRect(compact), bounds);
          previous = bounds;
        }
        await _settlePlayer(tester);
        expect(tester.getRect(artwork), restingBounds);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
