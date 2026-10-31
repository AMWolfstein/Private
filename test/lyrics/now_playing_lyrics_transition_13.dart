part of 'now_playing_lyrics_transition_test.dart';

void _registerNowPlayingLyricsTransition13() {
  for (final sistrum in [true]) {
    testWidgets(
      'original and romanization follow word timing and pauses ($sistrum)',
      (tester) async {
        final romanizationWords = base64.encode(
          utf8.encode(
            jsonEncode([
              {'text': 'Firsu ', 'startTimeMs': 1009, 'endTimeMs': 1307},
              {'text': 'secondu', 'startTimeMs': 2003, 'endTimeMs': 2497},
            ]),
          ),
        );
        metadataOverrides['lyrics'] =
            '[x-romaji:1009:${base64.encode(utf8.encode('Firsu secondu'))}]\n'
            '[x-romaji-words:1009:$romanizationWords]\n'
            '[00:01.009]<00:01.009>First <00:01.307>'
            '<00:02.003>second<00:02.497>';
        final playback = StreamController<PlaybackState>.broadcast();
        addTearDown(playback.close);
        await _pumpNowPlaying(
          tester,
          theme: sistrum ? AppTheme.build(Brightness.dark) : null,
          size: const Size(390, 844),
          playbackEvents: playback.stream,
        );
        mediaItems.add(_item('first'));
        await _settlePlayer(tester);
        if (sistrum) {
          await tester.tap(find.byIcon(CupertinoIcons.quote_bubble));
        } else {
          await tester.tap(find.byIcon(CupertinoIcons.quote_bubble));
        }
        await _settlePlayer(tester);

        Future<List<int>> pixelsAt(int milliseconds, String text) async {
          playback.add(
            PlaybackState(
              processingState: AudioProcessingState.ready,
              playing: false,
              updatePosition: Duration(milliseconds: milliseconds),
            ),
          );
          await _settlePlayer(tester);
          final pixels = <int>[];
          for (final phrase in sistrum ? text.split(' ') : [text]) {
            final paint = find.descendant(
              of: find.byWidgetPredicate(
                (widget) =>
                    widget is Semantics && widget.properties.label == phrase,
              ),
              matching: find.byType(CustomPaint),
            );
            expect(
              paint,
              findsOneWidget,
              reason: '$phrase at $milliseconds ms',
            );
            final painter = tester.widget<CustomPaint>(paint).painter!;
            final size = tester.getSize(paint);
            pixels.addAll(
              (await tester.runAsync(() async {
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
                final result = bytes.buffer.asUint8List().toList();
                image.dispose();
                picture.dispose();
                return result;
              }))!,
            );
          }
          return pixels;
        }

        for (final text in ['First second', 'Firsu secondu']) {
          final singingFirst = await pixelsAt(1100, text);
          final moves = sistrum && text == 'First second';
          final firstEnded = await pixelsAt(moves ? 1800 : 1307, text);
          expect(firstEnded, isNot(orderedEquals(singingFirst)));
          if (moves) {
            expect(
              await pixelsAt(1307, text),
              isNot(orderedEquals(firstEnded)),
              reason: 'Movement trails the finished color sweep',
            );
          }
          expect(await pixelsAt(1820, text), orderedEquals(firstEnded));
          final singingLast = await pixelsAt(2150, text);
          final lastEnded = await pixelsAt(moves ? 3100 : 2497, text);
          expect(lastEnded, isNot(orderedEquals(singingLast)));
          expect(await pixelsAt(3400, text), orderedEquals(lastEnded));
          expect(await pixelsAt(1100, text), orderedEquals(singingFirst));
        }
        final originalPixels = await pixelsAt(1100, 'First second');
        final options = find.byKey(const ValueKey('lyrics-language-options'));
        if (sistrum && options.hitTestable().evaluate().isEmpty) {
          final bounds = tester.getRect(find.byType(ListView));
          await tester.tapAt(Offset(bounds.right - 6, bounds.top + 10));
          await _settlePlayer(tester);
        }
        await tester.tap(options);
        await _settlePlayer(tester);
        await tester.tap(find.text('Hide Pronunciation'));
        await _settlePlayer(tester);
        expect(find.bySemanticsLabel('Firsu secondu'), findsNothing);
        expect(
          await pixelsAt(1100, 'First second'),
          orderedEquals(originalPixels),
        );
        await tester.tap(options);
        await _settlePlayer(tester);
        await tester.tap(find.text('Show Pronunciation'));
        await _settlePlayer(tester);
        await pixelsAt(2150, 'Firsu secondu');
        expect(tester.takeException(), isNull);
      },
    );
  }

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
}
