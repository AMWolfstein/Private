import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/models/library_scan_failure.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/providers/library_collections_provider.dart';
import 'package:sistrum/services/library/library_cleanup.dart';
import 'package:sistrum/services/library/library_database.dart';
import 'package:sistrum/services/library/library_mutation_ports.dart';
import 'package:sistrum/services/notification_service.dart';
import 'package:sistrum/services/platform_bridge.dart';
import 'package:sistrum/utils/logger.dart';
import 'package:sistrum/utils/file_access.dart';
import 'package:sistrum/utils/local_library_scan_prefs.dart';
import 'package:sistrum/utils/progress_stream_poller.dart';

final _log = AppLogger('LocalLibrary');

/// Resolves preferences per operation: SharedPreferences caches a successful
/// instance itself, so a failed first attempt is not retained for the process.
Future<SharedPreferences> _preferences() => SharedPreferences.getInstance();

class LocalLibraryState {
  final bool isLoading;
  final bool loadFailed;
  final bool isScanning;
  final bool scanIsFinalizing;
  final bool scanIsPaused;
  final double scanProgress;
  final String? scanCurrentFile;
  final int scanTotalFiles;
  final int scannedFiles;
  final int scanErrorCount;
  final bool scanWasCancelled;
  final int totalCount;
  final int loadedIndexVersion;
  final DateTime? lastScannedAt;
  final List<LocalLibrarySource> sources;
  final String? scanningSourceId;

  /// Files the last scan of each source could not read, by source ID.
  final Map<String, LibraryScanFailures> scanFailures;
  LocalLibraryState({
    this.isLoading = false,
    this.loadFailed = false,
    this.isScanning = false,
    this.scanIsFinalizing = false,
    this.scanIsPaused = false,
    this.scanProgress = 0,
    this.scanCurrentFile,
    this.scanTotalFiles = 0,
    this.scannedFiles = 0,
    this.scanErrorCount = 0,
    this.scanWasCancelled = false,
    this.totalCount = 0,
    this.loadedIndexVersion = 0,
    this.lastScannedAt,
    this.sources = const <LocalLibrarySource>[],
    this.scanningSourceId,
    this.scanFailures = const {},
  });

  LocalLibraryState copyWith({
    bool? isLoading,
    bool? loadFailed,
    bool? isScanning,
    bool? scanIsFinalizing,
    bool? scanIsPaused,
    double? scanProgress,
    String? scanCurrentFile,
    int? scanTotalFiles,
    int? scannedFiles,
    int? scanErrorCount,
    bool? scanWasCancelled,
    int? totalCount,
    int? loadedIndexVersion,
    DateTime? lastScannedAt,
    bool clearLastScannedAt = false,
    List<LocalLibrarySource>? sources,
    String? scanningSourceId,
    bool clearScanningSourceId = false,
    Map<String, LibraryScanFailures>? scanFailures,
  }) {
    return LocalLibraryState(
      isLoading: isLoading ?? this.isLoading,
      loadFailed: loadFailed ?? this.loadFailed,
      isScanning: isScanning ?? this.isScanning,
      scanIsFinalizing: scanIsFinalizing ?? this.scanIsFinalizing,
      scanIsPaused: scanIsPaused ?? this.scanIsPaused,
      scanProgress: scanProgress ?? this.scanProgress,
      scanCurrentFile: scanCurrentFile ?? this.scanCurrentFile,
      scanTotalFiles: scanTotalFiles ?? this.scanTotalFiles,
      scannedFiles: scannedFiles ?? this.scannedFiles,
      scanErrorCount: scanErrorCount ?? this.scanErrorCount,
      scanWasCancelled: scanWasCancelled ?? this.scanWasCancelled,
      totalCount: totalCount ?? this.totalCount,
      loadedIndexVersion: loadedIndexVersion ?? this.loadedIndexVersion,
      lastScannedAt: clearLastScannedAt
          ? null
          : lastScannedAt ?? this.lastScannedAt,
      sources: sources ?? this.sources,
      scanningSourceId: clearScanningSourceId
          ? null
          : scanningSourceId ?? this.scanningSourceId,
      scanFailures: scanFailures ?? this.scanFailures,
    );
  }
}

typedef LocalLibraryAvailabilityProbe = Future<bool?> Function(String path);

