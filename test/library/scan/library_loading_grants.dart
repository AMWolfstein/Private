part of 'library_loading_test.dart';

late Directory music;

late _LibraryDatabase _database;

late ProviderContainer container;

late LocalLibraryAvailabilityProbe probe;

late _Library _library;

late _Collections _collections;

const backendChannel = MethodChannel('com.amwolfstein.sistrum/backend');

/// Records native calls made while [body] runs; other channel traffic is
/// irrelevant here and answered with null.
Future<List<MethodCall>> _recordBackendCalls(
  Future<void> Function() body,
) async {
  final calls = <MethodCall>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(backendChannel, (call) async {
    calls.add(call);
    return null;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(backendChannel, null));
  await body();
  return calls;
}

void _registerLibraryLoadingGrants() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    music = await Directory.systemTemp.createTemp('library_loading_');
    _database = _LibraryDatabase([
      LocalLibrarySource(
        id: 'music',
        path: music.path,
        displayName: 'Music',
        trackCount: 2,
      ),
    ]);
    probe = (path) => Directory(path).exists();
    _collections = _Collections();
    container = ProviderContainer(
      overrides: [
        libraryCollectionsProvider.overrideWith(() => _collections),
        settingsProvider.overrideWith(_Settings.new),
        localLibraryProvider.overrideWith(
          () => _library = _Library(_database, (path) => probe(path)),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await music.delete(recursive: true);
  });

  test(
    'saved folders appear while a large track count is still loading',
    () async {
      final pending = Completer<int>();
      _database.count = () => pending.future;
      container.read(localLibraryProvider);
      await _waitFor(
        () => container.read(localLibraryProvider).sources.isNotEmpty,
      );
      final loading = container.read(localLibraryProvider);
      expect(loading.sources.single.path, music.path);
      expect(loading.isLoading, isTrue);
      pending.complete(2);
      await _waitFor(() => !container.read(localLibraryProvider).isLoading);
      expect(container.read(localLibraryProvider).totalCount, 2);
    },
  );

  test(
    'summary failure retains folders and retry recovers without reattaching',
    () async {
      _database.count = () async => throw StateError('count read failed');
      container.read(localLibraryProvider);
      await _waitFor(() => !container.read(localLibraryProvider).isLoading);
      final failed = container.read(localLibraryProvider);
      expect(failed.loadFailed, isTrue);
      expect(failed.sources.single.path, music.path);
      _database.count = () async => 2;
      await container.read(localLibraryProvider.notifier).reloadFromStorage();
      expect(container.read(localLibraryProvider).loadFailed, isFalse);
      expect(container.read(localLibraryProvider).totalCount, 2);
      expect(container.read(localLibraryProvider).sources.single.id, 'music');
    },
  );

  for (final edit in ['disable', 'enable', 'remove']) {
    test('initial index cannot overwrite a newer source $edit', () async {
      if (edit == 'enable') {
        _database.sources = [_database.sources.single.copyWith(enabled: false)];
      }
      int currentCount() => _database.sources
          .where((source) => source.enabled && source.available)
          .fold<int>(0, (total, source) => total + source.trackCount);
      final pending = Completer<int>();
      _database.count = () => pending.future;
      container.read(localLibraryProvider);
      await _waitFor(() => _database.countReads > 0);
      // The in-flight read holds the pre-edit count; a retry must read the
      // post-edit state instead of what this stale read returns.
      final staleCount = currentCount();
      _database.count = () async => currentCount();
      if (edit == 'remove') {
        await _library.removeSource('music');
      } else {
        await _library.setSourceEnabled('music', edit == 'enable');
      }
      final version = container.read(localLibraryProvider).loadedIndexVersion;
      pending.complete(staleCount);
      await _waitFor(() => !container.read(localLibraryProvider).isLoading);
      final loaded = container.read(localLibraryProvider);
      expect(loaded.loadFailed, false);
      expect(loaded.loadedIndexVersion, version);
      expect(loaded.totalCount, edit == 'enable' ? 2 : 0);
      if (edit == 'remove') {
        expect(loaded.sources, isEmpty);
      } else {
        expect(loaded.sources.single.enabled, edit == 'enable');
      }
    });
  }

  test('removing the last source on a tree releases its grant', () async {
    const tree =
        'content://com.android.externalstorage.documents/tree/primary%3AMusic';
    _database.sources = [
      LocalLibrarySource(
        id: 'saf',
        path: tree,
        displayName: 'Music',
        trackCount: 2,
      ),
    ];
    container.read(localLibraryProvider);
    await _waitFor(() => !container.read(localLibraryProvider).isLoading);
    final calls = await _recordBackendCalls(() => _library.removeSource('saf'));
    final releases = calls.where((call) => call.method == 'safReleaseTree');
    expect(releases.map((call) => call.arguments), [
      {'tree_uri': tree},
    ]);
    expect(container.read(localLibraryProvider).sources, isEmpty);
  });

  test('a shared tree keeps its grant until its last source is gone', () async {
    const tree =
        'content://com.android.externalstorage.documents/tree/primary%3AMusic';
    _database.sources = [
      LocalLibrarySource(
        id: 'saf-a',
        path: tree,
        displayName: 'Music',
        trackCount: 1,
      ),
      LocalLibrarySource(
        id: 'saf-b',
        path: tree,
        displayName: 'Music',
        trackCount: 1,
      ),
    ];
    container.read(localLibraryProvider);
    await _waitFor(() => !container.read(localLibraryProvider).isLoading);
    final first = await _recordBackendCalls(
      () => _library.removeSource('saf-a'),
    );
    expect(first.where((call) => call.method == 'safReleaseTree'), isEmpty);
    final second = await _recordBackendCalls(
      () => _library.removeSource('saf-b'),
    );
    expect(
      second
          .where((call) => call.method == 'safReleaseTree')
          .map((call) => call.arguments),
      [
        {'tree_uri': tree},
      ],
    );
  });

  test(
    'failed reload keeps the previously loaded folders and song count',
    () async {
      container.read(localLibraryProvider);
      await _waitFor(() => !container.read(localLibraryProvider).isLoading);
      _database.failSources = true;
      await container.read(localLibraryProvider.notifier).reloadFromStorage();
      final failed = container.read(localLibraryProvider);
      expect(failed.loadFailed, isTrue);
      expect(failed.totalCount, 2);
      expect(failed.sources.single.id, 'music');
      _database.failSources = false;
      await container.read(localLibraryProvider.notifier).reloadFromStorage();
      expect(container.read(localLibraryProvider).loadFailed, isFalse);
    },
  );

  test(
    'unchanged overlapping availability refreshes share one probe',
    () async {
      container.read(localLibraryProvider);
      await _waitFor(() => !container.read(localLibraryProvider).isLoading);
      final sourceReads = _database.sourceReads;
      final countReads = _database.countReads;
      final version = container.read(localLibraryProvider).loadedIndexVersion;
      final refresh = _library.refreshSourceAvailability();
      final overlapping = _library.refreshSourceAvailability();
      expect(identical(refresh, overlapping), isTrue);
      await Future.wait([refresh, overlapping]);
      expect(_database.sourceReads, sourceReads + 1);
      expect(_database.countReads, countReads);
      expect(container.read(localLibraryProvider).loadedIndexVersion, version);
    },
  );

  test('detach and reconnect each refresh the visible index once', () async {
    _database.count = () async => _database.sources.single.available ? 2 : 0;
    container.read(localLibraryProvider);
    await _waitFor(() => !container.read(localLibraryProvider).isLoading);
    final version = container.read(localLibraryProvider).loadedIndexVersion;
    final countReads = _database.countReads;
    probe = (path) async => false;
    await _library.refreshSourceAvailability();
    expect(
      container.read(localLibraryProvider).sources.single.available,
      false,
    );
    expect(container.read(localLibraryProvider).totalCount, 0);
    expect(
      container.read(localLibraryProvider).loadedIndexVersion,
      version + 1,
    );

    probe = (path) async => true;
    await Future.wait([
      _library.refreshSourceAvailability(),
      _library.refreshSourceAvailability(scanReconnected: true),
    ]);
    expect(container.read(localLibraryProvider).sources.single.available, true);
    expect(container.read(localLibraryProvider).totalCount, 2);
    expect(
      container.read(localLibraryProvider).loadedIndexVersion,
      version + 2,
    );
    expect(_database.countReads, countReads + 2);
    await _waitFor(() => _library.scannedSources.isNotEmpty);
    expect(_library.scannedSources, ['music']);
  });

  test(
    'an inconclusive probe retains availability and the loaded index',
    () async {
      container.read(localLibraryProvider);
      await _waitFor(() => !container.read(localLibraryProvider).isLoading);
      final countReads = _database.countReads;
      final version = container.read(localLibraryProvider).loadedIndexVersion;
      probe = (path) async => null;
      await _library.refreshSourceAvailability();
      expect(
        container.read(localLibraryProvider).sources.single.available,
        true,
      );
      expect(_database.countReads, countReads);
      expect(container.read(localLibraryProvider).loadedIndexVersion, version);
    },
  );

  test('a newer storage event supersedes a pending detached result', () async {
    container.read(localLibraryProvider);
    await _waitFor(() => !container.read(localLibraryProvider).isLoading);
    final pending = Completer<bool?>();
    var probes = 0;
    probe = (path) =>
        ++probes == 1 ? pending.future : Future<bool?>.value(true);
    final countReads = _database.countReads;
    final refresh = _library.refreshSourceAvailability();
    await _waitFor(() => probes == 1);
    final reconnect = _library.refreshSourceAvailability(scanReconnected: true);
    pending.complete(false);
    await Future.wait([refresh, reconnect]);
    expect(probes, 2);
    expect(_database.availabilityWrites, 0);
    expect(_database.countReads, countReads);
    expect(container.read(localLibraryProvider).sources.single.available, true);
  });

  for (final remove in [false, true]) {
    test(
      'pending probes do not overwrite ${remove ? 'removal' : 'disable'}',
      () async {
        container.read(localLibraryProvider);
        await _waitFor(() => !container.read(localLibraryProvider).isLoading);
        final pending = Completer<bool?>();
        var probes = 0;
        probe = (path) =>
            ++probes == 1 ? pending.future : Future<bool?>.value(true);
        final refresh = _library.refreshSourceAvailability();
        await _waitFor(() => probes == 1);
        if (remove) {
          await _library.removeSource('music');
        } else {
          await _library.setSourceEnabled('music', false);
        }
        final countReads = _database.countReads;
        final version = container.read(localLibraryProvider).loadedIndexVersion;
        pending.complete(false);
        await refresh;
        expect(_database.availabilityWrites, 0);
        expect(_database.countReads, countReads);
        expect(
          container.read(localLibraryProvider).loadedIndexVersion,
          version,
        );
        final sources = container.read(localLibraryProvider).sources;
        if (remove) {
          expect(sources, isEmpty);
        } else {
          expect(sources.single.enabled, false);
          expect(sources.single.available, true);
        }
      },
    );
  }

  test('a superseded summary cannot restore stale counts', () async {
    container.read(localLibraryProvider);
    await _waitFor(() => !container.read(localLibraryProvider).isLoading);
    final pending = Completer<int>();
    _database.count = () => pending.future;
    probe = (path) async => false;
    final countReads = _database.countReads;
    final refresh = _library.refreshSourceAvailability();
    await _waitFor(() => _database.countReads > countReads);
    // The superseded read still returns the old count; every fresh read after
    // the source is disabled must see 0.
    _database.count = () async => 0;
    await _library.setSourceEnabled('music', false);
    pending.complete(2);
    await refresh;
    expect(container.read(localLibraryProvider).sources.single.enabled, false);
    expect(container.read(localLibraryProvider).totalCount, 0);
  });

  test('an unavailable folder remains attached instead of vanishing', () async {
    await music.delete(recursive: true);
    _database.sources = [
      LocalLibrarySource(
        id: 'missing',
        path: music.path,
        displayName: 'Offline music',
        isRemovable: true,
        available: false,
      ),
    ];
    _database.count = () async => 0;
    container.read(localLibraryProvider);
    await _waitFor(() => !container.read(localLibraryProvider).isLoading);
    final loaded = container.read(localLibraryProvider);
    expect(loaded.loadFailed, isFalse);
    expect(loaded.sources.single.available, isFalse);
    expect(loaded.sources.single.path, music.path);
    // Keep teardown simple after deliberately removing the storage above.
    await music.create();
  });

  test('reload invalidates a summary already being read', () async {
    final first = Completer<int>();
    _database.count = () => first.future;
    container.read(localLibraryProvider);
    await _waitFor(() => _database.countReads == 1);
    _database.count = () async => 7;
    final reloaded = _library.reloadFromStorage();
    first.complete(2);
    await reloaded;
    final current = container.read(localLibraryProvider);
    expect(_database.countReads, 2);
    expect(current.totalCount, 7);
    expect(current.isLoading, isFalse);
  });

  test(
    'concurrent reloads share the retry after an earlier read fails',
    () async {
      final old = Completer<int>();
      final retry = Completer<int>();
      _database.count = () => old.future;
      container.read(localLibraryProvider);
      await _waitFor(() => _database.countReads == 1);
      _database.count = () => retry.future;
      final firstReload = _library.reloadFromStorage();
      final secondReload = _library.reloadFromStorage();
      old.completeError(StateError('stale read failed'));
      await _waitFor(() => _database.countReads == 2);
      retry.complete(2);
      await Future.wait([firstReload, secondReload]);
      expect(_database.countReads, 2);
      expect(container.read(localLibraryProvider).totalCount, 2);
    },
  );
}
