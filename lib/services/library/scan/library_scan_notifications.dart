import 'package:sistrum/services/platform/notification_service.dart';
import 'package:sistrum/utils/logging/logger.dart';

final _log = AppLogger('LocalLibrary');

/// Library scan notices: throttled progress, terminal results and pause or
/// cancel notices. Each notice queues behind the previous one, and a failed
/// notice is logged without stopping the scan.
class LibraryScanNotifications {
  LibraryScanNotifications({
    required NotificationService service,
    required bool Function() progressVisible,
  }) : _service = service,
       _progressVisible = progressVisible;

  final NotificationService _service;

  /// Whether progress notices may still show; the scan may already have ended.
  final bool Function() _progressVisible;

  static const _heartbeat = Duration(seconds: 4);
  Future<void> _tail = Future<void>.value();
  int _lastPercent = -1;
  int _lastTotalFiles = -1;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Completes once every queued notice has been attempted.
  Future<void> get pending => _tail;

  void reset() {
    _lastPercent = -1;
    _lastTotalFiles = -1;
    _lastAt = DateTime.fromMillisecondsSinceEpoch(0);
  }

  bool shouldShowProgress({
    required double progress,
    required int totalFiles,
    required bool isComplete,
  }) {
    final now = DateTime.now();
    final percent = progress.round().clamp(0, 100);
    final percentChanged = percent != _lastPercent;
    final totalFilesChanged = totalFiles != _lastTotalFiles;
    final heartbeatDue = now.difference(_lastAt) >= _heartbeat;

    if (!percentChanged && !totalFilesChanged && !isComplete && !heartbeatDue) {
      return false;
    }

    _lastPercent = percent;
    _lastTotalFiles = totalFiles;
    _lastAt = now;
    return true;
  }

  Future<void> showPaused(int scannedFiles) => notifyBestEffort(
    () => _service.showLibraryScanPaused(scannedFiles: scannedFiles),
    'Failed to show scan paused notification',
  );

  Future<void> cancelPaused() => notifyBestEffort(
    _service.cancelLibraryScanNotification,
    'Failed to clear scan paused notification',
  );

  Future<void> showProgress({
    required double progress,
    required int scannedFiles,
    required int totalFiles,
    required String? currentFile,
  }) => notifyBestEffort(() async {
    if (!_progressVisible()) return;
    await _service.showLibraryScanProgress(
      progress: progress,
      scannedFiles: scannedFiles,
      totalFiles: totalFiles,
      currentFile: shortenFile(currentFile),
    );
  }, 'Failed to show scan progress notification');

  Future<void> showComplete({
    required int totalTracks,
    required int errorCount,
  }) => notifyBestEffort(
    () => _service.showLibraryScanComplete(
      totalTracks: totalTracks,
      errorCount: errorCount,
    ),
    'Failed to show scan complete notification',
  );

  Future<void> showFailed(String message) => notifyBestEffort(
    () => _service.showLibraryScanFailed(message),
    'Failed to show scan failure notification',
  );

  Future<void> showCancelled() => notifyBestEffort(
    _service.showLibraryScanCancelled,
    'Failed to show scan cancelled notification',
  );

  /// Queues a scan notice whose failure must never stop the scan or cleanup.
  Future<void> notifyBestEffort(
    Future<void> Function() notify,
    String failure,
  ) async {
    try {
      await queue(notify);
    } catch (e) {
      _log.w('$failure: $e');
    }
  }

  Future<void> queue(Future<void> Function() notify) {
    final next = _tail.then((_) => notify());
    // A failed notification must not prevent the terminal notice or cleanup.
    _tail = next.catchError((Object _) {});
    return next;
  }

  static String? shortenFile(String? path) {
    final raw = path?.trim() ?? '';
    if (raw.isEmpty) return null;

    var decoded = raw;
    try {
      decoded = Uri.decodeFull(raw);
    } catch (_) {}

    final slashIdx = decoded.lastIndexOf('/');
    final backslashIdx = decoded.lastIndexOf('\\');
    final cut = slashIdx > backslashIdx ? slashIdx : backslashIdx;
    if (cut >= 0 && cut < decoded.length - 1) {
      return decoded.substring(cut + 1);
    }
    return decoded;
  }
}
