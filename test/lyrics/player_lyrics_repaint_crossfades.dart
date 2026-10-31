part of 'player_lyrics_repaint_test.dart';

void _registerPlayerLyricsRepaintCrossfades() {
  for (final reduceMotion in [false, true]) {
    testWidgets(
      'word-timed lyric crossfades honor reduced motion: $reduceMotion',
      (tester) async {
        final preview = ValueNotifier<Duration?>(const Duration(seconds: 2));
        addTearDown(preview.dispose);
        final theme = AppTheme.build(Brightness.dark);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              playbackStateProvider.overrideWith(
                (ref) => Stream.value(
                  PlaybackState(
                    processingState: AudioProcessingState.ready,
                    updatePosition: const Duration(seconds: 2),
                  ),
                ),
              ),
            ],
            child: MaterialApp(
              theme: theme,
              home: MediaQuery(
                data: MediaQueryData(disableAnimations: reduceMotion),
                child: Scaffold(
                  body: SyncedLyricsView(
                    lyrics: _lyrics,
                    seekPreview: preview,
                    colorScheme: theme.colorScheme,
                    isActive: true,
                    showPronunciation: false,
                    showTranslation: false,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final switchers = tester
            .widgetList<AnimatedSwitcher>(
              find.descendant(
                of: find.byType(SyncedLyricsView),
                matching: find.byType(AnimatedSwitcher),
              ),
            )
            .where((widget) => widget.child is KeyedSubtree);
        expect(switchers, isNotEmpty);
        for (final switcher in switchers) {
          expect(
            switcher.duration,
            reduceMotion ? Duration.zero : const Duration(milliseconds: 320),
          );
          expect(
            switcher.reverseDuration,
            reduceMotion ? Duration.zero : const Duration(milliseconds: 260),
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final sistrum in [true]) {
    testWidgets(
      'playing lyrics retain their painter and refresh stopped highlights ($sistrum)',
      (tester) async {
        final playback = StreamController<PlaybackState>.broadcast();
        final preview = ValueNotifier<Duration?>(null);
        addTearDown(playback.close);
        addTearDown(preview.dispose);
        final theme = sistrum
            ? AppTheme.build(Brightness.dark)
            : ThemeData.dark();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              playbackStateProvider.overrideWith((ref) => playback.stream),
            ],
            child: MaterialApp(
              theme: theme,
              home: Scaffold(
                body: SyncedLyricsView(
                  lyrics: _lyrics,
                  seekPreview: preview,
                  colorScheme: theme.colorScheme,
                  isActive: true,
                  showPronunciation: false,
                  showTranslation: false,
                ),
              ),
            ),
          ),
        );
        Future<void> report(
          int seconds, {
          bool playing = false,
          AudioProcessingState state = AudioProcessingState.ready,
        }) async {
          playback.add(
            PlaybackState(
              playing: playing,
              processingState: state,
              updatePosition: Duration(seconds: seconds),
            ),
          );
          await tester.pump();
          await tester.pump();
        }

        await report(2);
        await tester.pumpAndSettle();
        await report(2, playing: true);
        await tester.pump(const Duration(milliseconds: 500));
        final retained = tester.widget<CustomPaint>(_paint).painter!;
        final retainedBoxes = _segmentBoxes(tester);
        final early = await _pixels(tester);
        var repaintNotifications = 0;
        void repaint() => repaintNotifications++;
        retained.addListener(repaint);
        await report(6, playing: true);
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.widget<CustomPaint>(_paint).painter, same(retained));
        expect(repaintNotifications, greaterThan(0));
        expect(await _pixels(tester), isNot(orderedEquals(early)));
        retained.removeListener(repaint);

        await report(8);
        await tester.pumpAndSettle();
        expect(_segmentBoxes(tester), same(retainedBoxes));
        final paused = await _pixels(tester);
        await tester.pump(const Duration(seconds: 1));
        expect(await _pixels(tester), orderedEquals(paused));
        await report(3);
        await tester.pumpAndSettle();
        expect(await _pixels(tester), isNot(orderedEquals(paused)));

        await report(4, playing: true, state: AudioProcessingState.buffering);
        await tester.pumpAndSettle();
        if (sistrum) {
          expect(_paint, findsNothing);
        } else {
          final buffered = await _pixels(tester);
          await tester.pump(const Duration(seconds: 1));
          expect(await _pixels(tester), orderedEquals(buffered));
          await report(7, playing: true, state: AudioProcessingState.buffering);
          await tester.pumpAndSettle();
          expect(await _pixels(tester), isNot(orderedEquals(buffered)));
        }

        preview.value = const Duration(seconds: 2);
        await tester.pumpAndSettle();
        final sought = await _pixels(tester);
        final soughtBoxes = _segmentBoxes(tester);
        preview.value = const Duration(seconds: 8);
        await tester.pumpAndSettle();
        expect(_segmentBoxes(tester), same(soughtBoxes));
        expect(await _pixels(tester), isNot(orderedEquals(sought)));
        preview.value = const Duration(seconds: 2);
        await tester.pumpAndSettle();
        expect(await _pixels(tester), orderedEquals(sought));
        await report(12, playing: true, state: AudioProcessingState.buffering);
        await tester.pumpAndSettle();
        expect(await _pixels(tester), orderedEquals(sought));
        preview.value = null;
        await report(2);
        await tester.pumpAndSettle();
        expect(await _pixels(tester), orderedEquals(sought));

        // The last lead remains visible during an outro, but its completed
        // highlight must stop scheduling frames after the glow has faded.
        await report(22, playing: true);
        await tester.pumpAndSettle();
        final completedPainter = tester.widget<CustomPaint>(_paint).painter!;
        var completedRepaints = 0;
        void completedRepaint() => completedRepaints++;
        completedPainter.addListener(completedRepaint);
        await tester.pump(const Duration(milliseconds: 500));
        expect(completedRepaints, 0);
        await report(25, playing: true);
        await tester.pump(const Duration(milliseconds: 16));
        expect(completedRepaints, 0);
        expect(
          tester.widget<CustomPaint>(_paint).painter,
          same(completedPainter),
        );
        await report(4, playing: true);
        await tester.pump(const Duration(milliseconds: 16));
        expect(completedRepaints, greaterThan(0));
        completedPainter.removeListener(completedRepaint);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final hiddenByLifecycle in [false, true]) {
    testWidgets(
      'hidden lyrics suspend their timeline and resume the latest position ($hiddenByLifecycle)',
      (tester) async {
        final playback = StreamController<PlaybackState>.broadcast();
        final preview = ValueNotifier<Duration?>(null);
        addTearDown(playback.close);
        addTearDown(preview.dispose);
        final visibility = ValueNotifier(true);
        addTearDown(visibility.dispose);
        const nextText = 'Next voice';
        const lyrics = ParsedLyrics(
          synced: true,
          wordSynced: true,
          plainText: '',
          lines: [
            LyricLine(
              time: Duration.zero,
              end: Duration(seconds: 10),
              text: _text,
              words: [
                LyricWord(
                  time: Duration.zero,
                  end: Duration(seconds: 10),
                  text: _text,
                ),
              ],
            ),
            LyricLine(
              time: Duration(seconds: 10),
              end: Duration(seconds: 40),
              text: nextText,
              words: [
                LyricWord(
                  time: Duration(seconds: 10),
                  end: Duration(seconds: 40),
                  text: nextText,
                ),
              ],
            ),
          ],
        );
        final theme = AppTheme.build(Brightness.dark);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              playbackStateProvider.overrideWith((ref) => playback.stream),
            ],
            child: MaterialApp(
              theme: theme,
              home: ValueListenableBuilder<bool>(
                valueListenable: visibility,
                builder: (context, visible, child) =>
                    TickerMode(enabled: visible, child: child!),
                child: Scaffold(
                  body: SyncedLyricsView(
                    lyrics: lyrics,
                    seekPreview: preview,
                    colorScheme: theme.colorScheme,
                    isActive: true,
                    showPronunciation: false,
                    showTranslation: false,
                  ),
                ),
              ),
            ),
          ),
        );
        Future<void> report(int seconds) async {
          playback.add(
            PlaybackState(
              playing: true,
              processingState: AudioProcessingState.ready,
              updatePosition: Duration(seconds: seconds),
            ),
          );
          await tester.pump();
          await tester.pump();
        }

        Finder timed(String text) => find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.label == text,
        );
        await report(2);
        expect(timed(_text), findsOneWidget);
        if (hiddenByLifecycle) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
        } else {
          visibility.value = false;
        }
        await tester.pump();
        await report(15);
        await tester.pump(const Duration(seconds: 20));
        expect(timed(_text), findsOneWidget);
        expect(timed(nextText), findsNothing);
        if (hiddenByLifecycle) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        } else {
          visibility.value = true;
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(timed(nextText), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
