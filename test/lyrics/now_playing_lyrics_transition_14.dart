part of 'now_playing_lyrics_transition_test.dart';

void _registerNowPlayingLyricsTransition14() {
  for (final sistrum in [true]) {
    testWidgets('an unfinished line holds the view while the next starts '
        '($sistrum)', (tester) async {
      metadataOverrides['lyrics'] =
          '[00:01.00]<00:01.00>Long <00:02.00>held<00:06.00>\n'
          '[00:04.00]<00:04.00>Next<00:05.00>\n'
          '[00:09.00]<00:09.00>Later<00:10.00>';
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
      await tester.tap(
        sistrum
            ? find.byIcon(CupertinoIcons.quote_bubble)
            : find.byIcon(CupertinoIcons.quote_bubble),
      );
      await _settlePlayer(tester);

      Finder timed(String text) => find.descendant(
        of: find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.label == text,
        ),
        matching: find.byType(CustomPaint),
      );
      Future<void> seek(int milliseconds) async {
        playback.add(
          PlaybackState(
            playing: false,
            processingState: AudioProcessingState.ready,
            updatePosition: Duration(milliseconds: milliseconds),
          ),
        );
        await _settlePlayer(tester);
      }

      await seek(3500);
      final held = tester.getTopLeft(timed('Long held')).dy;
      await seek(4500);
      // Both lines keep their word sweep, and the view does not move.
      expect(timed('Long held'), findsOneWidget);
      expect(timed('Next'), findsOneWidget);
      expect(tester.getTopLeft(timed('Long held')).dy, held);
      await seek(6500);
      expect(timed('Long held'), findsNothing);
      expect(timed('Next'), findsOneWidget);
      expect(tester.getTopLeft(timed('Next')).dy, lessThan(held + 1));
      expect(tester.takeException(), isNull);
    });
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
}
