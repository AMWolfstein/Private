part of 'library_native_adapter_test.dart';

void _registerLibraryNativeAdapterTimestamps() {
  test(
    'timestamp snapshot retains sentinels and only backfills still missing eligible live rows',
    () async {
      for (final id in ['zero', 'changed', 'legacy']) {
        await addNativeLibraryTrack(
          live,
          nativeLibraryTrack(id, timestamp: 0, version: id == 'legacy' ? 3 : 4),
        );
      }
      _native.afterStage = () async {
        await live.update(
          'library',
          {'file_mod_time': 777, 'sort_added': 777},
          where: 'id=?',
          whereArgs: ['changed'],
        );
        await live.update(
          'library',
          {'file_mod_time': 0},
          where: 'id=?',
          whereArgs: ['old'],
        );
      };
      final path = await adapter.writeFileModTimesSnapshot(
        'source',
        requestId: 'snapshot',
        isCancelled: () => false,
      );
      expect(await File(path).readAsLines(), [
        '999\t/music/changed.flac',
        '-1\t/music/legacy.flac',
        '1770000000000\t/music/old.flac',
        '999\t/music/zero.flac',
      ]);
      final rows = await live.query(
        'library',
        columns: ['id', 'file_mod_time'],
        orderBy: 'id',
      );
      expect(rows, [
        {'id': 'changed', 'file_mod_time': 777},
        {'id': 'legacy', 'file_mod_time': 0},
        {'id': 'old', 'file_mod_time': 0},
        {'id': 'other', 'file_mod_time': 1770000000000},
        {'id': 'zero', 'file_mod_time': 999},
      ]);
      await _cleaned();
    },
  );

  test(
    'timestamp preparation DETACH failure retains projection and never invokes native',
    () async {
      final probed = _SqlProbe(live, live.path, (sql) {
        if (sql.startsWith('DETACH')) {
          throw StateError('fixture timestamp preparation detach failure');
        }
      });
      final candidate = LibraryNativeAdapter(
        probed,
        temporaryDirectory: root,
        nativeJobRunner: _native.run,
      );
      await expectLater(
        candidate.writeFileModTimesSnapshot(
          'source',
          requestId: 'timestamp-detach-prepare',
          isCancelled: () => false,
        ),
        throwsA(isA<NativeSqliteSnapshotDetachException>()),
      );
      expect(_native.stagedPaths, isEmpty);
      final stage = (await live.rawQuery('PRAGMA database_list')).singleWhere(
        (row) => (row['name'] as String).startsWith('library_private_'),
      );
      expect(await File(stage['file'] as String).exists(), isTrue);
      await live.execute('DETACH DATABASE "${stage['name']}"');
    },
  );

  test(
    'timestamp publication DETACH failure retains projection and returns durable snapshot',
    () async {
      await addNativeLibraryTrack(
        live,
        nativeLibraryTrack('zero', timestamp: 0),
      );
      var published = false;
      final probed = _SqlProbe(live, live.path, (sql) {
        if (sql.startsWith('UPDATE main.library SET file_mod_time')) {
          published = true;
        }
        if (published && sql.startsWith('DETACH')) {
          throw StateError('fixture timestamp postcommit detach failure');
        }
      });
      final candidate = LibraryNativeAdapter(
        probed,
        temporaryDirectory: root,
        nativeJobRunner: _native.run,
      );
      final output = await candidate.writeFileModTimesSnapshot(
        'source',
        requestId: 'timestamp-detach-publish',
        isCancelled: () => false,
      );
      expect(await File(output).exists(), isTrue);
      expect(
        (await live.query(
          'library',
          where: 'id=?',
          whereArgs: ['zero'],
        )).single['file_mod_time'],
        999,
      );
      expect(await File(_native.stagedPaths.single).exists(), isTrue);
      final stage = (await live.rawQuery('PRAGMA database_list')).singleWhere(
        (row) => (row['name'] as String).startsWith('library_private_'),
      );
      await live.execute('DETACH DATABASE "${stage['name']}"');
    },
  );
}
