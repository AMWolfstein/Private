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