class LocalLibraryNotifier extends Notifier<LocalLibraryState>
    implements LibrarySourceSink, LibraryRemovalSink {
  LocalLibraryNotifier({
    LibraryDatabase? database,
    LocalLibraryAvailabilityProbe? availabilityProbe,
  }) : _db = database ?? LibraryDatabase.instance,
       _availabilityProbe = availabilityProbe;

  final LibraryDatabase _db;
  final LocalLibraryAvailabilityProbe? _availabilityProbe;
  final NotificationService _notificationService = NotificationService();
  static const _progressPollingInterval = Duration(milliseconds: 350);
  static const _progressStreamBootstrapTimeout = Duration(milliseconds: 900);
  late final ProgressStreamPoller<Map<String, dynamic>> _progressPoller =
      ProgressStreamPoller<Map<String, dynamic>>(
        streamProvider: PlatformBridge.libraryScanProgressStream,
        pollProvider: PlatformBridge.getLibraryScanProgress,
        onProgress: _handleLibraryScanProgress,
        pollingInterval: _progressPollingInterval,
        bootstrapTimeout: _progressStreamBootstrapTimeout,
        onStreamProcessingError: (e) =>
            _log.w('Library scan progress stream processing failed: $e'),
        onStreamFailed: (error) => _log.w(
          'Library scan progress stream failed, fallback to polling: $error',
        ),
        onStreamTimeout: () =>
            _log.w('Library scan progress stream timeout, fallback to polling'),
        onPollError: (e) => _log.w('Library scan progress polling failed: $e'),
      );
  bool _isLoaded = false;
  bool _hasLoadedFromDatabase = false;
  Future<void>? _loadFuture;
  Future<void>? _scanRecovery;
  Future<void> _scanNotificationTail = Future<void>.value();
  bool _scanCancelRequested = false;
  bool _scanPauseRequested = false;
  bool _scanInProgress = false;
  Future<void>? _scanCompletion;
  Future<void>? _clearFuture;
  bool _clearingLibrary = false;
  int _scanEpoch = 0;
  String? _nativeLibraryRequestId;
  final Set<String> _pendingReconnectScans = {};
  bool _drainingReconnectScans = false;
  StreamSubscription<void>? _storageEventsSubscription;
  Timer? _storageEventDebounce;
  Timer? _availabilityRetry;
  int _availabilityRetryCount = 0;
  int _sourceVersion = 0;
  int _availabilityRequestVersion = 0;
  bool _scanReconnectedOnRefresh = false;
  Future<void>? _availabilityRefreshFuture;
  Future<({List<String> reconnected, bool changed, int requestVersion})>?
  _availabilityCheckFuture;
  static const _scanNotificationHeartbeat = Duration(seconds: 4);
  int _lastScanNotificationPercent = -1;
  int _lastScanNotificationTotalFiles = -1;
  DateTime _lastScanNotificationAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  LocalLibraryState build() {
    ref.onDispose(() {
      _scanCancelRequested = true;
      _scanPauseRequested = false;
      _pendingReconnectScans.clear();
      if (_scanInProgress) {
        final requestId = _nativeLibraryRequestId;
        if (requestId != null) {
          unawaited(
            PlatformBridge.cancelNativeDataJob(requestId).catchError((
              Object error,
            ) {
              _log.w('Failed to cancel disposed library ingestion: $error');
            }),
          );
        }
        unawaited(
          PlatformBridge.cancelLibraryScan().catchError((Object error) {
            _log.w('Failed to cancel disposed library scan: $error');
          }),
        );
      }
      _progressPoller.stop();
      _storageEventsSubscription?.cancel();
      _storageEventDebounce?.cancel();
      _availabilityRetry?.cancel();
    });

    if (Platform.isAndroid) {
      _storageEventsSubscription = PlatformBridge.libraryStorageEvents().listen(
        (_) {
          _storageEventDebounce?.cancel();
          _storageEventDebounce = Timer(
            const Duration(milliseconds: 900),
            () => refreshSourceAvailability(scanReconnected: true),
          );
        },
        onError: (Object e) =>
            _log.w('Library storage event stream failed: $e'),
      );
    }

    Future.microtask(_ensureLoadedFromDatabase);
    return LocalLibraryState(isLoading: true);
  }

  Future<void> _ensureLoadedFromDatabase() {
    if (_hasLoadedFromDatabase) {
      return Future<void>.value();
    }
    return _loadFuture ??= _loadFromDatabase();
  }

  Future<void> _loadFromDatabase() async {
    if (_hasLoadedFromDatabase) return;
    if (_isLoaded) {
      return _loadFuture ?? Future<void>.value();
    }
    _isLoaded = true;
    final scanEpoch = _scanEpoch;
    state = state.copyWith(isLoading: true, loadFailed: false);

    try {
      await _recoverInterruptedScan();
      if (!ref.mounted) return;
      // Folder configuration is independent of the potentially expensive
      // track index and storage probes. Publish it before either can fail.
      final configuredSources = await _db.getSources();
      if (!ref.mounted) return;
      state = state.copyWith(sources: configuredSources);
      await ref.read(settingsProvider.notifier).ensureLoaded();
      final reconnectedSources = await _refreshSourceAvailabilityInDatabase();
      while (ref.mounted) {
        final sourceVersion = _sourceVersion;
        final sources = await _db.getSources();
        if (!ref.mounted) return;
        if (sourceVersion != _sourceVersion) continue;
        state = state.copyWith(sources: sources);
        final count = await _db.getCount();

        DateTime? lastScannedAt;
        var scanFailures = const <String, LibraryScanFailures>{};
        try {
          final prefs = await _preferences();
          lastScannedAt = readLocalLibraryLastScannedAt(prefs);
          scanFailures = readLocalLibraryScanFailures(prefs);
        } catch (e) {
          _log.w('Failed to load lastScannedAt: $e');
        }

        if (!ref.mounted) return;
        if (sourceVersion != _sourceVersion) {
          if (_hasLoadedFromDatabase) break;
          continue;
        }
        state = state.copyWith(
          totalCount: count,
          loadedIndexVersion: state.loadedIndexVersion + 1,
          lastScannedAt: lastScannedAt,
          scanFailures: scanFailures,
          sources: sources,
        );
        _log.i(
          'Loaded local library summary: $count items, lastScannedAt: '
          '$lastScannedAt',
        );
        _hasLoadedFromDatabase = true;
        break;
      }
      if (ref.mounted &&
          !_clearingLibrary &&
          scanEpoch == _scanEpoch &&
          reconnectedSources.reconnected.isNotEmpty) {
        unawaited(
          Future<void>.microtask(
            () => _scanSourcesSequentially(reconnectedSources.reconnected),
          ),
        );
      }
    } catch (e, stack) {
      _isLoaded = false;
      if (ref.mounted) state = state.copyWith(loadFailed: true);
      _log.e('Failed to load library from database: $e', e, stack);
    } finally {
      _loadFuture = null;
      if (ref.mounted) state = state.copyWith(isLoading: false);
    }
  }

  Future<void> reloadFromStorage() async {
    if (!ref.mounted) return;
    // Invalidate snapshots already being read, not just the next load. The
    // active loader retries its summary when this generation changes.
    _sourceVersion++;
    _hasLoadedFromDatabase = false;
    final loading = _loadFuture;
    if (loading != null) {
      await loading;
      if (!ref.mounted || _hasLoadedFromDatabase) return;
    }
    // Another reload may already have started a retry after a failed load.
    // Join that owner rather than clearing its single-flight future.
    if (_loadFuture == null) _isLoaded = false;
    await _ensureLoadedFromDatabase();
  }

  @override
  Future<LocalLibrarySource> addSource({
    required String path,
    required String displayName,
    String? volumeId,
    bool isRemovable = false,
  }) async {
    final trimmedPath = path.trim();
    if (trimmedPath.isEmpty) {
      throw const FormatException('Library folder path is empty');
    }
    final existing = await _db.getSourceByPath(trimmedPath);
    if (existing != null) {
      _sourceVersion++;
      await _db.updateSourceState(
        existing.id,
        enabled: true,
        available: true,
        lastSeenAt: DateTime.now(),
      );
      await _refreshSummaryFromStorage();
      return existing.copyWith(
        enabled: true,
        available: true,
        lastSeenAt: DateTime.now(),
      );
    }

    final source = LocalLibrarySource(
      id: _newSourceId(trimmedPath),
      path: trimmedPath,
      displayName: displayName.trim().isEmpty
          ? _displayNameForPath(trimmedPath)
          : displayName.trim(),
      volumeId: volumeId?.trim().isEmpty == true ? null : volumeId,
      isRemovable: isRemovable || _looksLikeRemovablePath(trimmedPath),
      enabled: true,
      available: true,
      lastSeenAt: DateTime.now(),
    );
    _sourceVersion++;
    await _db.upsertSource(source);
    await _refreshSummaryFromStorage();
    return source;
  }

  String _newSourceId(String path) {
    const offset = 0xcbf29ce484222325;
    const prime = 0x100000001b3;
    const mask = 0xffffffffffffffff;
    var hash = offset;
    for (final unit in path.codeUnits) {
      hash = ((hash ^ unit) * prime) & mask;
    }
    return 'source_${hash.toRadixString(16).padLeft(16, '0')}';
  }

  Future<void> setSourceEnabled(String sourceId, bool enabled) async {
    final source = state.sources
        .where((entry) => entry.id == sourceId)
        .firstOrNull;
    _sourceVersion++;
    await _db.updateSourceState(sourceId, enabled: enabled);
    await _refreshSummaryFromStorage();
    if (enabled &&
        source?.available == true &&
        source?.isIndexed == true &&
        !_scanInProgress) {
      unawaited(startSourceScan(sourceId));
    }
  }

  Future<void> removeSource(String sourceId) async {
    LocalLibrarySource? removed;
    for (final source in state.sources) {
      if (source.id == sourceId) {
        removed = source;
        break;
      }
    }
    // Removal can run while the initial index is still loading, so it must not
    // wait for that load. The removed folder's path is only needed afterwards
    // to release its grant, so read it from storage when it is not in state.
    if (removed == null && !_hasLoadedFromDatabase) {
      try {
        removed = (await _db.getSources())
            .where((source) => source.id == sourceId)
            .firstOrNull;
      } catch (_) {
        removed = null;
      }
    }
    final releaseUri = removed?.path;
    final stillUsed =
        releaseUri != null &&
        state.sources.any(
          (source) => source.id != sourceId && source.path == releaseUri,
        );
    _sourceVersion++;
    await _db.removeSource(sourceId);
    await _setScanFailures(sourceId, null);
    await _refreshSummaryFromStorage();
    // Folder grants are a bounded platform resource; release the tree once no
    // remaining source refers to it.
    if (releaseUri != null &&
        releaseUri.startsWith('content://') &&
        !stillUsed) {
      try {
        await PlatformBridge.releaseSafTree(releaseUri);
      } catch (_) {
        _log.w('Failed to release the SAF tree grant for a removed source');
      }
    }
  }

  Future<void> refreshSourceAvailability({bool scanReconnected = false}) {
    _availabilityRequestVersion++;
    _scanReconnectedOnRefresh |= scanReconnected;
    return _availabilityRefreshFuture ??= _refreshSourceAvailability()
        .whenComplete(() {
          _availabilityRefreshFuture = null;
          _scanReconnectedOnRefresh = false;
        });
  }

  Future<void> _refreshSourceAvailability() async {
    final scanEpoch = _scanEpoch;
    await _ensureLoadedFromDatabase();
    final reconnected = <String>{};
    while (ref.mounted) {
      final result = await _refreshSourceAvailabilityInDatabase();
      if (!ref.mounted) return;
      reconnected.addAll(result.reconnected);
      if (result.changed) await _refreshSummaryFromStorage();
      if (result.requestVersion == _availabilityRequestVersion) break;
    }

    // Existing rows become visible as soon as availability flips. The
    // incremental pass then verifies changes made while storage was detached
    // without re-reading metadata for unchanged files.
    if (ref.mounted &&
        !_clearingLibrary &&
        scanEpoch == _scanEpoch &&
        _scanReconnectedOnRefresh &&
        reconnected.isNotEmpty) {
      _pendingReconnectScans.addAll(reconnected);
      unawaited(_drainReconnectScans());
    }
  }

  Future<void> _scanSourcesSequentially(
    Iterable<String> sourceIds, {
    bool forceFullScan = false,
  }) async {
    final epoch = _scanEpoch;
    for (final sourceId in sourceIds) {
      if (!ref.mounted || _clearingLibrary || epoch != _scanEpoch) break;
      await startSourceScan(sourceId, forceFullScan: forceFullScan);
      if (_scanCancelRequested) break;
    }
  }

  Future<void> scanAllSources({bool forceFullScan = false}) async {
    final epoch = _scanEpoch;
    if (_clearingLibrary || !ref.mounted) return;
    await _ensureLoadedFromDatabase();
    if (!ref.mounted || _clearingLibrary || epoch != _scanEpoch) return;
    final sourceIds = state.sources
        .where((source) => source.enabled && source.available)
        .map((source) => source.id)
        .toList(growable: false);
    await _scanSourcesSequentially(sourceIds, forceFullScan: forceFullScan);
  }

  @override
  Future<void> startSourceScan(
    String sourceId, {
    bool forceFullScan = false,
  }) async {
    final epoch = _scanEpoch;
    if (_clearingLibrary) return;
    final reconnect = _pendingReconnectScans.contains(sourceId);
    while (ref.mounted && !_clearingLibrary && epoch == _scanEpoch) {
      final source = await _sourceForScan(sourceId);
      if (!ref.mounted ||
          _clearingLibrary ||
          epoch != _scanEpoch ||
          source == null ||
          (reconnect && !_pendingReconnectScans.contains(sourceId))) {
        return;
      }
      if (_scanInProgress) {
        if (!reconnect) return;
        final active = _scanCompletion;
        if (active != null) await active;
        continue;
      }
      await startScan(
        source.path,
        forceFullScan: forceFullScan,
        sourceId: source.id,
      );
      return;
    }
  }

  Future<LocalLibrarySource?> _sourceForScan(String sourceId) async {
    if (!ref.mounted) return null;
    await _ensureLoadedFromDatabase();
    if (!ref.mounted) return null;
    while (ref.mounted) {
      final sourceVersion = _sourceVersion;
      final source = (await _db.getSources())
          .where((entry) => entry.id == sourceId)
          .firstOrNull;
      if (!ref.mounted) return null;
      if (sourceVersion != _sourceVersion) continue;
      return source?.enabled == true && source?.available == true
          ? source
          : null;
    }
    return null;
  }

  Future<void> _drainReconnectScans() async {
    if (_drainingReconnectScans || !ref.mounted || _clearingLibrary) return;
    _drainingReconnectScans = true;
    try {
      while (ref.mounted &&
          !_clearingLibrary &&
          _pendingReconnectScans.isNotEmpty) {
        final active = _scanCompletion;
        if (active != null) await active;
        if (!ref.mounted || _pendingReconnectScans.isEmpty) break;
        final sourceId = _pendingReconnectScans.first;
        await startSourceScan(sourceId);
        _pendingReconnectScans.remove(sourceId);
      }
    } catch (error, stack) {
      _log.e('Failed to scan reconnected library source: $error', error, stack);
    } finally {
      _drainingReconnectScans = false;
    }
  }

  Future<void> _refreshSummaryFromStorage({DateTime? lastScannedAt}) async {
    final sourceVersion = ++_sourceVersion;
    final sources = await _db.getSources();
    if (!ref.mounted || sourceVersion != _sourceVersion) return;
    state = state.copyWith(sources: sources);
    final count = await _db.getCount();
    if (!ref.mounted || sourceVersion != _sourceVersion) return;
    final latestSourceScan = sources
        .map((source) => source.lastScannedAt)
        .whereType<DateTime>()
        .fold<DateTime?>(
          null,
          (latest, value) =>
              latest == null || value.isAfter(latest) ? value : latest,
        );
    state = state.copyWith(
      loadFailed: false,
      totalCount: count,
      loadedIndexVersion: state.loadedIndexVersion + 1,
      lastScannedAt: lastScannedAt ?? latestSourceScan,
      sources: sources,
    );
    _hasLoadedFromDatabase = true;
    _isLoaded = true;
  }

  String _displayNameForPath(String path) {
    if (path.startsWith('content://')) {
      try {
        // `pathSegments` already percent-decodes each segment; decoding again
        // would turn a literal `%XX` in a folder name into a different name.
        final decoded = Uri.parse(path).pathSegments.last;
        final relative = decoded.contains(':')
            ? decoded.substring(decoded.indexOf(':') + 1)
            : decoded;
        if (relative.trim().isNotEmpty) {
          return relative.split('/').last;
        }
      } catch (_) {}
      return 'Music';
    }
    final normalized = path
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'/+$'), '');
    final name = normalized.split('/').last;
    return name.isEmpty ? path : name;
  }

  bool _looksLikeRemovablePath(String path) {
    if (path.startsWith('content://')) {
      try {
        // `pathSegments` is already decoded; see `_displayNameForPath`.
        final decoded = Uri.parse(path).pathSegments.last;
        return !decoded.startsWith('primary:');
      } catch (_) {
        return false;
      }
    }
    final normalized = path.replaceAll('\\', '/').toLowerCase();
    return normalized.startsWith('/storage/') &&
        !normalized.startsWith('/storage/emulated/');
  }

  Future<bool> _isPathAvailable(String path) async {
    return await _probePathAvailability(path) ?? true;
  }

  Future<bool?> _probePathAvailability(String path) async {
    try {
      if (_availabilityProbe != null) {
        return await _availabilityProbe(path);
      }
      if (Platform.isAndroid && path.startsWith('content://')) {
        return await PlatformBridge.probeSafTreeReadAccess(path);
      }

      return await Directory(path).exists();
    } catch (error) {
      // A busy provider or a filesystem exception cannot prove detachment.
      _log.w('Library source access probe failed: $error');
      return null;
    }
  }

  Future<({List<String> reconnected, bool changed, int requestVersion})>
  _refreshSourceAvailabilityInDatabase() =>
      _availabilityCheckFuture ??= _checkSourceAvailability().whenComplete(() {
        _availabilityCheckFuture = null;
      });

  Future<({List<String> reconnected, bool changed, int requestVersion})>
  _checkSourceAvailability() async {
    final reconnected = <String>{};
    var changed = false;
    while (ref.mounted) {
      final sourceVersion = _sourceVersion;
      final requestVersion = _availabilityRequestVersion;
      final sources = await _db.getSources();
      var inconclusive = false;
      for (final source in sources) {
        final available = await _probePathAvailability(source.path);
        if (!ref.mounted ||
            sourceVersion != _sourceVersion ||
            requestVersion != _availabilityRequestVersion) {
          break;
        }
        if (available == null) {
          inconclusive = true;
          _log.w(
            'Library source access inconclusive; retaining status: ${source.id}',
          );
          continue;
        }
        if (available != source.available) {
          await _db.updateSourceState(
            source.id,
            available: available,
            lastSeenAt: available ? DateTime.now() : null,
          );
          changed = true;
          if (available && source.enabled && source.isIndexed) {
            reconnected.add(source.id);
          }
        }
      }
      if (!ref.mounted) break;
      // A folder edit or a newer storage event supersedes pending probe
      // results. Re-read the source snapshot before applying them.
      if (sourceVersion != _sourceVersion ||
          requestVersion != _availabilityRequestVersion) {
        continue;
      }
      _availabilityRetry?.cancel();
      if (inconclusive && _availabilityRetryCount < 3) {
        _availabilityRetryCount++;
        _availabilityRetry = Timer(const Duration(seconds: 2), () {
          unawaited(refreshSourceAvailability(scanReconnected: true));
        });
      } else if (!inconclusive) {
        _availabilityRetryCount = 0;
      }
      return (
        reconnected: reconnected.toList(growable: false),
        changed: changed,
        requestVersion: requestVersion,
      );
    }
    return (
      reconnected: reconnected.toList(growable: false),
      changed: changed,
      requestVersion: _availabilityRequestVersion,
    );
  }

  Future<void> _recoverInterruptedScan() =>
      _scanRecovery ??= _recoverPreviousScan();

  Future<void> _recoverPreviousScan() async {
    try {
      final prefs = await _preferences();
      final sourceId = prefs.getString(localLibraryActiveScanSourceKey);
      if (!ref.mounted || sourceId == null || sourceId.trim().isEmpty) return;
      final startedAfter =
          prefs.getInt(localLibraryActiveScanStartedAtKey) ?? 0;
      final recoveryKey = '$sourceId:$startedAfter';
      if (prefs.getString(localLibraryRecoveredScanKey) == recoveryKey) return;
      var message = _notificationService.libraryScanInterruptedMessage;
      try {
        final exit = await PlatformBridge.getLibraryScanExitInfo(
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
      await _cancelScanPausedNotification();
      await _showScanFailedNotification(message);
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
        ? await PlatformBridge.scanSafTreeToNDJSONFile(
            folderPath,
            forceFullScan: forceFullScan,
            hasIndexedRows: hasIndexedRows,
            isCancelled: () => _scanCancelRequested,
          )
        : await PlatformBridge.scanLibraryFolderToNDJSONFile(
            folderPath,
            forceFullScan: forceFullScan,
            isCancelled: () => _scanCancelRequested,
          );
    var ingested = false;
    try {
      if (_scanCancelRequested) return null;
      await _endPauseForFinalization();
      state = state.copyWith(
        scanIsFinalizing: true,
        scanProgress: state.scanProgress >= 99 ? state.scanProgress : 99,
        scanCurrentFile: null,
        scannedFiles: scanFile.expectedCount,
        scanErrorCount: scanFile.errorCount,
      );
      final result = await _db.replaceSourceScanFile(
        sourceId,
        scanFile,
        requestId: _nativeLibraryRequestId ?? 'desktop-library-scan',
        isCancelled: () => _scanCancelRequested || !ref.mounted,
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

  Future<void> startScan(
    String folderPath, {
    bool forceFullScan = false,
    String? sourceId,
  }) async {
    final epoch = _scanEpoch;
    if (!ref.mounted || _clearingLibrary) return;
    await _recoverInterruptedScan();
    if (!ref.mounted || _clearingLibrary || epoch != _scanEpoch) return;
    if (_scanInProgress || state.isScanning) {
      _log.w('Scan already in progress');
      return;
    }

    final completion = Completer<void>();
    _scanCompletion = completion.future;
    _scanInProgress = true;
    if (sourceId != null) _pendingReconnectScans.remove(sourceId);
    _scanCancelRequested = false;
    _scanPauseRequested = false;
    _nativeLibraryRequestId = PlatformBridge.supportsCoreBackend
        ? 'library-scan-${DateTime.now().microsecondsSinceEpoch}'
        : null;
    try {
      await _runScan(
        folderPath,
        forceFullScan: forceFullScan,
        sourceId: sourceId,
      );
    } finally {
      if (ref.mounted) {
        state = state.copyWith(
          isScanning: false,
          scanIsFinalizing: false,
          clearScanningSourceId: true,
          scanIsPaused: false,
        );
      }
      _scanInProgress = false;
      _scanCompletion = null;
      _nativeLibraryRequestId = null;
      completion.complete();
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
        if (!ref.mounted || _scanCancelRequested) return;
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
      if (!ref.mounted || _scanCancelRequested) return;
      if (!available) {
        _sourceVersion++;
        await _db.updateSourceState(activeSourceId, available: false);
        await _refreshSummaryFromStorage();
        return;
      }
      if (await _sourceForScan(activeSourceId) == null ||
          !ref.mounted ||
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
      if (!ref.mounted || _scanCancelRequested) return;
      _log.i(
        'Starting library scan: $folderPath (incremental: ${!forceFullScan})',
      );
      state = state.copyWith(
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
      _resetScanNotificationTracking();
      // Hold before the first progress notification so Android shows a single
      // foreground-service notification; released in the final cleanup below.
      await _notificationService.beginLibraryScanWork();
      if (_shouldShowScanProgressNotification(
        progress: 0,
        totalFiles: 0,
        isComplete: false,
      )) {
        await _showScanProgressNotification(
          progress: 0,
          scannedFiles: 0,
          totalFiles: 0,
          currentFile: null,
        );
      }

      try {
        final appSupportDir = await getApplicationSupportDirectory();
        final coverCacheDir = '${appSupportDir.path}/library_covers';
        await PlatformBridge.setLibraryCoverCacheDir(coverCacheDir);
        _log.i('Cover cache directory set to: $coverCacheDir');
      } catch (e) {
        _log.w('Failed to set cover cache directory: $e');
      }
      if (!ref.mounted || _scanCancelRequested) return;

      _startProgressPolling();

      if (!ref.mounted || _scanCancelRequested) return;
      final isSaf = folderPath.startsWith('content://');

      final useStreamingFullScan =
          forceFullScan || await _db.getSourceCount(activeSourceId) == 0;
      if (useStreamingFullScan) {
        if (await _sourceForScan(activeSourceId) == null ||
            !ref.mounted ||
            _scanCancelRequested) {
          return;
        }
        final scanResult = await _replaceFromFullScanStream(
          sourceId: activeSourceId,
          folderPath: folderPath,
          isSaf: isSaf,
          forceFullScan: forceFullScan,
        );
        if (!ref.mounted) return;
        if (scanResult == null || _scanCancelRequested) {
          if (scanResult != null) {
            await _refreshSummaryFromStorage();
          }
          if (!ref.mounted) return;
          state = state.copyWith(
            isScanning: false,
            scanIsFinalizing: false,
            scanWasCancelled: true,
          );
          await _showScanCancelledNotification();
          return;
        }

        state = state.copyWith(
          scanIsFinalizing: true,
          scanProgress: state.scanProgress >= 99 ? state.scanProgress : 99,
          scanCurrentFile: null,
        );

        if (!await _finishScanSuccess(activeSourceId)) return;
        await _pruneLibraryCoverCache();

        final summary =
            'Full scan complete: ${state.totalCount} tracks found, '
            '${state.scanErrorCount} errors';
        if (state.scanErrorCount > 0) {
          _log.e(summary);
        } else {
          _log.i(summary);
        }
        await _showScanCompleteNotification(
          totalTracks: state.totalCount,
          errorCount: state.scanErrorCount,
        );
      } else {
        final nativeIngestion = PlatformBridge.supportsCoreBackend;
        final existingFiles = nativeIngestion
            ? const <String, int>{}
            : await _db.getFileModTimes(sourceId: activeSourceId);
        if (!nativeIngestion) {
          _log.i(
            'Incremental scan: ${existingFiles.length} existing files in database',
          );
        }

        final useSnapshotBridge =
            Platform.isAndroid && existingFiles.isNotEmpty;
        final snapshotPath = nativeIngestion
            ? await _db.exportNativeFileModTimesSnapshot(
                activeSourceId,
                requestId: _nativeLibraryRequestId!,
                isCancelled: () => _scanCancelRequested || !ref.mounted,
              )
            : useSnapshotBridge
            ? await _db.writeFileModTimesTsv(existingFiles)
            : null;

        Map<String, dynamic> result;
        try {
          if (await _sourceForScan(activeSourceId) == null ||
              _scanCancelRequested ||
              !ref.mounted) {
            return;
          }
          if (nativeIngestion) {
            result = await _db.scanIncrementalNative(
              activeSourceId,
              folderPath,
              snapshotPath!,
              isSaf: isSaf,
              requestId: _nativeLibraryRequestId!,
              isCancelled: () => _scanCancelRequested || !ref.mounted,
            );
          } else if (isSaf) {
            result = useSnapshotBridge && snapshotPath != null
                ? await PlatformBridge.scanSafTreeIncrementalFromSnapshot(
                    folderPath,
                    snapshotPath,
                  )
                : await PlatformBridge.scanSafTreeIncremental(
                    folderPath,
                    existingFiles,
                  );
          } else {
            result = useSnapshotBridge && snapshotPath != null
                ? await PlatformBridge.scanLibraryFolderIncrementalFromSnapshot(
                    folderPath,
                    snapshotPath,
                  )
                : await PlatformBridge.scanLibraryFolderIncremental(
                    folderPath,
                    existingFiles,
                  );
          }
        } finally {
          if (snapshotPath != null) {
            try {
              await File(snapshotPath).delete();
            } catch (_) {}
          }
        }

        if (!ref.mounted) return;
        if (_scanCancelRequested || result['cancelled'] == true) {
          if (result['committed'] == true) {
            await _refreshSummaryFromStorage();
          }
          if (!ref.mounted) return;
          state = state.copyWith(
            isScanning: false,
            scanIsFinalizing: false,
            scanWasCancelled: true,
          );
          await _showScanCancelledNotification();
          return;
        }

        await _endPauseForFinalization();
        state = state.copyWith(
          scanIsFinalizing: true,
          scanProgress: state.scanProgress >= 99 ? state.scanProgress : 99,
          scanCurrentFile: null,
        );

        final scannedList =
            (result['files'] as List<dynamic>?) ??
            (result['scanned'] as List<dynamic>?) ??
            [];
        final deletedPaths =
            (result['removedUris'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            (result['deletedPaths'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [];
        final skippedCount = result['skippedCount'] as int? ?? 0;
        final totalFiles = result['totalFiles'] as int? ?? 0;
        final scannedCount = nativeIngestion
            ? (result['scanned_count'] as num).toInt()
            : scannedList.length;
        final deletedCount = nativeIngestion
            ? (result['deleted_count'] as num).toInt()
            : deletedPaths.length;
        if (nativeIngestion && result['committed'] != true) {
          throw StateError('Native Library scan did not commit its index');
        }

        _log.i(
          'Incremental result: $scannedCount scanned, '
          '$skippedCount skipped, $deletedCount deleted, $totalFiles total',
        );

        final updatedItems = <LocalLibraryItem>[];
        if (!nativeIngestion && scannedList.isNotEmpty) {
          for (final json in scannedList) {
            final map = json as Map<String, dynamic>;
            final item = LocalLibraryItem.fromJson(map);
            updatedItems.add(item);
          }
          if (updatedItems.isNotEmpty) {
            await _db.upsertBatch(
              updatedItems.map((e) => e.toJson()).toList(),
              sourceId: activeSourceId,
            );
            _log.i('Upserted ${updatedItems.length} items');
          }
        }

        if (!nativeIngestion && deletedPaths.isNotEmpty) {
          final deleteCount = await _db.deleteByPaths(deletedPaths);
          _log.i('Deleted $deleteCount items from database');
        }

        if (!await _finishScanSuccess(activeSourceId)) return;

        final summary =
            'Incremental scan complete: ${state.totalCount} total tracks '
            '($scannedCount new/updated, $skippedCount unchanged, '
            '$deletedCount removed, '
            '${state.scanErrorCount} errors)';
        if (state.scanErrorCount > 0) {
          _log.e(summary);
        } else {
          _log.i(summary);
        }
        await _showScanCompleteNotification(
          totalTracks: state.totalCount,
          errorCount: state.scanErrorCount,
        );
      }
    } catch (e, stack) {
      if (!ref.mounted) return;
      if (_scanCancelRequested) {
        _log.i('Library scan cancelled');
        state = state.copyWith(
          isScanning: false,
          scanIsFinalizing: false,
          scanWasCancelled: true,
        );
        await _showScanCancelledNotification();
        return;
      }
      _log.e('Library scan failed: $e', e, stack);
      state = state.copyWith(
        isScanning: false,
        scanIsFinalizing: false,
        scanWasCancelled: false,
        sources: [
          for (final source in state.sources)
            source.id == activeSourceId
                ? source.copyWith(lastScanError: e.toString())
                : source,
        ],
      );
      _stopProgressPolling();
      await _showScanFailedNotification(e.toString());
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
      await _scanNotificationTail;
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

  /// Shared success tail for full and incremental scans: failure bookkeeping,
  /// source timestamps, summary refresh and the terminal state. Branch-specific
  /// work (cover pruning, summary text) stays with the caller. Returns false
  /// when the provider unmounted before the terminal state was published.
  Future<bool> _finishScanSuccess(String sourceId) async {
    await _recordScanFailures(sourceId);
    if (!ref.mounted) return false;
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
    if (!ref.mounted) return false;
    state = state.copyWith(
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
        LibraryScanFailures(count: state.scanErrorCount, files: const []);
    if (!ref.mounted) return;
    // Progress polling stops before the last files finish, so the finished
    // report has the final count.
    if (failures.count > state.scanErrorCount) {
      state = state.copyWith(scanErrorCount: failures.count);
    }
    await _setScanFailures(sourceId, failures.count > 0 ? failures : null);
  }

  Future<LibraryScanFailures?> _readNativeScanFailures() async {
    try {
      final progress = await PlatformBridge.getLibraryScanProgress();
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
    final current = state.scanFailures;
    if (failures == null && !current.containsKey(sourceId)) return;
    final next = {...current};
    if (failures == null) {
      next.remove(sourceId);
    } else {
      next[sourceId] = failures;
    }
    state = state.copyWith(scanFailures: next);
    try {
      await writeLocalLibraryScanFailures(await _preferences(), next);
    } catch (e) {
      _log.w('Failed to save library scan failures: $e');
    }
  }

  void _startProgressPolling() {
    final useStream = Platform.isAndroid;
    _progressPoller.start(useStream: useStream);
    if (useStream) {
      Future<void>.microtask(
        () => _progressPoller.pollOnce(
          (e) => _log.w('Initial library scan progress fetch failed: $e'),
        ),
      );
    }
  }

  Future<void> _handleLibraryScanProgress(Map<String, dynamic> progress) async {
    // A newly subscribed native stream may still contain the previous scan's
    // terminal snapshot (including the initial idle snapshot). Only the scan
    // method's result can start finalization; never stop polling on that replay.
    if (_scanCancelRequested ||
        !state.isScanning ||
        state.scanIsFinalizing ||
        progress['is_complete'] == true) {
      return;
    }
    final nextProgress = (progress['progress_pct'] as num?)?.toDouble() ?? 0;
    final normalizedProgress = ((nextProgress * 10).round() / 10).clamp(
      0.0,
      100.0,
    );
    final displayProgress = normalizedProgress >= 100.0
        ? 99.0
        : normalizedProgress;
    final currentFile = progress['current_file'] as String?;
    final totalFiles = (progress['total_files'] as num?)?.toInt() ?? 0;
    final scannedFiles = (progress['scanned_files'] as num?)?.toInt() ?? 0;
    final errorCount = (progress['error_count'] as num?)?.toInt() ?? 0;

    final shouldUpdateState =
        state.scanProgress != displayProgress ||
        state.scanCurrentFile != currentFile ||
        state.scanTotalFiles != totalFiles ||
        state.scannedFiles != scannedFiles ||
        state.scanErrorCount != errorCount;

    if (shouldUpdateState) {
      state = state.copyWith(
        scanProgress: displayProgress,
        scanCurrentFile: currentFile,
        scanTotalFiles: totalFiles,
        scannedFiles: scannedFiles,
        scanErrorCount: errorCount,
      );
    }

    // Files already in flight still finish after a pause; count them, but
    // keep the paused notice instead of reposting progress.
    if (!state.scanIsPaused &&
        _shouldShowScanProgressNotification(
          progress: normalizedProgress,
          totalFiles: totalFiles,
          isComplete: false,
        )) {
      await _showScanProgressNotification(
        progress: normalizedProgress,
        scannedFiles: scannedFiles,
        totalFiles: totalFiles,
        currentFile: currentFile,
      );
    }
  }

  void _stopProgressPolling() {
    _progressPoller.stop();
    _resetScanNotificationTracking();
  }

  void _resetScanNotificationTracking() {
    _lastScanNotificationPercent = -1;
    _lastScanNotificationTotalFiles = -1;
    _lastScanNotificationAt = DateTime.fromMillisecondsSinceEpoch(0);
  }

  bool _shouldShowScanProgressNotification({
    required double progress,
    required int totalFiles,
    required bool isComplete,
  }) {
    final now = DateTime.now();
    final percent = progress.round().clamp(0, 100);
    final percentChanged = percent != _lastScanNotificationPercent;
    final totalFilesChanged = totalFiles != _lastScanNotificationTotalFiles;
    final heartbeatDue =
        now.difference(_lastScanNotificationAt) >= _scanNotificationHeartbeat;

    if (!percentChanged && !totalFilesChanged && !isComplete && !heartbeatDue) {
      return false;
    }

    _lastScanNotificationPercent = percent;
    _lastScanNotificationTotalFiles = totalFiles;
    _lastScanNotificationAt = now;
    return true;
  }

  Future<void> cancelScan() async {
    if (!ref.mounted || (!_scanInProgress && !state.isScanning)) return;

    _log.i('Cancelling library scan');
    _scanCancelRequested = true;
    final requestId = _nativeLibraryRequestId;
    if (requestId != null) {
      try {
        await PlatformBridge.cancelNativeDataJob(requestId);
      } catch (error) {
        _log.w('Failed to cancel library data job: $error');
      }
    }
    _pendingReconnectScans.clear();
    _availabilityRequestVersion++;
    _scanReconnectedOnRefresh = false;
    // Native cancel also releases a paused scan.
    _scanPauseRequested = false;
    if (state.isScanning) {
      await PlatformBridge.cancelLibraryScan();
    }
    if (!ref.mounted) return;
    state = state.copyWith(
      scanIsFinalizing: false,
      scanIsPaused: false,
      scanWasCancelled: true,
    );
    _stopProgressPolling();
    await _showScanCancelledNotification();
  }

  /// Holds the running scan in place. Files already processed stay in the
  /// native scan's memory, so [resumeScan] continues with the next file.
  Future<void> pauseScan() async {
    if (!state.isScanning ||
        state.scanIsFinalizing ||
        state.scanIsPaused ||
        _scanCancelRequested) {
      return;
    }
    _log.i('Pausing library scan at ${state.scannedFiles} files');
    _scanPauseRequested = true;
    state = state.copyWith(scanIsPaused: true);
    try {
      await PlatformBridge.pauseLibraryScan();
    } catch (e) {
      _log.w('Failed to pause library scan: $e');
      _scanPauseRequested = false;
      state = state.copyWith(scanIsPaused: false);
      return;
    }
    // A paused scan does no work; release the foreground service and wake
    // lock (iOS background task) until the user resumes.
    await _notificationService.endBackgroundWork(
      NotificationService.libraryScanWorkKind,
    );
    await _showScanPausedNotification(state.scannedFiles);
  }

  Future<void> resumeScan() async {
    if (!state.isScanning || !state.scanIsPaused || !_scanPauseRequested) {
      return;
    }
    _log.i('Resuming library scan from ${state.scannedFiles} files');
    // Reacquire background work first so resumed reads survive screen-off.
    await _notificationService.beginLibraryScanWork();
    await _cancelScanPausedNotification();
    _scanPauseRequested = false;
    _resetScanNotificationTracking();
    state = state.copyWith(scanIsPaused: false);
    await _releaseNativeScanPause();
  }

  Future<void> _releaseNativeScanPause() async {
    try {
      await PlatformBridge.resumeLibraryScan();
    } catch (e) {
      _log.w('Failed to release library scan pause: $e');
    }
  }

  /// The native scan can finish while paused when the pause lands after its
  /// last file. Ingestion then runs normally, so restore background work.
  Future<void> _endPauseForFinalization() async {
    if (!_scanPauseRequested) return;
    _scanPauseRequested = false;
    state = state.copyWith(scanIsPaused: false);
    await _notificationService.beginLibraryScanWork();
    await _cancelScanPausedNotification();
    await _releaseNativeScanPause();
  }

  Future<void> _showScanPausedNotification(int scannedFiles) =>
      _notifyBestEffort(
        () => _notificationService.showLibraryScanPaused(
          scannedFiles: scannedFiles,
        ),
        'Failed to show scan paused notification',
      );

  Future<void> _cancelScanPausedNotification() => _notifyBestEffort(
    _notificationService.cancelLibraryScanNotification,
    'Failed to clear scan paused notification',
  );

  Future<void> _showScanProgressNotification({
    required double progress,
    required int scannedFiles,
    required int totalFiles,
    required String? currentFile,
  }) => _notifyBestEffort(() async {
    if (!ref.mounted || !state.isScanning || state.scanIsPaused) return;
    await _notificationService.showLibraryScanProgress(
      progress: progress,
      scannedFiles: scannedFiles,
      totalFiles: totalFiles,
      currentFile: _shortenFileForNotification(currentFile),
    );
  }, 'Failed to show scan progress notification');

  Future<void> _showScanCompleteNotification({
    required int totalTracks,
    required int errorCount,
  }) => _notifyBestEffort(
    () => _notificationService.showLibraryScanComplete(
      totalTracks: totalTracks,
      errorCount: errorCount,
    ),
    'Failed to show scan complete notification',
  );

  Future<void> _showScanFailedNotification(String message) => _notifyBestEffort(
    () => _notificationService.showLibraryScanFailed(message),
    'Failed to show scan failure notification',
  );

  Future<void> _showScanCancelledNotification() => _notifyBestEffort(
    _notificationService.showLibraryScanCancelled,
    'Failed to show scan cancelled notification',
  );

  /// Queues a scan notice whose failure must never stop the scan or cleanup.
  Future<void> _notifyBestEffort(
    Future<void> Function() notify,
    String failure,
  ) async {
    try {
      await _queueScanNotification(notify);
    } catch (e) {
      _log.w('$failure: $e');
    }
  }

  Future<void> _queueScanNotification(Future<void> Function() notify) {
    final next = _scanNotificationTail.then((_) => notify());
    // A failed notification must not prevent the terminal notice or cleanup.
    _scanNotificationTail = next.catchError((Object _) {});
    return next;
  }

  String? _shortenFileForNotification(String? path) {
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

  Future<int> cleanupMissingFiles() async {
    await refreshSourceAvailability();
    var removed = 0;
    for (final source in state.sources) {
      if (!source.enabled || !source.available) continue;
      try {
        removed += await _db.cleanupMissingFiles(
          sourceId: source.id,
          canDelete: () async {
            if (isContentUri(source.path)) {
              return await PlatformBridge.probeSafTreeReadAccess(source.path) ==
                  true;
            }
            // Recheck access after the file probes, before deleting a page.
            // An empty but readable source is valid; an offline one throws.
            await Directory(
              source.path,
            ).list(followLinks: false).take(1).drain<void>();
            return true;
          },
        );
      } finally {}
    }
    if (removed > 0) await _refreshSummaryFromStorage();
    return removed;
  }

  Future<void> clearLibrary() {
    return _clearFuture ??= _clearLibrary().whenComplete(() {
      _clearFuture = null;
    });
  }

  Future<void> _clearLibrary() async {
    if (!ref.mounted) return;
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

      if (!ref.mounted) return;
      await _refreshSummaryFromStorage();
      if (!ref.mounted) return;
      state = state.copyWith(clearLastScannedAt: true, scanFailures: const {});
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

      if (!ref.mounted || _scanCancelRequested) return;
      final libraryDatabase = await _db.database;
      if (!ref.mounted || _scanCancelRequested) return;

      final deletedCount = await pruneUnreferencedLibraryCovers(
        libraryCoverDir,
        const {},
        libraryDatabase: libraryDatabase,
        requestId: _nativeLibraryRequestId,
        canPrune: () => ref.mounted && !_scanCancelRequested,
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

  @override
  Future<void> removePhysicalFiles(Iterable<String> filePaths) async {
    await removeItems(await _db.getPhysicalFileIds(filePaths));
  }

  @override
  Future<void> removeItems(Iterable<String> ids) async {
    final selected = ids.toSet();
    if (selected.isEmpty) return;
    final collections = ref.read(libraryCollectionsProvider.notifier);
    // Purge persisted membership first. If that fails, retaining the library
    // rows allows the deletion cleanup to be retried without losing identity.
    await collections.removeLocalLibraryTracks(selected);
    await _db.deleteByIds(selected);
    if (!ref.mounted) return;
    await _refreshSummaryFromStorage();
  }

  Future<LocalLibraryItem?> getById(String id) async {
    final json = await _db.getById(id);
    return json == null ? null : LocalLibraryItem.fromJson(json);
  }
}

final localLibraryProvider =
    NotifierProvider<LocalLibraryNotifier, LocalLibraryState>(
      LocalLibraryNotifier.new,
    );

class LocalLibraryCoverRequest {
  final String? isrc;
  final String trackName;
  final String artistName;

  const LocalLibraryCoverRequest({
    this.isrc,
    required this.trackName,
    required this.artistName,
  });

  @override
  bool operator ==(Object other) {
    return other is LocalLibraryCoverRequest &&
        other.isrc == isrc &&
        other.trackName == trackName &&
        other.artistName == artistName;
  }

  @override
  int get hashCode => Object.hash(isrc, trackName, artistName);
}

class LocalLibraryCoverBatchRequest {
  final List<LocalLibraryCoverRequest> tracks;

  const LocalLibraryCoverBatchRequest(this.tracks);

  @override
  bool operator ==(Object other) {
    if (other is! LocalLibraryCoverBatchRequest) return false;
    if (other.tracks.length != tracks.length) return false;
    for (var i = 0; i < tracks.length; i++) {
      if (other.tracks[i] != tracks[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(tracks);
}

String? _nonEmptyCoverPath(Map<String, dynamic>? json) {
  final coverPath = json?['coverPath'] as String?;
  final trimmed = coverPath?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

final localLibraryCoverProvider = FutureProvider.autoDispose
    .family<String?, LocalLibraryCoverRequest>((ref, request) {
      ref.watch(
        localLibraryProvider.select((state) => state.loadedIndexVersion),
      );
      return LibraryDatabase.instance
          .findExisting(
            isrc: request.isrc,
            trackName: request.trackName,
            artistName: request.artistName,
          )
          .then(_nonEmptyCoverPath);
    });

/// Batch lookup hook so tests can observe the chunked first-cover search.
final libraryExistingBatchLoaderProvider =
    Provider<
      Future<List<Map<String, dynamic>?>> Function(
        List<LocalLibraryBatchLookupRequest>,
      )
    >(
      (ref) =>
          (requests) => LibraryDatabase.instance.findExistingBatch(requests),
    );

final localLibraryFirstCoverProvider = FutureProvider.autoDispose
    .family<String?, LocalLibraryCoverBatchRequest>((ref, request) async {
      ref.watch(
        localLibraryProvider.select((state) => state.loadedIndexVersion),
      );
      // OPT-PERF-006: resolve the batch in ordered chunks and stop at the
      // first usable cover, so a large playlist with an early cover does not
      // wait for every member lookup. Chunking preserves the exact matching
      // precedence of a single full-batch lookup.
      final load = ref.watch(libraryExistingBatchLoaderProvider);
      const chunkSize = 450;
      final lookups = [
        for (final track in request.tracks)
          LocalLibraryBatchLookupRequest(
            isrc: track.isrc,
            trackName: track.trackName,
            artistName: track.artistName,
          ),
      ];
      for (var start = 0; start < lookups.length; start += chunkSize) {
        final end = (start + chunkSize).clamp(0, lookups.length);
        final rows = await load(lookups.sublist(start, end));
        for (final row in rows) {
          final cover = _nonEmptyCoverPath(row);
          if (cover != null) return cover;
        }
      }
      return null;
    });
