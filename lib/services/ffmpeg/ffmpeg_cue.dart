import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sistrum/services/ffmpeg/audio_metadata_mapper.dart';
import 'package:sistrum/services/ffmpeg/ffmpeg_models.dart';
import 'package:sistrum/services/ffmpeg/ffmpeg_support.dart';
import 'package:sistrum/utils/logger.dart';

final _log = AppLogger('FFmpeg');

/// Successfully extracted tracks and how many could not be produced.
class CueSplitResult {
  final List<String> paths;
  final int failed;

  const CueSplitResult(this.paths, this.failed);
}

/// Extracts individual tracks from a CUE-referenced audio file.
abstract final class FFmpegCue {
  static Future<CueSplitResult?> splitCueToTracks({
    required String audioPath,
    required String outputDir,
    required List<CueSplitTrackInfo> tracks,
    required Map<String, String> albumMetadata,
    String? coverPath,
    void Function(int current, int total)? onProgress,
    @visibleForTesting Future<FFmpegResult> Function(List<String>)? execute,
  }) async {
    if (tracks.isEmpty) {
      _log.e('No tracks to split');
      return null;
    }
    final run = execute ?? FFmpegExecution.arguments;
    final outputPaths = <String>[];
    final usedOutputNames = <String>{};
    var failed = 0;
    final inputExt = audioPath.toLowerCase().split('.').last;
    final outputExt = const {'flac', 'wav', 'ape', 'wv'}.contains(inputExt)
        ? 'flac'
        : inputExt;
    for (var i = 0; i < tracks.length; i++) {
      final track = tracks[i];
      onProgress?.call(i + 1, tracks.length);
      final title = track.title
          .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final stem = '${track.number.toString().padLeft(2, '0')} - $title';
      var outputName = '$stem.$outputExt';
      // Duplicate numbers/titles must not reuse an earlier track's output:
      // cleaning up a failed run would delete the other track's file.
      for (var copy = 2; !usedOutputNames.add(outputName); copy++) {
        outputName = '$stem ($copy).$outputExt';
      }
      final outputPath = '$outputDir${Platform.pathSeparator}$outputName';
      final reencode = outputExt == 'flac';
      final arguments = <String>['-v', 'error', '-hide_banner'];
      if (reencode) {
        // Seeking before the input starts decoding at the track boundary.
        // With `-ss` after `-i` every track decodes its own prefix again,
        // which grows quadratically across a long album. `-t` replaces the
        // absolute `-to` end: both describe the same samples.
        arguments.addAll([
          '-ss',
          _formatSeconds(track.startSec),
          '-i',
          audioPath,
        ]);
        if (track.endSec > 0) {
          arguments.addAll([
            '-t',
            _formatSeconds(track.endSec - track.startSec),
          ]);
        }
      } else {
        // Stream copy does not decode, so keep the boundary semantics of
        // output seeking rather than changing where packets are cut.
        arguments.addAll([
          '-i',
          audioPath,
          '-ss',
          _formatSeconds(track.startSec),
        ]);
        if (track.endSec > 0) {
          arguments.addAll(['-to', _formatSeconds(track.endSec)]);
        }
      }
      arguments.addAll(
        reencode
            ? ['-c:a', 'flac', '-compression_level', '8']
            : ['-c:a', 'copy'],
      );
      final metadata = <String, String>{
        'TITLE': track.title,
        'ARTIST': track.artist.isNotEmpty
            ? track.artist
            : (albumMetadata['artist'] ?? ''),
        'ALBUM': albumMetadata['album'] ?? '',
        'ALBUMARTIST': albumMetadata['artist'] ?? '',
        'TRACKNUMBER': track.number.toString(),
        'GENRE': albumMetadata['genre'] ?? '',
        'DATE': albumMetadata['date'] ?? '',
        'ISRC': track.isrc,
        'COMPOSER': track.composer,
      }..removeWhere((_, value) => value.isEmpty);
      AudioMetadataMapper.appendMappedMetadataArguments(arguments, metadata);
      arguments.addAll([outputPath, '-y']);
      _log.d('CUE split track ${track.number}');
      final result = await run(arguments);
      if (!result.success) {
        _log.e('CUE split failed for track ${track.number}: ${result.output}');
        await FFmpegOutput.cleanup(outputPath);
        failed++;
        continue;
      }
      outputPaths.add(outputPath);
      _log.i('CUE split: track ${track.number} -> $outputName');
    }
    if (outputPaths.isEmpty) {
      _log.e('CUE split: no tracks were successfully extracted');
      return failed > 0 ? CueSplitResult(const [], failed) : null;
    }
    _log.i('CUE split complete: ${outputPaths.length}/${tracks.length} tracks');
    return CueSplitResult(outputPaths, failed);
  }

  static String _formatSeconds(double seconds) {
    if (seconds < 0) return '0';
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds - hours * 3600 - minutes * 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toStringAsFixed(3).padLeft(6, '0')}';
  }
}
