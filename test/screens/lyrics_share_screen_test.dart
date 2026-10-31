import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/l10n/app_localizations.dart';
import 'package:sistrum/screens/lyrics/lyrics_share_screen.dart';
import 'package:sistrum/screens/lyrics/lyrics_share_card.dart';
import 'package:sistrum/utils/lyrics/lyrics_parser.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/core/theme/app_theme.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('timed lyrics share their sung lines, plain lyrics their text', () {
    final timed = LyricsParser.parse('''
[00:01.00]First line
[00:03.00]
[00:05.00]Second line
''');
    expect(lyricsShareLines(timed).map((line) => line.text), [
      'First line',
      'Second line',
    ]);
    final plain = LyricsParser.parse('Verse one\n\nVerse two\n');
    expect(lyricsShareLines(plain).map((line) => line.text), [
      'Verse one',
      'Verse two',
    ]);
  });

  test('short quotes use larger type than long ones', () {
    expect(
      LyricsShareCard.fontSizeFor([(text: 'Short', background: false)]),
      greaterThan(
        LyricsShareCard.fontSizeFor([(text: 'A' * 200, background: false)]),
      ),
    );
  });

  testWidgets('each shared lyric line takes its own direction', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: LyricsShareCard(
            title: 'Track',
            artist: '',
            artUri: null,
            background: LyricsCardBackground.dark,
            lines: [
              (text: 'مرحبا بالعالم', background: false),
              (text: 'Hello world', background: false),
            ],
          ),
        ),
      ),
    );
    final arabic = tester.widget<Text>(find.text('مرحبا بالعالم'));
    final english = tester.widget<Text>(find.text('Hello world'));
    expect(arabic.textDirection, TextDirection.rtl);
    expect(arabic.textAlign, TextAlign.start);
    expect(english.textDirection, TextDirection.ltr);
    expect(english.textAlign, TextAlign.start);
  });

  testWidgets('selection is limited and required before sharing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.build(Brightness.dark),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: LyricsShareScreen(
            mediaItem: const MediaItem(id: 'track', title: 'Track'),
            lines: [
              for (var i = 0; i < 7; i++) (text: 'Line $i', background: false),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    CupertinoButton share() => tester.widget<CupertinoButton>(
      find.ancestor(
        of: find.text('Share'),
        matching: find.byType(CupertinoButton),
      ),
    );
    expect(share().onPressed, isNull);

    Finder choice(int index) => find.descendant(
      of: find.byType(ListView),
      matching: find.text('Line $index'),
    );
    for (var i = 0; i < lyricsShareMaxLines; i++) {
      await tester.ensureVisible(choice(i));
      await tester.pumpAndSettle();
      await tester.tap(choice(i));
      await tester.pumpAndSettle();
    }
    expect(find.text('5/5'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(share().onPressed, isNotNull);
    // The card quotes each selected line once.
    expect(
      find.descendant(
        of: find.byType(LyricsShareCard),
        matching: find.text('Line 0'),
      ),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(choice(6), 100);
    // Fully reveal the row; a partly clipped one cannot be tapped.
    await tester.ensureVisible(choice(6));
    await tester.pumpAndSettle();
    await tester.tap(choice(6));
    await tester.pumpAndSettle();
    expect(find.text('You can share up to 5 lines'), findsOneWidget);
    expect(find.text('Line 6'), findsOneWidget);
  });

  testWidgets('the selected-line count is a live region', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.build(Brightness.dark),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: LyricsShareScreen(
            mediaItem: const MediaItem(id: 'track', title: 'Track'),
            lines: [
              for (var i = 0; i < 3; i++) (text: 'Line $i', background: false),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final count = tester.widget<Semantics>(
      find
          .ancestor(of: find.text('0/5'), matching: find.byType(Semantics))
          .first,
    );
    expect(count.properties.liveRegion, isTrue);
    handle.dispose();
  });

  testWidgets('a landscape phone still lists several lines', (tester) async {
    tester.view.physicalSize = const Size(800, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.build(Brightness.dark),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: LyricsShareScreen(
            mediaItem: const MediaItem(id: 'track', title: 'Track'),
            lines: [
              for (var i = 0; i < 7; i++) (text: 'Line $i', background: false),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Side by side: the card shares the width instead of eating the height.
    final card = tester.getRect(find.byType(LyricsShareCard));
    final list = tester.getRect(find.byType(ListView));
    expect(list.left, greaterThan(card.right));
    for (var i = 0; i < 3; i++) {
      expect(find.text('Line $i'), findsOneWidget);
      expect(
        tester.getRect(find.text('Line $i')).bottom,
        lessThanOrEqualTo(360),
      );
    }
    for (final label in ['Artwork', 'Cover color', 'Dark', 'Light']) {
      final target = find
          .descendant(
            of: find.byTooltip(label),
            matching: find.byType(GestureDetector),
          )
          .first;
      expect(tester.getSize(target).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'short narrow large-text share keeps full-size background controls',
    (tester) async {
      tester.view.physicalSize = const Size(360, 560);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.build(Brightness.dark),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: LyricsShareScreen(
              mediaItem: const MediaItem(id: 'track', title: 'Track'),
              lines: [
                for (var i = 0; i < 7; i++)
                  (text: 'Line $i', background: false),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final label in ['Artwork', 'Cover color', 'Dark', 'Light']) {
        final target = find
            .descendant(
              of: find.byTooltip(label),
              matching: find.byType(GestureDetector),
            )
            .first;
        expect(tester.getSize(target).width, greaterThanOrEqualTo(48));
        expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
        expect(tester.getRect(target).bottom, lessThanOrEqualTo(560));
      }
      expect(tester.getSize(find.byType(ListView)).height, greaterThan(48));
      expect(tester.takeException(), isNull);
    },
  );
}
