part of 'now_playing_lyrics_transition_test.dart';

void _registerNowPlayingLyricsTransition3() {
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
}
