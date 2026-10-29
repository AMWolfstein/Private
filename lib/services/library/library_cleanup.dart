import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:sistrum/services/library/library_cover_snapshot.dart';
import 'package:sistrum/services/library/library_schema.dart';
import 'package:sistrum/services/library/native_cache_maintenance.dart';
import 'package:sistrum/utils/file_access.dart';
import 'package:sistrum/utils/logger.dart';

/// Removes rows superseded by a staged scan inside the caller's transaction.
/// On partial scans, an unreadable file is not evidence that it was deleted.
Future<void> deleteReplacedLibraryScanRows(
  DatabaseExecutor db,
  String sourceId, {
  required String stageTable,
  required bool preserveMissing,
}) async {
  final where = preserveMissing
      ? 'source_id = ? AND (id IN (SELECT id FROM $stageTable) '
            'OR file_path IN (SELECT file_path FROM $stageTable))'
      : 'source_id = ?';
  await db.rawDelete(
    'DELETE FROM library_path_keys WHERE item_id IN '
    '(SELECT id FROM library WHERE $where)',
    [sourceId],
  );
  await db.rawDelete('DELETE FROM library WHERE $where', [sourceId]);
}

/// Deletes a selection atomically without exceeding SQLite's parameter budget.
Future<void> deleteLibraryItemsByIds(Database db, Iterable<String> ids) async {
  final uniqueIds = ids.toSet().toList();
  if (uniqueIds.isEmpty) return;
  await db.transaction((txn) async {
    const chunkSize = 500;
    for (var start = 0; start < uniqueIds.length; start += chunkSize) {
      final chunk = uniqueIds.sublist(
        start,
        (start + chunkSize).clamp(0, uniqueIds.length),
      );
      final placeholders = List.filled(chunk.length, '?').join(',');
      await txn.delete(
        'library_path_keys',
        where: 'item_id IN ($placeholders)',
        whereArgs: chunk,
      );
      await txn.delete(
        'library',
        where: 'id IN ($placeholders)',
        whereArgs: chunk,
      );
    }
  });
}

Future<int> pruneUnreferencedLibraryCovers(
  Directory directory,
  Set<String> referencedPaths, {
  Database? libraryDatabase,
  String? requestId,
  Duration minimumAge = Duration.zero,
  NativeCacheJobRunner? nativeJobRunner,
  bool Function()? canPrune,
  Directory? temporaryDirectory,
}) async {
  if (minimumAge.isNegative) {
    throw ArgumentError.value(minimumAge, 'minimumAge');
  }
  if (canPrune != null && !canPrune()) return 0;
  if (libraryDatabase != null) {
    return withLibraryCoverSnapshot(
      libraryDatabase,
      (privatePath) => _pruneUnreferencedLibraryCovers(
        directory,
        const {},
        privateSnapshotPath: privatePath,
        requestId: requestId,
        minimumAge: minimumAge,
        nativeJobRunner: nativeJobRunner,
      ),
      canPrune: canPrune,
      temporaryDirectory: temporaryDirectory,
    );
  }
  return _pruneUnreferencedLibraryCovers(
    directory,
    referencedPaths,
    requestId: requestId,
    minimumAge: minimumAge,
    nativeJobRunner: nativeJobRunner,
  );
}

Future<int> _pruneUnreferencedLibraryCovers(
  Directory directory,
  Set<String> referencedPaths, {
  String? privateSnapshotPath,
  String? requestId,
  required Duration minimumAge,
  NativeCacheJobRunner? nativeJobRunner,
}) async {
  final result = await runNativeCacheMaintenance(
    {
      'operation': 'cache_prune_library',
      'directory': directory.absolute.path,
      'library_path': ?privateSnapshotPath,
      'schema_version': LibrarySchema.version,
      if (privateSnapshotPath == null)
        'referenced_paths': referencedPaths.toList(growable: false),
      'minimum_age_us': minimumAge.inMicroseconds,
    },
    requestId: requestId,
    nativeJobRunner: nativeJobRunner,
  );
  final deleted = cacheMaintenanceDeletedCount(result);
  final errors = result['errors'];
  if (errors is List) {
    for (final error in errors.whereType<String>()) {
      AppLogger('LocalLibrary').w(error);
    }
    final count = result['error_count'];
    if (count is int && count > errors.length) {
      AppLogger('LocalLibrary').w(
        'Failed deleting ${count - errors.length} additional stale library cover cache files',
      );
    }
  }
  return deleted;
}

/// Pages by stable ID (not OFFSET, since rows are removed during traversal).
/// A high-water mark bounds the run if a concurrent scan adds new rows.
Future<int> cleanupMissingLibraryRows(
  Database db, {
  String? sourceId,
  Future<bool> Function()? canDelete,
  Future<Map<String, bool?>> Function(List<String>) checkPaths =
      fileExistenceByPath,
}) async {
  const pageSize = 256;
  final sourceWhere = sourceId == null ? null : 'source_id = ?';
  final sourceArgs = sourceId == null ? null : <Object?>[sourceId];
  final last = await db.query(
    'library',
    columns: ['id'],
    where: sourceWhere,
    whereArgs: sourceArgs,
    orderBy: 'id DESC',
    limit: 1,
  );
  if (last.isEmpty) return 0;
  final upperId = last.single['id'] as String;
  String? cursor;
  var removed = 0;
  while (true) {
    final rows = await db.query(
      'library',
      columns: ['id', 'file_path'],
      where: [
        ?sourceWhere,
        'id <= ?',
        if (cursor != null) 'id > ?',
      ].join(' AND '),
      whereArgs: [?sourceId, upperId, ?cursor],
      orderBy: 'id ASC',
      limit: pageSize,
    );
    if (rows.isEmpty) break;
    cursor = rows.last['id'] as String;
    final paths = rows.map((row) => row['file_path'] as String).toList();
    Map<String, bool?> checks;
    try {
      checks = await checkPaths(paths);
    } catch (_) {
      continue; // No deletion on a failed batch.
    }
    final missing = rows
        .where((row) => checks[row['file_path']] == false)
        .toList();
    if (missing.isEmpty) continue;
    if (canDelete != null) {
      try {
        if (!await canDelete()) break;
      } catch (_) {
        break;
      }
    }
    // Compare the original path as well: a scan may repair it while I/O runs.
    final conditions = List.filled(
      missing.length,
      '(id = ? AND file_path = ?)',
    ).join(' OR ');
    final where =
        '($conditions)${sourceWhere == null ? '' : ' AND $sourceWhere'}';
    final args = <Object?>[
      for (final row in missing) ...[row['id'], row['file_path']],
      ?sourceId,
    ];
    removed += await db.transaction((txn) async {
      await txn.rawDelete(
        'DELETE FROM library_path_keys WHERE item_id IN '
        '(SELECT id FROM library WHERE $where)',
        args,
      );
      return txn.rawDelete('DELETE FROM library WHERE $where', args);
    });
  }
  return removed;
}
