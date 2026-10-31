part of 'album_completeness_query_test.dart';

void _registerAlbumCompletenessQueryRescan() {
  testWidgets(
    'cancelling ReplayGain restores current selection after a rescan',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      _visibleTrackIds = {'complete1', 'complete2'};
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(_Settings.new),
          localLibraryProvider.overrideWith(_Local.new),
          libraryCollectionsProvider.overrideWith(_Collections.new),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: MaterialTestTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: LibrarySectionTab(librarySection: 'all'),
            ),
          ),
        ),
      );
      await _waitFor(tester, find.text('Song 1').hitTestable());
      await tester.longPress(find.text('Song 1').hitTestable());
      await tester.pump();
      await _waitFor(tester, find.byType(LibraryTrackSelectionBar));
      final bar = tester.widget<LibraryTrackSelectionBar>(
        find.byType(LibraryTrackSelectionBar),
      );
      expect(bar.selectedCount, 1);
      bar.onReplayGain(remove: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AppAlertDialog), findsOneWidget);
      expect(find.byType(LibraryTrackSelectionBar), findsNothing);

      // The query refresh settles while the dialog suppresses selection UI.
      // Cancelling must not restore its captured, now-deleted selected row.
      _visibleTrackIds = {'complete2'};
      (container.read(localLibraryProvider.notifier) as _Local)
          .refreshVisibleRows(1);
      for (var attempt = 0; attempt < 40; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 50));
        if (find.text('Song 1').evaluate().isEmpty) break;
      }
      expect(find.text('Song 1'), findsNothing);
      expect(find.text('Song 2'), findsOneWidget);
      expect(find.byType(AppAlertDialog), findsOneWidget);
      final l10n = AppLocalizations.of(
        tester.element(find.byType(LibrarySectionTab)),
      );
      await tester.tap(find.widgetWithText(AppDialogAction, l10n.dialogCancel));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(find.byType(AppAlertDialog), findsNothing);
      expect(find.byType(LibraryTrackSelectionBar), findsNothing);

      // No additional library refresh: a new selection contains only the live
      // song, with no stale count or action resurrected by dialog cancellation.
      await tester.longPress(find.text('Song 2').hitTestable());
      await tester.pump();
      await _waitFor(tester, find.byType(LibraryTrackSelectionBar));
      final currentBar = tester.widget<LibraryTrackSelectionBar>(
        find.byType(LibraryTrackSelectionBar),
      );
      expect(currentBar.selectedCount, 1);
      expect(currentBar.allSelected, isTrue);
      expect(
        (currentBar.playbackActions! as LibrarySelectionPlaybackActions)
            .items
            .single
            .localItem
            .id,
        'complete2',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      for (var attempt = 0; attempt < 10; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
    },
  );
}
