part of 'now_playing_lyrics_transition_test.dart';

void _registerNowPlayingLyricsTransition2() {
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

  for (final size in [const Size(393, 852), const Size(768, 1024)]) {
    for (final reducedMotion in [false, true]) {
      testWidgets(
        'slider scrubs lyrics both ways before seeking (size: $size, reduced motion: $reducedMotion)',
        (tester) async {
          metadataOverrides['lyrics'] = List.generate(
            18,
            (index) =>
                '[${(index ~/ 6).toString().padLeft(2, '0')}:'
                '${(index % 6 * 10).toString().padLeft(2, '0')}.00]'
                'Line $index with enough words to wrap across several rows',
          ).join('\n');
          final playback = StreamController<PlaybackState>.broadcast();
          addTearDown(playback.close);
          final controller = _SeekController();
          await _pumpNowPlaying(
            tester,
            theme: AppTheme.build(Brightness.dark),
            size: size,
            playbackEvents: playback.stream,
            controller: controller,
            wrapPlayer: (player) => Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(disableAnimations: reducedMotion),
                child: player,
              ),
            ),
          );
          mediaItems.add(_item('first'));
          playback.add(
            PlaybackState(updatePosition: const Duration(seconds: 1)),
          );
          await _settlePlayer(tester);
          await tester.tap(find.byIcon(CupertinoIcons.quote_bubble));
          await _settlePlayer(tester);
          final slider = find.descendant(
            of: find.byType(PlaybackSeekSlider),
            matching: find.byType(Slider),
          );
          final bounds = tester.getRect(slider);
          Offset point(double fraction) => Offset(
            bounds.left + 8 + (bounds.width - 16) * fraction,
            bounds.center.dy,
          );
          final list = find.byType(ListView);
          double offset() => tester.widget<ListView>(list).controller!.offset;
          void expectFocus() {
            final seconds = tester.widget<Slider>(slider).value / 1000;
            final index = seconds ~/ 10;
            final line = find.text(
              'Line $index with enough words to wrap across several rows',
            );
            final focus = (size.height * 0.06).clamp(16, 48);
            expect(
              tester.getTopLeft(line).dy,
              closeTo(tester.getTopLeft(list).dy + focus + 16, 2),
            );
            final label = tester.widget<AppPlaybackTime>(
              find.byKey(const ValueKey('elapsed:first')),
            );
            expect(label.seconds, seconds.floor());
          }

          final gesture = await tester.startGesture(point(0.02));
          await _settlePlayer(tester);
          final initial = offset();
          await gesture.moveTo(point(0.82));
          await tester.pump();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 70));
          final intermediate = offset();
          expect(intermediate, greaterThan(initial));
          await _settlePlayer(tester);
          if (!reducedMotion) expect(offset(), greaterThan(intermediate));
          expectFocus();
          expect(controller.seeks, isEmpty);

          final forward = offset();
          await gesture.moveTo(point(0.19));
          await tester.pump();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 70));
          expect(offset(), lessThan(forward));
          await _settlePlayer(tester);
          expectFocus();
          final held = offset();
          // Neither playback ticks nor the automatic next-line timer may
          // move the user's preview while the finger is still down.
          playback.add(
            PlaybackState(
              processingState: AudioProcessingState.ready,
              playing: true,
              updatePosition: const Duration(seconds: 151),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(seconds: 10));
          expect(offset(), closeTo(held, 0.01));
          expectFocus();
          expect(controller.seeks, isEmpty);

          await gesture.up();
          await tester.pump();
          expect(controller.seeks, hasLength(1));
          playback.add(PlaybackState(updatePosition: controller.seeks.single));
          await tester.pump();
          controller.completions.single.complete();
          await _settlePlayer(tester);
          expect(offset(), closeTo(held, 0.01));
          expectFocus();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
