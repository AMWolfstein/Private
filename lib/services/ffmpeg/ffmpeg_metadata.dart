import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:sistrum/services/ffmpeg/audio_metadata_mapper.dart';
import 'package:sistrum/services/ffmpeg/ffmpeg_models.dart';
import 'package:sistrum/services/ffmpeg/ffmpeg_support.dart';
import 'package:sistrum/services/native/native_data_jobs.dart';
import 'package:sistrum/utils/logging/logger.dart';

final _log = AppLogger('FFmpeg');

/// A metadata/artwork write that FFmpeg could not complete. [message] is a
/// concise cause that survives the writer boundary into the save result.
class FFmpegMetadataFailure implements Exception {
  const FFmpegMetadataFailure(this.message);

  final String message;

  @override
  String toString() => 'FFmpegMetadataFailure: $message';
}

/// Container-specific metadata and artwork operations, independent of encoding.
abstract final class FFmpegMetadata {
  static List<String> buildCoverResizeArguments({
    required String inputPath,
    required String outputPath,
    required int maxDimension,
  }) {
    if (maxDimension < 64 || maxDimension > 8192) {
      throw ArgumentError.value(
        maxDimension,
        'maxDimension',
        'Must be between 64 and 8192 pixels',
      );
    }
    return [
      '-y',
      '-i',
      inputPath,
      '-map_metadata',
      '-1',
      '-an',
      '-sn',
      '-vf',
      'scale=$maxDimension:$maxDimension:'
          'force_original_aspect_ratio=decrease:flags=lanczos',
      '-frames:v',
      '1',
      '-update',
      '1',
      '-q:v',
      '2',
      outputPath,
    ];
  }

  /// Throws [FFmpegMetadataFailure] when no resized cover was produced.
  static Future<void> resizeCoverArt({
    required String inputPath,
    required String outputPath,
    required int maxDimension,
  }) async {
    String cause;
    try {
      if (!await File(inputPath).exists()) {
        throw FFmpegMetadataFailure('Cover input is missing');
      }
      final result = await FFmpegExecution.arguments(
        buildCoverResizeArguments(
          inputPath: inputPath,
          outputPath: outputPath,
          maxDimension: maxDimension,
        ),
      );
      final output = File(outputPath);
      if (result.success &&
          await output.exists() &&
          await output.length() > 0) {
        return;
      }
      _log.w(
        'Cover resize failed (${result.returnCode}): '
        '${FFmpegExecution.preview(result.output)}',
      );
      cause = 'FFmpeg exited with ${result.returnCode}';
    } on FFmpegMetadataFailure catch (error) {
      await FFmpegOutput.cleanup(outputPath);
      throw FFmpegMetadataFailure(error.message);
    } catch (e) {
      _log.w('Cover resize failed: $e');
      cause = '$e';
    }
    await FFmpegOutput.cleanup(outputPath);
    throw FFmpegMetadataFailure('Cover resize failed: $cause');
  }

  /// Runs one metadata command, turning a platform/execution failure into a
  /// cause the save result can report.
  static Future<FFmpegResult> _execute(
    List<String> arguments,
    String format, {
    Future<FFmpegResult> Function(List<String>)? execute,
  }) async {
    try {
      return await (execute ?? FFmpegExecution.arguments)(arguments);
    } catch (error) {
      _log.e('$format metadata command failed: $error');
      throw FFmpegMetadataFailure('$format metadata command failed: $error');
    }
  }

  static Future<String> _finish(
    FFmpegResult result,
    String tempOutput,
    String path,
    String format, {
    Future<bool> Function(String tempOutput)? beforePromote,
  }) async {
    if (!result.success) {
      await FFmpegOutput.cleanup(tempOutput);
      _log.e('$format Metadata/Cover embed failed: ${result.output}');
      throw FFmpegMetadataFailure(
        '$format metadata embed failed (exit ${result.returnCode})',
      );
    }
    if (beforePromote != null && !await beforePromote(tempOutput)) {
      await FFmpegOutput.cleanup(tempOutput);
      _log.e('$format metadata post-processing failed; keeping the original');
      throw FFmpegMetadataFailure('$format metadata post-processing failed');
    }
    final promoted = await FFmpegOutput.promote(
      tempOutput,
      path,
      onMissing: () =>
          _log.e('Temp $format output file not found: $tempOutput'),
      onError: (e) =>
          _log.e('Failed to replace $format file after metadata embed: $e'),
    );
    if (!promoted) {
      throw FFmpegMetadataFailure('Could not replace the $format file');
    }
    _log.d('$format metadata embedded successfully');
    return path;
  }

