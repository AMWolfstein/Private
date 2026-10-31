part of 'embedded_cover_resolver.dart';

extension _EmbeddedCoverExtraction on EmbeddedCoverResolver {
  static void _touch(String cleanPath, _EmbeddedCoverCacheEntry entry) {
    EmbeddedCoverResolver._cache
      ..remove(cleanPath)
      ..[cleanPath] = entry;
  }

  static void _trimCacheIfNeeded() {
    while (EmbeddedCoverResolver._cache.length >
        EmbeddedCoverResolver._maxCacheEntries) {
      final oldestKey = EmbeddedCoverResolver._cache.keys.first;
      final removed = EmbeddedCoverResolver._cache.remove(oldestKey);
      if (removed != null && !removed.isPersistent) {
        _EmbeddedCoverPersistence._scheduleTempCoverCleanup(
          removed.previewPath,
        );
      }
      EmbeddedCoverResolver._cacheGeneration[oldestKey] =
          (EmbeddedCoverResolver._cacheGeneration[oldestKey] ?? 0) + 1;
      _EmbeddedCoverExtraction._cancelPendingExtraction(oldestKey);
      EmbeddedCoverResolver._cacheGeneration.remove(oldestKey);
      EmbeddedCoverResolver._pendingPreviewValidation.remove(oldestKey);
      EmbeddedCoverResolver._failedExtract.remove(oldestKey);
    }
  }

  static void _rememberFailedExtract(String cleanPath) {
    EmbeddedCoverResolver._failedExtract
      ..remove(cleanPath)
      ..[cleanPath] = EmbeddedCoverResolver._validationClock();
    while (EmbeddedCoverResolver._failedExtract.length >
        EmbeddedCoverResolver._maxFailedExtractEntries) {
      EmbeddedCoverResolver._failedExtract.remove(
        EmbeddedCoverResolver._failedExtract.keys.first,
      );
    }
  }

  static void _validateCachedPreviewAsync(
    String cleanPath,
    _EmbeddedCoverCacheEntry entry, {
    VoidCallback? onChanged,
  }) {
    final existing = EmbeddedCoverResolver._pendingPreviewValidation[cleanPath];
    if (existing != null && identical(existing.entry, entry)) {
      if (onChanged != null) existing.callbacks.add(onChanged);
      return;
    }
    final lastValidated = entry.lastValidatedAt;
    if (lastValidated != null &&
        EmbeddedCoverResolver._validationClock().difference(lastValidated) <
            EmbeddedCoverResolver._previewValidationInterval) {
      return;
    }
    if (EmbeddedCoverResolver._pendingPreviewValidation.length >=
        EmbeddedCoverResolver._maxPendingPreviewValidations) {
      return; // A later visible cache hit can retry; extraction is unaffected.
    }
    final request = _PendingPreviewValidation(entry);
    if (onChanged != null) request.callbacks.add(onChanged);
    EmbeddedCoverResolver._pendingPreviewValidation[cleanPath] = request;
    EmbeddedCoverResolver._previewValidationFuture ??= Future.microtask(
      _EmbeddedCoverExtraction._drainPreviewValidations,
    );
  }

