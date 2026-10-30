import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sistrum/services/native/native_channel.dart';
import 'package:sistrum/utils/files/best_effort_delete.dart';

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
    await deleteBestEffort(file);
    // Remove the resumable scan checkpoint after ingestion.
    await deleteBestEffort(File('${file.path}.state'));
  }
}

/// Library folder and SAF tree scans, with their progress and exit events.
class LibraryScanBridge {
  static const _libraryScanProgressEvents = EventChannel(
    'com.amwolfstein.sistrum/library_scan_progress_stream',
  );

  /// Library storage change notices (see [NativeBackendEvents]).
  static Stream<void> libraryStorageEvents() =>
      NativeBackendEvents.libraryStorageChanges();

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
    NativeBackendEvents.ensureInstalled();
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
      final result = await nativeBackendChannel.invokeMethod(method, {
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

  static Future<Map<String, dynamic>> getLibraryScanProgress() async {
    final result = await nativeBackendChannel.invokeMethod(
      'getLibraryScanProgress',
    );
    return nativeDecodeMapResult(result);
  }

  static Future<Map<String, dynamic>?> getLibraryScanExitInfo({
    required int startedAfter,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    final result = await nativeBackendChannel.invokeMethod(
      'getLibraryScanExitInfo',
      {'started_after': startedAfter},
    );
    return nativeDecodeNullableMapResult(result, 'getLibraryScanExitInfo');
  }

  static Stream<Map<String, dynamic>> libraryScanProgressStream() {
    return _libraryScanProgressEvents.receiveBroadcastStream().map(
      nativeDecodeMapResult,
    );
  }

  static Future<void> cancelLibraryScan() async {
    await nativeBackendChannel.invokeMethod('cancelLibraryScan');
  }

  /// Holds the running native scan at its next file; it keeps its position.
  static Future<void> pauseLibraryScan() async {
    await nativeBackendChannel.invokeMethod('pauseLibraryScan');
  }

  static Future<void> resumeLibraryScan() async {
    await nativeBackendChannel.invokeMethod('resumeLibraryScan');
  }

  static Future<void> setLibraryCoverCacheDir(String cacheDir) async {
    await nativeBackendChannel.invokeMethod('setLibraryCoverCacheDir', {
      'cache_dir': cacheDir,
    });
  }
}
