part of 'embedded_cover_resolver.dart';

extension _EmbeddedCoverPersistence on EmbeddedCoverResolver {
  static Future<Directory> _getPersistentCacheDirectory() async {
    final override = EmbeddedCoverResolver._persistentCacheDirectoryOverride;
    final String rootPath;
    if (override != null) {
      rootPath = override.path;
    } else {
      final future = EmbeddedCoverResolver._persistentCacheRootFuture ??=
          () async {
            final appCache = await getApplicationCacheDirectory();
            return p.join(
              appCache.path,
              EmbeddedCoverResolver._persistentCacheDirectoryName,
            );
          }();
      rootPath = await future;
    }

    final directory = Directory(rootPath);
    EmbeddedCoverResolver._persistentCacheRootPath =
        _EmbeddedCoverPersistence._normalizedAbsolutePath(rootPath);
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  static String _persistentFileName(String cleanPath, int modTime) {
    return '${EmbeddedCoverResolver._persistentCacheVersion}_${_EmbeddedCoverPersistence._stablePathHash(cleanPath)}_'
        '${modTime.toRadixString(16)}.jpg';
  }

  /// Two independently mixed 63-bit FNV-1a lanes keep filenames compact.
  /// The exact source path is also stored in a sidecar and verified on every
  /// disk hit, so even a theoretical hash collision cannot serve wrong art.
  static String _stablePathHash(String value) {
    const mask = 0x7fffffffffffffff;
    const prime = 0x100000001b3;
    var first = 0x4bf29ce484222325;
    var second = 0x6c62272e07bb0142;
    for (final byte in utf8.encode(value)) {
      first ^= byte;
      first = (first * prime) & mask;
      second ^= (byte + 0x9d) & 0xff;
      second = ((second * prime) + 0x9e3779b9) & mask;
    }
    return '${first.toRadixString(16).padLeft(16, '0')}'
        '${second.toRadixString(16).padLeft(16, '0')}';
  }

  static String _persistentSourceSidecarPath(String previewPath) =>
      '$previewPath.source';
  static Future<bool> _isReusablePersistentPreview(
    String previewPath,
    String cleanPath,
  ) async {
    final preview = File(previewPath);
    final sidecar = File(
      _EmbeddedCoverPersistence._persistentSourceSidecarPath(previewPath),
    );
    try {
      if (!await preview.exists() || await preview.length() <= 0) return false;
      if (!await sidecar.exists()) return false;
      if (await sidecar.readAsString() != cleanPath) return false;
      final input = await preview.open();
      try {
        final header = await input.read(4);
        // Older ID3 extraction could cache an extra NUL before JPEG data.
        return !(header.length == 4 &&
            header[0] == 0 &&
            header[1] == 0xff &&
            header[2] == 0xd8 &&
            header[3] == 0xff);
      } finally {
        await input.close();
      }
    } catch (_) {
      return false;
    }
  }

  static Future<String> _publishPersistentPreview({
    required String stagingPath,
    required String targetPath,
    required String cleanPath,
  }) async {
    final target = File(targetPath);
    final sidecar = File(
      _EmbeddedCoverPersistence._persistentSourceSidecarPath(targetPath),
    );
    final sidecarStaging = File(
      '${sidecar.path}.stage_${DateTime.now().microsecondsSinceEpoch}_'
      '${EmbeddedCoverResolver._stagingSequence++}',
    );
    try {
      await sidecarStaging.writeAsString(cleanPath, flush: true);
      if (await sidecar.exists()) await sidecar.delete();
      await sidecarStaging.rename(sidecar.path);

      if (await target.exists()) await target.delete();
      await File(stagingPath).rename(targetPath);
      return targetPath;
    } finally {
      await _EmbeddedCoverPersistence._deleteFileIfPresent(sidecarStaging);
    }
  }

  static Future<void> _touchPersistentPreview(String previewPath) async {
    try {
      await File(previewPath).setLastModified(DateTime.now());
    } catch (_) {}
  }

  static void _schedulePersistentMaintenance() {
    if (EmbeddedCoverResolver._persistentMaintenanceFuture != null) return;
    late final Future<void> future;
    future = Future<void>(() async {
      try {
        final directory =
            await _EmbeddedCoverPersistence._getPersistentCacheDirectory();
        await _EmbeddedCoverPersistence._runPersistentCacheMaintenance(
          directory,
          maxEntries: EmbeddedCoverResolver._maxPersistentCacheEntries,
          maxBytes: EmbeddedCoverResolver._maxPersistentCacheBytes,
          targetBytes: EmbeddedCoverResolver._persistentCacheSweepTargetBytes,
        );
      } finally {
        if (identical(
          EmbeddedCoverResolver._persistentMaintenanceFuture,
          future,
        )) {
          EmbeddedCoverResolver._persistentMaintenanceFuture = null;
        }
      }
    });
    EmbeddedCoverResolver._persistentMaintenanceFuture = future;
    unawaited(future);
  }

  static Future<void> _runPersistentCacheMaintenance(
    Directory directory, {
    required int maxEntries,
    required int maxBytes,
    required int targetBytes,
  }) async {
    if (maxEntries < 0 || maxBytes < 0 || targetBytes < 0) {
      throw ArgumentError('Persistent cache limits must not be negative');
    }
    if (!await directory.exists()) return;

    final activePaths = EmbeddedCoverResolver._cache.values
        .where((entry) => entry.isPersistent)
        .map(
          (entry) => _EmbeddedCoverPersistence._normalizedAbsolutePath(
            entry.previewPath,
          ),
        )
        .toSet();
    final files = <File>[];
    final stats = <String, FileStat>{};
    var totalSize = 0;
    final now = DateTime.now();

    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      try {
        final stat = await entity.stat();
        if (name.startsWith('v1_') && name.endsWith('.jpg')) {
          await entity.delete();
          await _EmbeddedCoverPersistence._deleteFileIfPresent(
            File(
              _EmbeddedCoverPersistence._persistentSourceSidecarPath(
                entity.path,
              ),
            ),
          );
          continue;
        }
        final isAbandonedImageStage =
            name.startsWith(
              '.${EmbeddedCoverResolver._persistentCacheVersion}',
            ) &&
            name.contains('.stage_');
        final isAbandonedSidecarStage = name.contains('.jpg.source.stage_');
        if (isAbandonedImageStage || isAbandonedSidecarStage) {
          if (now.difference(stat.modified) > const Duration(hours: 1)) {
            await entity.delete();
          }
          continue;
        }
        if (name.endsWith('.jpg.source')) {
          final previewPath = entity.path.substring(
            0,
            entity.path.length - '.source'.length,
          );
          if (!await File(previewPath).exists()) await entity.delete();
          continue;
        }
        if (!name.startsWith(
              '${EmbeddedCoverResolver._persistentCacheVersion}_',
            ) ||
            !name.endsWith('.jpg')) {
          continue;
        }
        files.add(entity);
        stats[entity.path] = stat;
        totalSize += stat.size;
      } catch (_) {}
    }

    if (files.length <= maxEntries && totalSize <= maxBytes) return;
    files.sort(
      (a, b) => stats[a.path]!.modified.compareTo(stats[b.path]!.modified),
    );
    var remainingEntries = files.length;
    final byteGoal = totalSize > maxBytes ? targetBytes : maxBytes;
    for (final file in files) {
      if (remainingEntries <= maxEntries && totalSize <= byteGoal) break;
      if (activePaths.contains(
        _EmbeddedCoverPersistence._normalizedAbsolutePath(file.path),
      )) {
        continue;
      }
      final stat = stats[file.path]!;
      try {
        await file.delete();
      } catch (_) {
        // A file that cannot be deleted keeps its budget entry.
        continue;
      }
      await _EmbeddedCoverPersistence._deleteFileIfPresent(
        File(_EmbeddedCoverPersistence._persistentSourceSidecarPath(file.path)),
      );
      remainingEntries--;
      totalSize -= stat.size;
    }
  }

