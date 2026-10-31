part of 'now_playing_lyrics_transition_test.dart';

void _registerNowPlayingLyricsScrolling() {
  for (final height in [780.0, 520.0]) {
    testWidgets(
      'manual lyric scrolling keeps its viewport stable while controls animate (height: $height)',
      (tester) async {
        metadataOverrides['lyrics'] = List.generate(
          20,
          (index) =>
              '[00:${(index * 3).toString().padLeft(2, '0')}.00]Lyric $index with several words on this line',
        ).join('\n');
        await _pumpNowPlaying(
          tester,
          theme: AppTheme.build(Brightness.dark),
          size: Size(393, height),
          playback: PlaybackState(updatePosition: const Duration(seconds: 30)),
          glassLevel: 2,
        );
        mediaItems.add(_item('many'));
        await _settlePlayer(tester);
        await tester.tap(find.byIcon(CupertinoIcons.quote_bubble));
        await _settlePlayer(tester);
        final list = find.byType(ListView);
        final bounds = tester.getRect(list);
        void setClarity(int level) => unawaited(
          ProviderScope.containerOf(tester.element(list))
              .read(settingsProvider.notifier)
              .setGlassClarityLevel(level, persist: false),
        );
        final scrollable = find.descendant(
          of: list,
          matching: find.byType(Scrollable),
        );
        final state = tester.state<ScrollableState>(scrollable);
        final initialOffset = state.position.pixels;
        final headerTop = tester.getTopLeft(find.text('Second')).dy;
        final transport = find.byWidgetPredicate(
          (widget) =>
              widget is AppPlaybackButton &&
              const [
                CupertinoIcons.play_fill,
                CupertinoIcons.backward_fill,
                CupertinoIcons.forward_fill,
              ].contains(widget.icon),
        );
        expect(transport.hitTestable(), findsNWidgets(3));
        final touch = await tester.startGesture(
          Offset(bounds.center.dx, bounds.top + 100),
        );
        await touch.moveBy(const Offset(0, -20));
        await tester.pump();
        await touch.moveBy(const Offset(0, -60));
        await tester.pump();
        final hiddenOffset = state.position.pixels;
        expect(hiddenOffset, greaterThan(initialOffset));
        expect(transport.hitTestable(), findsNothing);
        // An appearance update must not reset playback following while the
        // user owns the scroll position.
        setClarity(3);
        await tester.pump();
        await tester.pump();
        expect(state.position.pixels, closeTo(hiddenOffset, 0.01));
        for (var frame = 0; frame < 3; frame++) {
          await tester.pump(const Duration(milliseconds: 40));
          expect(tester.getRect(list), bounds);
          expect(tester.state<ScrollableState>(scrollable), same(state));
          expect(state.position.pixels, closeTo(hiddenOffset, 0.01));
        }

        // A held drag must not expire the manual-scroll pause, even if the
        // finger has not changed direction for longer than its idle timeout.
        await tester.pump(const Duration(seconds: 5));
        await tester.pump(const Duration(milliseconds: 400));
        expect(state.position.pixels, closeTo(hiddenOffset, 0.01));

        // Continue the same drag and reverse while controls reappear.
        await touch.moveBy(const Offset(0, -32));
        await tester.pump();
        expect(state.position.pixels, closeTo(hiddenOffset + 32, 0.01));
        await touch.moveBy(const Offset(0, 48));
        await tester.pump();
        final restoredOffset = state.position.pixels;
        expect(restoredOffset, closeTo(hiddenOffset - 16, 0.01));
        for (var frame = 0; frame < 10; frame++) {
          await tester.pump(const Duration(milliseconds: 40));
          expect(tester.getRect(list), bounds);
          expect(tester.state<ScrollableState>(scrollable), same(state));
          expect(state.position.pixels, closeTo(restoredOffset, 0.01));
        }
        expect(tester.getTopLeft(find.text('Second')).dy, headerTop);
        expect(transport.hitTestable(), findsNWidgets(3));
        await touch.up();
        await _settlePlayer(tester);
        final releasedOffset = state.position.pixels;
        setClarity(2);
        await tester.pump();
        await _settlePlayer(tester);
        expect(state.position.pixels, closeTo(releasedOffset, 0.01));
        await tester.pump(const Duration(seconds: 3));

        // Starting another drag cancels the previous idle timeout. It must
        // remain paused through further scrolling in the same direction.
        final nextTouch = await tester.startGesture(
          Offset(bounds.center.dx, bounds.top + 100),
        );
        await nextTouch.moveBy(const Offset(0, -20));
        await tester.pump();
        await nextTouch.moveBy(const Offset(0, -40));
        await tester.pump();
        final nextOffset = state.position.pixels;
        await tester.pump(const Duration(seconds: 5));
        await tester.pump(const Duration(milliseconds: 400));
        expect(state.position.pixels, closeTo(nextOffset, 0.01));
        await nextTouch.up();
        await _settlePlayer(tester);
        await tester.pump(const Duration(seconds: 4));
        await _settlePlayer(tester);
        expect(state.position.pixels, closeTo(initialOffset, 0.01));
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      },
    );
  }

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
}
