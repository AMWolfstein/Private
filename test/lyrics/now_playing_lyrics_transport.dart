part of 'now_playing_lyrics_transition_test.dart';

void _registerNowPlayingLyricsTransport() {
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
