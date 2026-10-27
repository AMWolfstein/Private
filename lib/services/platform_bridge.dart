import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sistrum/utils/logger.dart';

final _log = AppLogger('PlatformBridge');

/// Outcome of replacing a SAF document, including a retained recovery copy
/// when the provider could not be restored after a failed write.
class SafWriteBackResult {
  final bool success;
  final String? error;
  final String? recoveryPath;

  const SafWriteBackResult({
    required this.success,
    this.error,
    this.recoveryPath,
  });
}

Object? _decodeJsonInBackground(String json) => jsonDecode(json);
String _encodeJsonInBackground(Object? value) => jsonEncode(value);

class _NativeDataJobState {
  bool dispatched = false;
  bool cancelled = false;
}

Object? _decodeJsonFileInBackground(String path) {
  final contents = File(path).readAsStringSync();
  return contents.isEmpty ? null : jsonDecode(contents);
}

class LibraryScanNDJSONFile {
  final File file;
  final int expectedCount;
  final int errorCount;

  const LibraryScanNDJSONFile({
    required this.file,
    required this.expectedCount,
    this.errorCount = 0,
  });

  Stream<Map<String, dynamic>> rows() async* {
    await for (final line
        in file
            .openRead()
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      if (line.trim().isEmpty) continue;
      final decoded = jsonDecode(line);
      if (decoded is! Map) {
        throw const FormatException('Library scan NDJSON row is not an object');
      }
      yield Map<String, dynamic>.from(decoded);
    }
  }

  Future<void> delete() async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
    // Remove the resumable scan checkpoint after ingestion.
    try {
      final checkpoint = File('${file.path}.state');
      if (await checkpoint.exists()) await checkpoint.delete();
    } catch (_) {}
  }
}

class ContentUriPlaybackLease {
  final String path;
  final String token;

  final String? displayName;

  const ContentUriPlaybackLease({
    required this.path,
    required this.token,
    this.displayName,
  });
}

class InstallationState {
  final bool markerExisted;
  final bool markerCreated;
  final bool freshPackageInstall;

  const InstallationState({
    required this.markerExisted,
    required this.markerCreated,
    required this.freshPackageInstall,
  });

  const InstallationState.unsupported()
    : markerExisted = true,
      markerCreated = true,
      freshPackageInstall = false;

  factory InstallationState.fromMap(Map<String, dynamic> map) {
    return InstallationState(
      markerExisted: map['marker_existed'] == true,
      markerCreated: map['marker_created'] == true,
      freshPackageInstall: map['fresh_package_install'] == true,
    );
  }
}

bool shouldResetRestoredInstallation({
  required bool hasPersistedSettings,
  required InstallationState installState,
}) {
  return hasPersistedSettings &&
      !installState.markerExisted &&
      installState.markerCreated &&
      installState.freshPackageInstall;
}

class PlatformBridge {
  static const _channel = MethodChannel('com.amwolfstein.sistrum/backend');

  static int _nativeDataJobSerial = 0;
  static final _nativeDataJobs = <String, Set<_NativeDataJobState>>{};

  /// A single background native operation. Binary inputs never become base64
  /// JSON, and large request/result codecs stay off the UI isolate.
  static Future<Map<String, dynamic>> runNativeDataJob(
    Map<String, dynamic> request, {
    Uint8List? bytes,
    String? requestId,
  }) async {
    final id =
        requestId ??
        'data_${DateTime.now().microsecondsSinceEpoch}_${_nativeDataJobSerial++}';
    final state = _NativeDataJobState();
    final states = _nativeDataJobs.putIfAbsent(id, () => {});
    states.add(state);
    try {
      final encoded = await compute(_encodeJsonInBackground, request);
      if (state.cancelled) {
        throw PlatformException(
          code: 'CANCELLED',
          message: 'Native data job cancelled',
        );
      }
      state.dispatched = true;
      Object? result;
      try {
        result = await _channel.invokeMethod('runNativeDataJob', {
          'request_json': encoded,
          'request_id': id,
          'bytes': ?bytes,
        });
      } finally {
        state.dispatched = false;
      }
      return await _decodeRequiredMapResultAsync(result, 'runNativeDataJob');
    } finally {
      states.remove(state);
      if (states.isEmpty) _nativeDataJobs.remove(id);
    }
  }

