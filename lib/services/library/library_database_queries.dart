part of 'library_database.dart';

extension LibraryDatabaseQueries on LibraryDatabase {
  bool get searchFtsAvailable => _searchFtsAvailable ?? false;

  Future<List<LibrarySearchHit>> searchLibrary({
    required String query,
    required LibrarySearchKind kind,
    int limit = 40,
    int offset = 0,
  }) async {
    final db = await database;
    return LibrarySearchStore(
      db,
      localFts: searchFtsAvailable,
    ).search(query: query, kind: kind, limit: limit, offset: offset);
  }

  void _putPathKeysInBatch(Batch batch, String id, String? filePath) =>
      sqlite.putPathKeysInBatch(batch, 'library_path_keys', id, filePath);

  Future<void> upsert(Map<String, dynamic> json, {String? sourceId}) async {
    final db = await database;
    await sqlite.transactionWithBusyRetry(db, (txn) async {
      final row = await sqlite.preserveLibraryRowId(
        txn,
        LibraryRowMapper.encode(json, sourceId: sourceId),
      );
      await txn.insert(
        'library',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      final batch = txn.batch();
      _putPathKeysInBatch(
        batch,
        row['id'] as String,
        json['filePath'] as String?,
      );
      await batch.commit(noResult: true);
    });
  }

  Future<void> upsertBatch(
    List<Map<String, dynamic>> items, {
    String? sourceId,
  }) async {
    if (items.isEmpty) return;
    final db = await database;
    await sqlite.transactionWithBusyRetry(db, (txn) async {
      final batch = txn.batch();
      for (final json in items) {
        final row = await sqlite.preserveLibraryRowId(
          txn,
          LibraryRowMapper.encode(json, sourceId: sourceId),
        );
        batch.insert(
          'library',
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        _putPathKeysInBatch(
          batch,
          row['id'] as String,
          json['filePath'] as String?,
        );
      }
      await batch.commit(noResult: true);
    });
    _log.i('Batch inserted ${items.length} items');
  }

  Future<void> replaceAll(List<Map<String, dynamic>> items) async {
    final db = await database;
    await sqlite.transactionWithBusyRetry(db, (txn) async {
      await txn.delete('library_path_keys');
      await txn.delete('library');
      if (items.isEmpty) {
        return;
      }

      final batch = txn.batch();
      for (final json in items) {
        batch.insert(
          'library',
          LibraryRowMapper.encode(json),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        _putPathKeysInBatch(
          batch,
          json['id'] as String,
          json['filePath'] as String?,
        );
      }
      await batch.commit(noResult: true);
    });
    _log.i('Replaced library with ${items.length} items');
  }

  Future<void> upsertSource(LocalLibrarySource source) async {
    final db = await database;
    final values = <String, Object?>{
      'path': source.path,
      'display_name': source.displayName,
      'volume_id': source.volumeId,
      'is_removable': source.isRemovable ? 1 : 0,
      'enabled': source.enabled ? 1 : 0,
      'available': source.available ? 1 : 0,
      'last_scanned_at': source.lastScannedAt?.toIso8601String(),
      'last_seen_at': source.lastSeenAt?.toIso8601String(),
      'last_scan_error': source.lastScanError,
    };
    final updated = await db.update(
      'library_sources',
      values,
      where: 'id = ?',
      whereArgs: [source.id],
    );
    if (updated == 0) {
      await db.insert('library_sources', {'id': source.id, ...values});
    }
  }

  Future<LibraryBrowseStore> _queueStore([
    LibraryBrowseDbQuery? request,
  ]) async {
    final db = await database;
    if (request != null && isLibrarySizeSort(request.sortMode)) {
      await (_fileSizes ??= LibraryFileSizes(db)).refresh();
    }
    return LibraryBrowseStore(db, localFts: searchFtsAvailable);
  }

  Future<LibraryBrowseDbPage> getBrowseTrackPage(
    LibraryBrowseDbQuery request,
  ) async => (await _queueStore(request)).trackPage(request);

  Future<LibraryBrowseCounts> getQueueCounts(
    LibraryBrowseDbQuery request,
  ) async => (await _queueStore()).counts(request);

  Future<LibraryBrowseDbPage> getBrowseAlbumPage(
    LibraryBrowseDbQuery request,
  ) async => (await _queueStore(request)).albumPage(request);

  /// Album artists across scanned music, excluding duplicate paths.
  Future<List<Map<String, dynamic>>> getBrowseArtistRows(
    LibraryBrowseDbQuery request,
  ) async => (await _queueStore()).artistPage(request);

  Future<List<Map<String, dynamic>>> getBrowseLocalAlbumRows(
    String albumName,
    String artistName,
  ) async => (await _queueStore()).localAlbumTracks(albumName, artistName);

  Future<List<Map<String, dynamic>>> getBrowseLocalAlbumRowsByKey(
    String albumKey,
  ) async => (await _queueStore()).localAlbumTracksByKey(albumKey);

  Future<Map<String, dynamic>?> getById(String id) async {
    final db = await database;
    final rows = await db.query(
      LibraryDatabase.visibleLibraryView,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return LibraryRowMapper.decode(rows.first);
  }

  Future<Map<String, dynamic>?> getByIsrc(String isrc) async {
    final db = await database;
    final rows = await db.query(
      LibraryDatabase.visibleLibraryView,
      where: 'isrc = ?',
      whereArgs: [isrc],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return LibraryRowMapper.decode(rows.first);
  }

  Future<List<Map<String, dynamic>>> findByTrackAndArtist(
    String trackName,
    String artistName,
  ) async {
    final db = await database;
    final rows = await db.query(
      LibraryDatabase.visibleLibraryView,
      where: 'match_key = ?',
      whereArgs: [LibraryDatabase.matchKeyFor(trackName, artistName)],
    );
    return rows.map(LibraryRowMapper.decode).toList();
  }

  Future<Map<String, dynamic>?> findExisting({
    String? isrc,
    String? trackName,
    String? artistName,
  }) async {
    if (isrc != null && isrc.isNotEmpty) {
      final byIsrc = await getByIsrc(isrc);
      if (byIsrc != null) return byIsrc;
    }

    if (trackName != null && artistName != null) {
      final matches = await findByTrackAndArtist(trackName, artistName);
      if (matches.isNotEmpty) return matches.first;
    }

    return null;
  }

  /// Physical copies sharing one ISRC, excluding inactive NAS sources and
  /// alternate index/URI references to the same file. Best quality comes first.
  Future<List<IsrcDuplicateGroup>> findIsrcDuplicateGroups() async {
    final db = await database;

    return readIsrcDuplicateGroups(db);
  }

  /// Removes one row; shares the batched delete so both paths stay identical.
  Future<int> deleteByPath(String filePath) => deleteByPaths([filePath]);

  Future<void> updateAudioMetadata(
    String id, {
    int? duration,
    int? bitDepth,
    int? sampleRate,
    int? bitrate,
    bool? explicit,
    bool? hasLyrics,
    bool? hasReplayGain,
    String? format,
  }) async {
    final values = <String, dynamic>{};
    if (duration != null && duration > 0) {
      values['duration'] = duration;
    }
    if (bitDepth != null && bitDepth > 0) {
      values['bit_depth'] = bitDepth;
    }
    if (sampleRate != null && sampleRate > 0) {
      values['sample_rate'] = sampleRate;
    }
    if (bitrate != null && bitrate > 0) {
      values['bitrate'] = bitrate;
    }
    if (explicit != null) {
      values['explicit'] = explicit ? 1 : 0;
    }
    if (hasLyrics != null) {
      values['has_lyrics'] = hasLyrics ? 1 : 0;
    }
    if (hasReplayGain != null) {
      values['has_replaygain'] = hasReplayGain ? 1 : 0;
    }
    final normalizedFormat = normalizeAudioFormatValue(format);
    if (normalizedFormat != null) {
      values['format'] = normalizedFormat;
    }
    if (values.isEmpty) return;

    final db = await database;
    if (hasReplayGain == null && hasLyrics == null) {
      await db.update('library', values, where: 'id = ?', whereArgs: [id]);
      return;
    }
    // A quality-only update must not confirm absent tags. ReplayGain-only
    // writes can advance lyrics-aware rows, while older rows still rescan.
    final replayGainOnly = hasReplayGain != null && hasLyrics == null;
    final scanVersion = hasReplayGain != null
        ? LibraryDatabase.audioMetadataScanVersion
        : LibraryDatabase.lyricsMetadataScanVersion;
    final versionSql = replayGainOnly
        ? 'CASE WHEN COALESCE(audio_metadata_scan_version, 0) >= ? '
              'THEN MAX(COALESCE(audio_metadata_scan_version, 0), ?) '
              'ELSE COALESCE(audio_metadata_scan_version, 0) END'
        : 'MAX(COALESCE(audio_metadata_scan_version, 0), ?)';
    final columns = values.keys.toList(growable: false);
    await db.rawUpdate(
      'UPDATE library SET ${columns.map((column) => '$column = ?').join(', ')}, '
      'audio_metadata_scan_version = $versionSql WHERE id = ?',
      [
        ...columns.map((column) => values[column]),
        if (replayGainOnly) LibraryDatabase.lyricsMetadataScanVersion,
        scanVersion,
        id,
      ],
    );
  }

  Future<void> delete(String id) async {
    await deleteByIds([id]);
  }

  Future<int> cleanupMissingFiles({
    String? sourceId,
    Future<bool> Function()? canDelete,
  }) async {
    final db = await database;
    final removed = await cleanupMissingLibraryRows(
      db,
      sourceId: sourceId,
      canDelete: canDelete,
    );

    if (removed > 0) {
      _log.i('Cleaned up $removed missing files from library');
    }
    return removed;
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
    LibraryDatabase._database.reset();
    _fileSizes = null;
    _searchFtsAvailable = null;
  }

  Future<int> deleteByPaths(List<String> filePaths) async {
    if (filePaths.isEmpty) return 0;
    final db = await database;
    var totalDeleted = 0;
    const chunkSize = 500;
    // One commit for the whole removal; a rescan that dropped a folder can
    // otherwise pay several WAL commits per chunk.
    await sqlite.transactionWithBusyRetry(db, (txn) async {
      for (var i = 0; i < filePaths.length; i += chunkSize) {
        final end = (i + chunkSize < filePaths.length)
            ? i + chunkSize
            : filePaths.length;
        final chunk = filePaths.sublist(i, end);
        final placeholders = List.filled(chunk.length, '?').join(',');
        await txn.rawDelete(
          'DELETE FROM library_path_keys WHERE item_id IN '
          '(SELECT id FROM library WHERE file_path IN ($placeholders))',
          chunk,
        );
        totalDeleted += await txn.rawDelete(
          'DELETE FROM library WHERE file_path IN ($placeholders)',
          chunk,
        );
      }
    });
    if (totalDeleted > 0) {
      _log.i('Deleted $totalDeleted items from library');
    }
    return totalDeleted;
  }
}
