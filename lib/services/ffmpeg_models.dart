class CueSplitTrackInfo {
  final int number;
  final String title;
  final String artist;
  final String isrc;
  final String composer;
  final double startSec;
  final double endSec;

  CueSplitTrackInfo({
    required this.number,
    required this.title,
    required this.artist,
    this.isrc = '',
    this.composer = '',
    required this.startSec,
    required this.endSec,
  });

  factory CueSplitTrackInfo.fromJson(Map<String, dynamic> json) {
    return CueSplitTrackInfo(
      number: json['number'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      isrc: json['isrc'] as String? ?? '',
      composer: json['composer'] as String? ?? '',
      startSec: (json['start_sec'] as num?)?.toDouble() ?? 0.0,
      endSec: (json['end_sec'] as num?)?.toDouble() ?? -1.0,
    );
  }
}

class FFmpegResult {
  final bool success;
  final int returnCode;
  final String output;

  FFmpegResult({
    required this.success,
    required this.returnCode,
    required this.output,
  });
}

/// Result of an EBU R128 loudness scan, used to compute ReplayGain tags.
class ReplayGainResult {
  /// Track gain in dB, e.g. "-6.50 dB".
  final String trackGain;

  /// Track peak as a linear ratio, e.g. "0.988831".
  final String trackPeak;

  /// Raw integrated loudness in LUFS (needed for album gain computation).
  final double integratedLufs;

  /// Raw true peak as linear ratio (needed for album peak computation).
  final double truePeakLinear;

  const ReplayGainResult({
    required this.trackGain,
    required this.trackPeak,
    required this.integratedLufs,
    required this.truePeakLinear,
  });

  @override
  String toString() =>
      'ReplayGainResult(trackGain: $trackGain, trackPeak: $trackPeak)';
}