  static Future<String?> embedMetadataToOpus({
    required String opusPath,
    String? coverPath,
    Map<String, String>? metadata,
    bool preserveMetadata = false,
    Future<FFmpegResult> Function(List<String>)? execute,
  }) async {
    final tempOutput = await FFmpegOutput.tempPath('.opus');
    // Opus tags are on the audio stream. Copy to output globals, override the
    // selected values and let the muxer write globals into the output stream.
    final arguments = <String>[
      '-v',
      'error',
      '-hide_banner',
      '-i',
      opusPath,
      '-map',
      '0:a',
      '-map_metadata',
      preserveMetadata ? '0:s:a:0' : '-1',
      '-map_metadata:s:a',
      '-1',
      '-c:a',
      'copy',
    ];
    if (metadata != null) {
      AudioMetadataMapper.appendVorbisMetadataArguments(arguments, metadata);
    }
    if (coverPath != null) {
      try {
        final pictureBlock = await _createMetadataBlockPicture(coverPath);
        if (pictureBlock != null) {
          arguments.addAll([
            '-metadata',
            'METADATA_BLOCK_PICTURE=$pictureBlock',
          ]);
          _log.d(
            'Created METADATA_BLOCK_PICTURE for Opus (${pictureBlock.length} chars)',
          );
        } else {
          _log.w('Failed to create METADATA_BLOCK_PICTURE, skipping cover');
        }
      } catch (e) {
        _log.e('Error creating METADATA_BLOCK_PICTURE: $e');
      }
    }
    arguments.addAll([tempOutput, '-y']);
    _log.d('Executing FFmpeg Opus embed command');
    return _finish(
      await _execute(arguments, 'Opus', execute: execute),
      tempOutput,
      opusPath,
      'Opus',
    );
  }

  static Future<String?> _createMetadataBlockPicture(String imagePath) async {
    try {
      final result = await NativeDataJobs.run({
        'operation': 'build_metadata_picture',
        'file_path': imagePath,
      });
      return result['picture'] as String?;
    } on MissingPluginException {
      return Isolate.run(
        () => _createMetadataBlockPictureInBackground(imagePath),
      );
    } catch (e) {
      _log.e('Error creating METADATA_BLOCK_PICTURE: $e');
      return null;
    }
  }

  static Future<String?> _createMetadataBlockPictureInBackground(
    String imagePath,
  ) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        _log.e('Cover image not found: $imagePath');
        return null;
      }
      final data = await file.readAsBytes();
      final path = imagePath.toLowerCase();
      final pngSignature =
          data.length >= 8 &&
          data[0] == 0x89 &&
          data[1] == 0x50 &&
          data[2] == 0x4e &&
          data[3] == 0x47;
      final mime =
          path.endsWith('.png') ||
              (!path.endsWith('.jpg') &&
                  !path.endsWith('.jpeg') &&
                  pngSignature)
          ? 'image/png'
          : 'image/jpeg';
      final mimeBytes = utf8.encode(mime);
      // One allocation: type, MIME length/string, empty description, four zero
      // image properties, payload length and the original image bytes.
      final buffer = ByteData(32 + mimeBytes.length + data.length);
      final bytes = buffer.buffer.asUint8List();
      buffer.setUint32(0, 3, Endian.big);
      buffer.setUint32(4, mimeBytes.length, Endian.big);
      bytes.setRange(8, 8 + mimeBytes.length, mimeBytes);
      buffer.setUint32(28 + mimeBytes.length, data.length, Endian.big);
      bytes.setRange(32 + mimeBytes.length, bytes.length, data);
      return base64Encode(bytes);
    } catch (e) {
      _log.e('Error creating METADATA_BLOCK_PICTURE: $e');
      return null;
    }
  }
}
