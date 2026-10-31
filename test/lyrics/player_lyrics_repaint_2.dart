part of 'player_lyrics_repaint_test.dart';

void _registerPlayerLyricsRepaint2() {
  testWidgets(
    'long lyrics measure in batches without moving the visible anchor',
    (tester) async {
      const focus = 250;
      final lines = List.generate(
        600,
        (index) => LyricLine(
          time: Duration(seconds: index),
          end: Duration(seconds: index + 1),
          text:
              'Line $index ${List.filled(index % 4 + 1, 'with enough words to wrap across several lines').join(' ')}',
          romanization: 'Pronunciation for line $index',
          translation: 'Translation for line $index',
        ),
      );
      final lyrics = ParsedLyrics(
        synced: true,
        wordSynced: false,
        plainText: '',
        lines: lines,
      );
      final preview = ValueNotifier<Duration?>(const Duration(seconds: focus));
      addTearDown(preview.dispose);
      final theme = AppTheme.build(Brightness.dark);
      var width = 420.0;
      Future<void> pumpView() => tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: theme,
            home: Scaffold(
              body: SizedBox(
                width: width,
                child: SyncedLyricsView(
                  lyrics: lyrics,
                  seekPreview: preview,
                  colorScheme: theme.colorScheme,
                  isActive: true,
                  showPronunciation: true,
                  showTranslation: true,
                ),
              ),
            ),
          ),
        ),
      );
      Future<void> stableAnchor({bool manualScroll = false}) async {
        await tester.pump();
        var line = find.text(lines[focus].text);
        if (manualScroll) {
          await tester.drag(find.byType(ListView), const Offset(0, -220));
          await tester.pump();
          final visibleText = tester
              .widgetList<Text>(find.byType(Text))
              .map((widget) => widget.data)
              .whereType<String>()
              .where((text) => text.startsWith('Line '))
              .firstWhere((text) {
                final bounds = tester.getRect(find.text(text));
                return bounds.bottom > 0 && bounds.top < 500;
              });
          line = find.text(visibleText);
        }
        expect(line, findsOneWidget);
        final y = tester.getTopLeft(line).dy;
        for (var frame = 0; frame < 60; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(tester.getTopLeft(line).dy, closeTo(y, 0.01));
          expect(tester.takeException(), isNull);
        }
      }

      await pumpView();
      await stableAnchor(manualScroll: true);
      width = 300;
      await pumpView();
      await stableAnchor();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'timed geometry survives rebuilds and tracks layout and boundaries',
    (tester) async {
      final preview = ValueNotifier<Duration?>(const Duration(seconds: 5));
      addTearDown(preview.dispose);
      final words = _lyrics.lines.single.words.toList();
      final lyrics = ParsedLyrics(
        synced: true,
        wordSynced: true,
        plainText: '',
        lines: [
          LyricLine(
            time: Duration.zero,
            end: const Duration(seconds: 20),
            text: _text,
            words: words,
            translation: 'Translation',
          ),
        ],
      );
      var width = 620.0;
      var letterSpacing = 0.0;
      var scale = 1.0;
      var direction = TextDirection.ltr;
      var locale = const Locale('en');
      var supplements = false;
      var viewKey = 0;
      Future<void> pump() async {
        final theme = ThemeData.dark().copyWith(
          textTheme: ThemeData.dark().textTheme.copyWith(
            headlineSmall: TextStyle(
              fontSize: 28,
              letterSpacing: letterSpacing,
            ),
          ),
        );
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: theme,
              locale: locale,
              supportedLocales: const [Locale('en'), Locale('en', 'US')],
              home: Scaffold(
                body: Directionality(
                  textDirection: direction,
                  child: MediaQuery(
                    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                    child: SizedBox(
                      width: width,
                      child: SyncedLyricsView(
                        key: ValueKey(viewKey),
                        lyrics: lyrics,
                        seekPreview: preview,
                        colorScheme: theme.colorScheme,
                        isActive: true,
                        showPronunciation: false,
                        showTranslation: supplements,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      Future<void> matchesFreshLayout() async {
        final cached = await _pixels(tester);
        viewKey++;
        await pump();
        expect(await _pixels(tester), orderedEquals(cached));
      }

      await pump();
      var boxes = _segmentBoxes(tester);
      final initial = await _pixels(tester);
      await pump();
      expect(_segmentBoxes(tester), same(boxes));
      supplements = true;
      await pump();
      expect(_segmentBoxes(tester), same(boxes));
      expect(await _pixels(tester), orderedEquals(initial));

      // Timing-only edits must repaint even though the geometry is retained.
      final oldPainter = tester.widget<CustomPaint>(_paint).painter!;
      words[0] = const LyricWord(
        time: Duration.zero,
        end: Duration(seconds: 6),
        text: 'AAAA ',
      );
      await pump();
      expect(_segmentBoxes(tester), same(boxes));
      expect(
        tester.widget<CustomPaint>(_paint).painter!.shouldRepaint(oldPainter),
        isTrue,
      );
      expect(await _pixels(tester), isNot(orderedEquals(initial)));

      // The paragraph is unchanged, but the timed selections have new bounds.
      words[0] = const LyricWord(
        time: Duration.zero,
        end: Duration(seconds: 10),
        text: 'AA',
      );
      words[1] = const LyricWord(
        time: Duration(seconds: 10),
        end: Duration(seconds: 20),
        text: 'AA BBBB',
      );
      await pump();
      expect(_segmentBoxes(tester), isNot(same(boxes)));
      expect(_segmentBoxes(tester), isNot(equals(boxes)));
      await matchesFreshLayout();

      for (final change in <VoidCallback>[
        () => width = 180,
        () => scale = 1.4,
        () => letterSpacing = 1.5,
        () => locale = const Locale('en', 'US'),
        () => width = 620,
      ]) {
        boxes = _segmentBoxes(tester);
        change();
        await pump();
        expect(_segmentBoxes(tester), isNot(same(boxes)));
        if (width == 180) {
          expect(
            _segmentBoxes(
              tester,
            ).expand((boxes) => boxes).map((box) => box.top).toSet().length,
            greaterThan(1),
          );
        }
        await matchesFreshLayout();
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
