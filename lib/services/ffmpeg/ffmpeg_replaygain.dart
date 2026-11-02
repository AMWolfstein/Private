import 'dart:io';
import 'dart:math' as math;

import 'package:sistrum/services/ffmpeg/ffmpeg_metadata.dart';
import 'package:sistrum/services/ffmpeg/ffmpeg_models.dart';
import 'package:sistrum/services/ffmpeg/ffmpeg_support.dart';
import 'package:sistrum/utils/logging/logger.dart';

final _log = AppLogger('FFmpeg');

/// EBU R128 measurement and non-Ogg ReplayGain stream-copy tagging.
abstract final class FFmpegReplayGain {
  static Future<ReplayGainResult?> scan(
    String filePath, {
    void Function()? onUnsupportedDecoder,
  }) async {
    _log.d(
      'Scanning ReplayGain for: ${filePath.split(Platform.pathSeparator).last}',
    );
    // Suppress per-frame measurements and retain the final ebur128 summary.
    final result = await FFmpegExecution.arguments([
      '-hide_banner',
      '-nostats',
      '-loglevel',
      'info',
      '-i',
      filePath,
      '-map',
      '0:a:0',
      '-vn',
      '-sn',
      '-dn',
      '-af',
      'ebur128=peak=true:framelog=quiet',
      '-f',
      'null',
      '-',
    ]);
    return parseScan(result, onUnsupportedDecoder: onUnsupportedDecoder);
  }

  /// Measures one album as a single programme: the files are decoded in
  /// order and measured together, so album gain follows the whole album's
  /// loudness rather than an average of its tracks. The same programme scan
  /// also measures true peak for the album tags.
  static Future<ReplayGainResult?> scanAlbum(
    List<String> filePaths, {
    void Function()? onUnsupportedDecoder,
  }) async {
    if (filePaths.isEmpty) return null;
    final inputs = <String>[];
    final chain = <String>[];
    for (var i = 0; i < filePaths.length; i++) {
      inputs.addAll(['-i', filePaths[i]]);
      // One sample format and rate, so the concat filter accepts every track.
      chain.add(
        '[$i:a:0]aformat=sample_fmts=fltp:sample_rates=48000:'
        'channel_layouts=stereo[a$i]',
      );
    }
    final joined = [for (var i = 0; i < filePaths.length; i++) '[a$i]'].join();
    final filter =
        '${chain.join(';')};'
        '${joined}concat=n=${filePaths.length}:v=0:a=1,'
        'ebur128=peak=true:framelog=quiet';
    final result = await FFmpegExecution.arguments([
      '-hide_banner',
      '-nostats',
      '-loglevel',
      'info',
      ...inputs,
      '-filter_complex',
      filter,
      '-vn',
      '-sn',
      '-dn',
      '-f',
      'null',
      '-',
    ]);
    return parseScan(result, onUnsupportedDecoder: onUnsupportedDecoder);
  }

  /// Hash of the decoded audio packets of [filePath], with tags and artwork
  /// left out. Equal hashes before and after a tag write mean the audio is
  /// unchanged. Null when FFmpeg cannot read the stream.
  static Future<String?> audioHash(String filePath) async {
    final result = await FFmpegExecution.arguments([
      '-hide_banner',
      '-nostats',
      '-loglevel',
      'error',
      '-i',
      filePath,
      '-map',
      '0:a:0',
      '-c',
      'copy',
      '-f',
      'hash',
      '-hash',
      'sha256',
      '-',
    ]);
    if (!result.success) return null;
    final match = RegExp(r'SHA256=([0-9a-fA-F]{64})').firstMatch(result.output);
    return match?.group(1)?.toLowerCase();
  }