  static Future<void> _deletePersistentVariantsForSource(
    String cleanPath, {
    String? exceptPath,
  }) async {
    final directory =
        await _EmbeddedCoverPersistence._getPersistentCacheDirectory();
    final prefix =
        '${EmbeddedCoverResolver._persistentCacheVersion}_${_EmbeddedCoverPersistence._stablePathHash(cleanPath)}_';
    final normalizedExcept = exceptPath == null
        ? null
        : _EmbeddedCoverPersistence._normalizedAbsolutePath(exceptPath);
    try {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (!name.startsWith(prefix) || !name.endsWith('.jpg')) continue;
        if (normalizedExcept != null &&
            _EmbeddedCoverPersistence._normalizedAbsolutePath(entity.path) ==
                normalizedExcept) {
          continue;
        }

        final sidecar = File(
          _EmbeddedCoverPersistence._persistentSourceSidecarPath(entity.path),
        );
        if (await sidecar.exists()) {
          try {
            if (await sidecar.readAsString() != cleanPath) continue;
          } catch (_) {
            continue;
          }
        }
        await _EmbeddedCoverPersistence._deleteFileIfPresent(entity);
        await _EmbeddedCoverPersistence._deleteFileIfPresent(sidecar);
      }
    } catch (_) {}
  }

  static bool _isPathInsidePersistentRoot(String candidatePath) {
    final root = EmbeddedCoverResolver._persistentCacheRootPath;
    if (root == null) return false;
    try {
      final candidate = _EmbeddedCoverPersistence._normalizedAbsolutePath(
        candidatePath,
      );
      return p.equals(candidate, root) || p.isWithin(root, candidate);
    } catch (_) {
      return false;
    }
  }

  static String _normalizedAbsolutePath(String path) =>
      p.normalize(p.absolute(path));
  static Future<void> _cleanupCacheEntry(_EmbeddedCoverCacheEntry entry) async {
    if (entry.isPersistent) {
      await _EmbeddedCoverPersistence._cleanupPersistentCoverPath(
        entry.previewPath,
      );
    } else {
      await _EmbeddedCoverPersistence._cleanupTempCoverPath(entry.previewPath);
    }
  }

  static Future<void> _cleanupCoverPath(String? coverPath) async {
    if (coverPath == null || coverPath.isEmpty) return;
    if (_EmbeddedCoverPersistence._isPathInsidePersistentRoot(coverPath)) {
      await _EmbeddedCoverPersistence._cleanupPersistentCoverPath(coverPath);
    } else {
      await _EmbeddedCoverPersistence._cleanupTempCoverPath(coverPath);
    }
  }

  static void _scheduleTempCoverCleanup(String? coverPath) {
    unawaited(_EmbeddedCoverPersistence._cleanupTempCoverPath(coverPath));
  }

  static Future<void> _cleanupPersistentCoverPath(String? coverPath) async {
    if (coverPath == null || coverPath.isEmpty) return;
    await _EmbeddedCoverPersistence._deleteFileIfPresent(File(coverPath));
    await _EmbeddedCoverPersistence._deleteFileIfPresent(
      File(_EmbeddedCoverPersistence._persistentSourceSidecarPath(coverPath)),
    );
  }

  static Future<void> _cleanupTempCoverPath(String? coverPath) async {
    if (coverPath == null || coverPath.isEmpty) return;
    try {
      final file = File(coverPath);
      await _EmbeddedCoverPersistence._deleteFileIfPresent(file);
      await deleteBestEffort(file.parent, recursive: true);
    } catch (_) {}
  }

  static Future<void> _deleteFileIfPresent(File file) async {
    await deleteBestEffort(file);
  }

  static Future<void> _clearDirectoryContents(Directory directory) async {
    if (!await directory.exists()) {
      await directory.create(recursive: true);
      return;
    }
    try {
      await for (final entity in directory.list(followLinks: false)) {
        await deleteBestEffort(entity, recursive: true);
      }
    } catch (_) {}
    if (!await directory.exists()) await directory.create(recursive: true);
  }
}
