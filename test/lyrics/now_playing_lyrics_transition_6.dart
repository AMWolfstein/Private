part of 'now_playing_lyrics_transition_test.dart';

void _registerNowPlayingLyricsTransition6() {
  testWidgets(
    'Sistrum heart shares Library favorites across tracks and compact headers',
    (tester) async {
      await _pumpNowPlaying(
        tester,
        theme: AppTheme.build(Brightness.light),
        size: const Size(393, 780),
      );
      mediaItems.add(_item('first'));
      await _settlePlayer(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(NowPlayingScreen)),
      );
      final heart = find.byIcon(CupertinoIcons.heart).hitTestable();
      expect(heart, findsOneWidget);
      await tester.tap(heart);
      await _settlePlayer(tester);
      expect(
        find.byIcon(CupertinoIcons.heart_fill).hitTestable(),
        findsOneWidget,
      );
      expect(
        container.read(libraryCollectionsProvider).loved.single.track.id,
        'first',
      );
      await tester.tap(find.byIcon(CupertinoIcons.ellipsis).hitTestable());
      await _settlePlayer(tester);
      await tester.tap(find.text('Favorited'));
      await _settlePlayer(tester);
      expect(container.read(libraryCollectionsProvider).loved, isEmpty);
      expect(heart, findsOneWidget);
      await tester.tap(find.byIcon(CupertinoIcons.ellipsis).hitTestable());
      await _settlePlayer(tester);
      await tester.tap(find.text('Favorite'));
      await _settlePlayer(tester);
      expect(
        container.read(libraryCollectionsProvider).loved.single.track.id,
        'first',
      );
      await tester.tap(find.byIcon(CupertinoIcons.list_bullet));
      await _settlePlayer(tester);
      expect(
        find.byIcon(CupertinoIcons.heart_fill).hitTestable(),
        findsOneWidget,
      );
      mediaItems.add(_item('second'));
      await _settlePlayer(tester);
      expect(find.byIcon(CupertinoIcons.heart).hitTestable(), findsOneWidget);
      mediaItems.add(_item('first'));
      await _settlePlayer(tester);
      expect(
        find.byIcon(CupertinoIcons.heart_fill).hitTestable(),
        findsOneWidget,
      );

      // A change from Library must also update the player, without reopening it.
      final track = container
          .read(libraryCollectionsProvider)
          .loved
          .single
          .track;
      await container
          .read(libraryCollectionsProvider.notifier)
          .toggleLoved(track);
      await _settlePlayer(tester);
      expect(find.byIcon(CupertinoIcons.heart).hitTestable(), findsOneWidget);
      expect(
        find.byType(AppPlayerFavoriteButton).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

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
}
