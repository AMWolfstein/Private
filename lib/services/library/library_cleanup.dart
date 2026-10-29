import 'dart:io';
import 'dart:isolate';
import 'package:sqflite/sqflite.dart';
import 'package:sistrum/services/library/library_cover_snapshot.dart';
import 'package:sistrum/services/library/library_schema.dart';
import 'package:sistrum/services/library/native_cache_maintenance.dart';
import 'package:sistrum/services/platform_bridge.dart';
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
    if (nativeJobRunner == null && !PlatformBridge.supportsCoreBackend) {
      return libraryDatabase.transaction((txn) async {
        final paths = await readLibraryCoverReferences(txn);
        if (canPrune != null && !canPrune()) return 0;
        return _pruneUnreferencedLibraryCovers(
          directory,
          paths,
          requestId: requestId,
          minimumAge: minimumAge,
        );
      }, exclusive: true);
    }
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
  if (result != null) {
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
  if (privateSnapshotPath != null) {
    throw StateError(
      'The desktop cache adapter requires explicit cover references',
    );
  }
  final path = directory.path;
  final outcome = await _pruneCoversOnWorker(path, referencedPaths, minimumAge);
  for (final error in outcome.errors) {
    AppLogger('LocalLibrary').w(error);
  }
  return outcome.deleted;
}

Future<({int deleted, List<String> errors})> _pruneCoversOnWorker(
  String path,
  Set<String> references,
  Duration minimumAge,
) => Isolate.run(() => _pruneCoversInWorker(path, references, minimumAge));

Future<({int deleted, List<String> errors})> _pruneCoversInWorker(
  String path,
  Set<String> referencedPaths,
  Duration minimumAge,
) async {
  final directory = Directory(path);
  final cutoff = DateTime.now().subtract(minimumAge);
  // Native scans may return canonical paths while Dart lists a directory alias.
  final retainedPaths = {...referencedPaths};
  for (final path in referencedPaths) {
    try {
      retainedPaths.add(await File(path).resolveSymbolicLinks());
    } on FileSystemException {
      // Missing cache files can remain referenced until the next full scan.
    }
  }
  var deleted = 0;
  final errors = <String>[];
  final survived = <String>{};
  final pointers = <File>[];
  await for (final entity in directory.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is! File) continue;
    if (_coverPointerName.hasMatch(_fileName(entity.path))) {
      // Key→content metadata: resolved below, once this pass knows which
      // cover files survived.
      pointers.add(entity);
      continue;
    }
    if (retainedPaths.contains(entity.path)) {
      survived.add(entity.path);
      continue;
    }
    try {
      if (retainedPaths.contains(await entity.resolveSymbolicLinks())) {
        survived.add(entity.path);
        continue;
      }
      final before = await entity.stat();
      if (before.type != FileSystemEntityType.file ||
          before.modified.isAfter(cutoff)) {
        survived.add(entity.path);
        continue;
      }
      await entity.delete();
      deleted++;
    } catch (error) {
      survived.add(entity.path);
      final message =
          'Failed deleting stale library cover cache ${entity.path}: $error';
      errors.add(message);
    }
  }
  // Old per-track mtime keys must not live forever just because their shared
  // cover is still referenced. Missing pointers only cause a safe cache miss.
  final expiry = DateTime.now().subtract(const Duration(days: 30));
  final pointerCutoff = cutoff.isBefore(expiry) ? cutoff : expiry;
  for (final pointer in pointers) {
    try {
      final modified = (await pointer.stat()).modified;
      final target = await pointer.readAsString();
      final name = target.trim();
      if (modified.isAfter(pointerCutoff) &&
          _coverFileName.hasMatch(name) &&
          survived.contains(
            '${pointer.parent.path}${Platform.pathSeparator}$name',
          )) {
        continue;
      }
      await pointer.delete();
      deleted++;
    } catch (error) {
      final message =
          'Failed deleting stale library cover pointer ${pointer.path}: $error';
      errors.add(message);
    }
  }
  return (deleted: deleted, errors: errors);
}

/// `cover_` + 64 lowercase hex + `.id`: a pointer from a per-track cache key to
/// the content-addressed cover it resolved to.
final _coverPointerName = RegExp(r'^cover_[0-9a-f]{64}\.id$');

/// The content file a pointer may name; also rejects path separators.
final _coverFileName = RegExp(r'^cover_[0-9a-f]{64}\.(jpg|png)$');

String _fileName(String path) =>
    path.substring(path.lastIndexOf(Platform.pathSeparator) + 1);

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
