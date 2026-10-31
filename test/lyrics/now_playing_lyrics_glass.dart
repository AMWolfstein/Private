part of 'now_playing_lyrics_transition_test.dart';

void _registerNowPlayingLyricsGlass() {
  testWidgets('custom glass keeps live lyrics under the finger on reversal', (
    tester,
  ) async {
    metadataOverrides['lyrics'] = List.generate(
      20,
      (index) =>
          '[00:${(index * 3).toString().padLeft(2, '0')}.00]Live lyric $index with several words on this line',
    ).join('\n');
    final playback = StreamController<PlaybackState>.broadcast();
    addTearDown(playback.close);
    await _pumpNowPlaying(
      tester,
      theme: AppTheme.build(Brightness.dark),
      glassLevel: 2,
      size: const Size(393, 852),
      playbackEvents: playback.stream,
    );
    mediaItems.add(_item('many'));
    playback.add(
      PlaybackState(
        playing: true,
        processingState: AudioProcessingState.ready,
        updatePosition: const Duration(seconds: 30),
      ),
    );
    await _settlePlayer(tester);
    await tester.tap(find.byIcon(CupertinoIcons.quote_bubble));
    await _settlePlayer(tester);
    final list = find.byType(ListView);
    final bounds = tester.getRect(list);
    final scroll = tester.widget<ListView>(list).controller!;
    final initial = scroll.offset;
    final pause = find.widgetWithIcon(
      AppPlaybackButton,
      CupertinoIcons.pause_fill,
    );
    final touch = await tester.startGesture(
      Offset(bounds.center.dx, bounds.top + 180),
    );
    await touch.moveBy(const Offset(0, -20));
    await tester.pump();
    await touch.moveBy(const Offset(0, -100));
    await tester.pump();
    final hidden = scroll.offset;
    expect(hidden, greaterThan(initial));
    expect(pause.hitTestable(), findsNothing);

    playback.add(
      PlaybackState(
        playing: true,
        processingState: AudioProcessingState.ready,
        updatePosition: const Duration(seconds: 33),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(scroll.offset, closeTo(hidden, 0.01));
    await touch.moveBy(const Offset(0, 24));
    await tester.pump();
    expect(scroll.offset, closeTo(hidden - 24, 0.01));
    expect(pause.hitTestable(), findsOneWidget);
    for (var frame = 0; frame < 15; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(scroll.offset, closeTo(hidden - 24, 0.01));
      expect(tester.getRect(list), bounds);
    }
    await touch.up();
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  for (final reducedMotion in [false, true]) {
    testWidgets(
      'static cover shrinks on pause without moving controls (reduced motion: $reducedMotion)',
      (tester) async {
        const longTitle =
            'I Do Not Want to Talk About It (A Long Album Version)';
        tester.view.padding = FakeViewPadding(top: 59, bottom: 34);
        tester.view.viewPadding = FakeViewPadding(top: 59, bottom: 34);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewPadding);
        final playbackEvents = StreamController<PlaybackState>.broadcast();
        addTearDown(playbackEvents.close);
        await _pumpNowPlaying(
          tester,
          theme: AppTheme.build(Brightness.dark),
          size: const Size(393, 852),
          playbackEvents: playbackEvents.stream,
          wrapPlayer: (player) => Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(disableAnimations: reducedMotion),
              child: player,
            ),
          ),
        );
        mediaItems.add(_item('first').copyWith(title: longTitle));
        await _settlePlayer(tester);
        playbackEvents.add(PlaybackState(playing: true));
        await _settlePlayer(tester);

        final cover = find.byKey(const ValueKey('full-player-artwork'));
        final playingCover = tester.getRect(cover);
        final titleFinder = find
            .text(longTitle)
            .hitTestable(at: Alignment.centerLeft)
            .first;
        final title = tester.getRect(titleFinder);
        final volume = tester.getRect(find.byType(AppVolumeControl));
        expect(playingCover.width, playingCover.height);
        expect(playingCover.width, greaterThanOrEqualTo(393 * 0.84));
        expect(playingCover.left, greaterThan(0));
        expect(playingCover.bottom, lessThan(title.top));
        expect(
          find.descendant(
            of: find.byType(AppPlayerBackground),
            matching: cover,
          ),
          findsNothing,
        );

        playbackEvents.add(PlaybackState(playing: false));
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));
        if (!reducedMotion) {
          expect(
            tester.getRect(cover).width,
            inExclusiveRange(playingCover.width * 0.73, playingCover.width),
          );
        }
        await _settlePlayer(tester);
        final pausedCover = tester.getRect(cover);
        expect(pausedCover.width, closeTo(playingCover.width * 0.73, 0.01));
        expect(pausedCover.center.dx, closeTo(playingCover.center.dx, 0.01));
        expect(pausedCover.center.dy, closeTo(playingCover.center.dy, 0.01));
        expect(tester.getRect(titleFinder), title);
        expect(tester.getRect(find.byType(AppVolumeControl)), volume);

        playbackEvents.add(PlaybackState(playing: true));
        await _settlePlayer(tester);
        expect(tester.getRect(cover).width, closeTo(playingCover.width, 0.01));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'Sistrum lyrics keep wrapped, first and last lines at upper focus',
    (tester) async {
      final lyrics = List.generate(100, (index) {
        final seconds = index * 2;
        final time =
            '${(seconds ~/ 60).toString().padLeft(2, '0')}:'
            '${(seconds % 60).toString().padLeft(2, '0')}.00';
        return '[$time]Line $index with enough words to wrap across several rows';
      }).join('\n');
      metadataOverrides = {'lyrics': lyrics};
      final playback = StreamController<PlaybackState>();
      addTearDown(playback.close);
      await _pumpNowPlaying(
        tester,
        theme: AppTheme.build(Brightness.dark),
        size: const Size(393, 780),
        playbackEvents: playback.stream,
      );
      mediaItems.add(_item('many'));
      playback.add(PlaybackState(updatePosition: const Duration(seconds: 140)));
      await _settlePlayer(tester);
      await tester.tap(find.byIcon(CupertinoIcons.quote_bubble));
      await _settlePlayer(tester);
      final current = find.text(
        'Line 70 with enough words to wrap across several rows',
      );
      expect(current, findsOneWidget);
      final list = find.byType(ListView);
      void expectUpperFocus(Finder line) {
        final bounds = tester.getRect(line);
        final viewport = tester.getRect(list);
        expect(bounds.top, closeTo(viewport.top + 16 + 780 * 0.06, 2));
      }

      expectUpperFocus(current);
      await tester.drag(list, const Offset(0, 200));
      await _settlePlayer(tester);
      await tester.tap(find.byIcon(CupertinoIcons.quote_bubble));
      await _settlePlayer(tester);
      await tester.tap(find.byIcon(CupertinoIcons.quote_bubble));
      await _settlePlayer(tester);
      expectUpperFocus(current);
      for (final index in [99, 0]) {
        playback.add(
          PlaybackState(updatePosition: Duration(seconds: index * 2)),
        );
        await _settlePlayer(tester);
        expectUpperFocus(
          find.text(
            'Line $index with enough words to wrap across several rows',
          ),
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [393.0, 768.0]) {
    testWidgets('Sistrum lyrics fit the timeline without rewrapping ($width)', (
      tester,
    ) async {
      const original =
          'A longer lyric with words that already wrap onto another row';
      const pronunciation = 'Pronunciation follows the same layout as before';
      const translation =
          'The translated words also keep their existing line breaks';
      metadataOverrides['lyrics'] =
          '[x-romaji:1000:${base64.encode(utf8.encode(pronunciation))}]\n'
          '[x-translation:1000:${base64.encode(utf8.encode(translation))}]\n'
          '[00:01.000]$original\n[00:15.000]Next line';
      await _pumpNowPlaying(
        tester,
        theme: AppTheme.build(Brightness.dark),
        size: Size(width, 1024),
        playback: PlaybackState(updatePosition: const Duration(seconds: 2)),
      );
      mediaItems.add(_item('first'));
      await _settlePlayer(tester);
      await tester.tap(find.byIcon(CupertinoIcons.quote_bubble));
      await _settlePlayer(tester);

      final track = _seekTrackBounds(tester);
      for (final text in [original, pronunciation, translation]) {
        final finder = find.text(text);
        final paragraph = tester.renderObject<RenderParagraph>(finder);
        final previousLayout = TextPainter(
          text: paragraph.text,
          textDirection: paragraph.textDirection,
          textAlign: paragraph.textAlign,
          textScaler: paragraph.textScaler,
          locale: paragraph.locale,
        )..layout(maxWidth: width - 48);
        final selection = TextSelection(
          baseOffset: 0,
          extentOffset: text.length,
        );
        expect(
          paragraph.getBoxesForSelection(selection).map((box) => box.toRect()),
          previousLayout
              .getBoxesForSelection(selection)
              .map((box) => box.toRect()),
        );
        final bounds = tester.getRect(finder);
        expect(bounds.left, closeTo(track.left, 0.01));
        expect(bounds.right, closeTo(track.right, 0.01));
        expect(bounds.height, lessThan(previousLayout.height));
        previousLayout.dispose();
      }
      expect(tester.takeException(), isNull);
    });
  }
}