  static Future<void> _drainPreviewValidations() async {
    try {
      while (EmbeddedCoverResolver._pendingPreviewValidation.isNotEmpty) {
        final batch = EmbeddedCoverResolver._pendingPreviewValidation.entries
            .take(EmbeddedCoverResolver._previewValidationBatchSize)
            .toList(growable: false);
        final safPaths = batch
            .where(
              (item) =>
                  isContentUri(item.key) &&
                  item.value.entry.sourceModTimeMillis != null,
            )
            .map((item) => item.key)
            .toList(growable: false);
        Map<String, int> safModTimes = const {};
        if (safPaths.isNotEmpty) {
          try {
            safModTimes = await MediaFileBridge.getSafFileModTimes(safPaths);
          } catch (_) {
            // An unavailable provider is not evidence of changed artwork.
          }
        }
        await Future.wait(
          batch.map((item) async {
            final path = item.key;
            final request = item.value;
            final entry = request.entry;
            bool isCurrent() =>
                identical(EmbeddedCoverResolver._cache[path], entry) &&
                identical(
                  EmbeddedCoverResolver._pendingPreviewValidation[path],
                  request,
                );
            try {
              if (!isCurrent()) return;
              final exists = await fileExists(entry.previewPath);
              if (!isCurrent()) return;
              if (!exists) {
                EmbeddedCoverResolver._cache.remove(path);
                EmbeddedCoverResolver._failedExtract.remove(path);
                await _EmbeddedCoverPersistence._cleanupCacheEntry(entry);
                request.notify();
                return;
              }
              final cachedModTime = entry.sourceModTimeMillis;
              final currentModTime = cachedModTime == null
                  ? null
                  : isContentUri(path)
                  ? safModTimes[path]
                  : await EmbeddedCoverResolver.readFileModTimeMillis(path);
              if (!isCurrent()) return;
              entry.lastValidatedAt = EmbeddedCoverResolver._validationClock();
              if (currentModTime != null &&
                  currentModTime > 0 &&
                  currentModTime != cachedModTime) {
                await _EmbeddedCoverExtraction._ensureCover(
                  path,
                  forceRefresh: true,
                  knownModTime: currentModTime,
                  onChanged: request.notify,
                );
              }
            } catch (_) {
              // Keep the cached preview on inconclusive I/O failures.
            } finally {
              if (identical(
                EmbeddedCoverResolver._pendingPreviewValidation[path],
                request,
              )) {
                EmbeddedCoverResolver._pendingPreviewValidation.remove(path);
              }
            }
          }),
        );
      }
    } finally {
      EmbeddedCoverResolver._previewValidationFuture = null;
    }
  }

  static Future<String?> _ensureCover(
    String cleanPath, {
    bool forceRefresh = false,
    int? knownModTime,
    VoidCallback? onChanged,
    bool isForeground = false,
  }) {
    if (cleanPath.isEmpty) return Future<String?>.value();

    final inFlight = EmbeddedCoverResolver._pendingExtract[cleanPath];
    if (inFlight != null) {
      if (onChanged != null) inFlight.callbacks.add(onChanged);
      if (isForeground && !inFlight.started && !inFlight.isForeground) {
        inFlight.isForeground = true;
        if (EmbeddedCoverResolver._backgroundExtractionQueue.remove(inFlight)) {
          EmbeddedCoverResolver._foregroundExtractionQueue.addLast(inFlight);
        }
        _EmbeddedCoverExtraction._scheduleExtractionDrain();
      }
      return inFlight.future;
    }

    final cached = EmbeddedCoverResolver._cache[cleanPath];
    if (!forceRefresh && cached != null) {
      return Future<String?>.value(cached.previewPath);
    }
    if (!forceRefresh &&
        EmbeddedCoverResolver._failedExtract.containsKey(cleanPath)) {
      // Both a document provider and a local/removable file can be temporarily
      // unavailable. Retry on demand after a cooldown, through the same bounded
      // extraction queue, instead of suppressing local failures for the session.
      final failedAt = EmbeddedCoverResolver._failedExtract[cleanPath]!;
      if (EmbeddedCoverResolver._validationClock().difference(failedAt) <
          EmbeddedCoverResolver._documentFailureRetryDelay) {
        return Future<String?>.value();
      }
      EmbeddedCoverResolver._failedExtract.remove(cleanPath);
    }

    final job = _PendingEmbeddedCoverExtraction(
      cleanPath: cleanPath,
      forceRefresh: forceRefresh,
      knownModTime: knownModTime,
      generation: EmbeddedCoverResolver._cacheGeneration[cleanPath] ?? 0,
      isForeground: isForeground,
      onChanged: onChanged,
    );
    EmbeddedCoverResolver._pendingExtract[cleanPath] = job;
    if (isForeground) {
      EmbeddedCoverResolver._foregroundExtractionQueue.addLast(job);
    } else {
      EmbeddedCoverResolver._backgroundExtractionQueue.addLast(job);
      _EmbeddedCoverExtraction._trimBackgroundExtractionQueue();
    }
    _EmbeddedCoverExtraction._scheduleExtractionDrain();
    return job.future;
  }

  static void _trimBackgroundExtractionQueue() {
    while (EmbeddedCoverResolver._backgroundExtractionQueue.length >
        EmbeddedCoverResolver._maxQueuedBackgroundExtractions) {
      final staleJob = EmbeddedCoverResolver._backgroundExtractionQueue
          .removeFirst();
      staleJob.cancelled = true;
      if (identical(
        EmbeddedCoverResolver._pendingExtract[staleJob.cleanPath],
        staleJob,
      )) {
        EmbeddedCoverResolver._pendingExtract.remove(staleJob.cleanPath);
      }
      if (!staleJob.completer.isCompleted) {
        staleJob.completer.complete(null);
      }
    }
  }

