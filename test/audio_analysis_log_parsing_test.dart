import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/audio_analysis/audio_analysis_log_parsing.dart';

const _astatsLog = '''
Channel: 1
Peak level dB: -2.5
RMS level dB: -14.0
Peak count: 3
Channel: 2
Peak level dB: -1.0
RMS level dB: -12.0
Peak count: 0
Overall
Peak level dB: -1.0
RMS level dB: -13.0
''';

const _metadata = '''
lavfi.astats.Overall.Peak_level=-1.5
lavfi.astats.Overall.RMS_level=-13.25
lavfi.r128.I=-9.8
lavfi.r128.true_peak=0.5
lavfi.astats.1.Peak_level=-2
lavfi.astats.1.RMS_level=-14
lavfi.astats.1.Peak_count=4
lavfi.astats.2.Peak_level=-1
lavfi.astats.2.RMS_level=-12
lavfi.astats.2.Peak_count=0
''';

void main() {
  test('the overall astats summary reads the final Overall section', () {
    final summary = parseAudioAstatsSummary(_astatsLog);
    expect(summary?.peakDb, -1.0);
    expect(summary?.rmsDb, -13.0);
  });

  test('an astats log without an Overall section gives no summary', () {
    expect(parseAudioAstatsSummary('Peak level dB: -3'), isNull);
  });

  test('the last value of a label wins over earlier ones', () {
    expect(
      parseLastAudioAstatsValue(
        'Peak level dB: -5\nPeak level dB: -2',
        'Peak level dB',
      ),
      -2,
    );
  });

  test('a non-finite value is ignored', () {
    expect(
      parseLastAudioAstatsValue('RMS level dB: NaN', 'RMS level dB'),
      isNull,
    );
  });

  test('channel sections are parsed with their peak count', () {
    final channels = parseAudioAnalysisChannelStats(_astatsLog);
    expect(channels.map((c) => c.channel), [1, 2]);
    expect(channels.first.peakDb, -2.5);
    expect(channels.first.dynamicRangeDb, closeTo(11.5, 1e-9));
    expect(channels.first.peakCount, 3);
    expect(channels.last.peakCount, 0);
  });

  test('a metadata dump gives the overall levels, loudness and true peak', () {
    final summary = parseAudioAnalysisMetadata(_metadata);
    expect(summary, isNotNull);
    expect(summary!.peakDb, -1.5);
    expect(summary.rmsDb, -13.25);
    expect(summary.integratedLufs, -9.8);
    // 0.5 linear is about -6.02 dBTP.
    expect(summary.truePeakDb, closeTo(-6.0206, 0.001));
  });

  test('metadata channels are sorted and carry their own levels', () {
    final channels = parseAudioAnalysisMetadata(_metadata)!.channelStats;
    expect(channels.map((c) => c.channel), [1, 2]);
    expect(channels.first.dynamicRangeDb, -2 - -14);
    expect(channels.first.peakCount, 4);
  });

  test('metadata without the overall levels is rejected', () {
    expect(parseAudioAnalysisMetadata('lavfi.r128.I=-9'), isNull);
  });

  test('a zero true-peak value has no dBTP', () {
    final summary = parseAudioAnalysisMetadata(
      _metadata.replaceAll('lavfi.r128.true_peak=0.5', 'lavfi.r128.true_peak=0'),
    );
    expect(summary!.truePeakDb, isNull);
  });

  test('channel stats round-trip through JSON', () {
    const stats = ChannelAnalysisStats(
      channel: 2,
      peakDb: -1,
      rmsDb: -12,
      dynamicRangeDb: 11,
      peakCount: 5,
    );
    final copy = ChannelAnalysisStats.fromJson(stats.toJson());
    expect(copy.channel, 2);
    expect(copy.peakDb, -1);
    expect(copy.rmsDb, -12);
    expect(copy.dynamicRangeDb, 11);
    expect(copy.peakCount, 5);
  });
}
