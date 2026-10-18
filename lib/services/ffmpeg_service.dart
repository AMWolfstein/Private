import 'package:flutter/foundation.dart';
import 'package:spotiflac_android/services/ffmpeg_cue.dart';
import 'package:spotiflac_android/services/ffmpeg_decryption.dart';
import 'package:spotiflac_android/services/ffmpeg_metadata.dart';
import 'package:spotiflac_android/services/ffmpeg_models.dart';
import 'package:spotiflac_android/services/ffmpeg_probe.dart';
import 'package:spotiflac_android/services/ffmpeg_replaygain.dart';
import 'package:spotiflac_android/utils/artist_utils.dart';

export 'package:spotiflac_android/services/ffmpeg_models.dart';

/// Compatibility entry point for callers; feature modules own the operations.
class FFmpegService {
  @visibleForTesting
  static List<String> buildCoverResizeArguments({
    required String inputPath,
    required String outputPath,
    required int maxDimension,
  }) => FFmpegMetadata.buildCoverResizeArguments(
    inputPath: inputPath,
    outputPath: outputPath,
    maxDimension: maxDimension,
  );

  /// Preserves aspect ratio, allowing upscale to the explicitly chosen size.
  static Future<bool> resizeCoverArt({
    required String inputPath,
    required String outputPath,
    required int maxDimension,
  }) => FFmpegMetadata.resizeCoverArt(
    inputPath: inputPath,
    outputPath: outputPath,
    maxDimension: maxDimension,
  );

  @visibleForTesting
  static ({int width, int height})? imageDimensionsFromProperties(
    Map<dynamic, dynamic> properties,
  ) => FFmpegProbe.imageDimensionsFromProperties(properties);

  /// Reads image dimensions without decoding a bitmap into Dart memory.
  static Future<({int width, int height})?> probeImageDimensions(
    String filePath,
  ) => FFmpegProbe.imageDimensions(filePath);

  static Future<String?> decryptWithDescriptor({
    required String inputPath,
    required DownloadDecryptionDescriptor descriptor,
    bool deleteOriginal = true,
    Future<void> Function(String)? prepareOutput,
  }) => FFmpegDecryption.decrypt(
    inputPath: inputPath,
    descriptor: descriptor,
    deleteOriginal: deleteOriginal,
    prepareOutput: prepareOutput,
  );

  /// Measures EBU R128 loudness and true peak using a -18 LUFS reference.
  static Future<ReplayGainResult?> scanReplayGain(
    String filePath, {
    void Function()? onUnsupportedDecoder,
  }) => FFmpegReplayGain.scan(
    filePath,
    onUnsupportedDecoder: onUnsupportedDecoder,
  );

  @visibleForTesting
  static ReplayGainResult? parseReplayGainScan(
    FFmpegResult result, {
    void Function()? onUnsupportedDecoder,
  }) => FFmpegReplayGain.parseScan(
    result,
    onUnsupportedDecoder: onUnsupportedDecoder,
  );

  /// With [returnTempPath], hands temp output to [onTempReady] for SAF write and
  /// cleanup by the caller. Otherwise publishes to the local file.
  static Future<bool> writeAlbumReplayGainTags(
    String filePath,
    String albumGain,
    String albumPeak, {
    bool returnTempPath = false,
    void Function(String tempPath)? onTempReady,
  }) => FFmpegReplayGain.writeAlbumTags(
    filePath,
    albumGain,
    albumPeak,
    returnTempPath: returnTempPath,
    onTempReady: onTempReady,
  );

  static Future<bool> writeTrackReplayGainTags(
    String filePath,
    String trackGain,
    String trackPeak,
  ) => FFmpegReplayGain.writeTrackTags(filePath, trackGain, trackPeak);

  static Future<String?> embedMetadata({
    required String flacPath,
    String? coverPath,
    Map<String, String>? metadata,
    String artistTagMode = artistTagModeJoined,
  }) => FFmpegMetadata.embedMetadata(
    flacPath: flacPath,
    coverPath: coverPath,
    metadata: metadata,
    artistTagMode: artistTagMode,
  );

  static Future<String?> embedMetadataToMp3({
    required String mp3Path,
    String? coverPath,
    Map<String, String>? metadata,
    String artistTagMode = artistTagModeJoined,
    bool preserveMetadata = false,
  }) => FFmpegMetadata.embedMetadataToMp3(
    mp3Path: mp3Path,
    coverPath: coverPath,
    metadata: metadata,
    artistTagMode: artistTagMode,
    preserveMetadata: preserveMetadata,
  );

  static Future<String?> embedMetadataToOpus({
    required String opusPath,
    String? coverPath,
    Map<String, String>? metadata,
    String artistTagMode = artistTagModeJoined,
    bool preserveMetadata = false,
    @visibleForTesting Future<FFmpegResult> Function(List<String>)? execute,
  }) => FFmpegMetadata.embedMetadataToOpus(
    opusPath: opusPath,
    coverPath: coverPath,
    metadata: metadata,
    artistTagMode: artistTagMode,
    preserveMetadata: preserveMetadata,
    execute: execute,
  );

  static Future<String?> embedMetadataToM4a({
    required String m4aPath,
    String? coverPath,
    Map<String, String>? metadata,
    String artistTagMode = artistTagModeJoined,
    bool preserveMetadata = true,
  }) => FFmpegMetadata.embedMetadataToM4a(
    m4aPath: m4aPath,
    coverPath: coverPath,
    metadata: metadata,
    artistTagMode: artistTagMode,
    preserveMetadata: preserveMetadata,
  );

  static Future<List<String>?> splitCueToTracks({
    required String audioPath,
    required String outputDir,
    required List<CueSplitTrackInfo> tracks,
    required Map<String, String> albumMetadata,
    String? coverPath,
    void Function(int current, int total)? onProgress,
  }) => FFmpegCue.splitCueToTracks(
    audioPath: audioPath,
    outputDir: outputDir,
    tracks: tracks,
    albumMetadata: albumMetadata,
    coverPath: coverPath,
    onProgress: onProgress,
  );
}
