part of 'local_library_provider.dart';

extension _LocalLibraryScanResults on LocalLibraryNotifier {
  /// Shared success tail for full and incremental scans: failure bookkeeping,
  /// source timestamps, summary refresh and the terminal _current. Branch-specific
  /// work (cover pruning, summary text) stays with the caller. Returns false
  /// when the provider unmounted before the terminal _current was published.
  Future<bool> _finishScanSuccess(String sourceId) async {
    await _recordScanFailures(sourceId);
    if (!_ref.mounted) return false;
    final now = DateTime.now();
    _sourceVersion++;
    await _db.updateSourceState(
      sourceId,
      available: true,
      lastSeenAt: now,
      lastScannedAt: now,
      clearLastScanError: true,
    );
    try {
      final prefs = await _preferences();
      await writeLocalLibraryLastScannedAt(prefs, now);
      _log.d('Saved lastScannedAt: $now');
    } catch (e) {
      _log.w('Failed to save lastScannedAt: $e');
    }

    await _refreshSummaryFromStorage(lastScannedAt: now);
    if (!_ref.mounted) return false;
    _current = _current.copyWith(
      isScanning: false,
      scanIsFinalizing: false,
      scanProgress: 100,
      lastScannedAt: now,
      scanWasCancelled: false,
    );
    return true;
  }

  /// Keeps the files a finished scan could not read, per source; a clean
  /// scan clears them.
  Future<void> _recordScanFailures(String sourceId) async {
    final failures =
        await _readNativeScanFailures() ??
        LibraryScanFailures(count: _current.scanErrorCount, files: const []);
    if (!_ref.mounted) return;
    // Progress polling stops before the last files finish, so the finished
    // report has the final count.
    if (failures.count > _current.scanErrorCount) {
      _current = _current.copyWith(scanErrorCount: failures.count);
    }
    await _setScanFailures(sourceId, failures.count > 0 ? failures : null);
  }

  Future<LibraryScanFailures?> _readNativeScanFailures() async {
    try {
      final progress = await LibraryScanBridge.getLibraryScanProgress();
      if (progress['is_complete'] != true) return null;
      return LibraryScanFailures.fromProgress(progress);
    } catch (e) {
      _log.w('Failed to read library scan failures: $e');
      return null;
    }
  }

  Future<void> _setScanFailures(
    String sourceId,
    LibraryScanFailures? failures,
  ) async {
    final current = _current.scanFailures;
    if (failures == null && !current.containsKey(sourceId)) return;
    final next = {...current};
    if (failures == null) {
      next.remove(sourceId);
    } else {
      next[sourceId] = failures;
    }
    _current = _current.copyWith(scanFailures: next);
    try {
      await writeLocalLibraryScanFailures(await _preferences(), next);
    } catch (e) {
      _log.w('Failed to save library scan failures: $e');
    }
  }

  void _startProgressPolling() =>
      _progressPolling.start(useStream: Platform.isAndroid);
  Future<void> _handleLibraryScanProgress(Map<String, dynamic> progress) async {
    final sample = readLibraryScanProgress(
      cancelRequested: _scanCancelRequested,
      isScanning: _current.isScanning,
      isFinalizing: _current.scanIsFinalizing,
      progress: progress,
    );
    if (sample == null) return;

    final shouldUpdateState =
        _current.scanProgress != sample.displayProgress ||
        _current.scanCurrentFile != sample.currentFile ||
        _current.scanTotalFiles != sample.totalFiles ||
        _current.scannedFiles != sample.scannedFiles ||
        _current.scanErrorCount != sample.errorCount;
    if (shouldUpdateState) {
      _current = _current.copyWith(
        scanProgress: sample.displayProgress,
        scanCurrentFile: sample.currentFile,
        scanTotalFiles: sample.totalFiles,
        scannedFiles: sample.scannedFiles,
        scanErrorCount: sample.errorCount,
      );
    }

    // Files already in flight still finish after a pause; count them, but
    // keep the paused notice instead of reposting progress.
    if (!_current.scanIsPaused &&
        _scanNotifications.shouldShowProgress(
          progress: sample.progress,
          totalFiles: sample.totalFiles,
          isComplete: false,
        )) {
      await _scanNotifications.showProgress(
        progress: sample.progress,
        scannedFiles: sample.scannedFiles,
        totalFiles: sample.totalFiles,
        currentFile: sample.currentFile,
      );
    }
  }

  void _stopProgressPolling() {
    _progressPolling.stop();
    _scanNotifications.reset();
  }

  Future<void> _releaseNativeScanPause() async {
    try {
      await LibraryScanBridge.resumeLibraryScan();
    } catch (e) {
      _log.w('Failed to release library scan pause: $e');
    }
  }

  /// The native scan can finish while paused when the pause lands after its
  /// last file. Ingestion then runs normally, so restore background work.
  Future<void> _endPauseForFinalization() async {
    if (!_scanPauseRequested) return;
    _scanPauseRequested = false;
    _current = _current.copyWith(scanIsPaused: false);
    await _notificationService.beginLibraryScanWork();
    await _scanNotifications.cancelPaused();
    await _releaseNativeScanPause();
  }

  Future<void> _clearLibrary() async {
    if (!_ref.mounted) return;
    _clearingLibrary = true;
    _scanEpoch++;
    _sourceVersion++;
    try {
      _pendingReconnectScans.clear();
      _availabilityRequestVersion++;
      _scanReconnectedOnRefresh = false;
      final activeScan = _scanCompletion;
      await cancelScan();
      // Cancellation can arrive after the native publication transaction has
      // started. Join its owner before clearing so it cannot repopulate rows.
      await activeScan;
      await _db.clearAll();

      try {
        final prefs = await SharedPreferences.getInstance();
        await clearLocalLibraryLastScannedAt(prefs);
        await writeLocalLibraryScanFailures(prefs, const {});
      } catch (e) {
        _log.w('Failed to clear lastScannedAt: $e');
      }

      if (!_ref.mounted) return;
      await _refreshSummaryFromStorage();
      if (!_ref.mounted) return;
      _current = _current.copyWith(
        clearLastScannedAt: true,
        scanFailures: const {},
      );
      _log.i('Library cleared');
    } finally {
      _pendingReconnectScans.clear();
      _scanReconnectedOnRefresh = false;
      _clearingLibrary = false;
    }
  }

  Future<void> _pruneLibraryCoverCache() async {
    try {
      final appSupportDir = await getApplicationSupportDirectory();
      final libraryCoverDir = Directory('${appSupportDir.path}/library_covers');
      if (!await libraryCoverDir.exists()) {
        return;
      }

      if (!_ref.mounted || _scanCancelRequested) return;
      final libraryDatabase = await _db.database;
      if (!_ref.mounted || _scanCancelRequested) return;

      final deletedCount = await pruneUnreferencedLibraryCovers(
        libraryCoverDir,
        const {},
        libraryDatabase: libraryDatabase,
        requestId: _nativeLibraryRequestId,
        canPrune: () => _ref.mounted && !_scanCancelRequested,
        // Avoid removing covers being written by a background producer before
        // its Library transaction publishes the reference. The scan guard is
        // still held here; the source sqflite transaction holds the writer
        // barrier while Rust reads its detached, private cover projection.
        minimumAge: const Duration(minutes: 1),
      );

      if (deletedCount > 0) {
        _log.i('Pruned $deletedCount stale library cover cache files');
      }
    } catch (e) {
      _log.w('Failed pruning library cover cache: $e');
    }
  }
}
