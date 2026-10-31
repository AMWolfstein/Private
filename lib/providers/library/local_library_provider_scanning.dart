part of 'local_library_provider.dart';

extension _LocalLibraryScanning on LocalLibraryNotifier {
  Future<void> _recoverPreviousScan() async {
    try {
      final prefs = await _preferences();
      final sourceId = prefs.getString(localLibraryActiveScanSourceKey);
      if (!_ref.mounted || sourceId == null || sourceId.trim().isEmpty) return;
      final startedAfter =
          prefs.getInt(localLibraryActiveScanStartedAtKey) ?? 0;
      final recoveryKey = '$sourceId:$startedAfter';
      if (prefs.getString(localLibraryRecoveredScanKey) == recoveryKey) return;
      var message = _notificationService.libraryScanInterruptedMessage;
      try {
        final exit = await LibraryScanBridge.getLibraryScanExitInfo(
          startedAfter: startedAfter,
        );
        if (exit != null) {
          _log.e('Android process exit during library scan: $exit');
          final reason = exit['reason'] as String?;
          final description = exit['description'] as String?;
          message = [
            message,
            if (reason != null && reason.isNotEmpty) reason,
            if (description != null && description.isNotEmpty) description,
          ].join('\n');
        }
      } catch (e) {
        _log.w('Android did not provide a scan exit report: $e');
      }
      _log.e('Interrupted library scan for $sourceId: $message');
      await _notificationService.endBackgroundWork(
        NotificationService.libraryScanWorkKind,
      );
      await _scanNotifications.cancelPaused();
      await _scanNotifications.showFailed(message);
      // Keep the checkpoint marker so enabled auto-scan can resume it. This
      // recovery also runs when auto-scan is off and never deletes tracks.
      await _db.updateSourceState(sourceId, lastScanError: message);
      await prefs.setString(localLibraryRecoveredScanKey, recoveryKey);
    } catch (e, stack) {
      _log.e('Could not fully recover interrupted library scan: $e', e, stack);
    }
  }

  Future<({int inserted})?> _replaceFromFullScanStream({
    required String sourceId,
    required String folderPath,
    required bool isSaf,
    required bool forceFullScan,
  }) async {
    if (_scanCancelRequested) return null;
    // A forced scan deletes the resume files, so the native scan cannot tell
    // from them whether this source still has rows. Tell it explicitly: an
    // empty provider listing must never wipe an indexed source.
    final hasIndexedRows = isSaf && (await _db.getSourceCount(sourceId) > 0);
    final scanFile = isSaf
        ? await LibraryScanBridge.scanSafTreeToNDJSONFile(
            folderPath,
            forceFullScan: forceFullScan,
            hasIndexedRows: hasIndexedRows,
            isCancelled: () => _scanCancelRequested,
          )
        : await LibraryScanBridge.scanLibraryFolderToNDJSONFile(
            folderPath,
            forceFullScan: forceFullScan,
            isCancelled: () => _scanCancelRequested,
          );
    var ingested = false;
    try {
      if (_scanCancelRequested) return null;
      await _endPauseForFinalization();
      _current = _current.copyWith(
        scanIsFinalizing: true,
        scanProgress: _current.scanProgress >= 99 ? _current.scanProgress : 99,
        scanCurrentFile: null,
        scannedFiles: scanFile.expectedCount,
        scanErrorCount: scanFile.errorCount,
      );
      final result = await _db.replaceSourceScanFile(
        sourceId,
        scanFile,
        requestId: _nativeLibraryRequestId!,
        isCancelled: () => _scanCancelRequested || !_ref.mounted,
      );
      _log.i(
        'Stream-ingested ${result.inserted}/${scanFile.expectedCount} scan rows',
      );
      ingested = true;
      return result;
    } finally {
      if (ingested) {
        await scanFile.delete();
      }
    }
  }

