import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:sistrum/services/library/metadata_edit_result.dart';
import 'package:sistrum/services/native/native_channel.dart';
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

/// Storage Access Framework trees, content URIs, and file metadata reached
/// through the native backend.
class MediaFileBridge {
  /// Holds local backend access until the media operation finishes.
  static Future<String> acquireMediaDirectory(String path) async {
    return await nativeBackendChannel.invokeMethod<String>(
          'acquireMediaDirectory',
          {'path': path},
        ) ??
        '';
  }

  static Future<void> releaseMediaDirectory(String token) async {
    if (token.isEmpty) return;
    await nativeBackendChannel.invokeMethod('releaseMediaDirectory', {
      'token': token,
    });
  }

  static Future<Map<String, dynamic>?> pickSafTree({
    void Function(String message)? onFailure,
  }) async {
    final result = await nativeBackendChannel.invokeMethod('pickSafTree');
    final decoded = nativeDecodeNullableMapResult(result, 'pickSafTree');
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
    await nativeBackendChannel.invokeMethod('safReleaseTree', {
      'tree_uri': treeUri,
    });
  }

  static Future<bool> safExists(String uri) async {
    final result = await nativeBackendChannel.invokeMethod('safExists', {
      'uri': uri,
    });
    return result as bool;
  }

  /// Exact-path checks. Only explicit `missing` results authorize cleanup;
  /// absent responses and permission/provider failures remain unknown.
  static Future<Map<String, bool?>> safExistsBatch(List<String> uris) async {
    if (uris.isEmpty) return const {};
    final result = await nativeInvokeMap('safExistsBatch', {
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
      Future<bool?> probe() => nativeBackendChannel.invokeMethod<bool>(
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

  static Future<bool> safDelete(String uri) async {
    final result = await nativeBackendChannel.invokeMethod('safDelete', {
      'uri': uri,
    });
    return result as bool;
  }

  static Future<Map<String, dynamic>> safStat(String uri) {
    return nativeInvokeMap('safStat', {'uri': uri});
  }

  /// Copies a SAF document to a temporary file. A refused or failed copy throws
  /// the native [PlatformException]: `saf_permission_denied` or `saf_copy_failed`.
  static Future<String> copyContentUriToTempOrThrow(String uri) async {
    final path = await nativeBackendChannel.invokeMethod<String>(
      'safCopyToTemp',
      {'uri': uri},
    );
    if (path == null || path.isEmpty) {
      throw PlatformException(
        code: 'saf_copy_failed',
        message: 'No temporary copy was made for $uri',
      );
    }
    return path;
  }

  /// [copyContentUriToTempOrThrow] for callers that only need a path or null.
  static Future<String?> copyContentUriToTemp(String uri) async {
    try {
      return await copyContentUriToTempOrThrow(uri);
    } on PlatformException {
      return null;
    }
  }

  static Future<ContentUriPlaybackLease?> openContentUriPlaybackLease(
    String uri,
  ) async {
    if (!Platform.isAndroid || !uri.startsWith('content://')) return null;
    final result = await nativeBackendChannel.invokeMethod(
      'safOpenPlaybackLease',
      {'uri': uri},
    );
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
      await nativeBackendChannel.invokeMethod('safClosePlaybackLease', {
        'token': token,
      });
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
    final result = await nativeBackendChannel
        .invokeMethod('safCreateFromPath', {
          'tree_uri': treeUri,
          'relative_dir': relativeDir,
          'file_name': fileName,
          'mime_type': mimeType,
          'src_path': srcPath,
        });
    return result as String?;
  }

  static Future<bool> shareContentUri(String uri, {String title = ''}) async {
    final result = await nativeBackendChannel.invokeMethod('shareContentUri', {
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
      return nativeInvokeMap('extractCoverToFile', {
        'audio_path': audioPath,
        'output_path': outputPath,
      });
    });
  }

  static Future<Map<String, dynamic>> readFileMetadata(
    String filePath, {
    String? displayName,
  }) {
    return nativeInvokeMap('readFileMetadata', {
      'file_path': filePath,
      'display_name': ?displayName,
    });
  }

  static Future<Map<String, dynamic>> _editFileMetadataRaw(
    String filePath,
    Map<String, String> metadata,
  ) {
    return _withMediaFileAccess([filePath, metadata['cover_path'] ?? ''], () {
      return nativeInvokeMap('editFileMetadata', {
        'file_path': filePath,
        'metadata_json': jsonEncode(metadata),
      });
    });
  }

  /// Typed variant of [editFileMetadata] for callers that act on the outcome.
  static Future<MetadataEditResult> editFileMetadata(
    String filePath,
    Map<String, String> metadata,
  ) async =>
      MetadataEditResult.decode(await _editFileMetadataRaw(filePath, metadata));

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

  /// Writes a completed temporary file back to its SAF document and reports
  /// any retained recovery copy. The caller keeps ownership of [tempPath].
  static Future<SafWriteBackResult> writeTempToSafDetailed(
    String tempPath,
    String safUri,
  ) async {
    final map = await nativeInvokeMap('writeTempToSaf', {
      'temp_path': tempPath,
      'saf_uri': safUri,
    });
    return SafWriteBackResult(
      success: map['success'] == true,
      error: map['error']?.toString(),
      recoveryPath: map['recovery_path']?.toString(),
    );
  }

  static Future<Map<String, int>> getSafFileModTimes(List<String> uris) async {
    final map = await nativeInvokeMap('getSafFileModTimes', {
      'uris': jsonEncode(uris),
    });
    return map.map((key, value) => MapEntry(key, (value as num).toInt()));
  }
}
