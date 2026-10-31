part of 'now_playing_lyrics_transition_test.dart';

void _registerNowPlayingLyricsTransition14() {
  testWidgets('Now Playing menu exposes Go to Album when album is known', (
    tester,
  ) async {
    await _pumpNowPlaying(tester);
    mediaItems.add(_item('first'));
    await _settlePlayer(tester);

    await tester.tap(find.byIcon(CupertinoIcons.ellipsis));
    await _settlePlayer(tester);

    expect(find.text('Go to Album'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.square_stack), findsOneWidget);
  });

  testWidgets('Now Playing menu exposes sleep timer duration choices', (
    tester,
  ) async {
    await _pumpNowPlaying(tester);
    mediaItems.add(_item('first'));
    await _settlePlayer(tester);

    await tester.tap(find.byIcon(CupertinoIcons.ellipsis));
    await _settlePlayer(tester);
    await tester.tap(find.text('Sleep timer'));
    await _settlePlayer(tester);

    expect(find.text('15 minutes'), findsOneWidget);
    expect(find.text('30 minutes'), findsOneWidget);
    expect(find.text('45 minutes'), findsOneWidget);
    expect(find.text('60 minutes'), findsOneWidget);
    expect(find.text('Turn off sleep timer'), findsNothing);
  });
}
