part of 'library_scan_scheduling_test.dart';

const backend = MethodChannel('com.amwolfstein.sistrum/backend');

const paths = MethodChannel('plugins.flutter.io/path_provider');

const notifications = MethodChannel(
  'dexterous.com/flutter/local_notifications',
);

final messenger =
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

late Directory directory;

late _Database _database;

late ProviderContainer container;

late LocalLibraryNotifier library;

late Map<String, bool> available;

late LocalLibraryAvailabilityProbe probe;

late List<(String, Completer<String>)> scans;

late List<String> calls;

late List<MethodCall> notificationCalls;

bool completeOnCancel = false;

Future<void> _reconnect() async {
  available['${directory.path}/reconnect'] = true;
  await library.refreshSourceAvailability(scanReconnected: true);
}

Future<void> _restartLibrary() async {
  container.dispose();
  container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(_Settings.new),
      localLibraryProvider.overrideWith(
        () => LocalLibraryNotifier(
          database: _database,
          availabilityProbe: (path) => probe(path),
        ),
      ),
    ],
  );
  library = container.read(localLibraryProvider.notifier);
  await _waitFor(() => !container.read(localLibraryProvider).isLoading);
}

void _registerLibraryScanScheduling1() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AndroidFlutterLocalNotificationsPlugin.registerWith();
  SharedPreferences.setMockInitialValues({});

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await (await SharedPreferences.getInstance()).clear();
    directory = await Directory.systemTemp.createTemp('library-scheduling-');
    _database = _Database([
      for (final id in ['active', 'reconnect'])
        LocalLibrarySource(
          id: id,
          path: '${directory.path}/$id',
          displayName: id,
          trackCount: 1,
          available: id == 'active',
        ),
    ]);
    available = {
      for (final source in _database.sources) source.path: source.available,
    };
    probe = (path, {bookmark}) async => available[path];
    scans = [];
    calls = [];
    notificationCalls = [];
    completeOnCancel = false;
    messenger.setMockMethodCallHandler(paths, (_) async => directory.path);
    messenger.setMockMethodCallHandler(notifications, (call) async {
      notificationCalls.add(call);
      return call.method == 'initialize' ? true : null;
    });
    messenger.setMockMethodCallHandler(backend, (call) async {
      calls.add(call.method);
      if (_isScanJob(call)) {
        final result = Completer<String>();
        scans.add((_jobRequest(call)['folder_path'] as String, result));
        return result.future;
      }
      if (call.method == 'cancelLibraryScan' && completeOnCancel) {
        for (final (_, response) in scans) {
          if (!response.isCompleted) response.complete('{"cancelled":true}');
        }
      }
      return null;
    });
    container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(_Settings.new),
        localLibraryProvider.overrideWith(
          () => LocalLibraryNotifier(
            database: _database,
            availabilityProbe: (path) => probe(path),
          ),
        ),
      ],
    );
    library = container.read(localLibraryProvider.notifier);
    await _waitFor(() => !container.read(localLibraryProvider).isLoading);
  });

  tearDown(() async {
    container.dispose();
    for (final (_, response) in scans) {
      if (!response.isCompleted) response.complete('{"cancelled":true}');
    }
    await Future<void>.delayed(Duration.zero);
    messenger.setMockMethodCallHandler(backend, null);
    messenger.setMockMethodCallHandler(paths, null);
    messenger.setMockMethodCallHandler(notifications, null);
    await directory.delete(recursive: true);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'Android crash details are recovered and retained without manual logs',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(localLibraryActiveScanStartedAtKey, 100);
      await prefs.setString(localLibraryActiveScanSourceKey, 'active');
      var exitReads = 0;
      messenger.setMockMethodCallHandler(backend, (call) async {
        if (call.method == 'getLibraryScanExitInfo') {
          exitReads++;
          expect((call.arguments as Map)['started_after'], 100);
          return {
            'reason': 'Native crash',
            'description': 'SIGSEGV in example codec',
            'timestamp': 200,
            'status': 11,
          };
        }
        return null;
      });
      await _restartLibrary();
      final state = container.read(localLibraryProvider);
      expect(state.sources.first.lastScanError, contains('Native crash'));
      expect(
        state.sources.first.lastScanError,
        contains('SIGSEGV in example codec'),
      );
      expect(state.totalCount, 1);
      expect(exitReads, 1);
      final shows = notificationCalls
          .where((call) => call.method == 'show')
          .length;
      await _restartLibrary();
      expect(exitReads, 1);
      expect(
        notificationCalls.where((call) => call.method == 'show').length,
        shows,
      );
      expect(
        container.read(localLibraryProvider).sources.first.lastScanError,
        contains('Native crash'),
      );
    },
  );

  for (final failErrorWrite in [false, true]) {
    test(
      'restart reports an interrupted scan with auto-scan off (save failure: $failErrorWrite)',
      () async {
        final previousCount = container.read(localLibraryProvider).totalCount;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(localLibraryActiveScanSourceKey, 'active');
        _database.failScanErrorWrite = failErrorWrite;
        container.dispose();
        container = ProviderContainer(
          overrides: [
            settingsProvider.overrideWith(_Settings.new),
            localLibraryProvider.overrideWith(
              () => LocalLibraryNotifier(
                database: _database,
                availabilityProbe: (path) => probe(path),
              ),
            ),
          ],
        );
        library = container.read(localLibraryProvider.notifier);
        await _waitFor(() => !container.read(localLibraryProvider).isLoading);
        final state = container.read(localLibraryProvider);
        expect(state.isScanning, isFalse);
        expect(state.loadFailed, isFalse);
        expect(state.totalCount, previousCount);
        expect(scans, isEmpty);
        expect(prefs.getString(localLibraryActiveScanSourceKey), 'active');
        if (!failErrorWrite) {
          expect(state.sources.first.lastScanError, contains('interrupted'));
        }
        final shows = notificationCalls.where((call) => call.method == 'show');
        final failure = shows.last.arguments as Map;
        expect(failure['title'], 'Library scan failed');
        expect(failure['body'], contains('interrupted'));
        expect(
          notificationCalls.any((call) => call.method == 'cancel'),
          isTrue,
        );
        final notificationCount = shows.length;
        await library.reloadFromStorage();
        expect(
          notificationCalls.where((call) => call.method == 'show').length,
          notificationCount,
        );
      },
    );
  }

  test(
    'a scan failure remains visible when saving the error also fails',
    () async {
      final previousCount = container.read(localLibraryProvider).totalCount;
      _database.failScanErrorWrite = true;
      final active = library.startSourceScan('active');
      await _waitFor(() => scans.length == 1);
      scans.single.$2.completeError(
        PlatformException(code: 'scan_failed', message: 'Invalid audio header'),
      );
      await active;
      final state = container.read(localLibraryProvider);
      expect(state.isScanning, isFalse);
      expect(state.totalCount, previousCount);
      expect(
        state.sources.first.lastScanError,
        contains('Invalid audio header'),
      );
      final failure =
          notificationCalls.lastWhere((call) => call.method == 'show').arguments
              as Map;
      expect(failure['title'], 'Library scan failed');
      expect(failure['body'], contains('Invalid audio header'));
      expect(
        (await SharedPreferences.getInstance()).getString(
          localLibraryActiveScanSourceKey,
        ),
        isNull,
      );
    },
  );

  test(
    'a delayed progress notification cannot overwrite a scan failure',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      messenger.setMockMethodCallHandler(notifications, (call) async {
        if (call.method == 'show' &&
            (call.arguments as Map)['body'].toString().contains('track.flac')) {
          if (!entered.isCompleted) entered.complete();
          await release.future;
        }
        notificationCalls.add(call);
        return call.method == 'initialize' ? true : null;
      });
      messenger.setMockMethodCallHandler(backend, (call) async {
        if (_isScanJob(call)) {
          final response = Completer<String>();
          scans.add((_jobRequest(call)['folder_path'] as String, response));
          return response.future;
        }
        if (call.method == 'getLibraryScanProgress') {
          return {
            'scanned_files': 785,
            'total_files': 1877,
            'progress_pct': 42,
            'current_file': 'track.flac',
          };
        }
        return null;
      });
      final active = library.startSourceScan('active');
      await entered.future.timeout(const Duration(seconds: 5));
      scans.single.$2.completeError(StateError('Scan stopped'));
      await _waitFor(() => !container.read(localLibraryProvider).isScanning);
      release.complete();
      await active;
      final shows = notificationCalls
          .where((call) => call.method == 'show')
          .toList();
      expect((shows.last.arguments as Map)['title'], 'Library scan failed');
      expect((shows.last.arguments as Map)['body'], contains('Scan stopped'));
      expect(
        (shows.last.arguments as Map)['id'],
        NotificationService.libraryScanId,
      );
    },
  );

  test('concurrent starts own one preflight and one native scan', () async {
    final pending = Completer<bool?>();
    var probes = 0;
    probe = (path, {bookmark}) {
      probes++;
      return pending.future;
    };
    final first = library.startSourceScan('active');
    await _waitFor(() => probes == 1);
    await library.startSourceScan('active');
    expect(probes, 1);
    pending.complete(true);
    await _waitFor(() => scans.length == 1);
    scans.single.$2.complete('{"cancelled":true}');
    await first;
    expect(scans, hasLength(1));
  });

  for (final dispose in [false, true]) {
    test('${dispose ? 'disposal' : 'cancel'} stops owned preflight', () async {
      final pending = Completer<bool?>();
      final started = Completer<void>();
      probe = (path, {bookmark}) {
        started.complete();
        return pending.future;
      };
      final scan = library.startSourceScan('active');
      await started.future;
      if (dispose) {
        container.dispose();
      } else {
        await library.cancelScan();
      }
      pending.complete(true);
      await scan;
      expect(scans, isEmpty);
      if (!dispose) {
        expect(container.read(localLibraryProvider).scanWasCancelled, isTrue);
        probe = (path, {bookmark}) async => available[path];
        final retry = library.startSourceScan('active');
        await _waitFor(() => scans.length == 1);
        scans.single.$2.complete('{"cancelled":true}');
        await retry;
      }
    });
  }

  for (final remove in [false, true]) {
    for (final duringProbe in [false, true]) {
      test(
        '${remove ? 'remove' : 'disable'} supersedes ${duringProbe ? 'probe' : 'source read'}',
        () async {
          final started = Completer<void>();
          final pending = Completer<bool?>();
          final snapshot = Completer<List<LocalLibrarySource>>();
          final oldSources = List.of(_database.sources);
          if (duringProbe) {
            probe = (path, {bookmark}) {
              started.complete();
              return pending.future;
            };
          } else {
            _database.sourceRead = () {
              started.complete();
              return snapshot.future;
            };
          }
          final scan = library.startSourceScan('active');
          await started.future;
          _database.sourceRead = null;
          if (remove) {
            await library.removeSource('active');
          } else {
            await library.setSourceEnabled('active', false);
          }
          if (duringProbe) {
            pending.complete(true);
          } else {
            snapshot.complete(oldSources);
          }
          await scan;
          expect(scans, isEmpty);
        },
      );
    }
  }
}
