part of 'now_playing_lyrics_transition_test.dart';

void _registerNowPlayingLyricsTransport() {
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

  for (final landscape in [false, true]) {
    testWidgets(
      'paused play glyph is smaller without moving controls (landscape: $landscape)',
      (tester) async {
        final playback = StreamController<PlaybackState>();
        addTearDown(playback.close);
        await _pumpNowPlaying(
          tester,
          theme: AppTheme.build(Brightness.dark),
          size: landscape ? const Size(852, 393) : const Size(393, 852),
          playbackEvents: playback.stream,
        );
        playback.add(PlaybackState(playing: true));
        mediaItems.add(_item('first'));
        await _settlePlayer(tester);
        final pause = find.widgetWithIcon(
          AppPlaybackButton,
          CupertinoIcons.pause_fill,
        );
        final pauseBounds = tester.getRect(pause);
        final pauseSize = tester.getSize(
          find.byIcon(CupertinoIcons.pause_fill),
        );
        final previous = find.byIcon(CupertinoIcons.backward_fill);
        final next = find.byIcon(CupertinoIcons.forward_fill);
        final previousBounds = tester.getRect(previous);
        final nextBounds = tester.getRect(next);
        final volumeBounds = tester.getRect(find.byType(AppVolumeControl));

        playback.add(PlaybackState(playing: false));
        await _settlePlayer(tester);
        final play = find.widgetWithIcon(
          AppPlaybackButton,
          CupertinoIcons.play_fill,
        );
        final playSize = tester.getSize(find.byIcon(CupertinoIcons.play_fill));
        expect(playSize.width, lessThan(pauseSize.width));
        expect(playSize.width / pauseSize.width, inInclusiveRange(0.85, 0.95));
        expect(tester.getRect(play), pauseBounds);
        expect(tester.getRect(previous), previousBounds);
        expect(tester.getRect(next), nextBounds);
        expect(tester.getRect(find.byType(AppVolumeControl)), volumeBounds);

        playback.add(PlaybackState(playing: true));
        await _settlePlayer(tester);
        expect(
          tester.getSize(find.byIcon(CupertinoIcons.pause_fill)),
          pauseSize,
        );
        expect(tester.getRect(pause), pauseBounds);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Sistrum player renders Apple-style transport controls', (
    tester,
  ) async {
    await _pumpNowPlaying(tester, theme: AppTheme.build(Brightness.light));
    mediaItems.add(_item('first'));
    await _settlePlayer(tester);

    expect(find.byIcon(CupertinoIcons.play_fill), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.backward_fill), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.forward_fill), findsOneWidget);
    expect(find.byType(AppVolumeControl), findsOneWidget);
    expect(tester.takeException(), isNull);

    final nextButton = find.widgetWithIcon(
      AppPlaybackButton,
      CupertinoIcons.forward_fill,
    );
    final nextState = tester.state(nextButton);
    mediaItems.add(_item('second'));
    await _settlePlayer(tester);
    expect(tester.state(nextButton), same(nextState));
  });
}
