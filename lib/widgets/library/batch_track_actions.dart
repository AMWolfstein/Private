import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/core/models/unified_library_item.dart';
import 'package:sistrum/providers/library/local_library_provider.dart';
import 'package:sistrum/services/ffmpeg/ffmpeg_metadata.dart';
import 'package:sistrum/services/ffmpeg/ffmpeg_models.dart';
import 'package:sistrum/services/ffmpeg/ffmpeg_replaygain.dart';
import 'package:sistrum/services/library/database/library_database.dart';
import 'package:sistrum/services/library/metadata/metadata_edit_result.dart';
import 'package:sistrum/services/native/media_file_bridge.dart';
import 'package:sistrum/services/playback/music_player/music_player_service.dart';
import 'package:sistrum/services/playback/audio/replaygain_write_result.dart';
import 'package:sistrum/utils/files/best_effort_delete.dart';
import 'package:sistrum/utils/files/file_access.dart';
import 'package:sistrum/utils/logging/logger.dart';
import 'package:sistrum/widgets/primitives/app_alert_dialog.dart';
import 'package:sistrum/widgets/selection/batch_progress_dialog.dart';

final _batchActionsLog = AppLogger('BatchActions');

/// Adds or removes ReplayGain tags for [selectedItems].
///
/// [onConfirmOpen] / [onConfirmClosed] let the caller hide and restore any
/// selection UI around the confirmation dialog; [onConfirmClosed] receives
/// whether the user confirmed.
///
/// Returns whether at least one file changed, so callers can skip refreshes
/// after a cancelled or failed batch.
Future<bool> runBatchReplayGain(
  BuildContext sourceContext,
  List<UnifiedLibraryItem> selectedItems, {
  required LibraryDatabase database,
  required VoidCallback onExitSelectionMode,
  bool remove = false,
  VoidCallback? onConfirmOpen,
  Future<void> Function(bool confirmed)? onConfirmClosed,
}) async {
  final items = selectedItems
      .where((item) => !isCueVirtualPath(item.filePath))
      .toList(growable: false);
  if (items.isEmpty) return false;

  final container = ProviderScope.containerOf(sourceContext, listen: false);
  // The selection overlay can disappear when opening the confirmation dialog.
  final context = Navigator.of(sourceContext, rootNavigator: true).context;

  onConfirmOpen?.call();

  final confirmed = await showAppDialog<bool>(
    context: context,
    builder: (ctx) => AppAlertDialog(
      title: Text(
        remove
            ? ctx.l10n.trackRemoveReplayGain
            : ctx.l10n.replayGainBatchConfirmTitle,
      ),
      content: Text(
        remove
            ? ctx.l10n.replayGainRemoveConfirmMessage(items.length)
            : ctx.l10n.replayGainBatchConfirmMessage(items.length),
      ),
      actions: [
        AppDialogAction(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(ctx.l10n.dialogCancel),
        ),
        AppDialogAction(
          filled: true,
          isDefault: true,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            remove
                ? ctx.l10n.trackRemoveReplayGain
                : ctx.l10n.replayGainBatchConfirmTitle,
          ),
        ),
      ],
    ),
  );

  await onConfirmClosed?.call(confirmed == true);

  if (confirmed != true || !context.mounted) return false;

  var cancelled = false;
  int successCount = 0;
  var unsupportedDecoder = false;
  final total = items.length;

  late final VoidCallback dismissProgress;
  dismissProgress = BatchProgressDialog.show(
    context: context,
    title: remove
        ? context.l10n.replayGainRemoving
        : context.l10n.replayGainBatchAnalyzing,
    total: total,
    icon: Icons.graphic_eq,
    onCancel: () {
      cancelled = true;
      dismissProgress();
    },
  );

  for (int i = 0; i < total; i++) {
    if (!context.mounted || cancelled) break;
    final item = items[i];
    BatchProgressDialog.update(current: i + 1, detail: item.trackName);
    try {
      final result = remove
          ? await ReplayGainService.removeFromFile(item.filePath)
          : await ReplayGainService.applyToFile(
              item.filePath,
              onUnsupportedDecoder: () => unsupportedDecoder = true,
            );
      if (result.isWritten) {
        successCount++;
        try {
          await database.updateAudioMetadata(
            item.localItem.id,
            hasReplayGain: !remove,
          );
        } catch (e) {
          _batchActionsLog.w('Could not refresh ReplayGain availability: $e');
        }
      } else {
        _batchActionsLog.w('ReplayGain did not change ${item.filePath}');
      }
    } catch (error, stackTrace) {
      _batchActionsLog.e(
        'ReplayGain failed for ${item.filePath}',
        error,
        stackTrace,
      );
    }
  }

  onExitSelectionMode();

  if (successCount > 0 && context.mounted) {
    await container.read(localLibraryProvider.notifier).reloadFromStorage();
  }

  if (!context.mounted) return successCount > 0;
  if (!cancelled) {
    dismissProgress();
  }
  ScaffoldMessenger.of(context).clearSnackBars();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        [
          remove
              ? context.l10n.replayGainRemoveBatchSuccess(successCount, total)
              : context.l10n.replayGainBatchSuccess(successCount, total),
          if (unsupportedDecoder) context.l10n.replayGainUnsupportedDecoder,
        ].join('\n'),
      ),
    ),
  );
  return successCount > 0;
}

