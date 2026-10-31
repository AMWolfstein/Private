part of 'now_playing_lyrics_transition_test.dart';

void _registerNowPlayingLyricsTransition10() {
  for (final landscape in [false, true]) {
    testWidgets(
      'language menu respects reduced motion and idle controls (landscape: $landscape)',
      (tester) async {
        metadataOverrides['lyrics'] =
            '[x-romaji:1009:${base64.encode(utf8.encode('Pronunciation'))}]\n'
            '[00:01.009]Original';
        await _pumpNowPlaying(
          tester,
          theme: AppTheme.build(Brightness.dark),
          size: landscape ? const Size(844, 390) : const Size(390, 844),
          playback: PlaybackState(playing: true),
          wrapPlayer: (player) => Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: player,
            ),
          ),
        );
        mediaItems.add(_item('first'));
        await _settlePlayer(tester);
        await tester.tap(find.byIcon(CupertinoIcons.quote_bubble));
        await _settlePlayer(tester);
        final options = find.byKey(const ValueKey('lyrics-language-options'));
        await tester.tap(options);
        await _settlePlayer(tester);
        await tester.pump(const Duration(seconds: 6));
        expect(find.text('Hide Pronunciation').hitTestable(), findsOneWidget);
        await tester.tap(find.text('Hide Pronunciation'));
        await tester.pump();
        await tester.pump();
        expect(find.text('Pronunciation'), findsNothing);
        expect(options.hitTestable(), findsOneWidget);

        await tester.pump(const Duration(seconds: 5));
        await _settlePlayer(tester);
        expect(options.hitTestable(), findsNothing);
        if (landscape) {
          await tester.tap(
            find.byKey(const ValueKey('landscape-actions-reveal')),
          );
        } else {
          final bounds = tester.getRect(find.byType(ListView));
          await tester.tapAt(Offset(bounds.right - 6, bounds.top + 10));
        }
        await _settlePlayer(tester);
        await tester.tap(options);
        await _settlePlayer(tester);
        await tester.tap(find.text('Show Pronunciation'));
        await tester.pump();
        await tester.pump();
        expect(find.text('Pronunciation'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
