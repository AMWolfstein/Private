import 'package:sistrum/services/native/library_scan_bridge.dart';
import 'package:sistrum/utils/progress_stream_poller.dart';

/// One native scan progress snapshot, normalised for the Library state.
final class LibraryScanProgressSample {
  const LibraryScanProgressSample({
    required this.progress,
    required this.displayProgress,
    required this.currentFile,
    required this.totalFiles,
    required this.scannedFiles,
    required this.errorCount,
  });

  /// Percentage rounded to one decimal place, for notices.
  final double progress;

  /// What the Library shows: a finished scan still reads as 99% until its
  /// result is committed.
  final double displayProgress;
  final String? currentFile;
  final int totalFiles;
  final int scannedFiles;
  final int errorCount;
}

/// Reads one native snapshot while a scan is running. Returns null for
/// snapshots that must not move the state: after a cancel, outside a scan,
/// while finalizing, or a completed snapshot (only the scan's own result
/// finishes it, so a replayed terminal snapshot never stops polling).
LibraryScanProgressSample? readLibraryScanProgress({
  required bool cancelRequested,
  required bool isScanning,
  required bool isFinalizing,
  required Map<String, dynamic> progress,
}) {
  if (cancelRequested ||
      !isScanning ||
      isFinalizing ||
      progress['is_complete'] == true) {
    return null;
  }
  final nextProgress = (progress['progress_pct'] as num?)?.toDouble() ?? 0;
  final normalized = ((nextProgress * 10).round() / 10).clamp(0.0, 100.0);
  return LibraryScanProgressSample(
    progress: normalized,
    displayProgress: normalized >= 100.0 ? 99.0 : normalized,
    currentFile: progress['current_file'] as String?,
    totalFiles: (progress['total_files'] as num?)?.toInt() ?? 0,
    scannedFiles: (progress['scanned_files'] as num?)?.toInt() ?? 0,
    errorCount: (progress['error_count'] as num?)?.toInt() ?? 0,
  );
}

/// Streams native scan progress, falling back to polling. Owns the timing
/// and fallback policy; the caller decides what a snapshot changes.
final class LibraryScanProgressPolling {
  LibraryScanProgressPolling({
    required Future<void> Function(Map<String, dynamic>) onProgress,
    required void Function(String message) onWarning,
  }) : _poller = ProgressStreamPoller<Map<String, dynamic>>(
         streamProvider: LibraryScanBridge.libraryScanProgressStream,
         pollProvider: LibraryScanBridge.getLibraryScanProgress,
         onProgress: onProgress,
         pollingInterval: _pollingInterval,
         bootstrapTimeout: _bootstrapTimeout,
         onStreamProcessingError: (e) => onWarning(
           'Library scan progress stream processing failed: $e',
         ),
         onStreamFailed: (error) => onWarning(
           'Library scan progress stream failed, fallback to polling: $error',
         ),
         onStreamTimeout: () => onWarning(
           'Library scan progress stream timeout, fallback to polling',
         ),
         onPollError: (e) =>
             onWarning('Library scan progress polling failed: $e'),
       ),
       _onWarning = onWarning;

  static const _pollingInterval = Duration(milliseconds: 350);
  static const _bootstrapTimeout = Duration(milliseconds: 900);

  final ProgressStreamPoller<Map<String, dynamic>> _poller;
  final void Function(String message) _onWarning;

  /// On Android the native stream is primary; one immediate poll fills in
  /// progress before the first streamed snapshot arrives.
  void start({required bool useStream}) {
    _poller.start(useStream: useStream);
    if (useStream) {
      Future<void>.microtask(
        () => _poller.pollOnce(
          (e) => _onWarning('Initial library scan progress fetch failed: $e'),
        ),
      );
    }
  }

  void stop() => _poller.stop();
}
