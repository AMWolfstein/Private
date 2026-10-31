import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sistrum/services/native/media_file_bridge.dart';
import 'package:sistrum/utils/files/best_effort_delete.dart';
import 'package:sistrum/utils/files/file_access.dart';

part 'embedded_cover_resolver_extraction.dart';
part 'embedded_cover_resolver_persistence.dart';

class _EmbeddedCoverCacheEntry {
  final String previewPath;
  final int? sourceModTimeMillis;
  final bool isPersistent;
  DateTime? lastValidatedAt;

  _EmbeddedCoverCacheEntry({
    required this.previewPath,
    required this.isPersistent,
    this.sourceModTimeMillis,
  });
}

class _PendingPreviewValidation {
  final _EmbeddedCoverCacheEntry entry;
  final Set<VoidCallback> callbacks = {};
  _PendingPreviewValidation(this.entry);

  void notify() {
    for (final callback in callbacks) {
      callback();
    }
  }
}

class _PendingEmbeddedCoverExtraction {
  final String cleanPath;
  final bool forceRefresh;
  final int? knownModTime;
  final int generation;
  final Completer<String?> completer = Completer<String?>();
  final LinkedHashSet<VoidCallback> callbacks = LinkedHashSet<VoidCallback>();
  bool isForeground;
  bool started = false;
  bool cancelled = false;

  _PendingEmbeddedCoverExtraction({
    required this.cleanPath,
    required this.forceRefresh,
    required this.knownModTime,
    required this.generation,
    required this.isForeground,
    VoidCallback? onChanged,
  }) {
    if (onChanged != null) callbacks.add(onChanged);
  }

  Future<String?> get future => completer.future;
}

/// Shared resolver for embedded cover previews from local music files.
///
/// The in-memory LRU is backed by a source-versioned persistent cache, while
/// all misses still pass through the bounded, foreground-prioritized scheduler
/// so Library scrolling cannot fan out native I/O.
class EmbeddedCoverResolver {
  static const int _maxCacheEntries = 180;
  static const int _maxFailedExtractEntries = 360;
  static const int _maxConcurrentExtractions = 2;
  static const int _maxQueuedBackgroundExtractions = 24;
  static const String _persistentCacheDirectoryName = 'embedded_cover_previews';
  // v1 SAF previews could contain the Library's 800px thumbnail instead of
  // original embedded artwork. Re-extract even when the audio has not changed.
  static const String _persistentCacheVersion = 'v2';
  static const int _maxPersistentCacheEntries = 384;
  static const int _maxPersistentCacheBytes = 160 << 20;
  static const int _persistentCacheSweepTargetBytes = 128 << 20;

  static final LinkedHashMap<String, _EmbeddedCoverCacheEntry> _cache =
      LinkedHashMap<String, _EmbeddedCoverCacheEntry>();
  static final Map<String, _PendingEmbeddedCoverExtraction> _pendingExtract =
      <String, _PendingEmbeddedCoverExtraction>{};
  static final Queue<_PendingEmbeddedCoverExtraction>
  _foregroundExtractionQueue = Queue<_PendingEmbeddedCoverExtraction>();
  static final Queue<_PendingEmbeddedCoverExtraction>
  _backgroundExtractionQueue = Queue<_PendingEmbeddedCoverExtraction>();
  static int _activeExtractions = 0;
  static bool _drainScheduled = false;
  static final Map<String, int> _cacheGeneration = <String, int>{};

  static final _pendingPreviewValidation =
      <String, _PendingPreviewValidation>{};
  static Future<void>? _previewValidationFuture;
  static const _previewValidationInterval = Duration(seconds: 5);
  static const _previewValidationBatchSize = 8;
  static const _maxPendingPreviewValidations = 64;
  static DateTime Function() _validationClock = DateTime.now;
  static final _failedExtract = <String, DateTime>{};
  static const _documentFailureRetryDelay = Duration(seconds: 30);

  static Directory? _persistentCacheDirectoryOverride;
  static Future<String>? _persistentCacheRootFuture;
  static String? _persistentCacheRootPath;
  static Future<void>? _persistentMaintenanceFuture;
  static int _stagingSequence = 0;

