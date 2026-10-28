import 'package:sistrum/utils/int_utils.dart';
import 'package:sistrum/utils/string_utils.dart';

/// Audio format/quality helpers shared by the library scan and metadata
/// readers.
Map<String, dynamic> normalizeScannedAudioMetadata(
  Map<String, dynamic> metadata,
) {
  dynamic firstValue(String snakeCase, String camelCase) {
    final snakeValue = metadata[snakeCase];
    return snakeValue ?? metadata[camelCase];
  }

  final normalized = <String, dynamic>{...metadata};
  final metadataFromFilename = metadata['metadataFromFilename'] == true;

  // readAudioMetadata uses the LibraryScanResult contract. Automatic metadata
  // probes use the same snake_case keys as readFileMetadata so callers can use
  // the cheaper SAF file-descriptor path without knowing which backend result
  // shape was returned.
  if (!metadataFromFilename) {
    normalized['title'] = firstValue('title', 'trackName');
    normalized['artist'] = firstValue('artist', 'artistName');
    normalized['album'] = firstValue('album', 'albumName');
  }
  normalized['album_artist'] = firstValue('album_artist', 'albumArtist');
  normalized['date'] = firstValue('date', 'releaseDate');
  normalized['track_number'] = firstValue('track_number', 'trackNumber');
  normalized['total_tracks'] = firstValue('total_tracks', 'totalTracks');
  normalized['disc_number'] = firstValue('disc_number', 'discNumber');
  normalized['total_discs'] = firstValue('total_discs', 'totalDiscs');
  normalized['bit_depth'] = firstValue('bit_depth', 'bitDepth');
  normalized['sample_rate'] = firstValue('sample_rate', 'sampleRate');
  normalized['album_type'] = firstValue('album_type', 'albumType');
  normalized['upc'] = firstValue('upc', 'barcode');
  normalized['comment'] = metadata['comment'];
  normalized['explicit'] = metadata['explicit'];
  normalized['audio_codec'] =
      firstValue('audio_codec', 'audioCodec') ?? metadata['format'];
  return normalized;
}

/// Whether scanned or probed tags carry a usable ReplayGain value. Library scans
/// and readFileMetadata both use the snake_case `replaygain_*` keys; persisted
/// rows round-trip through `hasReplayGain`.
bool metadataHasReplayGain(Map<String, dynamic> metadata) {
  final stored = metadata['hasReplayGain'];
  if (stored == true || stored == 1) return true;
  for (final key in const ['replaygain_track_gain', 'replaygain_album_gain']) {
    final value = metadata[key];
    final gain = double.tryParse(
      (value?.toString() ?? '')
          .replaceFirst(RegExp(r'\s*dB\s*$', caseSensitive: false), '')
          .trim(),
    );
    if (gain != null && gain.isFinite) return true;
  }
  return false;
}

int? readPositiveBitrateKbps(dynamic value) {
  final parsed = readPositiveInt(value);
  if (parsed == null) return null;
  final kbps = parsed >= 10000 ? (parsed / 1000).round() : parsed;
  return kbps >= 16 ? kbps : null;
}

String? audioFormatForPath(String? filePath, {String? fileName}) {
  final candidates = <String>[?filePath, ?fileName];
  for (final candidate in candidates) {
    final lower = candidate.trim().toLowerCase();
    if (lower.endsWith('.flac')) return 'FLAC';
    if (lower.endsWith('.alac')) return 'ALAC';
    if (lower.endsWith('.wav')) return 'WAV';
    if (lower.endsWith('.aiff') || lower.endsWith('.aif')) return 'AIFF';
    if (lower.endsWith('.opus') || lower.endsWith('.ogg')) return 'OPUS';
    if (lower.endsWith('.mp3')) return 'MP3';
    if (lower.endsWith('.aac')) return 'AAC';
    if (lower.endsWith('.m4a') || lower.endsWith('.mp4')) return 'M4A';
  }
  return null;
}

