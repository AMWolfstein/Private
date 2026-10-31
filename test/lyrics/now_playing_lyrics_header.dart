part of 'now_playing_lyrics_transition_test.dart';

void _registerNowPlayingLyricsHeader() {
  for (final landscape in [false, true]) {
    testWidgets(
      'outgoing lyrics keep their scroll state while queue fades in (landscape: $landscape)',
      (tester) async {
        metadataOverrides['lyrics'] = List.generate(
          16,
          (index) =>
              '[00:${(index * 2).toString().padLeft(2, '0')}.00]Line $index',
        ).join('\n');
        await _pumpNowPlaying(
          tester,
          theme: AppTheme.build(Brightness.dark),
          size: landscape ? const Size(852, 393) : const Size(393, 852),
          playback: PlaybackState(
            processingState: AudioProcessingState.ready,
            updatePosition: const Duration(seconds: 20),
          ),
        );
        mediaItems.add(_item('first'));
        await _settlePlayer(tester);
        await tester.tap(find.byIcon(CupertinoIcons.quote_bubble));
        await _settlePlayer(tester);
        final scrollable = find
            .ancestor(
              of: find.text('Line 10'),
              matching: find.byType(Scrollable),
            )
            .first;
        final state = tester.state<ScrollableState>(scrollable);
        final offset = state.position.pixels;
        expect(offset, greaterThan(0));
        await tester.tap(find.byIcon(CupertinoIcons.list_bullet));
        await tester.pump();
        for (var frame = 0; frame < 3; frame++) {
          expect(state.mounted, isTrue);
          expect(tester.state<ScrollableState>(scrollable), same(state));
          expect(state.position.pixels, offset);
          await tester.pump(const Duration(milliseconds: 50));
        }
        await _settlePlayer(tester);
        expect(state.mounted, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('header reverses in place and stays beside cover across panels', (
    tester,
  ) async {
    await _pumpNowPlaying(
      tester,
      theme: AppTheme.build(Brightness.dark),
      size: const Size(393, 852),
    );
    mediaItems.add(_item('first'));
    await _settlePlayer(tester);
    final header = find.byKey(const ValueKey('player-track-header'));
    final element = tester.element(header);
    final expandedBounds = tester.getRect(header);
    final lyrics = find.byIcon(CupertinoIcons.quote_bubble);
    final queue = find.byIcon(CupertinoIcons.list_bullet);
    await tester.tap(lyrics);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    final interruptedBounds = tester.getRect(header);
    await tester.tap(lyrics);
    await tester.pump();
    expect(tester.getRect(header), interruptedBounds);
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.getRect(header).top, greaterThan(interruptedBounds.top));
    expect(tester.getRect(header).left, lessThan(interruptedBounds.left));
    await _settlePlayer(tester);
    expect(tester.getRect(header), expandedBounds);

    await tester.tap(lyrics);
    await _settlePlayer(tester);
    final compactBounds = tester.getRect(header);
    await tester.tap(queue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    expect(tester.getRect(header), compactBounds);
    expect(tester.element(header), same(element));
    await _settlePlayer(tester);
    expect(tester.getRect(header), compactBounds);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shared header respects reduced motion and large text', (
    tester,
  ) async {
    await _pumpNowPlaying(
      tester,
      theme: AppTheme.build(Brightness.dark),
      size: const Size(393, 852),
      wrapPlayer: (player) => Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: true,
            textScaler: const TextScaler.linear(1.6),
          ),
          child: player,
        ),
      ),
    );
    mediaItems.add(_item('first'));
    await _settlePlayer(tester);
    final header = find.byKey(const ValueKey('player-track-header'));
    final expandedBounds = tester.getRect(header);
    final lyrics = find.byIcon(CupertinoIcons.quote_bubble);
    await tester.tap(lyrics);
    await tester.pump();
    final compactBounds = tester.getRect(header);
    final cover = tester.getRect(
      find.byKey(const ValueKey('compact-player-artwork')),
    );
    expect(compactBounds.left, cover.right + 12);
    expect(compactBounds.top, cover.top);
    expect(compactBounds.top, lessThan(expandedBounds.top));
    await tester.tap(lyrics);
    await tester.pump();
    expect(tester.getRect(header), expandedBounds);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Sistrum lyrics replace artwork while controls stay in place', (
    tester,
  ) async {
    await _pumpNowPlaying(
      tester,
      theme: AppTheme.build(Brightness.dark),
      size: const Size(393, 700),
    );
    mediaItems.add(_item('first'));
    await _settlePlayer(tester);

    final artwork = find.byType(Hero);
    final fullArtwork = tester.getRect(artwork);
    expect(fullArtwork.height, fullArtwork.width);
    final volume = find.byType(AppVolumeControl);
    final volumeRect = tester.getRect(volume);
    final play = find.byIcon(CupertinoIcons.play_fill);
    final playRect = tester.getRect(play);
    final lyricsButton = find.byIcon(CupertinoIcons.quote_bubble);
    await tester.tap(lyricsButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final fullCover = find.byKey(const ValueKey('full-player-artwork'));
    double fullCoverOpacity() => tester
        .widget<FadeTransition>(
          find
              .ancestor(of: fullCover, matching: find.byType(FadeTransition))
              .first,
        )
        .opacity
        .value;
    expect(fullCover, findsOneWidget);
    expect(fullCoverOpacity(), inExclusiveRange(0.0, 1.0));
    await _settlePlayer(tester);

    expect(find.byType(PageView), findsNothing);
    expect(find.text('First lyric').hitTestable(), findsOneWidget);
    expect(tester.getSize(artwork).width, lessThan(fullArtwork.width));
    expect(fullArtwork.top, greaterThan(0));
    expect(fullArtwork.width, lessThan(393));
    expect(tester.getRect(volume), volumeRect);
    expect(tester.getRect(play), playRect);

    mediaItems.add(_item('second'));
    await _settlePlayer(tester);
    expect(find.text('Second lyric').hitTestable(), findsOneWidget);
    expect(find.text('First lyric'), findsNothing);

    await tester.tap(lyricsButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(fullCoverOpacity(), inExclusiveRange(0.0, 1.0));
    expect(
      find.descendant(of: fullCover, matching: find.byType(Hero)),
      findsOneWidget,
    );
    await _settlePlayer(tester);
    expect(tester.getRect(artwork), fullArtwork);
    expect(find.text('Second lyric').hitTestable(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'automatic SAF track change refreshes lyrics while Lyrics page is active',
    (tester) async {
      await _pumpNowPlaying(tester);

      mediaItems.add(_item('first'));
      await _settlePlayer(tester);
      await tester.tap(find.byIcon(CupertinoIcons.quote_bubble));
      await _settlePlayer(tester);
      expect(find.text('First lyric'), findsOneWidget);

      mediaItems.add(_item('second'));
      await _settlePlayer(tester);

      expect(find.text('Second lyric'), findsOneWidget);
      expect(find.text('First lyric'), findsNothing);
    },
  );

  testWidgets(
    'lyrics end with writer and provider credits and clear them on track change',
    (tester) async {
      metadataOverrides['composer'] = 'Example Composer';
      metadataOverrides['lyrics'] =
          '[by:\u0053\u0070\u006f\u0074\u0069\u0046\u004c\u0041\u0043-Mobile via Example Lyrics API (source: upstream)]\n[00:01]Last lyric';
      await _pumpNowPlaying(
        tester,
        theme: AppTheme.build(Brightness.dark),
        size: const Size(390, 844),
      );
      mediaItems.add(_item('first'));
      await _settlePlayer(tester);
      await tester.tap(find.byIcon(CupertinoIcons.quote_bubble));
      await _settlePlayer(tester);
      final credit = find.text(
        'Written by: Example Composer\nLyrics: Example Lyrics',
      );
      expect(credit, findsOneWidget);
      expect(
        tester.getTopLeft(credit).dy,
        greaterThan(tester.getBottomLeft(find.text('Last lyric')).dy),
      );
      metadataOverrides.clear();
      mediaItems.add(_item('second'));
      await _settlePlayer(tester);
      expect(credit, findsNothing);
      expect(find.text('Second lyric'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('language toggles keep a later active lyric anchored in every frame', (
    tester,
  ) async {
    metadataOverrides['lyrics'] = [
      for (var i = 0; i < 12; i++) ...[
        '[x-romaji:${(i + 1) * 10000}:${base64.encode(utf8.encode('Pronunciation $i'))}]',
        '[x-translation:${(i + 1) * 10000}:${base64.encode(utf8.encode('Translation $i'))}]',
        '[${((i + 1) * 10 ~/ 60).toString().padLeft(2, '0')}:${((i + 1) * 10 % 60).toString().padLeft(2, '0')}.000]Original $i',
      ],
    ].join('\n');
    await _pumpNowPlaying(
      tester,
      theme: AppTheme.build(Brightness.dark),
      size: const Size(390, 844),
      playback: PlaybackState(
        processingState: AudioProcessingState.ready,
        updatePosition: const Duration(seconds: 45),
      ),
    );
    mediaItems.add(_item('anchored-supplements'));
    await _settlePlayer(tester);
    await tester.tap(find.byIcon(CupertinoIcons.quote_bubble));
    await _settlePlayer(tester);
    final original = find.text('Original 3');
    final anchor = tester.getTopLeft(original).dy;
    for (final action in [
      'Hide Pronunciation',
      'Show Pronunciation',
      'Hide Translation',
      'Show Translation',
    ]) {
      await tester.tap(find.byKey(const ValueKey('lyrics-language-options')));
      await _settlePlayer(tester);
      await tester.tap(find.text(action));
      await tester.pump();
      for (var frame = 0; frame < 32; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          tester.getTopLeft(original).dy,
          closeTo(anchor, 1),
          reason: '$action frame $frame',
        );
      }
    }
    expect(tester.takeException(), isNull);
  });
}
