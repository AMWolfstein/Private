import 'package:sistrum/utils/playback/audio_format_utils.dart';
import 'package:sistrum/utils/text/string_utils.dart';

String? _libraryFileFormatLabel(String? format) {
  final rawFormat = normalizeOptionalString(format);
  if (rawFormat == null) return null;

  return switch (normalizeAudioFormatValue(rawFormat)) {
    'flac' => 'FLAC',
    'alac' => 'ALAC',
    'wav' => 'WAV',
    'aiff' => 'AIFF',
    'aac' => 'AAC',
    'eac3' => 'EAC3',
    'ac3' => 'AC3',
    'ac4' => 'AC4',
    'mp3' => 'MP3',
    'opus' => 'OPUS',
    'm4a' => 'M4A',
    _ => rawFormat.replaceFirst(RegExp(r'^\.'), '').toUpperCase(),
  };
}

/// Builds the standard Library label from measured/stored bitrate metadata.
/// Legacy lossy files without a bitrate retain their detected codec label.
String? buildLibraryAudioQualityLabel({
  String? format,
  String? filePath,
  String? fileName,
  int? bitrateKbps,
  String? storedQuality,
}) {
  final effectiveFormat =
      normalizeOptionalString(format) ??
      audioFormatForPath(filePath, fileName: fileName);
  final stored = normalizeOptionalString(storedQuality);
  final storedBitrate = _bitrateFromStoredQuality(stored);
  final effectiveBitrate = bitrateKbps != null && bitrateKbps > 0
      ? bitrateKbps
      : storedBitrate;
  final bitrateLabel = effectiveBitrate != null
      ? buildDisplayAudioQuality(
          bitrateKbps: effectiveBitrate,
          format: effectiveFormat,
        )
      : null;
  if (isLossyAudioFormat(effectiveFormat)) {
    // Older rows may know the codec before their bitrate has been backfilled.
    // Keep a useful badge without showing stale lossless specs or inventing a
    // bitrate from the user's current download/conversion setting.
    return bitrateLabel ?? _libraryFileFormatLabel(effectiveFormat);
  }

  return bitrateLabel;
}

int? _bitrateFromStoredQuality(String? quality) {
  final match = RegExp(
    r'\b(\d+(?:\.\d+)?)\s*(k(?:bps)?|mbps)\b',
    caseSensitive: false,
  ).firstMatch(quality ?? '');
  final value = double.tryParse(match?.group(1) ?? '');
  if (value == null || value <= 0) return null;
  final unit = match?.group(2)?.toLowerCase();
  return unit == 'mbps' ? (value * 1000).round() : value.round();
}