  static void _scheduleExtractionDrain() {
    if (EmbeddedCoverResolver._drainScheduled) return;
    EmbeddedCoverResolver._drainScheduled = true;
    scheduleMicrotask(() {
      EmbeddedCoverResolver._drainScheduled = false;
      _EmbeddedCoverExtraction._drainExtractionQueue();
    });
  }

  static void _drainExtractionQueue() {
    while (EmbeddedCoverResolver._activeExtractions <
        EmbeddedCoverResolver._maxConcurrentExtractions) {
      final _PendingEmbeddedCoverExtraction? job;
      if (EmbeddedCoverResolver._foregroundExtractionQueue.isNotEmpty) {
        job = EmbeddedCoverResolver._foregroundExtractionQueue.removeFirst();
      } else if (EmbeddedCoverResolver._backgroundExtractionQueue.isNotEmpty) {
        job = EmbeddedCoverResolver._backgroundExtractionQueue.removeFirst();
      } else {
        return;
      }

      if (job.cancelled ||
          !identical(
            EmbeddedCoverResolver._pendingExtract[job.cleanPath],
            job,
          )) {
        if (!job.completer.isCompleted) job.completer.complete(null);
        continue;
      }

      job.started = true;
      EmbeddedCoverResolver._activeExtractions++;
      unawaited(_EmbeddedCoverExtraction._executeExtractionJob(job));
    }
  }

  static Future<void> _executeExtractionJob(
    _PendingEmbeddedCoverExtraction job,
  ) async {
    String? result;
    try {
      result = await _EmbeddedCoverExtraction._extractCover(job);
    } finally {
      if (!job.completer.isCompleted) job.completer.complete(result);
      if (identical(
        EmbeddedCoverResolver._pendingExtract[job.cleanPath],
        job,
      )) {
        EmbeddedCoverResolver._pendingExtract.remove(job.cleanPath);
      }
      EmbeddedCoverResolver._activeExtractions--;
      _EmbeddedCoverExtraction._scheduleExtractionDrain();
    }
  }

  static bool _isCurrentExtraction(_PendingEmbeddedCoverExtraction job) {
    return !job.cancelled &&
        (EmbeddedCoverResolver._cacheGeneration[job.cleanPath] ?? 0) ==
            job.generation;
  }

