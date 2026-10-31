part of 'library_native_adapter_test.dart';

late Directory root;

late SqliteProcessDatabase live;

late _NativeHarness _native;

late LibraryNativeAdapter adapter;

Future<LibraryScanNDJSONFile> _scan(
  List<Map<String, dynamic>> rows, {
  int errors = 0,
}) async {
  final file = File('${root.path}/_scan.ndjson');
  await file.writeAsString(rows.map(jsonEncode).join('\n'));
  return LibraryScanNDJSONFile(
    file: file,
    expectedCount: rows.length,
    errorCount: errors,
  );
}

Future<void> _cleaned() async {
  for (final path in _native.stagedPaths) {
    expect(await Directory(File(path).parent.path).exists(), isFalse);
  }
  expect(
    (await live.rawQuery(
      'PRAGMA database_list',
    )).map((r) => r['name']).where((name) => name != 'temp'),
    ['main'],
  );
  expect(await live.rawQuery('PRAGMA integrity_check'), [
    {'integrity_check': 'ok'},
  ]);
}

void _registerLibraryNativeAdapter1() {
  setUp(() async {
    root = await Directory.systemTemp.createTemp('library-private-adapter-');
    live = await SqliteProcessDatabase.open(path: '${root.path}/live.db');
    await createNativeLibraryFixture(live);
    _native = _NativeHarness(live);
    adapter = LibraryNativeAdapter(
      live,
      temporaryDirectory: root,
      nativeJobRunner: _native.run,
      platform: 'ios',
    );
    await addNativeLibraryTrack(live, nativeLibraryTrack('old'));
    await addNativeLibraryTrack(
      live,
      nativeLibraryTrack('other', path: '/other/other.flac'),
      source: 'other',
    );
  });
  tearDown(() async {
    await live.close();
    await root.delete(recursive: true);
  });

  test('full private staging publishes all local rows', () async {
    final rows = [nativeLibraryTrack('new'), nativeLibraryTrack('download')];
    final result = await adapter.importScanFile(
      'source',
      await _scan(rows),
      requestId: 'full',
      isCancelled: () => false,
    );
    expect(result, containsPair('durable', true));
    expect(result['inserted'], 2);
    expect(
      await live.query(
        'library',
        where: 'source_id = ?',
        whereArgs: ['source'],
      ),
      rows
          .map((row) => LibraryRowMapper.encode(row, sourceId: 'source'))
          .toList(),
    );
    expect(
      (await live.query('library_path_keys')).map((r) => r['item_id']).toSet(),
      {'new', 'download', 'other'},
    );
    expect(
      await live.rawQuery(
        "SELECT name FROM sqlite_master WHERE name LIKE '%lookup%'",
      ),
      isEmpty,
    );
    await _cleaned();
  });

  test(
    'partial and empty scans preserve missing rows only for partial scans',
    () async {
      await adapter.importScanFile(
        'source',
        await _scan([nativeLibraryTrack('new')], errors: 1),
        requestId: 'partial',
        isCancelled: () => false,
      );
      expect((await live.query('library', orderBy: 'id')).map((r) => r['id']), [
        'new',
        'old',
        'other',
      ]);
      await adapter.importScanFile(
        'source',
        await _scan([], errors: 1),
        requestId: 'empty-partial',
        isCancelled: () => false,
      );
      expect((await live.query('library', orderBy: 'id')).map((r) => r['id']), [
        'new',
        'old',
        'other',
      ]);
      final result = await adapter.importScanFile(
        'source',
        await _scan([]),
        requestId: 'empty',
        isCancelled: () => false,
      );
      expect(result['inserted'], 0);
      expect((await live.query('library')).map((r) => r['id']), ['other']);
      await _cleaned();
    },
  );

  test(
    'incremental keeps legacy downloads and removes exact source-scoped deleted paths',
    () async {
      await addNativeLibraryTrack(live, nativeLibraryTrack('unchanged'));
      await addNativeLibraryTrack(live, nativeLibraryTrack('unreadable'));
      _native.incremental = [
        nativeLibraryTrack('new'),
        nativeLibraryTrack('download'),
      ];
      _native.removed = [
        '/music/old.flac',
        '/music/old.flac',
        '/other/other.flac',
      ];
      final result = await adapter.scanIncremental(
        'source',
        '/music',
        '${root.path}/snapshot.tsv',
        isSaf: false,
        requestId: 'incremental',
        isCancelled: () => false,
      );
      expect(result['inserted'], 2);
      expect(result['deleted_count'], 1);
      expect(result['skippedCount'], 3);
      expect(result['scanned_count'], 2);
      expect(result['totalFiles'], 5);
      expect((await live.query('library', orderBy: 'id')).map((r) => r['id']), [
        'download',
        'new',
        'other',
        'unchanged',
        'unreadable',
      ]);
      expect(
        (await live.query(
          'library_path_keys',
        )).map((r) => r['item_id']).toSet(),
        {'download', 'new', 'other', 'unchanged', 'unreadable'},
      );
      await _cleaned();
    },
  );

  test(
    'source edit and cancellation after private commit never publish',
    () async {
      final before = await nativeLibraryDigest(live);
      var cancelled = false;
      _native.afterStage = () async {
        cancelled = true;
      };
      await expectLater(
        adapter.importScanFile(
          'source',
          await _scan([nativeLibraryTrack('new')]),
          requestId: 'cancel',
          isCancelled: () => cancelled,
        ),
        throwsStateError,
      );
      expect(await nativeLibraryDigest(live), before);
      _native.afterStage = () => live
          .update(
            'library_sources',
            {'path': '/changed'},
            where: 'id=?',
            whereArgs: ['source'],
          )
          .then((_) {});
      await expectLater(
        adapter.importScanFile(
          'source',
          await _scan([nativeLibraryTrack('new')]),
          requestId: 'source-edit',
          isCancelled: () => false,
        ),
        throwsStateError,
      );
      expect(await nativeLibraryDigest(live), before);
      await _cleaned();
    },
  );

  test(
    'late owner SQL failure rolls back rows, path keys and derived lookups',
    () async {
      final before = await nativeLibraryDigest(live);
      await live.execute(
        "CREATE TRIGGER reject_new BEFORE INSERT ON library WHEN new.id='new' BEGIN SELECT RAISE(ABORT,'fixture late failure'); END",
      );
      await expectLater(
        adapter.importScanFile(
          'source',
          await _scan([nativeLibraryTrack('new')]),
          requestId: 'rollback',
          isCancelled: () => false,
        ),
        throwsStateError,
      );
      expect(await nativeLibraryDigest(live), before);
      expect(
        await live.rawQuery(
          "SELECT name FROM sqlite_temp_master WHERE name LIKE 'library_private_%_selected'",
        ),
        isEmpty,
      );
      await _cleaned();
    },
  );

  test(
    'cancellation during owner publication rolls back accepted rows and keys',
    () async {
      var cancelled = false;
      final before = await nativeLibraryDigest(live);
      final probed = _SqlProbe(live, live.path, (sql) {
        if (sql.startsWith('INSERT OR REPLACE INTO main.library(')) {
          cancelled = true;
        }
      });
      final candidate = LibraryNativeAdapter(
        probed,
        temporaryDirectory: root,
        nativeJobRunner: _native.run,
      );
      await expectLater(
        candidate.importScanFile(
          'source',
          await _scan([nativeLibraryTrack('new')]),
          requestId: 'cancel-publication',
          isCancelled: () => cancelled,
        ),
        throwsStateError,
      );
      expect(await nativeLibraryDigest(live), before);
      await _cleaned();
    },
  );

  test(
    'failed preparation DETACH retains file and never invokes native',
    () async {
      final probed = _SqlProbe(live, live.path, (sql) {
        if (sql.startsWith('DETACH')) {
          throw StateError('fixture detach failure');
        }
      });
      final candidate = LibraryNativeAdapter(
        probed,
        temporaryDirectory: root,
        nativeJobRunner: _native.run,
      );
      await expectLater(
        candidate.importScanFile(
          'source',
          await _scan([nativeLibraryTrack('new')]),
          requestId: 'detach-prepare',
          isCancelled: () => false,
        ),
        throwsA(isA<NativeSqliteSnapshotDetachException>()),
      );
      expect(_native.stagedPaths, isEmpty);
      final attached = await live.rawQuery('PRAGMA database_list');
      final stage = attached.singleWhere(
        (row) => (row['name'] as String).startsWith('native_snapshot_'),
      );
      expect(await File(stage['file'] as String).exists(), isTrue);
      await live.execute('DETACH DATABASE "${stage['name']}"');
    },
  );

  test(
    'cancellation after durable commit still returns the committed result',
    () async {
      var publishing = false;
      var cancelled = false;
      final probed = _SqlProbe(live, live.path, (sql) {
        if (sql.startsWith('INSERT OR REPLACE INTO main.library(')) {
          publishing = true;
        }
        if (publishing && sql.startsWith('DETACH')) {
          cancelled = true;
        }
      });
      final candidate = LibraryNativeAdapter(
        probed,
        temporaryDirectory: root,
        nativeJobRunner: _native.run,
      );
      final result = await candidate.importScanFile(
        'source',
        await _scan([nativeLibraryTrack('new')]),
        requestId: 'cancel-after-commit',
        isCancelled: () => cancelled,
      );
      expect(cancelled, isTrue);
      expect(result['durable'], isTrue);
      expect(
        (await live.query('library', orderBy: 'id')).map((row) => row['id']),
        ['new', 'other'],
      );
      await _cleaned();
    },
  );

  test(
    'failed DETACH after durable publication retains stage and reports success',
    () async {
      var published = false;
      final probed = _SqlProbe(live, live.path, (sql) {
        if (sql.startsWith('INSERT OR REPLACE INTO main.library(')) {
          published = true;
        }
        if (published && sql.startsWith('DETACH')) {
          throw StateError('fixture postcommit detach failure');
        }
      });
      final candidate = LibraryNativeAdapter(
        probed,
        temporaryDirectory: root,
        nativeJobRunner: _native.run,
      );
      final result = await candidate.importScanFile(
        'source',
        await _scan([nativeLibraryTrack('new')]),
        requestId: 'detach-publish',
        isCancelled: () => false,
      );
      expect(result['durable'], isTrue);
      expect((await live.query('library', orderBy: 'id')).map((r) => r['id']), [
        'new',
        'other',
      ]);
      expect(await File(_native.stagedPaths.single).exists(), isTrue);
      final stage = (await live.rawQuery('PRAGMA database_list')).singleWhere(
        (row) => (row['name'] as String).startsWith('library_private_'),
      );
      await live.execute('DETACH DATABASE "${stage['name']}"');
    },
  );
}
