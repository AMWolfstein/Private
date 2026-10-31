part of 'now_playing_lyrics_transition_test.dart';

void _registerNowPlayingLyricsTransition6() {
  for (final layout in ['portrait', 'landscape']) {
    testWidgets('instrumental dots follow intro, break and seeks ($layout)', (
      tester,
    ) async {
      metadataOverrides['lyrics'] = '''
[00:09.00]First vocal
[00:12.00]
[00:21.00]Last vocal
[00:25.00]
''';
      final playback = StreamController<PlaybackState>.broadcast();
      addTearDown(playback.close);
      await _pumpNowPlaying(
        tester,
        theme: layout == 'material' ? null : AppTheme.build(Brightness.dark),
        size: layout == 'landscape'
            ? const Size(852, 393)
            : const Size(393, 852),
        playbackEvents: playback.stream,
      );
      mediaItems.add(_item('first'));
      await _settlePlayer(tester);
      if (layout == 'material') {
        await tester.tap(find.byIcon(CupertinoIcons.quote_bubble));
      } else {
        await tester.tap(find.byIcon(CupertinoIcons.quote_bubble));
      }
      await _settlePlayer(tester);

      Future<void> positionAt(
        int seconds, {
        bool playing = false,
        AudioProcessingState state = AudioProcessingState.ready,
      }) async {
        playback.add(
          PlaybackState(
            processingState: state,
            playing: playing,
            updatePosition: Duration(seconds: seconds),
          ),
        );
        if (state == AudioProcessingState.ready && !playing) {
          await _settlePlayer(tester);
        } else {
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
        }
      }

      List<double> dotAlphas() => List.generate(3, (index) {
        final dot = tester.widget<AnimatedContainer>(
          find.byKey(ValueKey('lyric-gap-dot-$index')),
        );
        return (dot.decoration! as BoxDecoration).color!.a;
      });

      if (layout != 'material') {
        // Before playback, the countdown must reserve no blank row. Its
        // entrance pushes the upcoming vocal down instead of jumping it.
        expect(find.byType(LyricGapIndicator), findsNothing);
        final firstVocal = find.text('First vocal');
        final before = tester.getTopLeft(firstVocal).dy;
        playback.add(
          PlaybackState(
            processingState: AudioProcessingState.ready,
            updatePosition: const Duration(seconds: 3),
          ),
        );
        await tester.pump();
        await tester.pump();
        var previous = before;
        for (var frame = 0; frame < 4; frame++) {
          await tester.pump(const Duration(milliseconds: 80));
          final top = tester.getTopLeft(firstVocal).dy;
          expect(top, greaterThan(previous));
          expect(top - before, lessThan(56));
          previous = top;
        }
        await _settlePlayer(tester);
        expect(tester.getTopLeft(firstVocal).dy - before, closeTo(56, 0.1));
      }

      for (final (seconds, expected) in [
        (3, [1.0, 0.25, 0.25]),
        (6, [1.0, 1.0, 0.25]),
        (15, [1.0, 0.25, 0.25]),
        (18, [1.0, 1.0, 0.25]),
        (6, [1.0, 1.0, 0.25]),
      ]) {
        await positionAt(seconds);
        expect(find.byType(LyricGapIndicator).hitTestable(), findsOneWidget);
        expect(dotAlphas(), expected);
        if (layout != 'material') {
          final filter = tester.widget<ImageFiltered>(
            find
                .ancestor(
                  of: find.text(seconds >= 12 ? 'Last vocal' : 'First vocal'),
                  matching: find.byType(ImageFiltered),
                )
                .first,
          );
          expect(filter.enabled, isTrue);
        }
      }

      final firstDot = find.byKey(const ValueKey('lyric-gap-dot-0'));
      double dotWidth([int index = 0]) {
        final dot = find.byKey(ValueKey('lyric-gap-dot-$index'));
        return (tester.getBottomRight(dot) - tester.getTopLeft(dot)).dx;
      }

      void expectSynchronizedDots() {
        for (var index = 1; index < 3; index++) {
          expect(dotWidth(index), closeTo(dotWidth(), 0.001));
        }
      }

      final restingWidth = dotWidth();
      final restingCenter = tester.getCenter(firstDot);
      final rowSize = tester.getSize(find.byType(LyricGapIndicator));
      // Leave enough intro time for the slower pulse to grow and shrink.
      await positionAt(3, playing: true);
      await tester.pump(const Duration(milliseconds: 800));
      final filling = dotAlphas();
      final growingWidth = dotWidth();
      expect(growingWidth, greaterThan(restingWidth));
      expectSynchronizedDots();
      await tester.pump(const Duration(milliseconds: 700));
      final peakWidth = dotWidth();
      expect(peakWidth, greaterThan(growingWidth));
      expectSynchronizedDots();
      await tester.pump(const Duration(milliseconds: 1500));
      expect(dotWidth(), lessThan(peakWidth));
      expectSynchronizedDots();
      expect(tester.getCenter(firstDot), restingCenter);
      expect(tester.getSize(find.byType(LyricGapIndicator)), rowSize);
      expect(dotAlphas(), filling);

      // Pause mid-pulse: both the size and countdown must hold their place.
      await tester.pump(const Duration(milliseconds: 900));
      await positionAt(6);
      final pausedWidth = dotWidth();
      await tester.pump(const Duration(seconds: 2));
      expect(dotWidth(), pausedWidth);
      expect(dotAlphas(), [1.0, 1.0, 0.25]);

      await positionAt(6, playing: true, state: AudioProcessingState.buffering);
      expect(find.byType(LyricGapIndicator), findsNothing);
      await positionAt(6);
      expect(dotAlphas(), [1.0, 1.0, 0.25]);
      await tester.pump(const Duration(seconds: 2));
      expect(dotAlphas(), [1.0, 1.0, 0.25]);

      for (final seconds in [9, 21, 25, 40]) {
        await positionAt(seconds);
        expect(find.byType(LyricGapIndicator), findsNothing);
      }
      await positionAt(6);
      expect(find.byType(LyricGapIndicator), findsOneWidget);
      metadataOverrides.clear();
      mediaItems.add(_item('second'));
      await _settlePlayer(tester);
      expect(find.byType(LyricGapIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Sistrum lyrics stay blurred until playback starts', (
    tester,
  ) async {
    final playback = StreamController<PlaybackState>();
    addTearDown(playback.close);
    await _pumpNowPlaying(
      tester,
      theme: AppTheme.build(Brightness.dark),
      size: const Size(393, 780),
      playbackEvents: playback.stream,
    );
    mediaItems.add(_item('many'));
    playback.add(
      PlaybackState(
        processingState: AudioProcessingState.loading,
        playing: true,
        updatePosition: const Duration(seconds: 2),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byIcon(CupertinoIcons.quote_bubble));
    await tester.pump();
    await _completeLyrics(tester);
    await tester.pump(const Duration(milliseconds: 400));

    void expectLine(String text, {required bool active}) {
      final line = find.text(text);
      final filter = tester.widget<ImageFiltered>(
        find.ancestor(of: line, matching: find.byType(ImageFiltered)).first,
      );
      final opacity = tester.widget<AnimatedOpacity>(
        find.ancestor(of: line, matching: find.byType(AnimatedOpacity)).first,
      );
      expect(opacity.opacity, active ? 1 : 0.48);
      expect(filter.enabled, !active, reason: '$text: ${filter.imageFilter}');
    }

    expectLine('First line', active: false);
    expectLine('Second line', active: false);
    expectLine('Third line', active: false);

    playback.add(PlaybackState(processingState: AudioProcessingState.ready));
    await _settlePlayer(tester);
    expectLine('First line', active: false);

    playback.add(
      PlaybackState(
        processingState: AudioProcessingState.ready,
        playing: true,
        updatePosition: const Duration(seconds: 2),
      ),
    );
    await tester.pump();
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump(const Duration(milliseconds: 160));
    }
    expectLine('First line', active: false);
    expectLine('Second line', active: true);
    expectLine('Third line', active: false);

    playback.add(
      PlaybackState(
        processingState: AudioProcessingState.ready,
        updatePosition: const Duration(seconds: 2),
      ),
    );
    await _settlePlayer(tester);
    expectLine('Second line', active: true);

    playback.add(
      PlaybackState(
        processingState: AudioProcessingState.buffering,
        playing: true,
        updatePosition: const Duration(seconds: 2),
      ),
    );
    await tester.pump();
    for (var frame = 0; frame < 3; frame++) {
      await tester.pump(const Duration(milliseconds: 160));
    }
    expectLine('First line', active: false);
    expectLine('Second line', active: false);
    expectLine('Third line', active: false);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Sistrum lyrics keep the active line sharp with bold leading-aligned text',
    (tester) async {
      await _pumpNowPlaying(
        tester,
        theme: AppTheme.build(Brightness.light),
        size: const Size(393, 780),
        playback: PlaybackState(updatePosition: const Duration(seconds: 2)),
      );
      mediaItems.add(_item('many'));
      await _settlePlayer(tester, const Duration(milliseconds: 16));
      await tester.tap(find.byIcon(CupertinoIcons.quote_bubble));
      await _settlePlayer(tester, const Duration(milliseconds: 16));
      final active = find.text('Second line');
      final inactive = find.text('Third line');
      final activeText = tester.widget<Text>(active);
      expect(activeText.textAlign, TextAlign.start);
      expect(activeText.style?.fontWeight, FontWeight.bold);
      expect(activeText.style?.fontSize, 34);
      expect(tester.getTopLeft(active).dx, tester.getTopLeft(inactive).dx);
      expect(tester.getTopLeft(active).dx, _seekTrackBounds(tester).left);
      final activeFilters = tester.widgetList<ImageFiltered>(
        find.ancestor(of: active, matching: find.byType(ImageFiltered)),
      );
      expect(activeFilters.any((filter) => !filter.enabled), isTrue);
      final inactiveFilters = tester.widgetList<ImageFiltered>(
        find.ancestor(of: inactive, matching: find.byType(ImageFiltered)),
      );
      expect(
        inactiveFilters.any(
          (filter) =>
              filter.enabled &&
              filter.imageFilter == ImageFilter.blur(sigmaX: 2.4, sigmaY: 2.4),
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Sistrum queue replaces artwork while volume and playback stay in place',
    (tester) async {
      await _pumpNowPlaying(
        tester,
        theme: AppTheme.build(Brightness.light),
        size: const Size(393, 780),
      );
      mediaItems.add(_item('first'));
      await _settlePlayer(tester, const Duration(milliseconds: 16));
      await tester.tap(find.byIcon(CupertinoIcons.quote_bubble));
      await _settlePlayer(tester, const Duration(milliseconds: 16));
      expect(find.text('First lyric').hitTestable(), findsOneWidget);
      final volume = tester.getRect(find.byType(AppVolumeControl));
      await tester.tap(find.byIcon(CupertinoIcons.list_bullet));
      await _settlePlayer(tester, const Duration(milliseconds: 16));
      expect(find.byType(AppPlayerQueue), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.getRect(find.byType(AppVolumeControl)), volume);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(CupertinoIcons.list_bullet));
      await tester.pump();
      expect(find.text('First lyric'), findsNothing);
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.text('First lyric'), findsNothing);
      expect(find.byType(AppPlayerQueue), findsOneWidget);
      expect(find.byType(AppPlayerQueue).hitTestable(), findsNothing);
      await _settlePlayer(tester, const Duration(milliseconds: 16));
      expect(find.byType(AppPlayerQueue), findsNothing);
      expect(tester.getRect(find.byType(AppVolumeControl)), volume);
    },
  );
}