/// ReplayGain scanning and tag removal for existing audio files.
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

  /// Removes track/album tags, including Opus R128 and M4A Sound Check tags.
  /// Native editors copy the audio payload unchanged and publish atomically.
  static Future<ReplayGainWriteResult> removeFromFile(String filePath) =>
      _updateFile(filePath, (path) async {
        if (!_isNativeWritableFormat(path)) {
          return const ReplayGainWriteResult.failed(
            ReplayGainWriteFailure.unsupportedFormat,
          );
        }
        const fields = {
          'replaygain_track_gain': '',
          'replaygain_track_peak': '',
          'replaygain_album_gain': '',
          'replaygain_album_peak': '',
        };
        final result = await MediaFileBridge.editFileMetadata(path, fields);
        if (result.outcome != MetadataEditOutcome.completed ||
            !result.isNativeMethod) {
          return ReplayGainWriteResult.failed(
            ReplayGainWriteFailure.writeFailed,
            error: result,
          );
        }
        final metadata = await MediaFileBridge.readFileMetadata(path);
        final cleared =
            metadata['error'] == null &&
            metadata['audio_codec'] != null &&
            fields.keys.every(
              (key) => (metadata[key]?.toString() ?? '').trim().isEmpty,
            );
        return cleared
            ? const ReplayGainWriteResult.written()
            : const ReplayGainWriteResult.failed(
                ReplayGainWriteFailure.verificationFailed,
              );
      });

  static Future<ReplayGainWriteResult> _writeLocalTags(
    String path,
    String gain,
    String peak, {
    required bool album,
  }) async {
    final scope = album ? 'album' : 'track';
    var written = false;
    if (_isNativeWritableFormat(path)) {
      final result = await MediaFileBridge.editFileMetadata(path, {
        'replaygain_${scope}_gain': gain,
        'replaygain_${scope}_peak': peak,
      });
      written =
          result.outcome == MetadataEditOutcome.completed &&
          result.isNativeMethod;
      if (!written) {
        _log.w('Native $scope ReplayGain write did not complete: $result');
      }
    }

    if (!written) {
      // Remuxing all streams rejects attached Opus artwork; mapping only audio
      // would discard it. M4A freeform tags do not survive this copy muxer
      // either. Keep the original if its native editor cannot handle the file,
      // rather than silently losing artwork or reporting a no-op.
      if (FFmpegReplayGain.requiresNativeWriter(path)) {
        return const ReplayGainWriteResult.failed(
          ReplayGainWriteFailure.unsupportedFormat,
        );
      }
      try {
        if (album) {
          await FFmpegReplayGain.writeAlbumTags(path, gain, peak);
        } else {
          await FFmpegReplayGain.writeTrackTags(path, gain, peak);
        }
      } on FFmpegMetadataFailure catch (error) {
        return ReplayGainWriteResult.failed(
          ReplayGainWriteFailure.writeFailed,
          error: error,
        );
      }
    }

    final metadata = await MediaFileBridge.readFileMetadata(path);
    final expectedGain = _gainDb(gain);
    final actualGain = _gainDb(metadata['replaygain_${scope}_gain']);
    final expectedPeak = double.tryParse(peak);
    final actualPeak = double.tryParse(
      metadata['replaygain_${scope}_peak']?.toString() ?? '',
    );
    final isOpus = metadata['audio_codec'] == 'opus';
    final verified =
        metadata['error'] == null &&
        expectedGain != null &&
        actualGain != null &&
        (actualGain - expectedGain).abs() <= 0.01 &&
        (isOpus ||
            (expectedPeak != null &&
                actualPeak != null &&
                (actualPeak - expectedPeak).abs() <= 0.000001));
    if (!verified) {
      _log.w('$scope ReplayGain verification failed after writing $path');
      return const ReplayGainWriteResult.failed(
        ReplayGainWriteFailure.verificationFailed,
      );
    }
    return const ReplayGainWriteResult.written();
  }

  static double? _gainDb(Object? value) => double.tryParse(
    (value?.toString() ?? '').replaceFirst(RegExp(r'\s*dB\s*$'), '').trim(),
  );

  static Future<ReplayGainWriteResult> _updateFile(
    String filePath,
    Future<ReplayGainWriteResult> Function(String) update,
  ) async {
    if (filePath.isEmpty) {
      return const ReplayGainWriteResult.failed(
        ReplayGainWriteFailure.storageFailed,
      );
    }

    final isSaf = isContentUri(filePath);
    var workingPath = filePath;
    String? safTempPath;

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

      final updated = await update(workingPath);
      if (!updated.isWritten) return updated;

      if (isSaf) {
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
      _log.e('Failed to update ReplayGain', e);
      return ReplayGainWriteResult.failed(
        ReplayGainWriteFailure.writeFailed,
        error: e,
      );
    } finally {
      if (safTempPath != null) {
        await deleteBestEffort(File(safTempPath));
      }
    }
  }
}
