import 'package:sistrum/utils/string_utils.dart';

/// Audio format/quality helpers shared by the library scan and metadata
/// readers.
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
