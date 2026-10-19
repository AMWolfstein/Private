import 'package:spotiflac_android/utils/audio_format_utils.dart';
import 'package:spotiflac_android/utils/string_utils.dart';

const highQualityBadgeBitrateThresholdKbps = 900;

final RegExp _bitDepthQualityPattern = RegExp(
  r'\b\d+\s*(?:-\s*)?bit\b',
  caseSensitive: false,
);

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

/// Keeps detailed bit-depth labels intact in Library grid badges while
/// shortening bitrate-only labels that already include a codec name.
String formatLibraryGridAudioQualityLabel(String quality) {
  final normalized = quality.trim().toLowerCase();
  if (_bitDepthQualityPattern.hasMatch(normalized)) return quality;

  final bitrateTextMatch = RegExp(
    r'(\d+)\s*k(?:bps)?',
    caseSensitive: false,
  ).firstMatch(quality);
  if (bitrateTextMatch != null) {
    return '${bitrateTextMatch.group(1)}k';
  }

  final bitrateIdMatch = RegExp(r'_(\d+)$').firstMatch(normalized);
  if (bitrateIdMatch != null) {
    return '${bitrateIdMatch.group(1)}k';
  }

  return quality.split(' ').first;
}

bool isDetailedLibraryAudioQualityLabel(String quality) {
  final normalized = quality.trim().toLowerCase();
  return _bitDepthQualityPattern.hasMatch(normalized) &&
      normalized.contains('/');
}

/// Preserves the highlighted color used by legacy 24-bit Library badges while
/// also supporting newer labels that display a measured bitrate instead.
bool shouldHighlightAudioQualityBadge(String quality) {
  final normalized = quality.trim().toLowerCase();
  if (RegExp(r'\b24(?:\s*[- ]?\s*bit|/)').hasMatch(normalized)) {
    return true;
  }

  final kbpsMatch = RegExp(
    r'\b(\d+(?:\.\d+)?)\s*k(?:bps)?\b',
  ).firstMatch(normalized);
  final kbps = double.tryParse(kbpsMatch?.group(1) ?? '');
  if (kbps != null) {
    return kbps > highQualityBadgeBitrateThresholdKbps;
  }

  final mbpsMatch = RegExp(
    r'\b(\d+(?:\.\d+)?)\s*mbps\b',
  ).firstMatch(normalized);
  final mbps = double.tryParse(mbpsMatch?.group(1) ?? '');
  return mbps != null && mbps * 1000 > highQualityBadgeBitrateThresholdKbps;
}
