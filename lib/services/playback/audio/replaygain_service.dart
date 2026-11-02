import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sistrum/services/ffmpeg/ffmpeg_metadata.dart';
import 'package:sistrum/services/ffmpeg/ffmpeg_support.dart';
import 'package:sistrum/services/ffmpeg/ffmpeg_models.dart';
import 'package:sistrum/services/ffmpeg/ffmpeg_replaygain.dart';
import 'package:sistrum/services/library/metadata/metadata_edit_result.dart';
import 'package:sistrum/services/native/media_file_bridge.dart';
import 'package:sistrum/services/playback/music_player/music_player_service.dart';
import 'package:sistrum/services/playback/audio/replaygain_write_result.dart';
import 'package:sistrum/utils/files/best_effort_delete.dart';
import 'package:sistrum/utils/files/file_access.dart';
import 'package:sistrum/utils/logging/logger.dart';

/// ReplayGain measurement and nonempty tag writing for existing audio files.
///
/// Computes EBU R128 loudness via FFmpeg and writes gain tags using the native
/// metadata editors where supported. Opus uses R128_* rather than legacy tags.
///
/// Handles SAF content:// URIs transparently by working on a temporary copy
/// and writing it back to the original document.
class ReplayGainService {
  ReplayGainService._();

  static final _log = AppLogger('ReplayGain');

  static const _nativeExtensions = <String>{
    '.flac',
    '.m4a',
    '.mp4',
    '.m4b',
    '.ape',
    '.wv',
    '.mpc',
    '.wav',
    '.aiff',
    '.aif',
    '.aifc',
    '.mp3',
    '.opus',
    '.ogg',
  };

  static bool _isNativeWritableFormat(String path) {
    final lower = path.toLowerCase();
    return _nativeExtensions.any(lower.endsWith);
  }

  /// Scans [filePath] for loudness and writes track ReplayGain tags in place.
  static Future<ReplayGainWriteResult> applyToFile(
    String filePath, {
    @visibleForTesting Future<ReplayGainResult?> Function(String)? scan,
    void Function()? onUnsupportedDecoder,
  }) => _updateFile(filePath, (workingPath) async {
    final rg = scan != null
        ? await scan(workingPath)
        : await FFmpegReplayGain.scan(
            workingPath,
            onUnsupportedDecoder: onUnsupportedDecoder,
          );
    if (rg == null) {
      _log.w('ReplayGain scan returned no result for $workingPath');
      return const ReplayGainWriteResult.failed(
        ReplayGainWriteFailure.scanFailed,
      );
    }
    return _writeLocalTags(
      workingPath,
      rg.trackGain,
      rg.trackPeak,
      album: false,
    );
  });

  static Future<ReplayGainWriteResult> writeTrackTags(
    String filePath,
    String gain,
    String peak,
  ) => _updateFile(
    filePath,
    (path) => _writeLocalTags(path, gain, peak, album: false),
  );

  static Future<ReplayGainWriteResult> writeAlbumTags(
    String filePath,
    String gain,
    String peak,
  ) => _updateFile(
    filePath,
    (path) => _writeLocalTags(path, gain, peak, album: true),
  );

  static Future<ReplayGainWriteResult> _writeLocalTags(
    String path,
    String gain,
    String peak, {
    required bool album,
  }) async {
    return _writeLocalFields(path, {
      'replaygain_${album ? 'album' : 'track'}_gain': gain,
      'replaygain_${album ? 'album' : 'track'}_peak': peak,
    });
  }

  /// Writes track and album values together, with one backup/hash/publication.
  static Future<ReplayGainWriteResult> writeTags(
    String filePath,
    Map<String, String> fields, {
    Future<bool> Function()? mayWrite,
  }) => _updateFile(
    filePath,
    (path) => _writeLocalFields(path, fields),
    mayWrite: mayWrite,
  );

