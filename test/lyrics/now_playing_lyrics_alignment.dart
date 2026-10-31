part of 'now_playing_lyrics_transition_test.dart';

void _registerNowPlayingLyricsAlignment() {
  for (final reducedMotion in [false, true]) {
    testWidgets(
      'timed words lift and settle without moving layout (reduced motion: $reducedMotion)',
      (tester) async {
        const text = 'AAAA BBBB';
        metadataOverrides['lyrics'] =
            '[00:00.500]<00:01.000>AAAA <00:01.500>'
            '<00:03.000>BBBB<00:06.000>';
        final playback = StreamController<PlaybackState>.broadcast();
        addTearDown(playback.close);
        await _pumpNowPlaying(
          tester,
          theme: AppTheme.build(Brightness.dark),
          size: const Size(390, 844),
          playbackEvents: playback.stream,
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
        await _settlePlayer(tester);
        await tester.tap(find.byIcon(CupertinoIcons.quote_bubble));
        await _settlePlayer(tester);
        final paintFinder = find.descendant(
          of: find.bySemanticsLabel(text),
          matching: find.byType(CustomPaint),
        );

        Future<(double, double)> paintedHeights({
          bool firstWordLetters = false,
        }) async {
          final painter = tester.widget<CustomPaint>(paintFinder).painter!;
          final size = tester.getSize(paintFinder);
          return (await tester.runAsync(() async {
            final recorder = ui.PictureRecorder();
            final canvas = Canvas(recorder)..translate(0, 8);
            painter.paint(canvas, size);
            final picture = recorder.endRecording();
            final image = await picture.toImage(
              size.width.ceil(),
              size.height.ceil() + 16,
            );
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            double centerFor(int from, int to) {
              var top = image.height;
              var bottom = -1;
              for (var y = 0; y < image.height; y++) {
                for (var x = from; x < to; x++) {
                  if (bytes.getUint8((y * image.width + x) * 4 + 3) < 16) {
                    continue;
                  }
                  if (y < top) top = y;
                  if (y > bottom) bottom = y;
                }
              }
              expect(bottom, greaterThan(top));
              return (top + bottom) / 2;
            }

            final result = firstWordLetters
                ? (
                    centerFor(0, (image.width * 0.1).floor()),
                    centerFor(
                      (image.width * 0.31).ceil(),
                      (image.width * 0.39).floor(),
                    ),
                  )
                : (
                    centerFor(0, (image.width * 0.4).floor()),
                    centerFor((image.width * 0.6).ceil(), image.width),
                  );
            image.dispose();
            picture.dispose();
            return result;
          }))!;
        }

        Future<(double, double)> seek(int milliseconds) async {
          playback.add(
            PlaybackState(
              processingState: AudioProcessingState.ready,
              updatePosition: Duration(milliseconds: milliseconds),
            ),
          );
          await _settlePlayer(tester);
          return paintedHeights();
        }

        final pending = await seek(800);
        final bounds = tester.getRect(paintFinder);
        await seek(1300);
        final letters = await paintedHeights(firstWordLetters: true);
        expect(
          letters.$1,
          letters.$2,
          reason: 'Letters in one timed word must rise together',
        );
        final firstEnded = await seek(1900);
        expect(firstEnded.$2, pending.$2);
        if (reducedMotion) {
          expect(firstEnded, pending);
        } else {
          expect(pending.$1 - firstEnded.$1, inInclusiveRange(1, 2.5));
        }
        final held = await seek(5500);
        final settled = await seek(6000);
        expect(held.$1, firstEnded.$1);
        if (reducedMotion) {
          expect(held, pending);
          expect(settled, pending);
        } else {
          expect(settled.$2 - held.$2, greaterThan(0));
          expect(pending.$2 - settled.$2, inInclusiveRange(1, 2.5));
        }
        expect(tester.getRect(paintFinder), bounds);
        expect(await seek(5500), held);
        await tester.pump(const Duration(seconds: 1));
        expect(
          await paintedHeights(),
          held,
          reason: 'Paused words must stay still',
        );
        expect(await seek(800), pending);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('timed lyric fills text fragments in reading order', (
    tester,
  ) async {
    const lyricText = 'AAAA BBBB CCCC DDDD EEEE FFFF GGGG HHHH';
    metadataOverrides['lyrics'] =
        '<tt xmlns="http://www.w3.org/ns/ttml"><body><div>'
        '<p begin="00:00.000" end="00:08.000">'
        '<span begin="00:00.000">$lyricText</span>'
        '</p></div></body></tt>';
    await _pumpNowPlaying(
      tester,
      theme: AppTheme.build(Brightness.dark),
      size: const Size(320, 844),
      playback: PlaybackState(
        processingState: AudioProcessingState.ready,
        playing: false,
        updatePosition: const Duration(seconds: 2),
      ),
    );
    mediaItems.add(_item('first'));
    await _settlePlayer(tester);
    await tester.tap(find.byIcon(CupertinoIcons.quote_bubble));
    await _settlePlayer(tester);

    final paintFinder = find.descendant(
      of: find.bySemanticsLabel(lyricText),
      matching: find.byType(CustomPaint),
    );
    final painter = tester.widget<CustomPaint>(paintFinder).painter!;
    final size = tester.getSize(paintFinder);
    final highlightedPixels = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), size);
      final picture = recorder.endRecording();
      final image = await picture.toImage(
        size.width.ceil(),
        size.height.ceil(),
      );
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      var upper = 0;
      var lower = 0;
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          if (bytes.getUint8((y * image.width + x) * 4 + 3) < 230) continue;
          if (y < image.height ~/ 2) {
            upper++;
          } else {
            lower++;
          }
        }
      }
      image.dispose();
      picture.dispose();
      return (upper, lower);
    });
    expect(highlightedPixels!.$1, greaterThan(0));
    expect(highlightedPixels.$2, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('short timed lyric keeps its Sistrum leading alignment', (
    tester,
  ) async {
    await _pumpNowPlaying(tester);

    mediaItems.add(_item('timed'));
    await _settlePlayer(tester);
    await tester.tap(find.byIcon(CupertinoIcons.quote_bubble));
    await _settlePlayer(tester);

    final lyric = find.bySemanticsLabel('Short');
    expect(lyric, findsOneWidget);
    expect(tester.getRect(lyric).left, greaterThanOrEqualTo(24));
    expect(tester.getRect(lyric).left, lessThan(200));
  });

  testWidgets('Now Playing menu exposes Go to Album when album is known', (
    tester,
  ) async {
    await _pumpNowPlaying(tester);
    mediaItems.add(_item('first'));
    await _settlePlayer(tester);

    await tester.tap(find.byIcon(CupertinoIcons.ellipsis));
    await _settlePlayer(tester);

    expect(find.text('Go to Album'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.square_stack), findsOneWidget);
  });

  testWidgets('Now Playing menu exposes sleep timer duration choices', (
    tester,
  ) async {
    await _pumpNowPlaying(tester);
    mediaItems.add(_item('first'));
    await _settlePlayer(tester);

    await tester.tap(find.byIcon(CupertinoIcons.ellipsis));
    await _settlePlayer(tester);
    await tester.tap(find.text('Sleep timer'));
    await _settlePlayer(tester);

    expect(find.text('15 minutes'), findsOneWidget);
    expect(find.text('30 minutes'), findsOneWidget);
    expect(find.text('45 minutes'), findsOneWidget);
    expect(find.text('60 minutes'), findsOneWidget);
    expect(find.text('Turn off sleep timer'), findsNothing);
  });
}
