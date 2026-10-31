part of 'album_completeness_query_test.dart';

void _registerAlbumCompletenessQueryFilters() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    _visibleTrackIds = null;
    _libraryTable ??= await TestWidgetsFlutterBinding.instance.runAsync(
      libraryTableDefinition,
    );
    SharedPreferences.setMockInitialValues({});
    final previousFactory = databaseFactoryOrNull;
    databaseFactory = databaseFactorySqflitePlugin;
    addTearDown(() => databaseFactory = previousFactory);
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => '/test/documents');
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    const sqliteChannel = MethodChannel('com.tekartik.sqflite');
    final versions = <int, int>{};
    final executor = _QueryFixture();
    messenger.setMockMethodCallHandler(sqliteChannel, (call) async {
      final args = (call.arguments as Map?) ?? {};
      if (call.method == 'openDatabase') {
        final id = versions.length + 1;
        versions[id] = LibraryDatabase.schemaVersion;
        return {'id': id};
      }
      final sql = args['sql'] as String? ?? '';
      if (call.method == 'execute') {
        if (sql.contains('CREATE VIRTUAL TABLE')) {
          throw PlatformException(
            code: 'sqlite_error',
            message: 'no such module: fts5',
          );
        }
        return null;
      }
      if (call.method != 'query') return null;
      final rows = sql.toLowerCase().contains('pragma user_version')
          ? <Map<String, Object?>>[
              {'user_version': versions[args['id']]},
            ]
          : await executor.rawQuery(
              sql,
              (args['arguments'] as List?)?.cast<Object?>(),
            );
      final columns = rows.isEmpty ? <String>[] : rows.first.keys.toList();
      return {
        'columns': columns,
        'rows': [
          for (final row in rows) [for (final column in columns) row[column]],
        ],
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(sqliteChannel, null));
  });

  testWidgets('Albums section filters metadata, supports search and can be reset', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tabActive = ValueNotifier(true);
    addTearDown(tabActive.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(_Settings.new),
          localLibraryProvider.overrideWith(_Local.new),
          libraryCollectionsProvider.overrideWith(_Collections.new),
        ],
        child: MaterialApp(
          theme: MaterialTestTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ValueListenableBuilder<bool>(
            valueListenable: tabActive,
            builder: (_, active, _) => Scaffold(
              body: TickerMode(
                enabled: active,
                child: const LibrarySectionTab(librarySection: 'albums'),
              ),
            ),
          ),
        ),
      ),
    );
    await _waitFor(tester, find.text('Filters').hitTestable());
    await _waitFor(tester, find.text('complete').hitTestable());
    await tester.tap(find.text('Filters').hitTestable());
    await tester.pump(const Duration(milliseconds: 400));
    // Every fixture file is FLAC. Other formats must still be selectable,
    // rather than disappearing when they are absent from the loaded page.
    for (final label in [
      'M4A / MP4',
      'AAC',
      'ALAC',
      'OPUS',
      'OGG',
      'WAV',
      'AIFF',
      'WavPack',
      'DSF',
      'DFF',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Has ReplayGain'), findsOneWidget);
    await tester.ensureVisible(find.text('M4A / MP4'));
    await _waitFor(tester, find.text('M4A / MP4').hitTestable());
    await tester.tap(find.text('M4A / MP4'));
    await tester.ensureVisible(find.text('Has ReplayGain'));
    await _waitFor(tester, find.text('Has ReplayGain').hitTestable());
    await tester.tap(find.text('Has ReplayGain'));
    await tester.ensureVisible(find.text('Apply'));
    await _waitFor(tester, find.text('Apply').hitTestable());
    await tester.tap(find.text('Apply'));
    await tester.pump(const Duration(milliseconds: 400));
    await _waitFor(tester, find.text('No local albums'));
    expect(find.text('Song 1'), findsNothing);
    await tester.tap(find.text('Filters').hitTestable());
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('M4A / MP4'), findsOneWidget);
    expect(find.text('Has ReplayGain'), findsOneWidget);
    await _waitFor(tester, find.text('Reset').hitTestable());
    await tester.tap(find.text('Reset'));
    await tester.ensureVisible(find.text('Incomplete albums'));
    await _waitFor(tester, find.text('Incomplete albums').hitTestable());
    await tester.tap(find.text('Incomplete albums'));
    await tester.ensureVisible(find.text('Apply'));
    await _waitFor(tester, find.text('Apply').hitTestable());
    await tester.tap(find.text('Apply'));
    await tester.pump(const Duration(milliseconds: 400));
    await _waitFor(tester, find.text('1/12'));
    expect(find.text('2/4'), findsOneWidget);
    expect(find.text('2/3'), findsOneWidget);
    expect(find.text('complete'), findsNothing);
    expect(find.byTooltip('2/4 tracks · 2 missing'), findsOneWidget);
    expect(
      tester
          .widget<LibrarySectionTab>(find.byType(LibrarySectionTab))
          .librarySection,
      'albums',
    );

    // Pushing an album/detail route disables the underlying route's ticker.
    // Popping it must retain the current Albums section.
    final navigator = Navigator.of(
      tester.element(find.byType(LibrarySectionTab)),
    );
    unawaited(
      navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Album details')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Album details'), findsOneWidget);
    navigator.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester
          .widget<LibrarySectionTab>(find.byType(LibrarySectionTab))
          .librarySection,
      'albums',
    );
    await _waitFor(tester, find.text('1/12'));

    // Even an empty matching result must retain the filter controls.
    expect(find.text('Filters').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Filters').hitTestable());
    await tester.pump(const Duration(milliseconds: 400));
    await _waitFor(tester, find.text('Reset').hitTestable());
    await tester.tap(find.text('Reset'));
    await tester.ensureVisible(find.text('Apply'));
    await _waitFor(tester, find.text('Apply').hitTestable());
    await tester.tap(find.text('Apply'));
    await tester.pump(const Duration(milliseconds: 400));
    await _waitFor(tester, find.text('complete'));
    expect(find.text('1/12'), findsNothing);
    expect(
      tester
          .widget<LibrarySectionTab>(find.byType(LibrarySectionTab))
          .librarySection,
      'albums',
    );
    // Switching tabs also retains the current section; there is no default-view reset.
    tabActive.value = false;
    await tester.pump();
    tabActive.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester
          .widget<LibrarySectionTab>(find.byType(LibrarySectionTab))
          .librarySection,
      'albums',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    // Let any already-dispatched SQLite queries finish after provider disposal.
    for (var attempt = 0; attempt < 10; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  });
  testWidgets('Songs selection follows refreshed visible rows and search', (
    tester,
  ) async {
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
          home: const Scaffold(body: LibrarySectionTab(librarySection: 'all')),
        ),
      ),
    );
    await _waitFor(tester, find.text('Song 1').hitTestable());
    await tester.longPress(find.text('Song 1').hitTestable());
    await tester.pump();
    await _waitFor(tester, find.byType(LibraryTrackSelectionBar));
    await tester.tap(find.text('Song 2').hitTestable());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester
          .widget<LibraryTrackSelectionBar>(
            find.byType(LibraryTrackSelectionBar),
          )
          .selectedCount,
      2,
    );

    // A completed scan drops one selected row; the count and actions must
    // resolve the remaining visible row instead of retaining the stale ID.
    _visibleTrackIds = {'complete2'};
    (container.read(localLibraryProvider.notifier) as _Local)
        .refreshVisibleRows(1);
    await _waitFor(
      tester,
      find.byWidgetPredicate(
        (widget) =>
            widget is LibraryTrackSelectionBar && widget.selectedCount == 1,
      ),
    );
    expect(find.text('Song 1'), findsNothing);
    final bar = tester.widget<LibraryTrackSelectionBar>(
      find.byType(LibraryTrackSelectionBar),
    );
    expect(bar.allSelected, isTrue);
    expect(
      (bar.playbackActions! as LibrarySelectionPlaybackActions)
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
  });
}
