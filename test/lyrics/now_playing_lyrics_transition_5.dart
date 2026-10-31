part of 'now_playing_lyrics_transition_test.dart';

void _registerNowPlayingLyricsTransition5() {
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

  testWidgets(
    'Sistrum heart shares Library favorites across tracks and compact headers',
    (tester) async {
      await _pumpNowPlaying(
        tester,
        theme: AppTheme.build(Brightness.light),
        size: const Size(393, 780),
      );
      mediaItems.add(_item('first'));
      await _settlePlayer(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(NowPlayingScreen)),
      );
      final heart = find.byIcon(CupertinoIcons.heart).hitTestable();
      expect(heart, findsOneWidget);
      await tester.tap(heart);
      await _settlePlayer(tester);
      expect(
        find.byIcon(CupertinoIcons.heart_fill).hitTestable(),
        findsOneWidget,
      );
      expect(
        container.read(libraryCollectionsProvider).loved.single.track.id,
        'first',
      );
      await tester.tap(find.byIcon(CupertinoIcons.ellipsis).hitTestable());
      await _settlePlayer(tester);
      await tester.tap(find.text('Favorited'));
      await _settlePlayer(tester);
      expect(container.read(libraryCollectionsProvider).loved, isEmpty);
      expect(heart, findsOneWidget);
      await tester.tap(find.byIcon(CupertinoIcons.ellipsis).hitTestable());
      await _settlePlayer(tester);
      await tester.tap(find.text('Favorite'));
      await _settlePlayer(tester);
      expect(
        container.read(libraryCollectionsProvider).loved.single.track.id,
        'first',
      );
      await tester.tap(find.byIcon(CupertinoIcons.list_bullet));
      await _settlePlayer(tester);
      expect(
        find.byIcon(CupertinoIcons.heart_fill).hitTestable(),
        findsOneWidget,
      );
      mediaItems.add(_item('second'));
      await _settlePlayer(tester);
      expect(find.byIcon(CupertinoIcons.heart).hitTestable(), findsOneWidget);
      mediaItems.add(_item('first'));
      await _settlePlayer(tester);
      expect(
        find.byIcon(CupertinoIcons.heart_fill).hitTestable(),
        findsOneWidget,
      );

      // A change from Library must also update the player, without reopening it.
      final track = container
          .read(libraryCollectionsProvider)
          .loved
          .single
          .track;
      await container
          .read(libraryCollectionsProvider.notifier)
          .toggleLoved(track);
      await _settlePlayer(tester);
      expect(find.byIcon(CupertinoIcons.heart).hitTestable(), findsOneWidget);
      expect(
        find.byType(AppPlayerFavoriteButton).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