  static String cleanFilePath(String? filePath) {
    return filePath ?? '';
  }

  static Future<int?> readFileModTimeMillis(String? filePath) async {
    final cleanPath = EmbeddedCoverResolver.cleanFilePath(filePath);
    if (cleanPath.isEmpty) return null;

    if (isContentUri(cleanPath)) {
      try {
        final modTimes = await MediaFileBridge.getSafFileModTimes([cleanPath]);
        final modTime = modTimes[cleanPath];
        return modTime != null && modTime > 0 ? modTime : null;
      } catch (_) {
        return null;
      }
    }

    try {
      final stat = await File(cleanPath).stat();
      if (stat.type == FileSystemEntityType.notFound) return null;
      final modTime = stat.modified.millisecondsSinceEpoch;
      return modTime > 0 ? modTime : null;
    } catch (_) {
      return null;
    }
  }

  static String? resolve(String? filePath, {VoidCallback? onChanged}) {
    final cleanPath = EmbeddedCoverResolver.cleanFilePath(filePath);
    if (cleanPath.isEmpty) return null;

    final cached = EmbeddedCoverResolver._cache[cleanPath];
    if (cached != null) {
      _EmbeddedCoverExtraction._touch(cleanPath, cached);
      _EmbeddedCoverExtraction._validateCachedPreviewAsync(
        cleanPath,
        cached,
        onChanged: onChanged,
      );
      return cached.previewPath;
    }

    // The local file is the source of truth for its artwork. Extract on a
    // cold cache so library rows can display their embedded cover.
    unawaited(
      _EmbeddedCoverExtraction._ensureCover(cleanPath, onChanged: onChanged),
    );
    return null;
  }

  /// Returns the cached embedded cover, waiting for one shared extraction when
  /// needed. Navigation uses this to start its Hero and blurred backdrop from
  /// the same file artwork instead of swapping from a placeholder after
  /// the route is already visible.
  /// Cache hits answer synchronously and misses await extraction. Any synchronous
  /// failure is still delivered as this Future's error, via [Future.sync].
  static Future<String?> resolveOrExtract(
    String? filePath, {
    VoidCallback? onChanged,
  }) => Future.sync(() {
    final cleanPath = EmbeddedCoverResolver.cleanFilePath(filePath);
    if (cleanPath.isEmpty) return null;

    final cached = EmbeddedCoverResolver._cache[cleanPath];
    if (cached != null) {
      _EmbeddedCoverExtraction._touch(cleanPath, cached);
      _EmbeddedCoverExtraction._validateCachedPreviewAsync(
        cleanPath,
        cached,
        onChanged: onChanged,
      );
      return cached.previewPath;
    }

    return _EmbeddedCoverExtraction._ensureCover(
      cleanPath,
      onChanged: onChanged,
      isForeground: true,
    );
  });

  /// Clears resolver state together with its App Cache-backed disk entries.
  /// Running native work is generation-cancelled and awaited before the disk
  /// directory is wiped, so a completed clear leaves no late staging output.
  static Future<void> clearPersistentCache() async {
    final keys = <String>{..._cache.keys, ..._pendingExtract.keys};
    for (final key in keys) {
      EmbeddedCoverResolver._cacheGeneration[key] =
          (EmbeddedCoverResolver._cacheGeneration[key] ?? 0) + 1;
      _EmbeddedCoverExtraction._cancelPendingExtraction(key);
      EmbeddedCoverResolver._cacheGeneration.remove(key);
    }
    while (EmbeddedCoverResolver._activeExtractions > 0) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    EmbeddedCoverResolver._cacheGeneration.clear();

    final entries = EmbeddedCoverResolver._cache.values.toList(growable: false);
    EmbeddedCoverResolver._cache.clear();
    EmbeddedCoverResolver._pendingPreviewValidation.clear();
    await EmbeddedCoverResolver._previewValidationFuture;
    EmbeddedCoverResolver._failedExtract.clear();
    for (final entry in entries) {
      if (!entry.isPersistent) {
        await _EmbeddedCoverPersistence._cleanupTempCoverPath(
          entry.previewPath,
        );
      }
    }

    final maintenance = EmbeddedCoverResolver._persistentMaintenanceFuture;
    if (maintenance != null) await maintenance;
    final directory =
        await _EmbeddedCoverPersistence._getPersistentCacheDirectory();
    await _EmbeddedCoverPersistence._clearDirectoryContents(directory);
  }