  static ReplayGainResult? parseScan(
    FFmpegResult result, {
    void Function()? onUnsupportedDecoder,
  }) {
    final output = result.output;
    if (!result.success) {
      final decoderMissing = RegExp(
        r'decoder.*not found|no decoder found|unknown decoder',
        caseSensitive: false,
      );
      final diagnostic = output
          .split('\n')
          .where(
            (line) =>
                decoderMissing.hasMatch(line) ||
                RegExp(
                  r'error|invalid|failed',
                  caseSensitive: false,
                ).hasMatch(line),
          )
          .take(3)
          .join(' ')
          .trim();
      _log.w(
        'ReplayGain scan failed (exit ${result.returnCode}): ${diagnostic.isEmpty ? "no decoder diagnostics" : diagnostic.substring(0, math.min(diagnostic.length, 500))}',
      );
      if (decoderMissing.hasMatch(output)) onUnsupportedDecoder?.call();
      // A failed decoder can print a partial/default summary, not a measurement
      // of the complete track.
      return null;
    }

    final integratedMatch = RegExp(
      r'I:\s+(-?\d+\.?\d*)\s+LUFS',
    ).allMatches(output);
    if (integratedMatch.isEmpty) {
      _log.w('ReplayGain scan: could not parse integrated loudness');
      return null;
    }
    // The final match is the summary, rather than a per-segment measurement.
    final integratedLufs = double.tryParse(integratedMatch.last.group(1) ?? '');
    if (integratedLufs == null) {
      _log.w('ReplayGain scan: invalid integrated loudness value');
      return null;
    }

    // Use the maximum true peak across channels, converting dBFS to a ratio.
    double? truePeakDbfs;
    for (final match in RegExp(
      r'Peak:\s+(-?\d+\.?\d*)\s+dBFS',
    ).allMatches(output)) {
      final value = double.tryParse(match.group(1) ?? '');
      if (value != null && (truePeakDbfs == null || value > truePeakDbfs)) {
        truePeakDbfs = value;
      }
    }
    final gainDb = -18.0 - integratedLufs;
    final peakLinear = truePeakDbfs == null
        ? 1.0
        : math.pow(10, truePeakDbfs / 20.0).toDouble();
    final trackGain =
        '${gainDb >= 0 ? "+" : ""}${gainDb.toStringAsFixed(2)} dB';
    final trackPeak = peakLinear.toStringAsFixed(6);
    _log.i(
      'ReplayGain scan result: gain=$trackGain, peak=$trackPeak (integrated=${integratedLufs.toStringAsFixed(1)} LUFS)',
    );
    return ReplayGainResult(
      trackGain: trackGain,
      trackPeak: trackPeak,
      integratedLufs: integratedLufs,
      truePeakLinear: peakLinear,
    );
  }

  /// Throws [FFmpegMetadataFailure] when the tags are not written.
  static Future<void> writeAlbumTags(
    String filePath,
    String gain,
    String peak,
  ) => _writeTags(filePath, 'Album', gain, peak);

  /// Throws [FFmpegMetadataFailure] when the tags are not written.
  static Future<void> writeTrackTags(
    String filePath,
    String gain,
    String peak,
  ) => _writeTags(filePath, 'Track', gain, peak);

  /// These containers cannot round-trip their freeform tags through this
  /// stream-copy muxer. Keep the original when the native writer fails instead
  /// of publishing a file that lost ReplayGain or artwork metadata.
  static bool requiresNativeWriter(String filePath) {
    final lower = filePath.toLowerCase();
    return const ['.opus', '.ogg', '.m4a', '.mp4', '.m4b'].any(lower.endsWith);
  }

  static Future<void> _writeTags(
    String filePath,
    String scope,
    String gain,
    String peak,
  ) async {
    if (requiresNativeWriter(filePath)) {
      _log.e(
        '${filePath.split('.').last} ReplayGain requires the native tag writer',
      );
      throw FFmpegMetadataFailure(
        '${filePath.split('.').last} ReplayGain requires the native tag writer',
      );
    }
    await writeTags(filePath, {
      'REPLAYGAIN_${scope.toUpperCase()}_GAIN': gain,
      'REPLAYGAIN_${scope.toUpperCase()}_PEAK': peak,
    });
  }

  /// Writes all requested tags in a single stream-copy operation.
  static Future<void> writeTags(
    String filePath,
    Map<String, String> fields,
  ) async {
    if (requiresNativeWriter(filePath)) {
      throw FFmpegMetadataFailure('ReplayGain requires the native tag writer');
    }
    final ext = filePath.contains('.')
        ? '.${filePath.split('.').last.toLowerCase()}'
        : '.tmp';
    final tempOutput = await FFmpegOutput.tempPath(ext);
    _log.d('Writing ReplayGain tags via FFmpeg');
    final result = await FFmpegExecution.arguments([
      '-v',
      'error',
      '-hide_banner',
      '-i',
      filePath,
      '-map',
      '0',
      '-c',
      'copy',
      '-map_metadata',
      '0',
      for (final entry in fields.entries) ...[
        '-metadata',
        '${entry.key}=${entry.value}',
      ],
      tempOutput,
      '-y',
    ]);
    if (!result.success) {
      _log.e(
        'ReplayGain write failed (code ${result.returnCode}): ${result.output}',
      );
    } else if (await FFmpegOutput.promote(
      tempOutput,
      filePath,
      onError: (e) => _log.w('Failed to replace file with ReplayGain: $e'),
    )) {
      _log.d('ReplayGain tags written successfully');
      return;
    }
    await FFmpegOutput.cleanup(tempOutput);
    throw FFmpegMetadataFailure('ReplayGain tags were not written');
  }
}
