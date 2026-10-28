import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:sistrum/services/audio_metadata_mapper.dart';
import 'package:sistrum/services/ffmpeg_models.dart';
import 'package:sistrum/services/ffmpeg_support.dart';
import 'package:sistrum/services/id3v23_lyrics.dart';
import 'package:sistrum/services/platform_bridge.dart';
import 'package:sistrum/utils/logger.dart';

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

  static Future<bool> resizeCoverArt({
    required String inputPath,
    required String outputPath,
    required int maxDimension,
  }) async {
    try {
      if (!await File(inputPath).exists()) return false;
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
        return true;
      }
      _log.w(
        'Cover resize failed (${result.returnCode}): '
        '${FFmpegExecution.preview(result.output)}',
      );
    } catch (e) {
      _log.w('Cover resize failed: $e');
    }
    await FFmpegOutput.cleanup(outputPath);
    return false;
  }

  static void appendCoverInputArguments(
    List<String> arguments, {
    String map = '1:v',
    String disposition = '-disposition:v:0',
  }) => arguments.addAll([
    '-map',
    map,
    '-c:v',
    'copy',
    disposition,
    'attached_pic',
    '-metadata:s:v',
    'title=Album cover',
    '-metadata:s:v',
    'comment=Cover (front)',
  ]);

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

  static Future<String?> embedMetadataToMp3({
    required String mp3Path,
    String? coverPath,
    Map<String, String>? metadata,
    bool preserveMetadata = false,
  }) async {
    // ID3 keeps one artist frame: only primary mode changes its value.
    if (preserveMetadata) {
      // A remux cannot round-trip unknown ID3 frames after the native writer
      // refuses them. Keep the source rather than bypassing that safety check.
      _log.e('MP3 metadata preservation requires the native tag writer');
      return null;
    }
    final tempOutput = await FFmpegOutput.tempPath('.mp3');
    final lyrics = AudioMetadataMapper.extractLyricsForId3(metadata);
    final result = await _runMp3Embed(
      mp3Path: mp3Path,
      tempOutput: tempOutput,
      coverPath: coverPath,
      metadata: metadata,
      preserveMetadata: preserveMetadata,
    );
    final embeddedPath = await _finish(result, tempOutput, mp3Path, 'MP3');
    if (lyrics != null) {
      await _ensureMp3UnsyncedLyricsFrame(embeddedPath, lyrics);
    }
    return embeddedPath;
  }

  static Future<FFmpegResult> _runMp3Embed({
    required String mp3Path,
    required String tempOutput,
    String? coverPath,
    Map<String, String>? metadata,
    required bool preserveMetadata,
  }) async {
    final arguments = buildMp3EmbedArguments(
      mp3Path: mp3Path,
      tempOutput: tempOutput,
      coverPath: coverPath,
      metadata: metadata,
      preserveMetadata: preserveMetadata,
    );
    _log.d('Executing FFmpeg MP3 embed command');
    return _execute(arguments, 'MP3');
  }

  /// MP3 edits always stream-copy the audio. Re-encoding a tag-only edit
  /// silently replaced the user's file with a lossy 192 kbps copy.
  static List<String> buildMp3EmbedArguments({
    required String mp3Path,
    required String tempOutput,
    String? coverPath,
    Map<String, String>? metadata,
    required bool preserveMetadata,
  }) {
    final arguments = <String>['-v', 'error', '-hide_banner', '-i', mp3Path];
    if (coverPath != null) arguments.addAll(['-i', coverPath]);
    arguments.addAll([
      '-map',
      '0:a',
      '-map_metadata',
      preserveMetadata ? '0' : '-1',
    ]);
    if (coverPath != null) {
      arguments.addAll([
        '-map',
        '1:0',
        '-c:v:0',
        'copy',
        '-id3v2_version',
        '3',
        '-metadata:s:v',
        'title=Album cover',
        '-metadata:s:v',
        'comment=Cover (front)',
      ]);
    }
    arguments.addAll(['-c:a', 'copy']);
    if (metadata != null) {
      AudioMetadataMapper.appendMappedMetadataArguments(
        arguments,
        AudioMetadataMapper.convertToId3Tags(metadata),
      );
    }
    arguments.addAll(['-id3v2_version', '3', tempOutput, '-y']);
    return arguments;
  }

  static Future<void> _ensureMp3UnsyncedLyricsFrame(
    String path,
    String lyrics,
  ) async {
    try {
      final file = File(path);
      if (!await file.exists()) return;
      if (!await Id3v23Lyrics.writeUnsyncedLyricsToFile(file, lyrics)) {
        _log.w('Skipping MP3 USLT lyrics frame update: unsupported ID3 tag');
        return;
      }
      _log.d('MP3 USLT lyrics frame written (${lyrics.length} chars)');
    } catch (e) {
      _log.w('Failed to write MP3 USLT lyrics frame: $e');
    }
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

  static Future<String?> embedMetadataToM4a({
    required String m4aPath,
    String? coverPath,
    Map<String, String>? metadata,
    bool preserveMetadata = true,
  }) async {
    if (preserveMetadata) {
      // FFmpeg drops unknown freeform atoms even with metadata copying. Local
      // edits must keep the original if the atom-preserving native edit fails.
      _log.e('M4A metadata preservation requires the native tag writer');
      return null;
    }
    final tempOutput = await FFmpegOutput.tempPath('.m4a');
    final normalizedCoverPath = coverPath?.trim();
    final hasCover =
        normalizedCoverPath != null &&
        normalizedCoverPath.isNotEmpty &&
        await File(normalizedCoverPath).exists();
    final preserveExistingStreams = preserveMetadata && !hasCover;
    List<String> buildArgs(bool forceMov) {
      final arguments = <String>['-v', 'error', '-hide_banner', '-i', m4aPath];
      if (hasCover) arguments.addAll(['-i', normalizedCoverPath]);
      // Preserve attached artwork when no replacement cover is supplied.
      arguments.addAll(
        preserveExistingStreams
            ? ['-map', '0', '-c', 'copy']
            : ['-map', '0:a', '-c:a', 'copy'],
      );
      arguments.addAll(['-map_metadata', preserveMetadata ? '0' : '-1']);
      if (hasCover) appendCoverInputArguments(arguments);
      if (metadata != null) {
        AudioMetadataMapper.appendMappedMetadataArguments(
          arguments,
          AudioMetadataMapper.convertToM4aTags(metadata),
        );
      }
      // The default .m4a (ipod) muxer rejects FLAC. MP4 supports FLAC and
      // writes artwork as covr atoms, including artwork copied from the input.
      if (forceMov) {
        arguments.addAll(['-f', 'mov']);
      } else {
        // Older FFmpeg builds require experimental compliance for FLAC in MP4.
        arguments.addAll(['-f', 'mp4', '-strict', 'experimental']);
      }
      return arguments..addAll([tempOutput, '-y']);
    }

    _log.d('Executing FFmpeg M4A embed command');
    var result = await _execute(buildArgs(false), 'M4A');
    // MOV supports some codecs MP4 rejects (for example AC-4). Other
    // failures keep their original error instead of trying MOV, which
    // cannot carry FLAC even with experimental compliance enabled.
    if (!result.success &&
        result.output.contains('codec not currently supported in container')) {
      _log.w(
        'M4A embed codec rejected by MP4, retrying with mov muxer: '
        '${FFmpegExecution.preview(result.output)}',
      );
      await FFmpegOutput.cleanup(tempOutput);
      result = await _execute(buildArgs(true), 'M4A');
    }
    final metadataTags = metadata;
    final embedded = await _finish(
      result,
      tempOutput,
      m4aPath,
      'M4A',
      beforePromote: metadataTags == null
          ? null
          : (temp) async {
              if (!await writeM4AFreeformTags(temp, metadataTags)) return false;
              return writeM4AReleaseIdentityTags(temp, metadataTags);
            },
    );
    return embedded;
  }

  static Future<String?> _createMetadataBlockPicture(String imagePath) async {
    try {
      final result = await PlatformBridge.runNativeDataJob({
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

  static Future<bool> writeM4AFreeformTags(
    String path,
    Map<String, String> metadata,
  ) async {
    final fields = <String, String>{};
    for (final entry in metadata.entries) {
      final key = entry.key.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
      switch (key) {
        case 'ISRC':
          fields['isrc'] = entry.value;
          break;
        case 'LABEL':
        case 'ORGANIZATION':
          fields['label'] = entry.value;
          break;
      }
    }
    if (fields.isEmpty) return true;
    try {
      final result = await PlatformBridge.writeM4AFreeformTags(path, fields);
      if (result['error'] != null) {
        _log.w('writeM4AFreeformTags was not completed for $path');
        return false;
      }
      return true;
    } catch (e) {
      _log.w('writeM4AFreeformTags failed for $path: $e');
      return false;
    }
  }

  static Future<bool> writeM4AReleaseIdentityTags(
    String path,
    Map<String, String> metadata,
  ) async {
    final fields = AudioMetadataMapper.m4aReleaseIdentityFields(metadata);
    if (fields.isEmpty) return true;
    try {
      final result = await PlatformBridge.editFileMetadata(path, fields);
      if (result['error'] != null || result['method'] != 'native_m4a') {
        _log.w('Native M4A release identity write was not completed for $path');
        return false;
      }
      return true;
    } catch (e) {
      _log.w('M4A release identity write failed for $path: $e');
      return false;
    }
  }
}