  @visibleForTesting
  static void setPersistentCacheDirectoryForTesting(Directory? directory) {
    if (EmbeddedCoverResolver._activeExtractions != 0 ||
        EmbeddedCoverResolver._pendingExtract.isNotEmpty) {
      throw StateError('Cannot replace persistent cache while work is active');
    }
    EmbeddedCoverResolver._persistentCacheDirectoryOverride = directory;
    EmbeddedCoverResolver._persistentCacheRootFuture = null;
    EmbeddedCoverResolver._persistentCacheRootPath = directory == null
        ? null
        : _EmbeddedCoverPersistence._normalizedAbsolutePath(directory.path);
  }

  /// Simulates a process restart without deleting persistent preview files.
  @visibleForTesting
  static Future<void> resetMemoryStateForTesting({
    bool preservePersistentFiles = true,
  }) async {
    final maintenance = EmbeddedCoverResolver._persistentMaintenanceFuture;
    if (maintenance != null) await maintenance;

    final keys = <String>{..._cache.keys, ..._pendingExtract.keys};
    for (final key in keys) {
      EmbeddedCoverResolver._cacheGeneration[key] =
          (EmbeddedCoverResolver._cacheGeneration[key] ?? 0) + 1;
      _EmbeddedCoverExtraction._cancelPendingExtraction(key);
    }
    while (EmbeddedCoverResolver._activeExtractions > 0) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }

    final entries = EmbeddedCoverResolver._cache.values.toList(growable: false);
    EmbeddedCoverResolver._cache.clear();
    EmbeddedCoverResolver._pendingExtract.clear();
    EmbeddedCoverResolver._foregroundExtractionQueue.clear();
    EmbeddedCoverResolver._backgroundExtractionQueue.clear();
    EmbeddedCoverResolver._pendingPreviewValidation.clear();
    await EmbeddedCoverResolver._previewValidationFuture;
    EmbeddedCoverResolver._validationClock = DateTime.now;
    EmbeddedCoverResolver._failedExtract.clear();
    EmbeddedCoverResolver._cacheGeneration.clear();
    EmbeddedCoverResolver._drainScheduled = false;
    for (final entry in entries) {
      if (!entry.isPersistent) {
        await _EmbeddedCoverPersistence._cleanupTempCoverPath(
          entry.previewPath,
        );
      }
    }

    if (!preservePersistentFiles) {
      final directory =
          await _EmbeddedCoverPersistence._getPersistentCacheDirectory();
      await _EmbeddedCoverPersistence._clearDirectoryContents(directory);
    }
  }

  @visibleForTesting
  static Future<void> runPersistentCacheMaintenanceForTesting({
    int maxEntries = EmbeddedCoverResolver._maxPersistentCacheEntries,
    int maxBytes = EmbeddedCoverResolver._maxPersistentCacheBytes,
    int targetBytes = EmbeddedCoverResolver._persistentCacheSweepTargetBytes,
  }) async {
    final scheduled = EmbeddedCoverResolver._persistentMaintenanceFuture;
    if (scheduled != null) await scheduled;
    final directory =
        await _EmbeddedCoverPersistence._getPersistentCacheDirectory();
    await _EmbeddedCoverPersistence._runPersistentCacheMaintenance(
      directory,
      maxEntries: maxEntries,
      maxBytes: maxBytes,
      targetBytes: targetBytes,
    );
  }

  @visibleForTesting
  static void setValidationClockForTesting(DateTime Function() clock) {
    EmbeddedCoverResolver._validationClock = clock;
  }

  @visibleForTesting
  static Future<void> waitForPreviewValidationForTesting() async {
    await EmbeddedCoverResolver._previewValidationFuture;
  }
}
