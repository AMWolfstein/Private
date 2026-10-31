part of 'library_scan_scheduling_test.dart';

void _registerLibraryScanScheduling2() {
  test('a finished scan keeps the files it could not read', () async {
    var progress = <String, Object>{
      'is_complete': true,
      'error_count': 3,
      'failures': [
        {'path': '/music/A/broken.flac', 'message': 'invalid FLAC header'},
        {
          'path':
              'content://example.documents/tree/primary%3AMusic/document/'
              'primary%3AMusic%2FB%2Fcut.mp3',
          'message': 'Input/output error',
        },
      ],
    };
    messenger.setMockMethodCallHandler(backend, (call) async {
      if (_isScanJob(call)) {
        return '{"committed":true,"scanned_count":0,"deleted_count":0,"totalFiles":4,"skippedCount":1}';
      }
      if (call.method == 'getLibraryScanProgress') return progress;
      return null;
    });

    await library.startSourceScan('active');
    var state = container.read(localLibraryProvider);
    expect(state.scanErrorCount, 3);
    final failures = state.scanFailures['active']!;
    expect(failures.count, 3);
    expect(failures.files.map((file) => file.fileName), [
      'broken.flac',
      'cut.mp3',
    ]);
    expect(failures.files.map((file) => file.folder), ['/music/A', 'Music/B']);
    expect(failures.files.last.message, 'Input/output error');

    await _restartLibrary();
    state = container.read(localLibraryProvider);
    expect(state.scanFailures['active']?.files, hasLength(2));

    // A clean scan forgets the old list.
    progress = {'is_complete': true, 'error_count': 0};
    await library.startSourceScan('active');
    expect(container.read(localLibraryProvider).scanFailures, isEmpty);
    await _restartLibrary();
    expect(container.read(localLibraryProvider).scanFailures, isEmpty);

    // A removed folder takes its list with it.
    progress = {
      'is_complete': true,
      'error_count': 1,
      'failures': [
        {'path': '/music/broken.flac', 'message': 'EIO'},
      ],
    };
    await library.startSourceScan('active');
    expect(container.read(localLibraryProvider).scanFailures, hasLength(1));
    await library.removeSource('active');
    expect(container.read(localLibraryProvider).scanFailures, isEmpty);
    await _restartLibrary();
    expect(container.read(localLibraryProvider).scanFailures, isEmpty);
  });

  test('paused scan retains _reconnect work until it completes', () async {
    final active = library.startSourceScan('active');
    await _waitFor(() => scans.length == 1);
    await library.pauseScan();
    await _reconnect();
    await _reconnect();
    expect(scans, hasLength(1));
    await library.resumeScan();
    scans.first.$2.complete('{"cancelled":true}');
    await active;
    await _waitFor(() => scans.length == 2);
    expect(scans.last.$1, '${directory.path}/reconnect');
    scans.last.$2.complete('{"cancelled":true}');
    await _waitFor(() => !container.read(localLibraryProvider).isScanning);
  });

  test('cancel drops queued and pending-refresh _reconnect work', () async {
    final active = library.startSourceScan('active');
    await _waitFor(() => scans.length == 1);
    await _reconnect();
    final pending = Completer<bool?>();
    final started = Completer<void>();
    probe = (path, {bookmark}) {
      if (path.endsWith('/reconnect') && !started.isCompleted) {
        started.complete();
        return pending.future;
      }
      return Future<bool?>.value(available[path]);
    };
    // Make a second source transition pending rather than reusing the queue.
    await _database.updateSourceState('reconnect', available: false);
    final refresh = library.refreshSourceAvailability(scanReconnected: true);
    await started.future;
    await library.cancelScan();
    pending.complete(true);
    await refresh;
    scans.first.$2.complete('{"cancelled":true}');
    await active;
    await Future<void>.delayed(Duration.zero);
    expect(scans, hasLength(1));
  });

  test(
    'clear joins native publication and drops queued _reconnect scans',
    () async {
      final active = library.startSourceScan('active');
      await _waitFor(() => scans.length == 1);
      await _reconnect();
      final clearing = library.clearLibrary();
      await _waitFor(() => calls.contains('cancelLibraryScan'));
      expect(_database.clearCalls, 0);
      await library.startSourceScan('reconnect');
      expect(scans, hasLength(1));
      _database.countOverride = 7;
      scans.single.$2.complete(
        jsonEncode({'committed': true, 'scanned_count': 0, 'deleted_count': 0}),
      );
      await active;
      await clearing;
      await Future<void>.delayed(Duration.zero);
      expect(_database.clearCalls, 1);
      expect(_database.countOverride, 0);
      expect(container.read(localLibraryProvider).totalCount, 0);
      expect(container.read(localLibraryProvider).lastScannedAt, isNull);
      expect(scans, hasLength(1));
    },
  );

  test('clear retires scan admission waiting for its source', () async {
    final pending = Completer<List<LocalLibrarySource>>();
    final entered = Completer<void>();
    _database.sourceRead = () {
      if (!entered.isCompleted) entered.complete();
      return pending.future;
    };
    final starting = library.startSourceScan('active');
    await entered.future;
    _database.sourceRead = null;
    await library.clearLibrary();
    pending.complete(List.of(_database.sources));
    await starting;
    expect(scans, isEmpty);
    expect(_database.clearCalls, 1);
  });

  test(
    'clear avoids state publication after disposal during refresh',
    () async {
      final pending = Completer<List<LocalLibrarySource>>();
      final entered = Completer<void>();
      _database.sourceRead = () {
        if (!entered.isCompleted) entered.complete();
        return pending.future;
      };
      final clearing = library.clearLibrary();
      await entered.future;
      container.dispose();
      pending.complete(List.of(_database.sources));
      await clearing;
      expect(_database.clearCalls, 1);
    },
  );

  test('disposing a paused scan cancels native ownership', () async {
    final active = library.startSourceScan('active');
    await _waitFor(() => scans.length == 1);
    await library.pauseScan();
    await _reconnect();
    completeOnCancel = true;
    container.dispose();
    await active;
    expect(calls, contains('cancelLibraryScan'));
    expect(scans, hasLength(1));
  });

  test('setup failure releases admission for a later scan', () async {
    _database.failLookup = true;
    await library.startScan('${directory.path}/active');
    _database.failLookup = false;
    final retry = library.startSourceScan('active');
    await _waitFor(() => scans.length == 1);
    scans.single.$2.complete(jsonEncode({'cancelled': true}));
    await retry;
    expect(container.read(localLibraryProvider).isScanning, isFalse);
  });

  test(
    'cancel after incremental native commit publishes the changed index',
    () async {
      final version = container.read(localLibraryProvider).loadedIndexVersion;
      final active = library.startSourceScan('active');
      await _waitFor(() => scans.length == 1);
      await library.cancelScan();
      _database.countOverride = 7;
      scans.single.$2.complete(
        jsonEncode({'committed': true, 'scanned_count': 0, 'deleted_count': 0}),
      );
      await active;
      final state = container.read(localLibraryProvider);
      expect(state.totalCount, 7);
      expect(state.loadedIndexVersion, greaterThan(version));
      expect(state.scanWasCancelled, isTrue);
      expect(state.isScanning, isFalse);
    },
  );

  test('cancel after full replacement publishes the committed index', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    _database.fullReplacement = () async {
      entered.complete();
      await release.future;
      _database.countOverride = 7;
      return (inserted: 7);
    };
    messenger.setMockMethodCallHandler(backend, (call) async {
      if (call.method == 'scanLibraryFolderToNDJSONFile') {
        final path = (call.arguments as Map)['output_path'] as String;
        await File(path).writeAsString('');
        return {'path': path, 'count': 0, 'error_count': 0};
      }
      return null;
    });
    final version = container.read(localLibraryProvider).loadedIndexVersion;
    final active = library.startSourceScan('active', forceFullScan: true);
    await entered.future;
    await library.cancelScan();
    release.complete();
    await active;
    final state = container.read(localLibraryProvider);
    expect(state.totalCount, 7);
    expect(state.loadedIndexVersion, greaterThan(version));
    expect(state.scanWasCancelled, isTrue);
    expect(state.isScanning, isFalse);
  });
}