String? nonPlaceholderQuality(String? quality) {
  final normalized = normalizeOptionalString(quality);
  if (normalized == null || isPlaceholderQualityLabel(normalized)) {
    return null;
  }
  final bitrateMatch = RegExp(
    r'\b(\d+)\s*kbps\b',
    caseSensitive: false,
  ).firstMatch(normalized);
  if (bitrateMatch != null) {
    final bitrate = int.tryParse(bitrateMatch.group(1) ?? '');
    if (bitrate != null && bitrate < 16) return null;
  }
  final lower = normalized.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  const requestedLosslessLabels = {
    'hi_res_lossless',
    'hires_lossless',
    'hi_res',
    'hires',
    'flac_best_available',
  };
  if (requestedLosslessLabels.contains(lower)) return null;
  return normalized;
}

String? normalizeAudioFormatValue(String? value) {
  final normalized = normalizeOptionalString(
    value,
  )?.toLowerCase().replaceAll('-', '_');
  return switch (normalized) {
    'flac' => 'flac',
    'alac' => 'alac',
    'wav' || 'wave' => 'wav',
    'aiff' || 'aif' || 'aifc' => 'aiff',
    'aac' || 'mp4a' => 'aac',
    'eac3' || 'ec_3' => 'eac3',
    'ac3' || 'ac_3' => 'ac3',
    'ac4' || 'ac_4' => 'ac4',
    'mp3' => 'mp3',
    'opus' || 'ogg' => 'opus',
    'm4a' || 'mp4' => 'm4a',
    _ => null,
  };
}

bool isLossyAudioFormat(String? value) {
  return const {
    'aac',
    'eac3',
    'ac3',
    'ac4',
    'mp3',
    'opus',
    'm4a',
  }.contains(normalizeAudioFormatValue(value));
}

/// Returns a provider-independent quality label suitable for a filename.
///
/// Requested labels such as LOSSLESS and HI_RES are intentionally ignored:
/// they describe provider intent, not the audio that was actually written.
String? buildQualityVariantFilenameLabel({
  String? detectedFormat,
  int? bitDepth,
  int? sampleRate,
  int? bitrateKbps,
  String? measuredQuality,
}) {
  if (isLossyAudioFormat(detectedFormat)) {
    final effectiveBitrate =
        bitrateKbps ?? _bitrateFromQuality(measuredQuality);
    return effectiveBitrate != null && effectiveBitrate >= 16
        ? '${effectiveBitrate}kbps'
        : null;
  }

  final measured = _losslessSpecsFromQuality(measuredQuality);
  final effectiveBitDepth = bitDepth ?? measured?.$1;
  final effectiveSampleRate = sampleRate ?? measured?.$2;
  if (effectiveBitDepth == null ||
      effectiveBitDepth <= 0 ||
      effectiveSampleRate == null ||
      effectiveSampleRate <= 0) {
    return null;
  }
  return '${effectiveBitDepth}bit-${formatSampleRateKHz(effectiveSampleRate)}';
}

int? _bitrateFromQuality(String? quality) {
  final match = RegExp(
    r'\b(\d+)\s*kbps\b',
    caseSensitive: false,
  ).firstMatch(quality ?? '');
  final value = int.tryParse(match?.group(1) ?? '');
  return value != null && value >= 16 ? value : null;
}

(int, int)? _losslessSpecsFromQuality(String? quality) {
  final match = RegExp(
    r'\b(\d+)\s*(?:-|\s)?bit\s*[/_-]\s*(\d+(?:\.\d+)?)\s*k?hz\b',
    caseSensitive: false,
  ).firstMatch(quality ?? '');
  final bitDepth = int.tryParse(match?.group(1) ?? '');
  final rate = double.tryParse(match?.group(2) ?? '');
  if (bitDepth == null || bitDepth <= 0 || rate == null || rate <= 0) {
    return null;
  }
  final sampleRate = rate < 1000 ? (rate * 1000).round() : rate.round();
  return (bitDepth, sampleRate);
}
