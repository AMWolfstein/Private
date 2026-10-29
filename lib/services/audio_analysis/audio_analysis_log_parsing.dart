import 'dart:math' as math;

class AudioAstatsSummary {
  final double peakDb;
  final double rmsDb;

  const AudioAstatsSummary({required this.peakDb, required this.rmsDb});
}

class AudioAnalysisMetadataSummary extends AudioAstatsSummary {
  final double? integratedLufs;
  final double? truePeakDb;
  final List<ChannelAnalysisStats> channelStats;

  const AudioAnalysisMetadataSummary({
    required super.peakDb,
    required super.rmsDb,
    this.integratedLufs,
    this.truePeakDb,
    this.channelStats = const [],
  });
}

AudioAstatsSummary? parseAudioAstatsSummary(String logs) {
  final overallMatch = RegExp(r'Overall([\s\S]*)').firstMatch(logs);
  final section = overallMatch?.group(1) ?? logs;
  final peak = parseLastAudioAstatsValue(section, 'Peak level dB');
  final rms = parseLastAudioAstatsValue(section, 'RMS level dB');
  if (peak == null || rms == null) return null;
  return AudioAstatsSummary(peakDb: peak, rmsDb: rms);
}

double? parseLastAudioAstatsValue(String text, String label) {
  final matches = RegExp(
    '${RegExp.escape(label)}:\\s*([-+]?\\d+(?:\\.\\d+)?)',
    caseSensitive: false,
  ).allMatches(text);
  double? value;
  for (final match in matches) {
    final parsed = double.tryParse(match.group(1) ?? '');
    if (parsed != null && parsed.isFinite) {
      value = parsed;
    }
  }
  return value;
}

AudioAnalysisMetadataSummary? parseAudioAnalysisMetadata(String metadata) {
  final peak = _parseLastMetadataValue(
    metadata,
    'lavfi.astats.Overall.Peak_level',
  );
  final rms = _parseLastMetadataValue(
    metadata,
    'lavfi.astats.Overall.RMS_level',
  );
  if (peak == null || rms == null) return null;

  final channelNumbers = RegExp(
    r'^lavfi\.astats\.(\d+)\.',
    multiLine: true,
  ).allMatches(metadata).map((match) => int.parse(match.group(1)!)).toSet();
  final channelStats = channelNumbers.toList()..sort();

  final truePeakLinear = _parseLastMetadataValue(
    metadata,
    'lavfi.r128.true_peak',
  );
  return AudioAnalysisMetadataSummary(
    peakDb: peak,
    rmsDb: rms,
    integratedLufs: _parseLastMetadataValue(metadata, 'lavfi.r128.I'),
    truePeakDb: truePeakLinear != null && truePeakLinear > 0
        ? 20 * math.log(truePeakLinear) / math.ln10
        : null,
    channelStats: channelStats.map((channel) {
      final channelPeak = _parseLastMetadataValue(
        metadata,
        'lavfi.astats.$channel.Peak_level',
      );
      final channelRms = _parseLastMetadataValue(
        metadata,
        'lavfi.astats.$channel.RMS_level',
      );
      return ChannelAnalysisStats(
        channel: channel,
        peakDb: channelPeak,
        rmsDb: channelRms,
        dynamicRangeDb: channelPeak != null && channelRms != null
            ? channelPeak - channelRms
            : null,
        peakCount:
            _parseLastMetadataValue(
              metadata,
              'lavfi.astats.$channel.Peak_count',
            )?.round() ??
            0,
      );
    }).toList(),
  );
}

double? _parseLastMetadataValue(String metadata, String key) {
  final matches = RegExp(
    '^${RegExp.escape(key)}=([^\\r\\n]+)',
    multiLine: true,
  ).allMatches(metadata);
  double? value;
  for (final match in matches) {
    final parsed = double.tryParse(match.group(1)?.trim() ?? '');
    if (parsed != null && parsed.isFinite) value = parsed;
  }
  return value;
}

class ChannelAnalysisStats {
  final int channel;
  final double? peakDb;
  final double? rmsDb;
  final double? dynamicRangeDb;
  final int peakCount;

  const ChannelAnalysisStats({
    required this.channel,
    this.peakDb,
    this.rmsDb,
    this.dynamicRangeDb,
    this.peakCount = 0,
  });

  Map<String, dynamic> toJson() => {
    'channel': channel,
    'peakDb': peakDb,
    'rmsDb': rmsDb,
    'dynamicRangeDb': dynamicRangeDb,
    'peakCount': peakCount,
  };

  factory ChannelAnalysisStats.fromJson(Map<dynamic, dynamic> json) {
    return ChannelAnalysisStats(
      channel: (json['channel'] as num?)?.toInt() ?? 0,
      peakDb: (json['peakDb'] as num?)?.toDouble(),
      rmsDb: (json['rmsDb'] as num?)?.toDouble(),
      dynamicRangeDb: (json['dynamicRangeDb'] as num?)?.toDouble(),
      peakCount: (json['peakCount'] as num?)?.toInt() ?? 0,
    );
  }
}

List<ChannelAnalysisStats> parseAudioAnalysisChannelStats(String logs) {
  final stats = <ChannelAnalysisStats>[];
  final channelMatches = RegExp(
    r'Channel:\s*(\d+)([\s\S]*?)(?=Channel:\s*\d+|Overall|$)',
    caseSensitive: false,
  ).allMatches(logs);

  for (final match in channelMatches) {
    final channel = int.tryParse(match.group(1) ?? '') ?? 0;
    final section = match.group(2) ?? '';
    if (channel <= 0 || section.trim().isEmpty) continue;
    final peakDb = parseLastAudioAstatsValue(section, 'Peak level dB');
    final rmsDb = parseLastAudioAstatsValue(section, 'RMS level dB');
    stats.add(
      ChannelAnalysisStats(
        channel: channel,
        peakDb: peakDb,
        rmsDb: rmsDb,
        dynamicRangeDb: peakDb != null && rmsDb != null ? peakDb - rmsDb : null,
        peakCount:
            parseLastAudioAstatsInt(section, 'Peak count') ??
            parseLastAudioAstatsInt(section, 'Peak count ch') ??
            0,
      ),
    );
  }

  return stats;
}

int? parseLastAudioAstatsInt(String text, String label) {
  final matches = RegExp(
    '${RegExp.escape(label)}:\\s*(\\d+)',
    caseSensitive: false,
  ).allMatches(text);
  int? value;
  for (final match in matches) {
    value = int.tryParse(match.group(1) ?? '') ?? value;
  }
  return value;
}
