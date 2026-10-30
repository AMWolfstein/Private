import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/audio_analysis/audio_analysis_ffmpeg_args.dart';

void main() {
  test('a spectrogram without a cutoff plane maps only the spectrum', () {
    final args = buildAudioSpectrogramArguments(
      inputPath: '/music/song.flac',
      outputPath: '/cache/spectrum.rgba',
    );
    expect(args, containsAllInOrder(['-i', '/music/song.flac']));
    expect(args, containsAllInOrder(['-map', '[spectrum]']));
    expect(args, containsAllInOrder(['-pix_fmt', 'rgba']));
    expect(args, isNot(contains('[cutoff]')));
    expect(args.last, '/cache/spectrum.rgba');
  });

  test('a cutoff output adds a gray plane mapped after the spectrum', () {
    final args = buildAudioSpectrogramArguments(
      inputPath: '/music/song.flac',
      outputPath: '/cache/spectrum.rgba',
      cutoffOutputPath: '/cache/cutoff.gray',
    );
    final cutoffMap = args.indexOf('[cutoff]');
    expect(cutoffMap, greaterThan(args.indexOf('[spectrum]')));
    expect(args.sublist(cutoffMap), containsAllInOrder(['-pix_fmt', 'gray']));
    expect(args.last, '/cache/cutoff.gray');
  });

  test('a short track is not resampled, a long track is windowed', () {
    // Eight million stereo samples at 44.1 kHz cover about 90 seconds.
    final short = buildAudioSpectrogramFilter(
      durationSeconds: 60,
      sampleRate: 44100,
      channels: 2,
    );
    expect(short, isNot(contains('aselect')));

    // Eight million selected samples cannot cover this track at once.
    final long = buildAudioSpectrogramFilter(
      durationSeconds: 3600,
      sampleRate: 48000,
      channels: 2,
    );
    expect(long, contains("aselect='lt(mod(t,"));
    expect(long, contains('asetpts=N/SR/TB'));
  });

  test('a single channel selection mixes down to that channel', () {
    final filter = buildAudioSpectrogramFilter(channel: 1);
    expect(filter, startsWith('[0:a:0]pan=mono|c0=c1,'));
  });

  test('metrics filter escapes the metadata path for ffmpeg', () {
    final filter = buildAudioMetricsFilter(
      durationSeconds: 200,
      metadataPath: r"C:\tmp\it's:here.txt",
    );
    expect(filter, contains(r"file='C\:\\tmp\\it\'s\:here.txt'"));
    // Only the last two seconds are kept for the peak and loudness readout.
    expect(filter, contains("aselect='gte(t,198.000)'"));
  });

  test('metrics arguments discard the output and read only audio', () {
    final args = buildAudioMetricsArguments(
      inputPath: '/music/song.flac',
      metadataPath: '/cache/metrics.txt',
      durationSeconds: 60,
    );
    expect(args, containsAll(['-nostats', '-vn', '-sn', '-dn', '-f', 'null']));
    expect(args.last, '-');
    expect(args, containsAllInOrder(['-map', '0:a:0']));
  });
}
