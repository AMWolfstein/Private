part of 'now_playing_lyrics_transition_test.dart';

void _registerNowPlayingLyricsTransition12() {
  for (final sistrum in [true]) {
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
  }
}
