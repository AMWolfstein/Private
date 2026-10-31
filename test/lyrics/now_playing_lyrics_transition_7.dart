part of 'now_playing_lyrics_transition_test.dart';

void _registerNowPlayingLyricsTransition7() {
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

  testWidgets('Sistrum elapsed and remaining times roll on the same second', (
    tester,
  ) async {
    final playbackEvents = StreamController<PlaybackState>();
    addTearDown(playbackEvents.close);
    await _pumpNowPlaying(
      tester,
      theme: AppTheme.build(Brightness.dark),
      size: const Size(393, 780),
      playbackEvents: playbackEvents.stream,
    );
    mediaItems.add(
      _item(
        'first',
      ).copyWith(duration: const Duration(seconds: 180, milliseconds: 600)),
    );

    Future<void> positionAt(int milliseconds) async {
      playbackEvents.add(
        PlaybackState(
          processingState: AudioProcessingState.ready,
          playing: false,
          updatePosition: Duration(milliseconds: milliseconds),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    final elapsed = find.byKey(const ValueKey('elapsed:first'));
    final remaining = find.byKey(const ValueKey('remaining:first'));
    void expectTimes(int elapsedSeconds, int remainingSeconds) {
      expect(tester.widget<AppPlaybackTime>(elapsed).seconds, elapsedSeconds);
      expect(
        tester.widget<AppPlaybackTime>(remaining).seconds,
        remainingSeconds,
      );
    }

    await positionAt(34200);
    await _settlePlayer(tester);
    expectTimes(34, 146);
    final transport = tester
        .widgetList<AppPlaybackButton>(find.byType(AppPlaybackButton))
        .toList();
    await positionAt(34800);
    expectTimes(34, 146);
    final updatedTransport = tester
        .widgetList<AppPlaybackButton>(find.byType(AppPlaybackButton))
        .toList();
    for (var i = 0; i < transport.length; i++) {
      expect(updatedTransport[i], same(transport[i]));
    }

    await positionAt(35000);
    await tester.pump(const Duration(milliseconds: 80));
    expectTimes(35, 145);
    double incomingOffset(Finder label) => tester
        .widget<SlideTransition>(
          find
              .ancestor(
                of: find.descendant(of: label, matching: find.text('5')),
                matching: find.byType(SlideTransition),
              )
              .first,
        )
        .position
        .value
        .dy;
    expect(incomingOffset(elapsed), greaterThan(0));
    expect(incomingOffset(remaining), -incomingOffset(elapsed));

    // Another position report within this second must not restart either roll.
    await positionAt(35200);
    await tester.pump(const Duration(milliseconds: 200));
    expect(incomingOffset(elapsed), 0);
    expect(incomingOffset(remaining), 0);
    await positionAt(35900);
    expectTimes(35, 145);
    await positionAt(36000);
    expectTimes(36, 144);
    await _settlePlayer(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Sistrum volume stays above the bottom actions on a phone', (
    tester,
  ) async {
    await _pumpNowPlaying(
      tester,
      theme: AppTheme.build(Brightness.dark),
      size: const Size(393, 700),
    );
    mediaItems.add(_item('first'));
    await _settlePlayer(tester);

    final volume = find.byType(AppVolumeControl);
    final lyricsButton = find.byIcon(CupertinoIcons.quote_bubble);
    final slider = find.descendant(of: volume, matching: find.byType(Slider));
    expect(
      tester.getRect(volume).bottom,
      lessThan(tester.getRect(lyricsButton).top),
    );
    expect(tester.getSize(slider).height, greaterThanOrEqualTo(44));
    final gesture = await tester.startGesture(tester.getCenter(slider));
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump(const Duration(milliseconds: 16));
    expect(volumeWrites, isNotEmpty);
    expect(volumeWrites.last, greaterThan(0.5));
    await gesture.up();
    await _settlePlayer(tester, const Duration(milliseconds: 16));
    expect(volumeWrites, isNotEmpty);
    expect(volumeWrites.last, greaterThan(0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Sistrum landscape opens the player and reveals hidden lyric actions on a bottom tap',
    (tester) async {
      await _pumpNowPlaying(
        tester,
        theme: AppTheme.build(Brightness.dark),
        size: const Size(393, 852),
        playback: PlaybackState(playing: true),
      );
      mediaItems.add(_item('first'));
      await _settlePlayer(tester);

      tester.view.physicalSize = const Size(852, 393);
      tester.view.padding = FakeViewPadding(left: 59, right: 59, bottom: 21);
      addTearDown(tester.view.resetPadding);
      await _settlePlayer(tester);

      final artwork = find.byType(Hero);
      final volume = find.byType(AppVolumeControl);
      final artRect = tester.getRect(artwork);
      expect(artRect.width, closeTo(artRect.height, 0.1));
      expect(artRect.width, greaterThan(140));
      expect(artRect.top, greaterThanOrEqualTo(36));
      final header = find.text('First').hitTestable();
      final lyric = find.text('First lyric').hitTestable();
      expect(header, findsOneWidget);
      expect(lyric, findsNothing);
      expect(tester.getRect(header).left, greaterThan(artRect.right));
      expect(volume.hitTestable(), findsOneWidget);
      expect(
        find.byIcon(CupertinoIcons.quote_bubble).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.byIcon(CupertinoIcons.list_bullet).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      expect(
        find.byIcon(CupertinoIcons.pause_fill).hitTestable(),
        findsOneWidget,
      );
      final volumeSlider = find.descendant(
        of: volume,
        matching: find.byType(Slider),
      );
      final drag = await tester.startGesture(tester.getCenter(volumeSlider));
      await drag.moveBy(const Offset(30, 0));
      await tester.pump(const Duration(seconds: 5));
      expect(volume.hitTestable(), findsOneWidget);
      expect(volumeWrites, isNotEmpty);
      await drag.up();
      await tester.pump(const Duration(seconds: 4));
      await _settlePlayer(tester);
      expect(volume.hitTestable(), findsOneWidget);

      await tester.tap(find.byIcon(CupertinoIcons.quote_bubble).hitTestable());
      await _settlePlayer(tester);
      expect(volume, findsNothing);
      expect(find.text('First lyric').hitTestable(), findsOneWidget);
      expect(tester.getRect(lyric).left, greaterThan(artRect.right));
      expect(
        tester.getRect(lyric).top,
        greaterThan(tester.getRect(header).bottom),
      );
      await tester.pump(const Duration(seconds: 5));
      await _settlePlayer(tester);
      expect(
        find.byIcon(CupertinoIcons.quote_bubble).hitTestable(),
        findsNothing,
      );
      expect(
        find.byIcon(CupertinoIcons.list_bullet).hitTestable(),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('landscape-actions-reveal')));
      await _settlePlayer(tester);
      expect(
        find.byIcon(CupertinoIcons.quote_bubble).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byIcon(CupertinoIcons.quote_bubble).hitTestable());
      await _settlePlayer(tester);
      expect(volume.hitTestable(), findsOneWidget);
      expect(lyric, findsNothing);
      await tester.tap(find.byIcon(CupertinoIcons.quote_bubble).hitTestable());
      await _settlePlayer(tester);

      mediaItems.add(_item('second'));
      await _settlePlayer(tester);
      expect(find.text('Second lyric').hitTestable(), findsOneWidget);
      expect(find.text('First lyric'), findsNothing);
      tester.view.physicalSize = const Size(393, 852);
      tester.view.resetPadding();
      await _settlePlayer(tester);
      expect(
        find.byIcon(CupertinoIcons.quote_bubble).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.byIcon(CupertinoIcons.list_bullet).hitTestable(),
        findsOneWidget,
      );
      expect(
        tester.getRect(artwork).bottom,
        lessThan(tester.getRect(volume).top),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('immersive rotation retains the background and artwork keys', (
    tester,
  ) async {
    await _pumpNowPlaying(
      tester,
      theme: AppTheme.build(Brightness.dark),
      size: const Size(393, 852),
      playerView: PlayerView.immersive,
    );
    mediaItems.add(_item('first'));
    await _settlePlayer(tester);
    final background = tester.element(find.byType(AppPlayerBackground));
    expect(
      tester
          .widget<AppPlayerBackground>(find.byType(AppPlayerBackground))
          .fadeStart,
      .72,
    );
    tester.view.physicalSize = const Size(852, 393);
    await _settlePlayer(tester);
    expect(tester.element(find.byType(AppPlayerBackground)), same(background));
    expect(find.byKey(const ValueKey('full-player-artwork')), findsOneWidget);
    tester.view.physicalSize = const Size(393, 852);
    await _settlePlayer(tester);
    expect(tester.element(find.byType(AppPlayerBackground)), same(background));
    expect(
      tester.getRect(find.byKey(const ValueKey('full-player-artwork'))).width,
      393,
    );
    expect(tester.takeException(), isNull);
  });
}
