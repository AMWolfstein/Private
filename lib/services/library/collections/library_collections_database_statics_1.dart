part of 'library_collections_database.dart';

extension _LibraryCollectionsDatabaseStatics1 on LibraryCollectionsDatabase {
  static Future<void> upgradeDatabaseSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    _log.i(
      'Collections database v$oldVersion needs no upgrade to v$newVersion',
    );
  }

  static Future<LibraryCollectionsSnapshot> writeDatabaseBackupSnapshot(
    Database db, {
    Directory? temporaryDirectory,
  }) async {
    final directory =
        await (temporaryDirectory ?? await getTemporaryDirectory()).createTemp(
          'collection-backup-',
        );
    final path = '${directory.path}/rows.ndjson';
    final output = File(path).openWrite();
    var count = 0;
    try {
      await db.transaction((txn) async {
        for (final (table, kind, date, ascending) in [
          (tableLoved, 'loved', 'added_at', false),
          (tablePlaylists, 'playlist', 'created_at', false),
          (tableFavoriteArtists, 'artist', 'added_at', false),
          (tablePlaylistTracks, 'backup_track', 'added_at', true),
        ]) {
          Object? lastDate;
          int? lastRow;
          final direction = ascending ? 'ASC' : 'DESC';
          final compare = ascending ? '>' : '<';
          while (true) {
            final rows = await txn.rawQuery(
              'SELECT rowid AS __row, * FROM $table '
              '${lastRow == null ? '' : 'WHERE $date$compare? OR ($date=? AND rowid$compare?)'} '
              'ORDER BY $date $direction,rowid $direction LIMIT 256',
              lastRow == null ? const [] : [lastDate, lastDate, lastRow],
            );
            if (rows.isEmpty) break;
            for (final row in rows) {
              final values = Map<String, dynamic>.from(row)..remove('__row');
              output.writeln(jsonEncode({'kind': kind, 'row': values}));
              count++;
            }
            await output.flush();
            lastDate = rows.last[date];
            lastRow = rows.last['__row'] as int;
            if (rows.length < 256) break;
          }
        }
      });
      await output.close();
      return LibraryCollectionsSnapshot(
        lovedRows: const [],
        playlistRows: const [],
        playlistTrackRows: const [],
        favoriteArtistRows: const [],
        nativeRowsPath: path,
        nativeRowsDirectory: directory.path,
        nativeRowCount: count,
      );
    } catch (_) {
      await output.close();
      await directory.delete(recursive: true);
      rethrow;
    }
  }

  static Future<LibraryCollectionsSnapshot> readDatabaseSnapshot(
    Database db, {
    NativeCollectionsJobRunner? nativeJobRunner,
    Directory? temporaryDirectory,
  }) async {
    final probe = await db.rawQuery('''
      SELECT 1 FROM $tableLoved
      UNION ALL SELECT 1 FROM $tablePlaylists
      UNION ALL SELECT 1 FROM $tablePlaylistTracks
      UNION ALL SELECT 1 FROM $tableFavoriteArtists LIMIT 64
    ''');
    if (probe.length == 64) {
      return readNativeRows(
        db,
        nativeJobRunner: nativeJobRunner,
        temporaryDirectory: temporaryDirectory,
      );
    }
    return readDartSnapshot(db);
  }

  static Future<LibraryCollectionsSnapshot> readDartSnapshotForTesting(
    Database db,
  ) => readDartSnapshot(db);

  static Future<LibraryPlaylistTracksSnapshot> readDatabasePlaylistTracks(
    Database db,
    String playlistId, {
    NativeCollectionsJobRunner? nativeJobRunner,
    Directory? temporaryDirectory,
  }) async {
    final probe = await db.rawQuery(
      'SELECT 1 FROM $tablePlaylistTracks WHERE playlist_id=? LIMIT 64',
      [playlistId],
    );
    if (probe.length == 64) {
      final snapshot = await readNativeRows(
        db,
        playlistId: playlistId,
        nativeJobRunner: nativeJobRunner,
        temporaryDirectory: temporaryDirectory,
      );
      return LibraryPlaylistTracksSnapshot(
        nativeRowsPath: snapshot.nativeRowsPath,
        nativeRowsDirectory: snapshot.nativeRowsDirectory,
        nativeRowCount: snapshot.nativeRowCount,
      );
    }
    return readDartPlaylistTracks(db, playlistId);
  }

  static Future<LibraryPlaylistTracksSnapshot> readDartPlaylistTracksForTesting(
    Database db,
    String playlistId,
  ) => readDartPlaylistTracks(db, playlistId);

  static Future<void> writeDatabaseLovedTracks(
    Database db,
    List<Map<String, String>> tracks,
  ) async {
    if (tracks.isEmpty) return;
    await sqlite.transactionWithBusyRetry(db, (txn) async {
      for (var start = 0; start < tracks.length; start += 128) {
        final batch = txn.batch();
        for (final row in tracks.skip(start).take(128)) {
          batch.insert(
            tableLoved,
            row,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      }
    });
  }

  static Future<void> deleteDatabaseLovedTracks(
    Database db,
    List<String> keys,
  ) async {
    if (keys.isEmpty) return;
    await sqlite.transactionWithBusyRetry(
      db,
      (txn) => _deleteTrackKeys(txn, tableLoved, keys),
    );
  }

  static Future<void> _deleteTrackKeys(
    DatabaseExecutor db,
    String table,
    List<String> keys, {
    String? playlistId,
  }) async {
    for (var start = 0; start < keys.length; start += 128) {
      final end = start + 128 < keys.length ? start + 128 : keys.length;
      final chunk = keys.sublist(start, end);
      await db.delete(
        table,
        where:
            '${playlistId == null ? '' : 'playlist_id = ? AND '}track_key IN (${List.filled(chunk.length, '?').join(',')})',
        whereArgs: [?playlistId, ...chunk],
      );
    }
  }

  static Future<void> deleteDatabasePlaylists(
    Database db,
    List<String> playlistIds,
  ) async {
    if (playlistIds.isEmpty) return;
    await sqlite.transactionWithBusyRetry(db, (txn) async {
      for (var start = 0; start < playlistIds.length; start += 128) {
        final end = start + 128 < playlistIds.length
            ? start + 128
            : playlistIds.length;
        final ids = playlistIds.sublist(start, end);
        await txn.delete(
          tablePlaylists,
          where: 'id IN (${List.filled(ids.length, '?').join(',')})',
          whereArgs: ids,
        );
      }
    });
  }

  static Future<void> writeDatabasePlaylistTracks(
    Database db, {
    required String playlistId,
    required String playlistUpdatedAt,
    required List<Map<String, String>> tracks,
  }) async {
    if (tracks.isEmpty) return;
    await sqlite.transactionWithBusyRetry(db, (txn) async {
      var batch = txn.batch();
      var pending = 0;
      for (final track in tracks) {
        batch.insert(tablePlaylistTracks, {
          'playlist_id': playlistId,
          'track_key': track['track_key'],
          'track_json': track['track_json'],
          'added_at': track['added_at'],
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        if (++pending == 128) {
          await batch.commit(noResult: true);
          batch = txn.batch();
          pending = 0;
        }
      }
      batch.update(
        tablePlaylists,
        {'updated_at': playlistUpdatedAt},
        where: 'id = ?',
        whereArgs: [playlistId],
      );
      await batch.commit(noResult: true);
    });
  }

  static Future<void> deleteDatabasePlaylistTracks(
    Database db, {
    required String playlistId,
    required List<String> trackKeys,
    required String playlistUpdatedAt,
  }) async {
    if (trackKeys.isEmpty) return;
    await sqlite.transactionWithBusyRetry(db, (txn) async {
      await _deleteTrackKeys(
        txn,
        tablePlaylistTracks,
        trackKeys,
        playlistId: playlistId,
      );
      await txn.update(
        tablePlaylists,
        {'updated_at': playlistUpdatedAt},
        where: 'id = ?',
        whereArgs: [playlistId],
      );
    });
  }

  static Future<void> replaceDatabaseFromBackup(
    Database db,
    Map<String, dynamic> collectionsJson, {
    String? nowIso,
  }) async {
    final restoreTime = nowIso ?? DateTime.now().toIso8601String();
    final temporary = await Directory(
      (await getTemporaryDirectory()).path,
    ).createTemp('collection-restore-');
    var detached = true;
    try {
      final path = '${temporary.path}/commands.ndjson';
      final count = await writeCollectionRestoreCommands(
        path,
        collectionsJson,
        restoreTime,
      );
      // The native backend bundles its own SQLite. Give it a private file
      // after sqflite closes that file; only the database owner publishes
      // into the live database, preserving its WAL and connection caches.
      final stagedPath = '${temporary.path}/$dbFileName';
      final stagedDatabase = await openDatabase(
        stagedPath,
        version: dbVersion,
        onConfigure: (staged) => staged.execute('PRAGMA foreign_keys=ON'),
        onCreate: createCollectionsSchema,
      );
      detached = false;
      await stagedDatabase.close();
      detached = true;
      final result = await NativeDataJobs.run({
        'operation': 'backup_collections_import',
        'collections_path': stagedPath,
        'ndjson_path': path,
        'expected_count': count,
      });
      if (result['committed'] != true) {
        throw const FormatException('Incomplete collection restore');
      }
      final alias =
          'collection_restore_${LibraryCollectionsDatabase._restoreAttachmentSequence++}';
      await db.execute('ATTACH DATABASE ? AS $alias', [stagedPath]);
      var committed = false;
      try {
        await db.transaction((txn) async {
          for (final table in [
            tablePlaylistTracks,
            tablePlaylists,
            tableLoved,
            tableFavoriteArtists,
          ]) {
            await txn.delete(table);
          }
          for (final (table, columns) in [
            (tableLoved, 'track_key,track_json,added_at'),
            (tableFavoriteArtists, 'artist_key,artist_json,added_at'),
            (tablePlaylists, 'id,name,cover_image_path,created_at,updated_at'),
            (tablePlaylistTracks, 'playlist_id,track_key,track_json,added_at'),
          ]) {
            await txn.execute(
              'INSERT INTO main.$table($columns) '
              'SELECT $columns FROM $alias.$table ORDER BY rowid',
            );
          }
        });
        committed = true;
      } finally {
        try {
          await detachNativeSqliteSnapshot(db, alias, stagedPath);
        } on NativeSqliteSnapshotDetachException {
          detached = false;
          if (!committed) rethrow;
          _log.w(
            'Collections restored; retaining staging after a failed database detach',
          );
        }
      }
    } on NativeSqliteSnapshotDetachException {
      detached = false;
      _log.w(
        'Retaining collection restore staging after a failed database detach',
      );
      rethrow;
    } finally {
      if (detached) {
        try {
          await temporary.delete(recursive: true);
        } on FileSystemException catch (error) {
          _log.w('Could not remove collection restore staging: $error');
        }
      }
    }
    _log.i('Restored collections from backup');
  }
}