  Future<void> _runScan(
    String folderPath, {
    required bool forceFullScan,
    required String? sourceId,
  }) async {
    var activeSourceId = sourceId;
    try {
      if (activeSourceId == null) {
        final existingSource = await _db.getSourceByPath(folderPath);
        if (!_ref.mounted || _scanCancelRequested) return;
        activeSourceId = existingSource?.id;
        if (activeSourceId == null) {
          final source = await addSource(
            path: folderPath,
            displayName: _displayNameForPath(folderPath),
            isRemovable: _looksLikeRemovablePath(folderPath),
          );
          activeSourceId = source.id;
        }
      }

      final available = await _isPathAvailable(folderPath);
      if (!_ref.mounted || _scanCancelRequested) return;
      if (!available) {
        _sourceVersion++;
        await _db.updateSourceState(activeSourceId, available: false);
        await _refreshSummaryFromStorage();
        return;
      }
      if (await _sourceForScan(activeSourceId) == null ||
          !_ref.mounted ||
          _scanCancelRequested) {
        return;
      }

      // A pause left behind by an interrupted Dart session would hold the new
      // native scan forever; clear it before the pause control becomes visible.
      await _releaseNativeScanPause();
      try {
        final prefs = await _preferences();
        await prefs.setInt(
          localLibraryActiveScanStartedAtKey,
          DateTime.now().millisecondsSinceEpoch,
        );
        await prefs.setString(localLibraryActiveScanSourceKey, activeSourceId);
        await prefs.remove(localLibraryRecoveredScanKey);
      } catch (e) {
        _log.w('Failed to persist active library scan marker: $e');
      }
      if (!_ref.mounted || _scanCancelRequested) return;
      _log.i(
        'Starting library scan: $folderPath (incremental: ${!forceFullScan})',
      );
      _current = _current.copyWith(
        isScanning: true,
        scanIsFinalizing: false,
        scanIsPaused: false,
        scanProgress: 0,
        scanCurrentFile: null,
        scanTotalFiles: 0,
        scannedFiles: 0,
        scanErrorCount: 0,
        scanWasCancelled: false,
        scanningSourceId: activeSourceId,
      );
      _scanNotifications.reset();
      // Hold before the first progress notification so Android shows a single
      // foreground-service notification; released in the final cleanup below.
      await _notificationService.beginLibraryScanWork();
      if (_scanNotifications.shouldShowProgress(
        progress: 0,
        totalFiles: 0,
        isComplete: false,
      )) {
        await _scanNotifications.showProgress(
          progress: 0,
          scannedFiles: 0,
          totalFiles: 0,
          currentFile: null,
        );
      }

      try {
        final appSupportDir = await getApplicationSupportDirectory();
        final coverCacheDir = '${appSupportDir.path}/library_covers';
        await LibraryScanBridge.setLibraryCoverCacheDir(coverCacheDir);
        _log.i('Cover cache directory set to: $coverCacheDir');
      } catch (e) {
        _log.w('Failed to set cover cache directory: $e');
      }
      if (!_ref.mounted || _scanCancelRequested) return;

      _startProgressPolling();

      if (!_ref.mounted || _scanCancelRequested) return;
      final isSaf = folderPath.startsWith('content://');

      final useStreamingFullScan =
          forceFullScan || await _db.getSourceCount(activeSourceId) == 0;
      if (useStreamingFullScan) {
        if (await _sourceForScan(activeSourceId) == null ||
            !_ref.mounted ||
            _scanCancelRequested) {
          return;
        }
        final scanResult = await _replaceFromFullScanStream(
          sourceId: activeSourceId,
          folderPath: folderPath,
          isSaf: isSaf,
          forceFullScan: forceFullScan,
        );
        if (!_ref.mounted) return;
        if (scanResult == null || _scanCancelRequested) {
          if (scanResult != null) {
            await _refreshSummaryFromStorage();
          }
          if (!_ref.mounted) return;
          _current = _current.copyWith(
            isScanning: false,
            scanIsFinalizing: false,
            scanWasCancelled: true,
          );
          await _scanNotifications.showCancelled();
          return;
        }

        _current = _current.copyWith(
          scanIsFinalizing: true,
          scanProgress: _current.scanProgress >= 99
              ? _current.scanProgress
              : 99,
          scanCurrentFile: null,
        );

        if (!await _finishScanSuccess(activeSourceId)) return;
        await _pruneLibraryCoverCache();

        final summary =
            'Full scan complete: ${_current.totalCount} tracks found, '
            '${_current.scanErrorCount} errors';
        if (_current.scanErrorCount > 0) {
          _log.e(summary);
        } else {
          _log.i(summary);
        }
        await _scanNotifications.showComplete(
          totalTracks: _current.totalCount,
          errorCount: _current.scanErrorCount,
        );
      } else {
        final snapshotPath = await _db.exportNativeFileModTimesSnapshot(
          activeSourceId,
          requestId: _nativeLibraryRequestId!,
          isCancelled: () => _scanCancelRequested || !_ref.mounted,
        );

        Map<String, dynamic> result;
        try {
          if (await _sourceForScan(activeSourceId) == null ||
              _scanCancelRequested ||
              !_ref.mounted) {
            return;
          }
          result = await _db.scanIncrementalNative(
            activeSourceId,
            folderPath,
            snapshotPath,
            isSaf: isSaf,
            requestId: _nativeLibraryRequestId!,
            isCancelled: () => _scanCancelRequested || !_ref.mounted,
          );
        } finally {
          await deleteBestEffort(File(snapshotPath));
        }

        if (!_ref.mounted) return;
        if (_scanCancelRequested || result['cancelled'] == true) {
          if (result['committed'] == true) {
            await _refreshSummaryFromStorage();
          }
          if (!_ref.mounted) return;
          _current = _current.copyWith(
            isScanning: false,
            scanIsFinalizing: false,
            scanWasCancelled: true,
          );
          await _scanNotifications.showCancelled();
          return;
        }

        await _endPauseForFinalization();
        _current = _current.copyWith(
          scanIsFinalizing: true,
          scanProgress: _current.scanProgress >= 99
              ? _current.scanProgress
              : 99,
          scanCurrentFile: null,
        );

        final skippedCount = result['skippedCount'] as int? ?? 0;
        final scannedCount = (result['scanned_count'] as num).toInt();
        final deletedCount = (result['deleted_count'] as num).toInt();
        final totalFiles = result['totalFiles'] as int? ?? 0;
        if (result['committed'] != true) {
          throw StateError('Native Library scan did not commit its index');
        }

        _log.i(
          'Incremental result: $scannedCount scanned, '
          '$skippedCount skipped, $deletedCount deleted, $totalFiles total',
        );

        if (!await _finishScanSuccess(activeSourceId)) return;

        final summary =
            'Incremental scan complete: ${_current.totalCount} total tracks '
            '($scannedCount new/updated, $skippedCount unchanged, '
            '$deletedCount removed, '
            '${_current.scanErrorCount} errors)';
        if (_current.scanErrorCount > 0) {
          _log.e(summary);
        } else {
          _log.i(summary);
        }
        await _scanNotifications.showComplete(
          totalTracks: _current.totalCount,
          errorCount: _current.scanErrorCount,
        );
      }
    } catch (e, stack) {
      if (!_ref.mounted) return;
      if (_scanCancelRequested) {
        _log.i('Library scan cancelled');
        _current = _current.copyWith(
          isScanning: false,
          scanIsFinalizing: false,
          scanWasCancelled: true,
        );
        await _scanNotifications.showCancelled();
        return;
      }
      _log.e('Library scan failed: $e', e, stack);
      _current = _current.copyWith(
        isScanning: false,
        scanIsFinalizing: false,
        scanWasCancelled: false,
        sources: [
          for (final source in _current.sources)
            source.id == activeSourceId
                ? source.copyWith(lastScanError: e.toString())
                : source,
        ],
      );
      _stopProgressPolling();
      await _scanNotifications.showFailed(e.toString());
      if (activeSourceId != null) {
        try {
          await _db.updateSourceState(
            activeSourceId,
            lastScanError: e.toString(),
          );
          await _refreshSummaryFromStorage();
        } catch (saveError, saveStack) {
          _log.e(
            'Could not save library scan failure: $saveError',
            saveError,
            saveStack,
          );
        }
      }
    } finally {
      _stopProgressPolling();
      await _scanNotifications.pending;
      await _notificationService.endBackgroundWork(
        NotificationService.libraryScanWorkKind,
      );

      if (_scanPauseRequested) {
        _scanPauseRequested = false;
        await _releaseNativeScanPause();
      }
      try {
        final prefs = await _preferences();
        if (prefs.getString(localLibraryActiveScanSourceKey) ==
            activeSourceId) {
          await prefs.remove(localLibraryActiveScanSourceKey);
          await prefs.remove(localLibraryActiveScanStartedAtKey);
          await prefs.remove(localLibraryRecoveredScanKey);
        }
      } catch (e) {
        _log.w('Failed to clear active library scan marker: $e');
      }
    }
  }
}
