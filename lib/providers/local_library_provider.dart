import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/core/models/library_scan_failure.dart';
import 'package:sistrum/core/models/local_library_item.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/providers/library_collections_provider.dart';
import 'package:sistrum/providers/library_database_provider.dart';
import 'package:sistrum/services/library/scan/library_cleanup.dart';
import 'package:sistrum/services/library/database/library_database.dart';
import 'package:sistrum/services/library/database/library_mutation_ports.dart';
import 'package:sistrum/services/library/scan/library_scan_progress.dart';
import 'package:sistrum/services/library/scan/library_scan_notifications.dart';
import 'package:sistrum/services/native/library_scan_bridge.dart';
import 'package:sistrum/services/native/media_file_bridge.dart';
import 'package:sistrum/services/platform/notification_service.dart';
import 'package:sistrum/services/native/native_data_jobs.dart';
import 'package:sistrum/utils/files/best_effort_delete.dart';
import 'package:sistrum/utils/logging/logger.dart';
import 'package:sistrum/utils/files/file_access.dart';
import 'package:sistrum/utils/scan/local_library_scan_prefs.dart';

part 'local_library_provider_sources.dart';

part 'local_library_provider_loading.dart';
part 'local_library_provider_scanning.dart';
part 'local_library_provider_scan_results.dart';
part 'local_library_state_1.dart';

final _log = AppLogger('LocalLibrary');

/// Resolves preferences per operation: SharedPreferences caches a successful
/// instance itself, so a failed first attempt is not retained for the process.
Future<SharedPreferences> _preferences() => SharedPreferences.getInstance();

typedef LocalLibraryAvailabilityProbe = Future<bool?> Function(String path);

class LocalLibraryNotifier extends Notifier<LocalLibraryState>
    implements LibrarySourceSink, LibraryRemovalSink {
  LocalLibraryNotifier({
    LibraryDatabase? database,
    LocalLibraryAvailabilityProbe? availabilityProbe,
  }) : _injectedDb = database,
       _availabilityProbe = availabilityProbe;

  final LibraryDatabase? _injectedDb;
  LibraryDatabase get _db => _injectedDb ?? ref.read(libraryDatabaseProvider);
  final LocalLibraryAvailabilityProbe? _availabilityProbe;
  final NotificationService _notificationService = NotificationService();
  late final LibraryScanNotifications _scanNotifications =
      LibraryScanNotifications(
        service: _notificationService,
        progressVisible: () =>
            ref.mounted && state.isScanning && !state.scanIsPaused,
      );
  late final LibraryScanProgressPolling _progressPolling =
      LibraryScanProgressPolling(
        onProgress: _handleLibraryScanProgress,
        onWarning: _log.w,
      );
  bool _isLoaded = false;
  bool _hasLoadedFromDatabase = false;
  Future<void>? _loadFuture;
  Future<void>? _scanRecovery;
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

  LocalLibraryState get _current => state;

  set _current(LocalLibraryState value) => state = value;

  Ref get _ref => ref;

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
            NativeDataJobs.cancel(requestId).catchError((Object error) {
              _log.w('Failed to cancel disposed library ingestion: $error');
            }),
          );
        }
        unawaited(
          LibraryScanBridge.cancelLibraryScan().catchError((Object error) {
            _log.w('Failed to cancel disposed library scan: $error');
          }),
        );
      }
      _progressPolling.stop();
      _storageEventsSubscription?.cancel();
      _storageEventDebounce?.cancel();
      _availabilityRetry?.cancel();
    });

    if (Platform.isAndroid) {
      _storageEventsSubscription = LibraryScanBridge.libraryStorageEvents()
          .listen(
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
    _nativeLibraryRequestId =
        'library-scan-${DateTime.now().microsecondsSinceEpoch}';
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

  Future<void> cancelScan() async {
    if (!ref.mounted || (!_scanInProgress && !state.isScanning)) return;

    _log.i('Cancelling library scan');
    _scanCancelRequested = true;
    final requestId = _nativeLibraryRequestId;
    if (requestId != null) {
      try {
        await NativeDataJobs.cancel(requestId);
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
      await LibraryScanBridge.cancelLibraryScan();
    }
    if (!ref.mounted) return;
    state = state.copyWith(
      scanIsFinalizing: false,
      scanIsPaused: false,
      scanWasCancelled: true,
    );
    _stopProgressPolling();
    await _scanNotifications.showCancelled();
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
      await LibraryScanBridge.pauseLibraryScan();
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
    await _scanNotifications.showPaused(state.scannedFiles);
  }

  Future<void> resumeScan() async {
    if (!state.isScanning || !state.scanIsPaused || !_scanPauseRequested) {
      return;
    }
    _log.i('Resuming library scan from ${state.scannedFiles} files');
    // Reacquire background work first so resumed reads survive screen-off.
    await _notificationService.beginLibraryScanWork();
    await _scanNotifications.cancelPaused();
    _scanPauseRequested = false;
    _scanNotifications.reset();
    state = state.copyWith(scanIsPaused: false);
    await _releaseNativeScanPause();
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
              return await MediaFileBridge.probeSafTreeReadAccess(
                    source.path,
                  ) ==
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
