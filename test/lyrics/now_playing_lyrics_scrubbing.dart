part of 'now_playing_lyrics_transition_test.dart';

void _registerNowPlayingLyricsScrubbing() {
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

  testWidgets('scrubbing previews word fills and instrumental dots exactly', (
    tester,
  ) async {
    metadataOverrides['lyrics'] = '''
<tt xmlns="http://www.w3.org/ns/ttml"><body><div>
<p begin="00:10.000" end="00:30.000"><span begin="00:10.000" end="00:20.000">First </span><span begin="00:20.000" end="00:30.000">second</span></p>
<p begin="00:40.000" end="00:50.000">Last vocal</p>
</div></body></tt>
''';
    final playback = StreamController<PlaybackState>.broadcast();
    addTearDown(playback.close);
    final controller = _SeekController();
    await _pumpNowPlaying(
      tester,
      theme: AppTheme.build(Brightness.dark),
      size: const Size(393, 852),
      playbackEvents: playback.stream,
      controller: controller,
    );
    mediaItems.add(_item('first'));
    playback.add(PlaybackState(updatePosition: const Duration(seconds: 1)));
    await _settlePlayer(tester);
    await tester.tap(find.byIcon(CupertinoIcons.quote_bubble));
    await _settlePlayer(tester);
    final sliderFinder = find.descendant(
      of: find.byType(PlaybackSeekSlider),
      matching: find.byType(Slider),
    );
    Slider slider() => tester.widget<Slider>(sliderFinder);
    // Exact millisecond targets let this check word fills independently of
    // the gesture/scroll integration test above.
    slider().onChangeStart!(1000);
    Future<void> preview(int milliseconds) async {
      slider().onChanged!(milliseconds.toDouble());
      await _settlePlayer(tester);
    }

    Future<List<int>> wordPixels() async {
      final paint = find.descendant(
        of: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.label == 'First second',
        ),
        matching: find.byType(CustomPaint),
      );
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.ancestor(of: paint, matching: find.byType(RepaintBoundary)).first,
      );
      return (await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final result = bytes.buffer.asUint8List().toList();
        image.dispose();
        return result;
      }))!;
    }

    await preview(15000);
    final firstWord = await wordPixels();
    await preview(25000);
    expect(await wordPixels(), isNot(firstWord));
    await preview(15000);
    expect(await wordPixels(), firstWord);
    playback.add(
      PlaybackState(
        processingState: AudioProcessingState.ready,
        playing: true,
        updatePosition: const Duration(seconds: 45),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(await wordPixels(), firstWord);

    for (final (milliseconds, alpha) in [(33333, 0.25), (36667, 1.0)]) {
      await preview(milliseconds);
      final dot = tester.widget<AnimatedContainer>(
        find.byKey(const ValueKey('lyric-gap-dot-1')),
      );
      expect(
        (dot.decoration! as BoxDecoration).color!.a,
        closeTo(alpha, 0.001),
      );
    }
    await preview(170000);
    expect(find.byType(LyricGapIndicator), findsNothing);
    expect(controller.seeks, isEmpty);
    await preview(15000);
    slider().onChangeEnd!(15000);
    await tester.pump();
    expect(controller.seeks, [const Duration(seconds: 15)]);

    // A pending old seek must not leave the next track at the preview time.
    metadataOverrides['lyrics'] = '[00:02.00]New track start\n[00:14.00]Later';
    mediaItems.add(_item('second'));
    playback.add(PlaybackState(updatePosition: Duration.zero));
    await _settlePlayer(tester);
    expect(slider().value, 0);
    expect(find.text('New track start'), findsOneWidget);
    expect(find.byType(LyricGapIndicator), findsNothing);
    slider().onChangeStart!(0);
    await preview(35000);
    await preview(0);
    final list = tester.widget<ListView>(find.byType(ListView));
    expect(list.controller!.offset, 0);
    controller.completions.single.complete();
    await _settlePlayer(tester);
    expect(slider().value, 0);
    expect(
      tester
          .widget<PlaybackSeekSlider>(find.byType(PlaybackSeekSlider))
          .preview!
          .value,
      Duration.zero,
    );
    slider().onChangeEnd!(0);
    controller.completions.last.complete();
    await _settlePlayer(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Sistrum landscape has no top handle or reserved toolbar height',
    (tester) async {
      await _pumpNowPlaying(
        tester,
        theme: AppTheme.build(
          Brightness.dark,
        ).copyWith(platform: TargetPlatform.android),
        size: const Size(900, 420),
      );
      mediaItems.add(_item('first'));
      await _settlePlayer(tester);
      final bar = tester.widget<AppBar>(find.byType(AppBar));
      expect(bar.toolbarHeight, 0);
      expect(bar.title, isNull);
    },
  );
}