  /// SAF metadata/measurement always uses an owned temporary copy. All copies
  /// from an album remain alive until FFmpeg finishes, then are cleaned even
  /// when one provider refuses access or the measurement throws.
  static Future<T> _withReadableFiles<T>(
    List<String> paths,
    Future<T> Function(List<String>) read,
  ) async {
    final copies = <String>[];
    try {
      final readable = <String>[];
      for (final path in paths) {
        if (isContentUri(path)) {
          final copy = await MediaFileBridge.copyContentUriToTempOrThrow(path);
          copies.add(copy);
          readable.add(copy);
        } else {
          readable.add(path);
        }
      }
      return await read(readable);
    } finally {
      for (final path in copies) {
        await deleteBestEffort(File(path));
      }
    }
  }

  static Future<Map<String, dynamic>> readTags(String path) =>
      _withReadableFiles([
        path,
      ], (files) => MediaFileBridge.readFileMetadata(files.single));

  static Future<ReplayGainResult?> measureTrack(String path) =>
      _withReadableFiles([
        path,
      ], (files) => FFmpegReplayGain.scan(files.single));

  static Future<ReplayGainResult?> measureAlbum(
    List<String> paths, {
    @visibleForTesting Future<ReplayGainResult?> Function(List<String>)? scan,
  }) => _withReadableFiles(paths, scan ?? FFmpegReplayGain.scanAlbum);

  static Future<ReplayGainWriteResult> _writeLocalFields(
    String path,
    Map<String, String> fields,
  ) async {
    // This service only writes measured values; it has no tag-removal API.
    if (fields.isEmpty ||
        fields.entries.any((entry) {
          final value = entry.key.endsWith('_gain')
              ? _gainDb(entry.value)
              : double.tryParse(entry.value);
          return value == null ||
              !value.isFinite ||
              (entry.key.endsWith('_peak') && value < 0);
        })) {
      return const ReplayGainWriteResult.failed(
        ReplayGainWriteFailure.verificationFailed,
      );
    }
    var written = false;
    if (_isNativeWritableFormat(path)) {
      final result = await MediaFileBridge.editFileMetadata(path, fields);
      written =
          result.outcome == MetadataEditOutcome.completed &&
          result.isNativeMethod;
      if (!written) _log.w('Native ReplayGain write did not complete: $result');
    }
    if (!written) {
      if (FFmpegReplayGain.requiresNativeWriter(path)) {
        return const ReplayGainWriteResult.failed(
          ReplayGainWriteFailure.unsupportedFormat,
        );
      }
      try {
        await FFmpegReplayGain.writeTags(path, {
          for (final entry in fields.entries)
            entry.key.toUpperCase(): entry.value,
        });
      } on FFmpegMetadataFailure catch (error) {
        return ReplayGainWriteResult.failed(
          ReplayGainWriteFailure.writeFailed,
          error: error,
        );
      }
    }
    final metadata = await MediaFileBridge.readFileMetadata(path);
    final isOpus = metadata['audio_codec'] == 'opus';
    final verified =
        metadata['error'] == null &&
        fields.entries.every((entry) {
          if (entry.key.endsWith('_peak')) {
            if (isOpus) return true;
            final expected = double.tryParse(entry.value);
            final actual = double.tryParse(
              metadata[entry.key]?.toString() ?? '',
            );
            return expected != null &&
                actual != null &&
                (actual - expected).abs() <= 0.000001;
          }
          final expected = _gainDb(entry.value);
          final actual = _gainDb(metadata[entry.key]);
          return expected != null &&
              actual != null &&
              (actual - expected).abs() <= 0.01;
        });
    return verified
        ? const ReplayGainWriteResult.written()
        : const ReplayGainWriteResult.failed(
            ReplayGainWriteFailure.verificationFailed,
          );
  }

  static double? _gainDb(Object? value) => double.tryParse(
    (value?.toString() ?? '').replaceFirst(RegExp(r'\s*dB\s*$'), '').trim(),
  );

  /// Runs [update] on [filePath] only when the audio can be proven unchanged.
  ///
  /// Local files: a backup copy is taken first, the audio hash and size are
  /// compared afterwards, and the backup is copied back on any mismatch or
  /// failed write. SAF documents already work on a temp copy, which is
  /// written back only after the same checks pass.
  /// Whether writes are guarded by the audio hash and size check. Tests that
  /// drive the SAF channel with fake files turn it off; production keeps it on.
  @visibleForTesting
  static bool integrityChecks = true;