  static Future<String?> _extractCover(
    _PendingEmbeddedCoverExtraction job,
  ) async {
    final cleanPath = job.cleanPath;
    String? outputPath;
    var outputIsPersistent = false;
    try {
      if (!_EmbeddedCoverExtraction._isCurrentExtraction(job)) return null;
      final candidateModTime =
          job.knownModTime ??
          await EmbeddedCoverResolver.readFileModTimeMillis(cleanPath);
      final modTime = candidateModTime != null && candidateModTime > 0
          ? candidateModTime
          : null;
      if (!_EmbeddedCoverExtraction._isCurrentExtraction(job)) return null;

      String? persistentPath;
      if (modTime != null) {
        final directory =
            await _EmbeddedCoverPersistence._getPersistentCacheDirectory();
        persistentPath = p.join(
          directory.path,
          _EmbeddedCoverPersistence._persistentFileName(cleanPath, modTime),
        );
        if (!job.forceRefresh &&
            await _EmbeddedCoverPersistence._isReusablePersistentPreview(
              persistentPath,
              cleanPath,
            )) {
          if (!_EmbeddedCoverExtraction._isCurrentExtraction(job)) return null;
          await _EmbeddedCoverPersistence._touchPersistentPreview(
            persistentPath,
          );
          final next = _EmbeddedCoverCacheEntry(
            previewPath: persistentPath,
            sourceModTimeMillis: modTime,
            isPersistent: true,
          );
          _EmbeddedCoverExtraction._touch(cleanPath, next);
          EmbeddedCoverResolver._failedExtract.remove(cleanPath);
          _EmbeddedCoverExtraction._trimCacheIfNeeded();
          _EmbeddedCoverExtraction._notifyCoverChanged(job);
          _EmbeddedCoverPersistence._schedulePersistentMaintenance();
          return persistentPath;
        }
      }

      if (persistentPath != null) {
        final directory = File(persistentPath).parent;
        outputPath = p.join(
          directory.path,
          '.${p.basenameWithoutExtension(persistentPath)}.stage_'
          '${DateTime.now().microsecondsSinceEpoch}_${EmbeddedCoverResolver._stagingSequence++}.jpg',
        );
      } else {
        final tempDir = await Directory.systemTemp.createTemp('cover_preview_');
        outputPath = p.join(tempDir.path, 'cover_preview.jpg');
      }

      final result = await MediaFileBridge.extractCoverToFile(
        cleanPath,
        outputPath,
      );

      if (!_EmbeddedCoverExtraction._isCurrentExtraction(job)) {
        await _EmbeddedCoverPersistence._cleanupCoverPath(outputPath);
        return null;
      }

      final outputFile = File(outputPath);
      final hasCover =
          result['error'] == null &&
          await outputFile.exists() &&
          await outputFile.length() > 0;
      if (!hasCover) {
        _EmbeddedCoverExtraction._rememberFailedExtract(cleanPath);
        if (job.forceRefresh) {
          final previous = EmbeddedCoverResolver._cache.remove(cleanPath);
          if (previous != null) {
            await _EmbeddedCoverPersistence._cleanupCacheEntry(previous);
          }
          await _EmbeddedCoverPersistence._deletePersistentVariantsForSource(
            cleanPath,
          );
          _EmbeddedCoverExtraction._notifyCoverChanged(job);
        }
        await _EmbeddedCoverPersistence._cleanupCoverPath(outputPath);
        return null;
      }

      if (!_EmbeddedCoverExtraction._isCurrentExtraction(job)) {
        await _EmbeddedCoverPersistence._cleanupCoverPath(outputPath);
        return null;
      }

      var finalPath = outputPath;
      if (persistentPath != null) {
        finalPath = await _EmbeddedCoverPersistence._publishPersistentPreview(
          stagingPath: outputPath,
          targetPath: persistentPath,
          cleanPath: cleanPath,
        );
        outputPath = finalPath;
        outputIsPersistent = true;
      }

      if (!_EmbeddedCoverExtraction._isCurrentExtraction(job)) {
        await _EmbeddedCoverPersistence._cleanupCoverPath(finalPath);
        return null;
      }

      final previous = EmbeddedCoverResolver._cache[cleanPath];
      final next = _EmbeddedCoverCacheEntry(
        previewPath: finalPath,
        sourceModTimeMillis: modTime,
        isPersistent: outputIsPersistent,
      );
      _EmbeddedCoverExtraction._touch(cleanPath, next);
      EmbeddedCoverResolver._failedExtract.remove(cleanPath);
      _EmbeddedCoverExtraction._trimCacheIfNeeded();

      if (previous != null && previous.previewPath != finalPath) {
        await _EmbeddedCoverPersistence._cleanupCacheEntry(previous);
      }
      if (outputIsPersistent) {
        await _EmbeddedCoverPersistence._deletePersistentVariantsForSource(
          cleanPath,
          exceptPath: finalPath,
        );
        _EmbeddedCoverPersistence._schedulePersistentMaintenance();
      }
      _EmbeddedCoverExtraction._notifyCoverChanged(job);
      return finalPath;
    } catch (_) {
      if (_EmbeddedCoverExtraction._isCurrentExtraction(job)) {
        _EmbeddedCoverExtraction._rememberFailedExtract(cleanPath);
        if (job.forceRefresh) {
          final previous = EmbeddedCoverResolver._cache.remove(cleanPath);
          if (previous != null) {
            await _EmbeddedCoverPersistence._cleanupCacheEntry(previous);
          }
          await _EmbeddedCoverPersistence._deletePersistentVariantsForSource(
            cleanPath,
          );
          _EmbeddedCoverExtraction._notifyCoverChanged(job);
        }
      }
      await _EmbeddedCoverPersistence._cleanupCoverPath(outputPath);
      return null;
    }
  }

  static void _notifyCoverChanged(_PendingEmbeddedCoverExtraction job) {
    for (final callback in job.callbacks.toList(growable: false)) {
      try {
        callback();
      } catch (_) {}
    }
  }

  static void _cancelPendingExtraction(String cleanPath) {
    final job = EmbeddedCoverResolver._pendingExtract.remove(cleanPath);
    if (job == null) return;
    job.cancelled = true;
    if (!job.started) {
      EmbeddedCoverResolver._foregroundExtractionQueue.remove(job);
      EmbeddedCoverResolver._backgroundExtractionQueue.remove(job);
    }
    if (!job.completer.isCompleted) job.completer.complete(null);
  }
}
