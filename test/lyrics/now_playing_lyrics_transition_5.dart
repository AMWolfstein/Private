part of 'now_playing_lyrics_transition_test.dart';

void _registerNowPlayingLyricsTransition5() {
  testWidgets(
    'accessible navigation keeps lyric controls available while idle',
    (tester) async {
      await _pumpNowPlaying(
        tester,
        theme: AppTheme.build(Brightness.dark),
        size: const Size(393, 852),
        playback: PlaybackState(playing: true),
        wrapPlayer: (player) => Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(accessibleNavigation: true),
            child: player,
          ),
        ),
      );
      mediaItems.add(_item('many'));
      await _settlePlayer(tester);
      await tester.tap(find.byIcon(CupertinoIcons.quote_bubble));
      await _settlePlayer(tester);
      await tester.pump(const Duration(seconds: 6));
      expect(find.byType(AppVolumeControl).hitTestable(), findsOneWidget);
      expect(
        find.byIcon(CupertinoIcons.quote_bubble).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Sistrum player background does not reveal the page below', (
    tester,
  ) async {
    final background = ValueNotifier<Color>(Colors.white);
    addTearDown(background.dispose);
    final capture = GlobalKey();
    await _pumpNowPlaying(
      tester,
      theme: AppTheme.build(Brightness.light),
      size: const Size(393, 780),
      wrapPlayer: (player) => RepaintBoundary(
        key: capture,
        child: ValueListenableBuilder<Color>(
          valueListenable: background,
          child: player,
          builder: (context, color, child) => Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: color),
              child!,
            ],
          ),
        ),
      ),
    );
    mediaItems.add(_item('first'));
    await _settlePlayer(tester);

    Future<List<int>?> edgePixel() => tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(capture),
      );
      final image = await boundary.toImage();
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final offset = (image.width + 1) * 4;
      final pixel = List<int>.generate(4, (i) => bytes.getUint8(offset + i));
      image.dispose();
      return pixel;
    });

    final onWhite = await edgePixel();
    background.value = Colors.red;
    await _settlePlayer(tester);
    expect(await edgePixel(), onWhite);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Sistrum player menu floats above its button and retains dark colors',
    (tester) async {
      await _pumpNowPlaying(
        tester,
        theme: AppTheme.build(Brightness.light),
        size: const Size(393, 780),
      );
      mediaItems.add(_item('first'));
      await _settlePlayer(tester);
      final moreButton = find.byIcon(CupertinoIcons.ellipsis).hitTestable();
      final anchor = tester.getRect(moreButton);
      await tester.tap(moreButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final panel = find.byType(AppPlayerActionsSheet);
      final enteringWidth = tester.getSize(panel).width;
      await _settlePlayer(tester);
      expect(tester.getSize(panel).width, enteringWidth);
      expect(tester.getRect(panel).bottom, lessThan(anchor.top));
      expect(tester.getRect(panel).width, 280);
      expect(find.byType(BottomSheet), findsNothing);
      expect(Theme.of(tester.element(panel)).brightness, Brightness.dark);
      expect(
        tester.widget<Text>(find.text('Go to Album')).style?.color,
        Colors.white,
      );
      expect(find.byIcon(CupertinoIcons.square_stack), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.moon_zzz), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.gear_alt), findsNothing);
      expect(
        find.text(
          AppLocalizations.of(tester.element(panel)).collectionAddToPlaylist,
        ),
        findsOneWidget,
      );
      expect(find.text('Go to Artist'), findsOneWidget);
      expect(find.text('Favorite'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(tester.widget<Text>(find.text('Go to Album')).style?.fontSize, 16);
      await tester.ensureVisible(find.text('Sleep timer'));
      await tester.tap(find.text('Sleep timer'));
      await _settlePlayer(tester);
      expect(
        Theme.of(tester.element(find.text('15 minutes'))).brightness,
        Brightness.dark,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Sistrum title opens artist and album destinations with subtitles',
    (tester) async {
      await _pumpNowPlaying(
        tester,
        theme: AppTheme.build(Brightness.dark),
        size: const Size(393, 780),
      );
      mediaItems.add(_item('first'));
      await _settlePlayer(tester);
      await tester.tap(find.text('First').hitTestable());
      await _settlePlayer(tester);
      expect(find.text('Go to Artist'), findsOneWidget);
      expect(find.text('Go to Album'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppPlayerNavigationMenu),
          matching: find.text('Artist'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(AppPlayerNavigationMenu),
          matching: find.text('Album'),
        ),
        findsOneWidget,
      );
      await tester.tapAt(const Offset(5, 770));
      await _settlePlayer(tester);
      expect(find.byType(AppPlayerNavigationMenu), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Go to Artist offers each artist of a split credit', (
    tester,
  ) async {
    await _pumpNowPlaying(
      tester,
      theme: AppTheme.build(Brightness.dark),
      size: const Size(393, 780),
    );
    mediaItems.add(_item('first').copyWith(artist: 'Tamer، Khaled, Balti'));
    await _settlePlayer(tester);
    await tester.tap(find.text('First').hitTestable());
    await _settlePlayer(tester);
    await tester.tap(find.text('Go to Artist'));
    await _settlePlayer(tester);
    for (final name in ['Tamer', 'Khaled', 'Balti']) {
      expect(find.widgetWithText(ListTile, name), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Android Details reads full tags from a restored content URI', (
    tester,
  ) async {
    metadataOverrides = {
      'album_artist': 'Album Artist',
      'genre': 'Pop/Rock',
      'composer': 'Composer Name',
      'date': '2025-04-16',
      'track_number': 4,
    };
    await _pumpNowPlaying(
      tester,
      theme: AppTheme.build(
        Brightness.dark,
      ).copyWith(platform: TargetPlatform.android),
      size: const Size(393, 852),
    );
    mediaItems.add(_item('first'));
    await _settlePlayer(tester);
    expect(metadataReads, isEmpty);

    await tester.tap(find.byIcon(CupertinoIcons.ellipsis).hitTestable());
    await _settlePlayer(tester);
    await tester.tap(find.text('Details'));
    await _settlePlayer(tester);

    expect(metadataReads, ['content://library/first.flac']);
    final details = tester.widget<AppPlayerDetailsSheet>(
      find.byType(AppPlayerDetailsSheet),
    );
    expect(
      details.rows,
      containsAll([
        ('Title', 'First'),
        ('Album', 'Album'),
        ('Album Artist', 'Album Artist'),
        ('Genre', 'Pop/Rock'),
        ('Composer', 'Composer Name'),
        ('Date', '2025-04-16'),
        ('Track #', '4'),
      ]),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Sistrum Details keeps long values readable and Done visible while scrolling',
    (tester) async {
      final rights = List.filled(10, 'A long copyright value').join(' ');
      metadataOverrides = {
        'title': 'First',
        'artist': 'Artist',
        'album': 'Album',
        'genre': 'Rock',
        'composer': 'Composer',
        'isrc': 'USAAA2600001',
        'copyright': rights,
        'format': 'flac',
        'sample_rate': 96000,
        'bit_depth': 24,
      };
      await _pumpNowPlaying(
        tester,
        theme: AppTheme.build(Brightness.light),
        size: const Size(393, 780),
      );
      mediaItems.add(
        _item('first').copyWith(extras: {'source': '/library/first.flac'}),
      );
      await _settlePlayer(tester);
      await tester.tap(find.byIcon(CupertinoIcons.ellipsis).hitTestable());
      await _settlePlayer(tester);
      await tester.tap(find.text('Details'));
      await _settlePlayer(tester);
      final sheet = find.byType(AppPlayerDetailsSheet);
      expect(sheet, findsOneWidget);
      expect(Theme.of(tester.element(sheet)).brightness, Brightness.dark);
      expect(
        find.descendant(of: sheet, matching: find.byType(Card)),
        findsNothing,
      );
      expect(
        find.descendant(of: sheet, matching: find.byType(AppGlass)),
        findsOneWidget,
      );
      final titleRow = find.widgetWithText(AppMetadataRow, 'Title');
      expect(
        tester
            .getTopLeft(
              find.descendant(of: titleRow, matching: find.text('First')),
            )
            .dy,
        greaterThan(tester.getBottomLeft(find.text('Title')).dy),
      );
      await tester.scrollUntilVisible(
        find.text(rights),
        200,
        scrollable: find.descendant(
          of: sheet,
          matching: find.byType(Scrollable),
        ),
      );
      expect(tester.getSize(find.text(rights)).height, greaterThan(40));
      expect(find.text('Done').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Done'));
      await _settlePlayer(tester);
      expect(sheet, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
