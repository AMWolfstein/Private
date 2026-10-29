import 'dart:math' as math;

const int audioSpectrogramWidth = 1600;
const int audioSpectrogramHeight = 800;
const int audioSpectralAnalysisWidth = 400;
const double audioSpectrogramDynamicRangeDb = 120;
// Keep splice boundaries well below the cutoff estimator's top temporal
// percentile. Too many short excerpts turn waveform discontinuities into a
// persistent broadband floor, which can make a real low-pass edge look like
// full-band content. Longer windows preserve the same whole-track coverage and
// memory bound while making the small number of seams statistical outliers.
const int audioSpectrogramSampleWindowCount = 16;
const int audioSpectrogramMaxSelectedChannelSamples = 8 * 1024 * 1024;

String _buildShowspectrumOptions({required int width, required String color}) {
  return 'showspectrumpic='
      's=${width}x$audioSpectrogramHeight:'
      'legend=0:mode=combined:color=$color:scale=log:fscale=lin:'
      'win_func=hann:drange=${audioSpectrogramDynamicRangeDb.toStringAsFixed(0)}:'
      'limit=0';
}

String buildAudioSpectrogramFilter({
  int channel = -1,
  bool includeCutoffPlane = false,
  double? durationSeconds,
  int? sampleRate,
  int? channels,
}) {
  final channelFilter = channel >= 0 ? 'pan=mono|c0=c$channel,' : '';
  final samplingFilter = _buildAudioSpectrogramSamplingFilter(
    channel: channel,
    durationSeconds: durationSeconds,
    sampleRate: sampleRate,
    channels: channels,
  );
  final input =
      '[0:a:0]$channelFilter${samplingFilter}aformat=sample_fmts=fltp';
  final display = _buildShowspectrumOptions(
    width: audioSpectrogramWidth,
    color: 'intensity',
  );
  if (!includeCutoffPlane) {
    return '$input,$display,format=rgba[spectrum]';
  }

  // The display palette encodes quiet bins as saturated blue/purple pixels,
  // so RGB brightness is not a monotonic measure of spectral magnitude. Keep
  // the colorful UI output, but generate a small fixed-hue plane whose gray
  // values can be used safely for effective-bandwidth detection.
  final cutoff = _buildShowspectrumOptions(
    width: audioSpectralAnalysisWidth,
    color: 'green',
  );
  return '$input,asplit=2[display_input][cutoff_input];'
      '[display_input]$display,format=rgba[spectrum];'
      '[cutoff_input]$cutoff,format=gray[cutoff]';
}

List<String> buildAudioSpectrogramArguments({
  required String inputPath,
  required String outputPath,
  String? cutoffOutputPath,
  int channel = -1,
  double? durationSeconds,
  int? sampleRate,
  int? channels,
}) {
  final arguments = <String>[
    '-hide_banner',
    '-y',
    '-i',
    inputPath,
    '-filter_complex',
    buildAudioSpectrogramFilter(
      channel: channel,
      includeCutoffPlane: cutoffOutputPath != null,
      durationSeconds: durationSeconds,
      sampleRate: sampleRate,
      channels: channels,
    ),
    '-map',
    '[spectrum]',
    '-frames:v',
    '1',
    '-f',
    'rawvideo',
    '-pix_fmt',
    'rgba',
    outputPath,
  ];
  if (cutoffOutputPath != null) {
    arguments.addAll([
      '-map',
      '[cutoff]',
      '-frames:v',
      '1',
      '-f',
      'rawvideo',
      '-pix_fmt',
      'gray',
      cutoffOutputPath,
    ]);
  }
  return arguments;
}

String _buildAudioSpectrogramSamplingFilter({
  required int channel,
  required double? durationSeconds,
  required int? sampleRate,
  required int? channels,
}) {
  final duration = durationSeconds ?? 0;
  final rate = sampleRate ?? 0;
  if (!duration.isFinite || duration <= 0 || rate <= 0) return '';

  final selectedChannels = channel >= 0
      ? 1
      : ((channels ?? 0) > 0 ? channels! : 2);
  final maxSelectedDuration =
      audioSpectrogramMaxSelectedChannelSamples / (rate * selectedChannels);
  if (duration <= maxSelectedDuration) return '';

  // showspectrumpic retains its complete input until it can render the final
  // frame. Feed it equal windows spread across the whole track so memory is
  // bounded without biasing the image or cutoff estimate toward the intro.
  final interval = duration / audioSpectrogramSampleWindowCount;
  final window = maxSelectedDuration / audioSpectrogramSampleWindowCount;
  return "aselect='lt(mod(t,${interval.toStringAsFixed(9)}),"
      "${window.toStringAsFixed(9)})',asetpts=N/SR/TB,";
}

String buildAudioMetricsFilter({
  required double durationSeconds,
  required String metadataPath,
}) {
  final metadataStart = math.max(0.0, durationSeconds - 2.0);
  final escapedPath = metadataPath
      .replaceAll(r'\', r'\\')
      .replaceAll(':', r'\:')
      .replaceAll("'", r"\'");
  return 'astats=metadata=1:reset=0:'
      'measure_perchannel=Peak_level+RMS_level+Peak_count:'
      'measure_overall=Peak_level+RMS_level,'
      'ebur128=peak=true:metadata=1:framelog=quiet,'
      "aselect='gte(t,${metadataStart.toStringAsFixed(3)})',"
      "ametadata=print:file='$escapedPath'";
}

List<String> buildAudioMetricsArguments({
  required String inputPath,
  required String metadataPath,
  required double durationSeconds,
}) {
  // FFmpegKit's log level is process-global. A native download finalizer can
  // run `-v error` concurrently, so analyzer results must come from this
  // session's metadata file rather than info-level log callbacks.
  return [
    '-hide_banner',
    '-nostats',
    '-i',
    inputPath,
    '-map',
    '0:a:0',
    '-vn',
    '-sn',
    '-dn',
    '-af',
    buildAudioMetricsFilter(
      durationSeconds: durationSeconds,
      metadataPath: metadataPath,
    ),
    '-f',
    'null',
    '-',
  ];
}
