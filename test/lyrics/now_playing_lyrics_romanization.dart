part of 'now_playing_lyrics_transition_test.dart';

void _registerNowPlayingLyricsRomanization() {
  for (final sistrum in [true]) {
    testWidgets(
      'singers keep their side before and during overlapping vocals ($sistrum)',
      (tester) async {
        metadataOverrides['lyrics'] =
            '[x-romaji:2000:${base64.encode(utf8.encode('Guest reading'))}]\n'
            '[x-translation:2000:${base64.encode(utf8.encode('Guest translation'))}]\n'
            '[00:01.00]v1:<00:01.00>Lead<00:08.00>\n'
            '[00:02.00]v2:<00:02.00>Guest<00:06.00>';
        final playback = StreamController<PlaybackState>.broadcast();
        addTearDown(playback.close);
        await _pumpNowPlaying(
          tester,
          theme: sistrum ? AppTheme.build(Brightness.dark) : null,
          size: const Size(390, 1100),
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
        expect(
          tester.widget<Text>(find.text('Lead')).textAlign,
          TextAlign.start,
        );
        for (final text in ['Guest', 'Guest reading', 'Guest translation']) {
          expect(tester.widget<Text>(find.text(text)).textAlign, TextAlign.end);
        }
        expect(find.textContaining('v1:'), findsNothing);
        expect(find.textContaining('v2:'), findsNothing);

        Finder timed(String text) => find.descendant(
          of: find.byWidgetPredicate(
            (widget) => widget is Semantics && widget.properties.label == text,
          ),
          matching: find.byType(CustomPaint),
        );
        playback.add(
          PlaybackState(
            processingState: AudioProcessingState.ready,
            playing: false,
            updatePosition: const Duration(seconds: 3),
          ),
        );
        await _settlePlayer(tester);
        for (final text in ['Lead', 'Guest']) {
          final paint = timed(text);
          expect(
            paint,
            findsOneWidget,
            reason: 'Both overlapping parts stay highlighted',
          );
          final painter = tester.widget<CustomPaint>(paint).painter!;
          final size = tester.getSize(paint);
          final bounds = await tester.runAsync(() async {
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
            var left = image.width;
            var right = 0;
            for (var y = 0; y < image.height; y++) {
              for (var x = 0; x < image.width; x++) {
                if (bytes.getUint8((y * image.width + x) * 4 + 3) > 10) {
                  if (x < left) left = x;
                  if (x > right) right = x;
                }
              }
            }
            image.dispose();
            picture.dispose();
            return (left, right);
          });
          if (text == 'Lead') {
            expect(bounds!.$1, lessThan(5));
          } else {
            expect(bounds!.$2, greaterThan(size.width - 5));
          }
        }
        expect(
          tester.widget<Text>(find.text('Guest translation')).textAlign,
          TextAlign.end,
        );
        playback.add(
          PlaybackState(
            processingState: AudioProcessingState.ready,
            playing: false,
            updatePosition: const Duration(seconds: 7),
          ),
        );
        await _settlePlayer(tester);
        expect(timed('Guest'), findsOneWidget);
        expect(find.text('Lead'), findsNothing);
        playback.add(
          PlaybackState(
            processingState: AudioProcessingState.ready,
            playing: false,
            updatePosition: const Duration(seconds: 9),
          ),
        );
        await _settlePlayer(tester);
        expect(find.text('Lead'), findsOneWidget);
        expect(timed('Guest'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets('player shows original, romanization and English ($sistrum)', (
      tester,
    ) async {
      metadataOverrides['lyrics'] =
          '[x-romaji:1009:${base64.encode(utf8.encode('Romanized text'))}]\n'
          '[x-translation:1009:${base64.encode(utf8.encode('English text'))}]\n'
          '[00:01.01]Original text';
      await _pumpNowPlaying(
        tester,
        theme: sistrum ? AppTheme.build(Brightness.dark) : null,
        size: const Size(390, 844),
      );
      mediaItems.add(_item('first'));
      await _settlePlayer(tester);
      if (sistrum) {
        await tester.tap(find.byIcon(CupertinoIcons.quote_bubble));
      } else {
        await tester.tap(find.byIcon(CupertinoIcons.quote_bubble));
      }
      await _settlePlayer(tester);
      for (final text in ['Original text', 'Romanized text', 'English text']) {
        expect(find.text(text), findsOneWidget);
      }
      if (sistrum) {
        final pronunciation = tester.widget<Text>(find.text('Romanized text'));
        final translation = tester.widget<Text>(find.text('English text'));
        expect(pronunciation.style?.fontSize, 22);
        expect(pronunciation.style?.fontWeight, FontWeight.bold);
        expect(translation.style?.fontSize, 18);
      }
      expect(
        tester.getTopLeft(find.text('Romanized text')).dy,
        greaterThan(tester.getBottomLeft(find.text('Original text')).dy),
      );
      expect(
        tester.getTopLeft(find.text('English text')).dy,
        greaterThan(tester.getBottomLeft(find.text('Romanized text')).dy),
      );
      expect(tester.takeException(), isNull);
    });
    testWidgets(
      'lyric language toggles fade, resize and remember choices ($sistrum)',
      (tester) async {
        metadataOverrides['lyrics'] =
            '[x-romaji:1009:${base64.encode(utf8.encode('Romanized text'))}]\n'
            '[x-translation:1009:${base64.encode(utf8.encode('English text'))}]\n'
            '[00:01.009]Original text\n[00:10.000]Next line';
        Future<void> openPlayer(String id) async {
          await _pumpNowPlaying(
            tester,
            theme: sistrum ? AppTheme.build(Brightness.dark) : null,
            size: const Size(390, 844),
            playback: PlaybackState(
              processingState: AudioProcessingState.ready,
              updatePosition: const Duration(milliseconds: 1500),
            ),
          );
          mediaItems.add(_item(id));
          await _settlePlayer(tester);
          if (sistrum) {
            await tester.tap(find.byIcon(CupertinoIcons.quote_bubble));
          } else {
            await tester.tap(find.byIcon(CupertinoIcons.quote_bubble));
          }
          await _settlePlayer(tester);
        }

        final options = find.byKey(const ValueKey('lyrics-language-options'));
        Future<void> choose(String label) async {
          await tester.tap(options);
          await _settlePlayer(tester);
          await tester.tap(find.text(label));
          await tester.pump();
        }

        double gap() =>
            tester.getTopLeft(find.text('Next line')).dy -
            tester.getTopLeft(find.text('Original text')).dy;
        double pronunciationOpacity() => tester
            .widget<Opacity>(
              find
                  .ancestor(
                    of: find.text('Romanized text'),
                    matching: find.byType(Opacity),
                  )
                  .first,
            )
            .opacity;

        await openPlayer('first');
        final expandedGap = gap();
        await choose('Hide Pronunciation');
        await tester.pump(const Duration(milliseconds: 100));
        expect(pronunciationOpacity(), inExclusiveRange(0, 1));
        final intermediateGap = gap();
        expect(intermediateGap, lessThan(expandedGap));
        await _settlePlayer(tester);
        expect(find.text('Romanized text'), findsNothing);
        expect(find.text('English text'), findsOneWidget);
        expect(gap(), lessThan(intermediateGap));

        await choose('Show Pronunciation');
        await tester.pump(const Duration(milliseconds: 100));
        expect(pronunciationOpacity(), inExclusiveRange(0, 1));
        await _settlePlayer(tester);
        expect(gap(), closeTo(expandedGap, 1));
        await choose('Hide Translation');
        await _settlePlayer(tester);
        expect(find.text('English text'), findsNothing);
        expect(find.text('Romanized text'), findsOneWidget);
        await choose('Hide Pronunciation');
        await _settlePlayer(tester);
        expect(find.text('Original text'), findsOneWidget);
        expect(find.text('Romanized text'), findsNothing);
        expect(options.hitTestable(), findsOneWidget);

        await tester.pumpWidget(const SizedBox());
        await openPlayer('second');
        expect(find.text('English text'), findsNothing);
        expect(find.text('Romanized text'), findsNothing);
        await choose('Show Translation');
        await _settlePlayer(tester);
        expect(find.text('English text'), findsOneWidget);
        expect(find.text('Romanized text'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets('finished lyric stays bright until the next lead ($sistrum)', (
      tester,
    ) async {
      metadataOverrides['lyrics'] =
          '[00:01.00]v1:<00:01.00>Held<00:02.00>\n'
          '[00:07.00]v2:<00:07.00>Next<00:08.00>';
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
      for (final milliseconds in [1500, 2500, 6999, 7000, 8000, 6999]) {
        playback.add(
          PlaybackState(
            playing: false,
            processingState: AudioProcessingState.ready,
            updatePosition: Duration(milliseconds: milliseconds),
          ),
        );
        await _settlePlayer(tester);
        final text = milliseconds < 7000 ? 'Held' : 'Next';
        expect(timed(text), findsOneWidget);
        final opacity = tester.widget<AnimatedOpacity>(
          find
              .ancestor(of: timed(text), matching: find.byType(AnimatedOpacity))
              .first,
        );
        expect(opacity.opacity, 1, reason: 'At $milliseconds ms');
        expect(timed(text == 'Held' ? 'Next' : 'Held'), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
