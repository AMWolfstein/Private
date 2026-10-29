export 'audio_analysis_ffmpeg_args.dart';
export 'audio_analysis_log_parsing.dart';
export 'audio_analysis_spectral_cutoff.dart';

String formatAudioAnalysisSpectralCutoff(
  double? cutoffHz, {
  required String notDetectedLabel,
}) {
  if (cutoffHz == null || !cutoffHz.isFinite || cutoffHz <= 0) {
    return notDetectedLabel;
  }
  if (cutoffHz >= 1000) {
    return '${(cutoffHz / 1000).toStringAsFixed(1)} kHz';
  }
  return '${cutoffHz.round()} Hz';
}

final RegExp _ac4CodecTokenPattern = RegExp(
  r'(^|[^a-z0-9])ac[\s_-]?4($|[^a-z0-9])',
  caseSensitive: false,
);

/// Returns whether the bundled FFmpeg decoder can analyze this audio codec.
/// Container formats such as MP4 are intentionally not used here because the
/// same container may hold supported AAC/ALAC/E-AC-3 or unsupported AC-4.
bool isAudioAnalysisCodecSupported(String? codecName) {
  final value = codecName?.trim() ?? '';
  if (value.isEmpty) return true;
  return !_ac4CodecTokenPattern.hasMatch(value);
}

String? unsupportedAudioAnalysisCodecLabel(String? codecName) =>
    isAudioAnalysisCodecSupported(codecName) ? null : 'AC-4';

class UnsupportedAudioAnalysisCodecException implements Exception {
  final String codecLabel;

  const UnsupportedAudioAnalysisCodecException(this.codecLabel);
}

int estimateAudioTotalSamples({
  required Map<dynamic, dynamic> props,
  required double duration,
  required int sampleRate,
  required int channels,
}) {
  final nbSamples = int.tryParse(props['nb_samples']?.toString() ?? '');
  if (nbSamples != null && nbSamples > 0) {
    return nbSamples;
  }

  final durationTs = int.tryParse(props['duration_ts']?.toString() ?? '');
  final timeBase = props['time_base']?.toString() ?? '';
  if (durationTs != null && durationTs > 0 && timeBase.contains('/')) {
    final parts = timeBase.split('/');
    final numerator = double.tryParse(parts[0]);
    final denominator = double.tryParse(parts[1]);
    if (numerator != null &&
        numerator > 0 &&
        denominator != null &&
        denominator > 0 &&
        sampleRate > 0) {
      final seconds = durationTs * numerator / denominator;
      return (seconds * sampleRate).round();
    }
  }

  if (duration > 0 && sampleRate > 0) {
    return (duration * sampleRate).round();
  }
  return 0;
}

bool audioCodecHasStoredBitDepth(String codecName) {
  if (codecName.isEmpty) return false;
  return codecName == 'flac' ||
      codecName == 'alac' ||
      codecName == 'wavpack' ||
      codecName == 'ape' ||
      codecName == 'tta' ||
      codecName.startsWith('pcm_');
}

String normalizeAudioAnalysisLabel(String value) {
  final trimmed = value.trim();
  final lower = trimmed.toLowerCase();
  if (lower.isEmpty || lower == 'unknown' || lower == 'n/a') return '';
  return trimmed;
}

String formatAudioCodecLabel(String codecName, String codecLongName) {
  final name = codecName.trim();
  final longName = normalizeAudioAnalysisLabel(codecLongName);
  if (name.isEmpty) return longName;
  if (longName.isEmpty || longName.toLowerCase() == name.toLowerCase()) {
    return name.toUpperCase();
  }
  return '${name.toUpperCase()} ($longName)';
}

String formatAudioContainerLabel(String formatName, String formatLongName) {
  final longName = normalizeAudioAnalysisLabel(formatLongName);
  if (longName.isNotEmpty) return longName;
  final name = formatName.trim();
  return name.isEmpty ? '' : name.toUpperCase();
}