  static Future<ReplayGainWriteResult> _updateFile(
    String filePath,
    Future<ReplayGainWriteResult> Function(String) update, {
    Future<bool> Function()? mayWrite,
  }) async {
    if (filePath.isEmpty) {
      return const ReplayGainWriteResult.failed(
        ReplayGainWriteFailure.storageFailed,
      );
    }

    final isSaf = isContentUri(filePath);
    var workingPath = filePath;
    String? safTempPath;
    String? backupPath;
    var keepBackup = false;
    var backupReady = false;

    try {
      if (isSaf) {
        try {
          safTempPath = await MediaFileBridge.copyContentUriToTempOrThrow(
            filePath,
          );
        } catch (e) {
          _log.w('Failed to copy SAF file to temp for ReplayGain update: $e');
          return ReplayGainWriteResult.failed(
            ReplayGainWriteFailure.storageFailed,
            error: e,
          );
        }
        workingPath = safTempPath;
      }

      // The backup and hashes exist only when the guard is on. The original
      // is then restored from the backup on any rejected or failed write.
      String? beforeHash;
      var sizeBefore = 0;
      if (integrityChecks) {
        final dot = workingPath.lastIndexOf('.');
        final extension = dot < 0 ? '' : workingPath.substring(dot);
        backupPath = await FFmpegOutput.tempPath(extension);
        await File(workingPath).copy(backupPath);
        backupReady = true;
        beforeHash = await FFmpegReplayGain.audioHash(backupPath);
        sizeBefore = await File(backupPath).length();
        if (beforeHash == null) {
          return const ReplayGainWriteResult.failed(
            ReplayGainWriteFailure.verificationFailed,
          );
        }
      }

      if (mayWrite != null && !await mayWrite()) {
        return const ReplayGainWriteResult.failed(
          ReplayGainWriteFailure.deferred,
        );
      }
      final updated = await update(workingPath);
      if (!updated.isWritten) {
        if (backupPath != null) {
          keepBackup = !await _restore(backupPath, workingPath);
        }
        return updated;
      }

      if (backupPath != null) {
        final failure = ReplayGainIntegrity.check(
          beforeHash: beforeHash,
          afterHash: await FFmpegReplayGain.audioHash(workingPath),
          sizeBefore: sizeBefore,
          sizeAfter: await File(workingPath).length(),
        );
        if (failure != null) {
          _log.e(
            'ReplayGain write rejected ($failure) for $filePath; restoring',
          );
          keepBackup = !await _restore(backupPath, workingPath);
          return ReplayGainWriteResult.failed(failure);
        }
      }

      if (isSaf) {
        if (mayWrite != null && !await mayWrite()) {
          return const ReplayGainWriteResult.failed(
            ReplayGainWriteFailure.deferred,
          );
        }
        final written = await MediaFileBridge.writeTempToSafDetailed(
          workingPath,
          filePath,
        );
        if (!written.success) {
          _log.w(
            'Failed to write ReplayGain temp file back to SAF document: '
            '${written.error ?? 'unknown error'}',
          );
          return ReplayGainWriteResult.failed(
            ReplayGainWriteFailure.storageFailed,
            error: written.error,
          );
        }
      }

      refreshPlaybackNormalization(filePath);
      _log.i('ReplayGain tags updated and verified: $filePath');
      return const ReplayGainWriteResult.written();
    } catch (e) {
      if (backupPath != null && backupReady) {
        keepBackup = !await _restore(backupPath, workingPath);
      }
      _log.e('Failed to update ReplayGain', e);
      return ReplayGainWriteResult.failed(
        ReplayGainWriteFailure.writeFailed,
        error: e,
      );
    } finally {
      if (safTempPath != null) {
        await deleteBestEffort(File(safTempPath));
      }
      if (backupPath != null && !keepBackup) {
        await deleteBestEffort(File(backupPath));
      }
    }
  }

  /// Copies [backup] over [target]. False when the copy itself failed, in
  /// which case the backup is kept on disk for recovery.
  static Future<bool> _restore(String backup, String target) async {
    try {
      await File(backup).copy(target);
      return true;
    } catch (e) {
      _log.e('Could not restore $target from $backup: $e');
      return false;
    }
  }
}
