part of 'now_playing_lyrics_transition_test.dart';

void _registerNowPlayingLyricsTransition11() {
  for (final sistrum in [true]) {
    testWidgets(
      'TTML V3 without group metadata keeps the primary side ($sistrum)',
      (tester) async {
        metadataOverrides['lyrics'] = '''
  <tt xmlns="http://www.w3.org/ns/ttml" xmlns:m="http://www.w3.org/ns/ttml#metadata">
  <head><metadata><m:agent xml:id="v1" type="person"/><m:agent xml:id="v3" type="person"/><m:agent xml:id="v2" type="person"/></metadata></head>
  <body><p begin="1s" end="3s" m:agent="v2">Guest</p><p begin="3s" end="6s" m:agent="v3">Together</p><p begin="6s" end="9s" m:agent="v2">Guest returns</p></body></tt>
  ''';
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
        for (final seconds in [0, 2, 4, 7, 4]) {
          playback.add(
            PlaybackState(
              playing: false,
              processingState: AudioProcessingState.ready,
              updatePosition: Duration(seconds: seconds),
            ),
          );
          await _settlePlayer(tester);
          expect(
            tester.widget<Text>(find.text('Together')).textAlign,
            TextAlign.start,
          );
          expect(
            tester.widget<Text>(find.text('Guest returns')).textAlign,
            TextAlign.end,
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
    for (final ttml in [false, true]) {
      testWidgets(
        'backing vocals stay smaller under the lead with independent timing (Sistrum: $sistrum, TTML: $ttml)',
        (tester) async {
          metadataOverrides['lyrics'] = ttml
              ? '''
  <tt xmlns="http://www.w3.org/ns/ttml" xmlns:m="http://www.w3.org/ns/ttml#metadata">
  <head><metadata><m:agent xml:id="v1" type="person"/><m:agent xml:id="v2" type="person"/></metadata></head>
  <body><p begin="1s" end="7s" m:agent="v2"><span begin="1s" end="6s">Lead</span><span m:role="x-bg" m:agent="v1" begin="3s" end="7s">Echo</span></p><p begin="8s" end="10s">Next</p></body></tt>
  '''
              : '''
  [00:01.00]v2:<00:01.00>Lead<00:06.00>
  [bg:v1:<00:03.00>Echo<00:07.00>]
  [00:08.00]<00:08.00>Next<00:10.00>
  ''';
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
          final lead = tester.widget<Text>(find.text('Lead'));
          expect(find.text('Echo'), findsNothing);
          expect(find.textContaining('[bg:'), findsNothing);
          expect(find.textContaining('v1:'), findsNothing);

          Finder timed(String text) => find.descendant(
            of: find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics && widget.properties.label == text,
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

          double offset() =>
              tester.widget<ListView>(find.byType(ListView)).controller!.offset;

          await seek(2000);
          expect(timed('Lead'), findsOneWidget);
          expect(timed('Echo'), findsNothing);
          expect(find.text('Echo'), findsNothing);
          final leadOffset = offset();
          final leadTop = tester.getTopLeft(timed('Lead')).dy;
          var nextTop = tester.getTopLeft(find.text('Next')).dy;
          playback.add(
            PlaybackState(
              processingState: AudioProcessingState.ready,
              updatePosition: const Duration(seconds: 3),
            ),
          );
          await tester.pump();
          await tester.pump();
          for (var frame = 0; frame < 4; frame++) {
            await tester.pump(const Duration(milliseconds: 80));
            expect(tester.getTopLeft(timed('Lead')).dy, closeTo(leadTop, 0.1));
            final top = tester.getTopLeft(find.text('Next')).dy;
            expect(top, greaterThan(nextTop));
            nextTop = top;
          }
          await seek(4000);
          expect(timed('Lead'), findsOneWidget);
          expect(timed('Echo'), findsOneWidget);
          expect(offset(), closeTo(leadOffset, 0.1));
          expect(
            tester.getSize(timed('Echo')).height,
            lessThan(tester.getSize(timed('Lead')).height * 0.8),
          );
          await seek(6500);
          expect(timed('Lead'), findsOneWidget);
          expect(timed('Echo'), findsOneWidget);
          expect(offset(), closeTo(leadOffset, 0.1));
          await seek(7500);
          final backing = tester.widget<Text>(find.text('Echo'));
          expect(
            backing.style!.fontSize,
            lessThan(lead.style!.fontSize! * 0.85),
          );
          expect(backing.textAlign, TextAlign.end);
          if (sistrum) {
            // Inactive vocals shrink around their center. Check the row gap
            // before that paint transform, rather than the scaled text bounds.
            Finder lyricScale(Finder content) => find
                .ancestor(of: content, matching: find.byType(AnimatedScale))
                .first;
            expect(
              tester.getTopLeft(lyricScale(find.text('Echo'))).dy -
                  tester.getBottomLeft(lyricScale(timed('Lead'))).dy,
              closeTo(6, 0.1),
            );
          }
          await seek(2000);
          expect(timed('Lead'), findsOneWidget);
          expect(timed('Echo'), findsNothing);
          expect(find.text('Echo'), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
    testWidgets(
      'simultaneous wrapped lyrics stay inside the viewport ($sistrum)',
      (tester) async {
        const lead =
            'The first singer has a long line that wraps across several rows';
        const guest = 'The second singer starts at exactly the same timestamp';
        metadataOverrides['lyrics'] =
            '[00:01.00]v1:$lead\n[00:01.00]v2:$guest\n[00:08.00]Next';
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
        await tester.tap(
          sistrum
              ? find.byIcon(CupertinoIcons.quote_bubble)
              : find.byIcon(CupertinoIcons.quote_bubble),
        );
        await _settlePlayer(tester);
        playback.add(
          PlaybackState(
            processingState: AudioProcessingState.ready,
            playing: false,
            updatePosition: const Duration(seconds: 2),
          ),
        );
        await _settlePlayer(tester);
        final scrollable = find
            .ancestor(of: find.text(lead), matching: find.byType(Scrollable))
            .first;
        final viewport = tester.getRect(scrollable);
        for (final text in [lead, guest]) {
          final bounds = tester.getRect(find.text(text));
          expect(bounds.top, greaterThanOrEqualTo(viewport.top));
          expect(bounds.bottom, lessThanOrEqualTo(viewport.bottom));
          final opacity = tester.widget<AnimatedOpacity>(
            find
                .ancestor(
                  of: find.text(text),
                  matching: find.byType(AnimatedOpacity),
                )
                .first,
          );
          expect(opacity.opacity, 1);
        }
        expect(tester.takeException(), isNull);
      },
    );
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
  }
}
