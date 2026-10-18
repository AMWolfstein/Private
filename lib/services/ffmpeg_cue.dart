import 'dart:io';

import 'package:spotiflac_android/services/audio_metadata_mapper.dart';
import 'package:spotiflac_android/services/ffmpeg_models.dart';
import 'package:spotiflac_android/services/ffmpeg_support.dart';
import 'package:spotiflac_android/utils/logger.dart';

final _log = AppLogger('FFmpeg');

/// Extracts individual tracks from a CUE-referenced audio file.
abstract final class FFmpegCue {
  static Future<List<String>?> splitCueToTracks({
    required String audioPath,
    required String outputDir,
    required List<CueSplitTrackInfo> tracks,
    required Map<String, String> albumMetadata,
    String? coverPath,
    void Function(int current, int total)? onProgress,
  }) async {
    if (tracks.isEmpty) {
      _log.e('No tracks to split');
      return null;
    }
    final outputPaths = <String>[];
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
      final outputName =
          '${track.number.toString().padLeft(2, '0')} - $title.$outputExt';
      final outputPath = '$outputDir${Platform.pathSeparator}$outputName';
      final arguments = <String>[
        '-v',
        'error',
        '-hide_banner',
        '-i',
        audioPath,
        '-ss',
        _formatSeconds(track.startSec),
      ];
      if (track.endSec > 0) {
        arguments.addAll(['-to', _formatSeconds(track.endSec)]);
      }
      arguments.addAll(
        outputExt == 'flac'
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
      final result = await FFmpegExecution.arguments(arguments);
      if (!result.success) {
        _log.e('CUE split failed for track ${track.number}: ${result.output}');
        continue;
      }
      outputPaths.add(outputPath);
      _log.i('CUE split: track ${track.number} -> $outputName');
    }
    if (outputPaths.isEmpty) {
      _log.e('CUE split: no tracks were successfully extracted');
      return null;
    }
    _log.i('CUE split complete: ${outputPaths.length}/${tracks.length} tracks');
    return outputPaths;
  }

  static String _formatSeconds(double seconds) {
    if (seconds < 0) return '0';
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds - hours * 3600 - minutes * 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toStringAsFixed(3).padLeft(6, '0')}';
  }
}
