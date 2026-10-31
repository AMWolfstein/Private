part of 'local_song_menu_actions_test.dart';

void _registerLocalSongMenuNavigation() {
  testWidgets('ReplayGain cancel reports no change', (tester) async {
    await _mount(tester);
    final l10n = AppLocalizations.of(tester.element(find.byType(LocalSongRow)));
    for (final label in [l10n.trackReplayGain, l10n.trackRemoveReplayGain]) {
      await _openMenu(tester);
      await tester.ensureVisible(find.text(label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await _pumpUntil(tester, find.text(l10n.dialogCancel));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.dialogCancel));
      await _runAction(tester, pendingAction!);
      await tester.pumpAndSettle();
      expect(await pendingAction!, isFalse);
    }
  });

  testWidgets('album and artist actions navigate from the song menu', (
    tester,
  ) async {
    await _mount(tester);
    final l10n = AppLocalizations.of(tester.element(find.byType(LocalSongRow)));
    await _openMenu(tester);
    await tester.tap(find.text(l10n.homeGoToAlbum));
    await _runAction(tester, pendingAction!);
    await tester.pumpAndSettle();
    expect(
      find.text(l10n.clickableInformationUnavailable(l10n.trackAlbum)),
      findsOneWidget,
    );

    await _openMenu(tester);
    await tester.tap(find.text(l10n.appGoToArtist));
    await _pumpUntil(tester, find.byType(LocalArtistScreen));
    expect(find.byType(LocalArtistScreen), findsOneWidget);
  });

  testWidgets('go to artist offers each name of a featured credit', (
    tester,
  ) async {
    await _mount(
      tester,
      item: LocalLibraryItem(
        id: 'song',
        trackName: 'Song',
        artistName: 'Artist feat. Guest',
        albumName: 'Album',
        filePath: song.filePath,
        scannedAt: DateTime(2026),
      ),
    );
    final l10n = AppLocalizations.of(tester.element(find.byType(LocalSongRow)));
    await _openMenu(tester);
    await tester.ensureVisible(find.text(l10n.appGoToArtist));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.appGoToArtist));
    // A credit that splits into several names asks which artist to open.
    final picker = find.byType(ListTile);
    await _pumpUntil(
      tester,
      find.descendant(of: picker, matching: find.text('Guest')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: picker, matching: find.text('Artist')),
    );
    await _pumpUntil(tester, find.byType(LocalArtistScreen));
    expect(
      tester
          .widget<LocalArtistScreen>(find.byType(LocalArtistScreen))
          .artistName,
      'Artist',
    );
  });

  testWidgets('the metadata sheet cannot be dismissed while saving', (
    tester,
  ) async {
    const channel = MethodChannel('com.amwolfstein.sistrum/backend');
    final saving = Completer<Map<String, dynamic>>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      switch (call.method) {
        case 'editFileMetadata':
          return saving.future;
        case 'acquireMediaDirectory' || 'releaseMediaDirectory':
          return '';
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await _mount(tester);
    final l10n = AppLocalizations.of(tester.element(find.byType(LocalSongRow)));
    await _openMenu(tester);
    await tester.ensureVisible(find.text(l10n.trackEditMetadata));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.trackEditMetadata));
    await _pumpUntil(tester, find.byType(EditMetadataSheet));
    await tester.pump(const Duration(milliseconds: 300));
    // The route's own drag must not bypass the PopScope guard.
    expect(
      tester.widget<BottomSheet>(find.byType(BottomSheet)).enableDrag,
      isFalse,
    );

    await tester.tap(find.text(l10n.dialogSave));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(EditMetadataSheet), findsOneWidget);

    saving.complete({'method': 'native'});
    await tester.pumpAndSettle();
    expect(find.byType(EditMetadataSheet), findsNothing);
    await _runAction(tester, pendingAction!);
    expect(await pendingAction!, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('CUE split confirm explains the destination picker', (
    tester,
  ) async {
    const channel = MethodChannel('com.amwolfstein.sistrum/backend');
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call.method);
      if (call.method == 'parseCueSheet') {
        return {
          'audio_path': '/audio.flac',
          'album': 'Album',
          'artist': 'Artist',
          'tracks': [
            {'number': 1, 'title': 'Part one', 'start_sec': 0, 'end_sec': 30},
          ],
        };
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final file = File('${directory.path}/album.cue')
      ..writeAsStringSync('FILE "album.flac" WAVE');
    final cue = LocalLibraryItem(
      id: 'cue-row',
      trackName: 'Part one',
      artistName: 'Artist',
      albumName: 'Album',
      filePath: '${file.path}#track01',
      format: 'cue+flac',
      scannedAt: DateTime(2026),
    );
    await _mount(tester, item: cue);
    final l10n = AppLocalizations.of(tester.element(find.byType(LocalSongRow)));
    await _openMenu(tester);
    await tester.ensureVisible(find.text(l10n.cueSplitTitle));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.cueSplitTitle));
    await _pumpUntil(tester, find.text(l10n.cueSplitConfirmTitle));
    await tester.pumpAndSettle();
    expect(find.text(l10n.cueSplitConfirmMessage('Album', 1)), findsOneWidget);
    await tester.tap(find.text(l10n.cueSplitButton));
    await _runAction(tester, pendingAction!);
    await tester.pumpAndSettle();
    expect(calls, contains('pickSafTree'));
    expect(calls, isNot(contains('safCreateFromPath')));
  });
}