  static Future<void> cancelNativeDataJob(String requestId) async {
    final states = _nativeDataJobs[requestId];
    if (states == null) return;
    for (final state in states) {
      state.cancelled = true;
    }
    if (states.any((state) => state.dispatched)) {
      await _channel.invokeMethod<void>('cancelNativeDataJob', {
        'request_id': requestId,
      });
    }
  }

  static Future<void> setScreenAwake(bool enabled) async {
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    await _channel.invokeMethod<void>('setScreenAwake', {'enabled': enabled});
  }

  static const _jsonResultFileKey = '__json_file';
  static const _backgroundJsonDecodeThresholdBytes = 128 * 1024;
  static const _libraryScanProgressEvents = EventChannel(
    'com.amwolfstein.sistrum/library_scan_progress_stream',
  );
  static final StreamController<void> _libraryStorageEvents =
      StreamController<void>.broadcast();

  static bool _backendEventHandlerInstalled = false;

  static bool get supportsCoreBackend => Platform.isAndroid;

  static Stream<void> libraryStorageEvents() {
    _ensureBackendEventHandler();
    return _libraryStorageEvents.stream;
  }

  static void _ensureBackendEventHandler() {
    if (_backendEventHandlerInstalled) return;
    _backendEventHandlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'libraryScanError':
          final args = call.arguments;
          if (args is Map) {
            final path = args['path']?.toString() ?? '';
            final operation = args['operation']?.toString() ?? 'scan';
            final message = args['message']?.toString() ?? 'Unknown error';
            AppLogger('LocalLibrary').e('$operation [$path]: $message');
          }
          return null;
        case 'libraryStorageChanged':
          _libraryStorageEvents.add(null);
          return null;
        default:
          return null;
      }
    });
  }

  static Future<Map<String, dynamic>> _invokeMap(
    String method, [
    dynamic args,
  ]) async {
    final result = await _channel.invokeMethod(method, args);
    return _decodeRequiredMapResultAsync(result, method);
  }

  static Future<InstallationState> ensureInstallMarker() async {
    if (!Platform.isAndroid) return const InstallationState.unsupported();
    final result = await _invokeMap('ensureInstallMarker');
    return InstallationState.fromMap(result);
  }

  static Future<void> exitApp() async {
    await _channel.invokeMethod('exitApp');
  }

  /// Holds local backend access until the media operation finishes.
  static Future<String> acquireMediaDirectory(String path) async {
    if (!supportsCoreBackend) return '';
    return await _channel.invokeMethod<String>('acquireMediaDirectory', {
          'path': path,
        }) ??
        '';
  }

  static Future<void> releaseMediaDirectory(String token) async {
    if (!supportsCoreBackend || token.isEmpty) return;
    await _channel.invokeMethod('releaseMediaDirectory', {'token': token});
  }

  static Future<Map<String, String>> getBackendImplementations({
    String? filePath,
  }) async {
    final result = await _channel.invokeMapMethod<String, String>(
      'getBackendImplementations',
      filePath == null ? null : {'file_path': filePath},
    );
    return result ?? const {};
  }

  static Future<Map<String, dynamic>?> pickSafTree({
    bool forSetup = false,
    void Function(String message)? onFailure,
  }) async {
    final result = await _channel.invokeMethod(
      'pickSafTree',
      forSetup ? {'for_setup': true} : null,
    );
    final decoded = _decodeNullableMapResult(result, 'pickSafTree');
    if (decoded != null && decoded['success'] == false) {
      // The native side could not persist the grant; treat it like a cancel so
      // no caller stores a folder that loses access after the next restart.
      final message = decoded['error']?.toString() ?? '';
      _log.w('SAF tree pick failed');
      if (message.isNotEmpty) onFailure?.call(message);
      return null;
    }
    return decoded;
  }

  /// Releases a persisted SAF tree grant after its library source is removed.
  /// Best effort: a missing or already-released grant is not an error.
  static Future<void> releaseSafTree(String treeUri) async {
    if (treeUri.isEmpty) return;
    await _channel.invokeMethod('safReleaseTree', {'tree_uri': treeUri});
  }

  static Future<bool> safExists(String uri) async {
    final result = await _channel.invokeMethod('safExists', {'uri': uri});
    return result as bool;
  }

  /// Exact-path checks. Only explicit `missing` results authorize cleanup;
  /// absent responses and permission/provider failures remain unknown.
  static Future<Map<String, bool?>> safExistsBatch(List<String> uris) async {
    if (uris.isEmpty) return const {};
    final result = await _invokeMap('safExistsBatch', {
      'uris_json': jsonEncode(uris),
    });
    return {
      for (final uri in uris)
        uri: switch (result[uri]) {
          'found' => true,
          'missing' => false,
          _ => null,
        },
    };
  }

  /// Read access for a Library source, independent of download write access.
  /// Null means the provider could not confirm access (loading/query failure).
  static Future<bool?> probeSafTreeReadAccess(String treeUri) async {
    try {
      Future<bool?> probe() => _channel.invokeMethod<bool>(
        'probeSafTreeReadAccess',
        {'tree_uri': treeUri},
      );
      final readable = await probe();
      if (readable != false) return readable;
      // A busy provider can briefly return an empty root after a write.
      // Confirm a negative before hiding all tracks from this source.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return await probe();
    } catch (e) {
      _log.w('Failed to probe SAF library read access: $e');
      return null;
    }
  }

  /// Whether the persisted SAF grant for [treeUri] is still usable: the
  /// permission is present in the system's persisted list and the tree
  /// document still exists and is writable. Returns true on channel errors
  /// so a bridge problem never raises a false "access lost" alarm.
  static Future<bool> isSafTreeAccessible(String treeUri) async {
    try {
      return await validateSafTreeAccess(treeUri);
    } catch (e) {
      _log.w('Failed to check SAF tree accessibility: $e');
      return true;
    }
  }

  /// Strict SAF validation for startup and download preflight. Unlike
  /// [isSafTreeAccessible], channel failures are surfaced to the caller so a
  /// write cannot proceed on an unverified destination.
  static Future<bool> validateSafTreeAccess(String treeUri) async {
    final result = await _channel.invokeMethod('isSafTreeAccessible', {
      'tree_uri': treeUri,
    });
    return result as bool? ?? false;
  }

  static Future<bool> safDelete(String uri) async {
    final result = await _channel.invokeMethod('safDelete', {'uri': uri});
    return result as bool;
  }

  static Future<Map<String, dynamic>> safStat(String uri) {
    return _invokeMap('safStat', {'uri': uri});
  }

  static Future<String?> copyContentUriToTemp(String uri) async {
    final result = await _channel.invokeMethod('safCopyToTemp', {'uri': uri});
    return result as String?;
  }

  static Future<ContentUriPlaybackLease?> openContentUriPlaybackLease(
    String uri,
  ) async {
    if (!Platform.isAndroid || !uri.startsWith('content://')) return null;
    final result = await _channel.invokeMethod('safOpenPlaybackLease', {
      'uri': uri,
    });
    if (result is! Map) return null;
    final map = Map<String, dynamic>.from(result);
    final path = map['path']?.toString() ?? '';
    final token = map['token']?.toString() ?? '';
    if (path.isEmpty || token.isEmpty) return null;
    return ContentUriPlaybackLease(
      path: path,
      token: token,
      displayName: result['display_name'] as String?,
    );
  }

  static Future<void> closeContentUriPlaybackLease(String token) async {
    if (!Platform.isAndroid || token.isEmpty) return;
    try {
      await _channel.invokeMethod('safClosePlaybackLease', {'token': token});
    } catch (e) {
      _log.w('Failed to close SAF playback lease: $e');
    }
  }

  static Future<String?> createSafFileFromPath({
    required String treeUri,
    required String relativeDir,
    required String fileName,
    required String mimeType,
    required String srcPath,
  }) async {
    final result = await _channel.invokeMethod('safCreateFromPath', {
      'tree_uri': treeUri,
      'relative_dir': relativeDir,
      'file_name': fileName,
      'mime_type': mimeType,
      'src_path': srcPath,
    });
    return result as String?;
  }

  static Future<void> openContentUri(String uri, {String mimeType = ''}) async {
    await _channel.invokeMethod('openContentUri', {
      'uri': uri,
      'mime_type': mimeType,
    });
  }

  static Future<bool> shareContentUri(String uri, {String title = ''}) async {
    final result = await _channel.invokeMethod('shareContentUri', {
      'uri': uri,
      'title': title,
    });
    return result as bool? ?? false;
  }

  static Future<Map<String, dynamic>> extractCoverToFile(
    String audioPath,
    String outputPath,
  ) {
    return _withMediaFileAccess([audioPath, outputPath], () {
      return _invokeMap('extractCoverToFile', {
        'audio_path': audioPath,
        'output_path': outputPath,
      });
    });
  }

  static Future<Map<String, dynamic>> readFileMetadata(
    String filePath, {
    String? displayName,
  }) {
    return _invokeMap('readFileMetadata', {
      'file_path': filePath,
      'display_name': ?displayName,
    });
  }

  static Future<Map<String, dynamic>> editFileMetadata(
    String filePath,
    Map<String, String> metadata,
  ) {
    return _withMediaFileAccess([filePath, metadata['cover_path'] ?? ''], () {
      return _invokeMap('editFileMetadata', {
        'file_path': filePath,
        'metadata_json': jsonEncode(metadata),
      });
    });
  }

  static Future<T> _withMediaFileAccess<T>(
    Iterable<String> paths,
    Future<T> Function() operation,
  ) async {
    // A user-selected library file or cover can live outside the selected library
    // folder. Hold only this operation's backend grants; SAF is staged natively.
    final scopes = <String>[];
    try {
      final directories = <String>{
        for (final path in paths)
          if (path.startsWith('/')) File(path).parent.path,
      };
      for (final directory in directories) {
        scopes.add(await acquireMediaDirectory(directory));
      }
      return await operation();
    } finally {
      for (final scope in scopes.reversed) {
        try {
          await releaseMediaDirectory(scope);
        } catch (e) {
          _log.w('Failed to release media file access: $e');
        }
      }
    }
  }

  /// Writes ISRC and label into an M4A/MP4 file as iTunes freeform atoms.
  /// FFmpeg's MP4 muxer drops these keys, so they must be written natively
  /// after the FFmpeg metadata pass. [filePath] must be a local file path.
  /// Only the keys present in [fields] are touched; an empty value clears it.
  static Future<Map<String, dynamic>> writeM4AFreeformTags(
    String filePath,
    Map<String, String> fields,
  ) {
    return _withMediaFileAccess([filePath], () {
      return _invokeMap('writeM4AFreeformTags', {
        'file_path': filePath,
        'metadata_json': jsonEncode(fields),
      });
    });
  }

  static Future<bool> writeTempToSaf(String tempPath, String safUri) async {
    return (await writeTempToSafDetailed(tempPath, safUri)).success;
  }

  /// Writes a completed temporary file back to its SAF document and reports
  /// any retained recovery copy. The caller keeps ownership of [tempPath].
  static Future<SafWriteBackResult> writeTempToSafDetailed(
    String tempPath,
    String safUri,
  ) async {
    final map = await _invokeMap('writeTempToSaf', {
      'temp_path': tempPath,
      'saf_uri': safUri,
    });
    return SafWriteBackResult(
      success: map['success'] == true,
      error: map['error']?.toString(),
      recoveryPath: map['recovery_path']?.toString(),
    );
  }

  /// Keeps user-started work of [kind] alive with the screen off: an Android
  /// foreground service, or an iOS background-task grace period. Returns
  /// whether the platform accepted it.
  static Future<bool> startBackgroundWork(
    String kind, {
    required String title,
    String text = '',
  }) async {
    final started = await _channel.invokeMethod<bool>('startBackgroundWork', {
      'kind': kind,
      'title': title,
      'text': text,
    });
    return started ?? false;
  }

  /// Updates the Android work notification; [progress] is a percentage, or
  /// negative while indeterminate.
  static Future<void> updateBackgroundWork(
    String kind, {
    required String title,
    String text = '',
    int progress = -1,
  }) async {
    await _channel.invokeMethod('updateBackgroundWork', {
      'kind': kind,
      'title': title,
      'text': text,
      'progress': progress,
    });
  }

  static Future<void> stopBackgroundWork(String kind) async {
    await _channel.invokeMethod('stopBackgroundWork', {'kind': kind});
  }

  static Future<void> releaseNativeMemory({bool underPressure = false}) async {
    try {
      await _channel.invokeMethod(
        underPressure ? 'releaseMemoryUnderPressure' : 'releaseMemory',
      );
    } catch (_) {}
  }

  static Future<void> setLibraryCoverCacheDir(String cacheDir) async {
    await _channel.invokeMethod('setLibraryCoverCacheDir', {
      'cache_dir': cacheDir,
    });
  }

  static Future<LibraryScanNDJSONFile> scanLibraryFolderToNDJSONFile(
    String folderPath, {
    bool forceFullScan = false,
    bool Function()? isCancelled,
  }) {
    return _scanToNDJSONFile(
      method: 'scanLibraryFolderToNDJSONFile',
      arguments: {'folder_path': folderPath},
      forceFullScan: forceFullScan,
      isCancelled: isCancelled,
    );
  }

  static Future<Map<String, dynamic>> scanLibraryFolderIncremental(
    String folderPath,
    Map<String, int> existingFiles,
  ) async {
    final result = await _channel.invokeMethod('scanLibraryFolderIncremental', {
      'folder_path': folderPath,
      'existing_files': jsonEncode(existingFiles),
    });
    return _decodeRequiredMapResultAsync(
      result,
      'scanLibraryFolderIncremental',
    );
  }

  static Future<Map<String, dynamic>> scanLibraryFolderIncrementalFromSnapshot(
    String folderPath,
    String snapshotPath,
  ) async {
    final result = await _channel.invokeMethod(
      'scanLibraryFolderIncrementalFromSnapshot',
      {'folder_path': folderPath, 'snapshot_path': snapshotPath},
    );
    return _decodeRequiredMapResultAsync(
      result,
      'scanLibraryFolderIncrementalFromSnapshot',
    );
  }

  static Future<LibraryScanNDJSONFile> scanSafTreeToNDJSONFile(
    String treeUri, {
    bool forceFullScan = false,
    bool hasIndexedRows = false,
    bool Function()? isCancelled,
  }) {
    return _scanToNDJSONFile(
      method: 'scanSafTreeToNDJSONFile',
      arguments: {'tree_uri': treeUri},
      forceFullScan: forceFullScan,
      hasIndexedRows: hasIndexedRows,
      isCancelled: isCancelled,
    );
  }

  static Future<LibraryScanNDJSONFile> _scanToNDJSONFile({
    required String method,
    required Map<String, dynamic> arguments,
    required bool forceFullScan,
    bool hasIndexedRows = false,
    bool Function()? isCancelled,
  }) async {
    // Stable support-directory path lets native SAF scans resume after process death.
    _ensureBackendEventHandler();
    final scanDir = await getApplicationSupportDirectory();
    await scanDir.create(recursive: true);
    final identity = jsonEncode(<String, dynamic>{
      'method': method,
      'arguments': arguments,
    });
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(identity)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    final output = File(
      '${scanDir.path}${Platform.pathSeparator}'
      'library_scan_${hash.toRadixString(16).padLeft(8, '0')}.ndjson',
    );
    try {
      if (isCancelled?.call() == true) {
        throw StateError('Library scan cancelled before native scan');
      }
      if (forceFullScan) {
        // An explicit rescan must not resume metadata from an earlier attempt.
        for (final file in [output, File('${output.path}.state')]) {
          if (await file.exists()) await file.delete();
        }
        // Preserve covers referenced by the current DB until ingestion succeeds.
        // Fresh paths bypass native disk and Flutter image caches together.
        final covers = Directory('${scanDir.path}/library_covers');
        await covers.create(recursive: true);
        final freshCovers = await covers.createTemp('full_scan_');
        await setLibraryCoverCacheDir(freshCovers.path);
      }
      if (isCancelled?.call() == true) {
        throw StateError('Library scan cancelled before native scan');
      }
      final result = await _channel.invokeMethod(method, {
        ...arguments,
        // Not part of the resume identity: the output path must not change
        // when a source's row count crosses zero.
        'has_indexed_rows': hasIndexedRows,
        'output_path': output.path,
      });
      if (result is! Map) {
        throw FormatException('$method returned ${result.runtimeType}');
      }
      if (result['cancelled'] == true) {
        throw FormatException('$method returned a cancelled partial scan');
      }
      final errors = result['error_count'];
      if (errors is! num ||
          !errors.isFinite ||
          errors < 0 ||
          errors != errors.toInt()) {
        throw FormatException('$method returned an invalid error count');
      }
      final pathValue = result['path'];
      final countValue = result['count'];
      if (pathValue is! String || pathValue.trim().isEmpty) {
        throw FormatException('$method returned an invalid output path');
      }
      if (countValue is! num ||
          !countValue.isFinite ||
          countValue < 0 ||
          countValue != countValue.toInt()) {
        throw FormatException('$method returned an invalid row count');
      }
      final path = pathValue;
      final count = countValue.toInt();
      final file = File(path);
      if (!await file.exists()) {
        throw FormatException('$method did not create its output file');
      }
      return LibraryScanNDJSONFile(
        file: file,
        expectedCount: count,
        errorCount: errors.toInt(),
      );
    } catch (_) {
      // Keep partial output; native SAF scan resumes from its sidecar.
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> scanSafTreeIncremental(
    String treeUri,
    Map<String, int> existingFiles,
  ) async {
    _ensureBackendEventHandler();
    final result = await _channel.invokeMethod('scanSafTreeIncremental', {
      'tree_uri': treeUri,
      'existing_files': jsonEncode(existingFiles),
    });
    return _decodeRequiredMapResultAsync(result, 'scanSafTreeIncremental');
  }

  static Future<Map<String, dynamic>> scanSafTreeIncrementalFromSnapshot(
    String treeUri,
    String snapshotPath,
  ) async {
    _ensureBackendEventHandler();
    final result = await _channel.invokeMethod(
      'scanSafTreeIncrementalFromSnapshot',
      {'tree_uri': treeUri, 'snapshot_path': snapshotPath},
    );
    return _decodeRequiredMapResultAsync(
      result,
      'scanSafTreeIncrementalFromSnapshot',
    );
  }

  static Future<Map<String, int>> getSafFileModTimes(List<String> uris) async {
    final map = await _invokeMap('getSafFileModTimes', {
      'uris': jsonEncode(uris),
    });
    return map.map((key, value) => MapEntry(key, (value as num).toInt()));
  }

  static Future<Map<String, dynamic>> getLibraryScanProgress() async {
    final result = await _channel.invokeMethod('getLibraryScanProgress');
    return _decodeMapResult(result);
  }

  static Future<Map<String, dynamic>?> getLibraryScanExitInfo({
    required int startedAfter,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    final result = await _channel.invokeMethod('getLibraryScanExitInfo', {
      'started_after': startedAfter,
    });
    return _decodeNullableMapResult(result, 'getLibraryScanExitInfo');
  }

  static Stream<Map<String, dynamic>> libraryScanProgressStream() {
    return _libraryScanProgressEvents.receiveBroadcastStream().map(
      _decodeMapResult,
    );
  }

  static Future<void> cancelLibraryScan() async {
    await _channel.invokeMethod('cancelLibraryScan');
  }

  /// Holds the running native scan at its next file; it keeps its position.
  static Future<void> pauseLibraryScan() async {
    await _channel.invokeMethod('pauseLibraryScan');
  }

  static Future<void> resumeLibraryScan() async {
    await _channel.invokeMethod('resumeLibraryScan');
  }

  static Object? _decodeJsonResult(dynamic result) {
    if (result is String) {
      if (result.isEmpty) return null;
      return jsonDecode(result);
    }
    return result;
  }

  static Future<Object?> _decodeJsonResultAsync(dynamic result) async {
    if (result is Map && result[_jsonResultFileKey] is String) {
      final file = File(result[_jsonResultFileKey] as String);
      try {
        // Read and decode where the result is built, so the UI isolate never
        // retains a second copy of the entire spill file's text.
        return await compute(_decodeJsonFileInBackground, file.path);
      } finally {
        try {
          await file.delete();
        } catch (_) {}
      }
    }
    if (result is String &&
        result.length >= _backgroundJsonDecodeThresholdBytes) {
      return _decodeJsonStringAsync(result);
    }
    return _decodeJsonResult(result);
  }

  static Future<Object?> _decodeJsonStringAsync(String json) {
    if (json.length < _backgroundJsonDecodeThresholdBytes) {
      return Future<Object?>.value(jsonDecode(json));
    }
    return compute(_decodeJsonInBackground, json);
  }

  static Map<String, dynamic>? _decodeNullableMapResult(
    dynamic result,
    String method,
  ) {
    final decoded = _decodeJsonResult(result);
    if (decoded == null) return null;
    if (decoded is Map) {
      return decoded.cast<String, dynamic>();
    }
    throw FormatException(
      'Expected nullable map result from $method, got ${decoded.runtimeType}',
    );
  }

  static Future<Map<String, dynamic>> _decodeRequiredMapResultAsync(
    dynamic result,
    String method,
  ) async {
    final decoded = await _decodeJsonResultAsync(result);
    if (decoded is Map) {
      return decoded.cast<String, dynamic>();
    }
    throw FormatException(
      'Expected map result from $method, got ${decoded.runtimeType}',
    );
  }

  static Map<String, dynamic> _decodeMapResult(dynamic result) {
    if (result is Map) {
      return result.cast<String, dynamic>();
    }
    if (result is String) {
      if (result.isEmpty) return const <String, dynamic>{};
      final decoded = jsonDecode(result);
      if (decoded is Map) {
        return decoded.cast<String, dynamic>();
      }
    }
    return const <String, dynamic>{};
  }

  static Future<Map<String, dynamic>?> readAudioMetadata(
    String filePath,
  ) async {
    try {
      final result = await _channel.invokeMethod('readAudioMetadata', {
        'file_path': filePath,
      });
      return _decodeNullableMapResult(result, 'readAudioMetadata');
    } catch (e) {
      _log.w('Failed to read audio metadata: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>> parseCueSheet(
    String cuePath, {
    String audioDir = '',
  }) {
    _log.i('parseCueSheet: $cuePath (audioDir: $audioDir)');
    return _invokeMap('parseCueSheet', {
      'cue_path': cuePath,
      'audio_dir': audioDir,
    });
  }
}
