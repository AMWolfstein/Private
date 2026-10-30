import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sistrum/services/audio_analysis/audio_analysis_jobs.dart';
import 'package:sistrum/services/audio_analysis/audio_analysis_parsing.dart';
import 'package:sistrum/services/audio_analysis/audio_analysis_store.dart';
import 'package:sistrum/services/native/media_file_bridge.dart';
import 'package:sistrum/services/native/native_data_jobs.dart';
import 'package:sistrum/utils/files/best_effort_delete.dart';

/// Records of one analysis run and its spectrogram, kept apart from the card.
class GeneratedSpectrogram {
  final ui.Image image;
  final Uint8List rgba;
  final double? cutoffFrequencyHz;

  const GeneratedSpectrogram({
    required this.image,
    required this.rgba,
    this.cutoffFrequencyHz,
  });
}

class AudioAnalysisRunResult {
  final AudioAnalysisData data;
  final ui.Image spectrogramImage;

  const AudioAnalysisRunResult({
    required this.data,
    required this.spectrogramImage,
  });
}

class _MediaInfo {
  final int fileSize;
  final String codecName;
  final String codec;
  final String container;
  final String decodedSampleFormat;
  final int sampleRate;
  final int channels;
  final String channelLayout;
  final int bitsPerSample;
  final double duration;
  final int bitrate;
  final int totalSamples;

  const _MediaInfo({
    required this.fileSize,
    required this.codecName,
    required this.codec,
    required this.container,
    required this.decodedSampleFormat,
    required this.sampleRate,
    required this.channels,
    required this.channelLayout,
    required this.bitsPerSample,
    required this.duration,
    required this.bitrate,
    required this.totalSamples,
  });
}

class _LevelMetrics {
  final double peakDb;
  final double rmsDb;
  final double? integratedLufs;
  final double? truePeakDb;
  final int clippingSamples;
  final List<ChannelAnalysisStats> channelStats;

  const _LevelMetrics({
    required this.peakDb,
    required this.rmsDb,
    this.integratedLufs,
    this.truePeakDb,
    this.clippingSamples = 0,
    this.channelStats = const [],
  });
}

/// Runs the FFmpeg, FFprobe and native analysis work for one track. The card
/// owns request ids and widget state; [checkRequest] throws
/// [AudioAnalysisCancelled] once a run is no longer current.
class AudioAnalysisRunner {
  AudioAnalysisRunner({
    required this.jobs,
    required this.nativeRequests,
    required this.checkRequest,
  });

  final AudioAnalysisJobs<FFmpegSession> jobs;
  final Set<String> nativeRequests;
  final void Function(int requestId) checkRequest;

  Future<AudioAnalysisRunResult> runAnalysis(
    String filePath,
    int requestId, {
    String? sourcePath,
  }) async {
    checkRequest(requestId);
    String workingPath = filePath;
    String? tempCopy;
    if (filePath.startsWith('content://')) {
      tempCopy = await MediaFileBridge.copyContentUriToTempOrThrow(filePath);
      workingPath = tempCopy;
    }

    try {
      checkRequest(requestId);
      final info = await _getMediaInfo(workingPath);
      checkRequest(requestId);
      final unsupported = unsupportedAudioAnalysisCodecLabel(info.codecName);
      if (unsupported != null) {
        throw UnsupportedAudioAnalysisCodecException(unsupported);
      }
      GeneratedSpectrogram? spectrogram;
      try {
        final effectiveDuration = info.totalSamples > 0 && info.sampleRate > 0
            ? info.totalSamples / info.sampleRate
            : info.duration;
        spectrogram = await _generateSpectrogram(
          workingPath,
          requestId: requestId,
          channel: -1,
          includeCutoffPlane: true,
          durationSeconds: effectiveDuration,
          sampleRate: info.sampleRate,
          channels: info.channels,
        );
        checkRequest(requestId);
        final spectralCutoffHz = spectrogram.cutoffFrequencyHz;
        final levelMetrics = await _runFullStreamLevelAnalysis(
          workingPath,
          requestId: requestId,
          durationSeconds: effectiveDuration,
        );
        if (levelMetrics == null) {
          throw Exception('FFmpeg level analysis returned no usable metrics');
        }
        final peakAmplitude = levelMetrics.peakDb;
        final rmsLevel = levelMetrics.rmsDb;
        final dynamicRange = peakAmplitude - rmsLevel;

        return AudioAnalysisRunResult(
          data: AudioAnalysisData(
            filePath: sourcePath ?? filePath,
            fileSize: info.fileSize,
            codec: info.codec,
            container: info.container,
            decodedSampleFormat: info.decodedSampleFormat,
            sampleRate: info.sampleRate,
            channels: info.channels,
            channelLayout: info.channelLayout,
            bitsPerSample: info.bitsPerSample,
            duration: info.duration,
            bitrate: info.bitrate,
            bitDepth: info.bitsPerSample > 0
                ? '${info.bitsPerSample}-bit'
                : 'N/A',
            dynamicRange: dynamicRange,
            peakAmplitude: peakAmplitude,
            rmsLevel: rmsLevel,
            integratedLufs: levelMetrics.integratedLufs,
            truePeakDb: levelMetrics.truePeakDb,
            clippingSamples: levelMetrics.clippingSamples,
            spectralCutoffHz: spectralCutoffHz,
            channelStats: levelMetrics.channelStats,
            totalSamples: info.totalSamples,
          ),
          spectrogramImage: spectrogram.image,
        );
      } catch (_) {
        spectrogram?.image.dispose();
        rethrow;
      }
    } finally {
      if (tempCopy != null) {
        await deleteBestEffort(File(tempCopy));
      }
    }
  }

  Future<GeneratedSpectrogram> generateSpectrogramForFile(
    String filePath, {
    required int requestId,
    required int channel,
    double? durationSeconds,
    int? sampleRate,
    int? channels,
  }) async {
    checkRequest(requestId);
    String workingPath = filePath;
    String? tempCopy;
    if (filePath.startsWith('content://')) {
      tempCopy = await MediaFileBridge.copyContentUriToTempOrThrow(filePath);
      workingPath = tempCopy;
    }

    try {
      return await _generateSpectrogram(
        workingPath,
        requestId: requestId,
        channel: channel,
        durationSeconds: durationSeconds,
        sampleRate: sampleRate,
        channels: channels,
      );
    } finally {
      if (tempCopy != null) {
        await deleteBestEffort(File(tempCopy));
      }
    }
  }

  Future<GeneratedSpectrogram> _generateSpectrogram(
    String inputPath, {
    required int requestId,
    required int channel,
    bool includeCutoffPlane = false,
    double? durationSeconds,
    int? sampleRate,
    int? channels,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final rawPath =
        '${tempDir.path}/analysis_spectrum_'
        '${DateTime.now().microsecondsSinceEpoch}_${channel + 1}.rgba';
    final cutoffPath = includeCutoffPlane ? '$rawPath.cutoff.gray' : null;

    try {
      checkRequest(requestId);
      final session = await jobs.run(
        buildAudioSpectrogramArguments(
          inputPath: inputPath,
          outputPath: rawPath,
          cutoffOutputPath: cutoffPath,
          channel: channel,
          durationSeconds: durationSeconds,
          sampleRate: sampleRate,
          channels: channels,
        ),
      );

      final returnCode = await session.getReturnCode();
      if (!ReturnCode.isSuccess(returnCode)) {
        final logs = await session.getLogsAsString();
        throw Exception('FFmpeg spectrogram failed: $logs');
      }

      final expectedLength = audioSpectrogramWidth * audioSpectrogramHeight * 4;
      final rawBytes = await File(rawPath).readAsBytes();
      if (rawBytes.length < expectedLength) {
        throw Exception(
          'Incomplete spectrogram output '
          '(${rawBytes.length}/$expectedLength bytes)',
        );
      }
      final rgba = rawBytes.length == expectedLength
          ? rawBytes
          : Uint8List.sublistView(rawBytes, 0, expectedLength);
      double? cutoffFrequencyHz;
      if (cutoffPath != null) {
        final expectedCutoffLength =
            audioSpectralAnalysisWidth * audioSpectrogramHeight;
        final cutoffLength = await File(cutoffPath).length();
        if (cutoffLength != expectedCutoffLength) {
          throw Exception(
            'Incomplete spectral cutoff output '
            '($cutoffLength/$expectedCutoffLength bytes)',
          );
        }
        checkRequest(requestId);
        final nativeRequest = 'spectral-$rawPath';
        nativeRequests.add(nativeRequest);
        try {
          try {
            final result = await NativeDataJobs.run({
              'operation': 'spectral_cutoff',
              'path': cutoffPath,
              'width': audioSpectralAnalysisWidth,
              'height': audioSpectrogramHeight,
              'max_frequency': (sampleRate ?? 0) / 2,
            }, requestId: nativeRequest);
            cutoffFrequencyHz = (result['cutoff'] as num?)?.toDouble();
          } on MissingPluginException {
            cutoffFrequencyHz = await compute(
              estimateEffectiveSpectralCutoffFileInIsolate,
              SpectralCutoffFileParams(
                path: cutoffPath,
                width: audioSpectralAnalysisWidth,
                height: audioSpectrogramHeight,
                maxFrequencyHz: (sampleRate ?? 0) / 2,
              ),
            );
          }
        } finally {
          nativeRequests.remove(nativeRequest);
        }
        checkRequest(requestId);
      }
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        rgba,
        audioSpectrogramWidth,
        audioSpectrogramHeight,
        ui.PixelFormat.rgba8888,
        completer.complete,
      );
      return GeneratedSpectrogram(
        image: await completer.future,
        rgba: rgba,
        cutoffFrequencyHz: cutoffFrequencyHz,
      );
    } finally {
      await deleteBestEffort(File(rawPath));
      if (cutoffPath != null) {
        await deleteBestEffort(File(cutoffPath));
      }
    }
  }

  Future<_MediaInfo> _getMediaInfo(String filePath) async {
    final session = await FFprobeKit.getMediaInformation(filePath);
    final info = session.getMediaInformation();

    if (info == null) {
      throw Exception('Failed to get media information');
    }

    int fileSize = 0;
    try {
      fileSize = await File(filePath).length();
    } catch (_) {}

    final streams = info.getStreams();
    final audioStream = streams.firstWhere(
      (s) => s.getAllProperties()?['codec_type'] == 'audio',
      orElse: () => throw Exception('No audio stream found'),
    );

    final props = audioStream.getAllProperties() ?? {};
    final infoProps = info.getAllProperties() ?? {};
    final codecName = props['codec_name']?.toString().toLowerCase() ?? '';
    final codecLongName = props['codec_long_name']?.toString() ?? '';
    final decodedSampleFormat = props['sample_fmt']?.toString() ?? '';
    final formatName = infoProps['format_name']?.toString() ?? '';
    final formatLongName = infoProps['format_long_name']?.toString() ?? '';
    final sampleRate =
        int.tryParse(props['sample_rate']?.toString() ?? '') ?? 0;
    final channels = int.tryParse(props['channels']?.toString() ?? '') ?? 0;
    final channelLayout =
        props['channel_layout']?.toString() ??
        props['ch_layout']?.toString() ??
        '';
    final streamDuration = double.tryParse(props['duration']?.toString() ?? '');
    final containerDuration = double.tryParse(info.getDuration() ?? '');
    final duration =
        (streamDuration != null && streamDuration > 0
            ? streamDuration
            : containerDuration) ??
        0;
    final streamBitrate = int.tryParse(props['bit_rate']?.toString() ?? '');
    final containerBitrate = int.tryParse(info.getBitrate() ?? '');
    final bitrate =
        streamBitrate ??
        containerBitrate ??
        (duration > 0 && fileSize > 0 ? (fileSize * 8 / duration).round() : 0);

    final canReportStoredBitDepth = audioCodecHasStoredBitDepth(codecName);

    int bitsPerSample = 0;
    if (canReportStoredBitDepth) {
      bitsPerSample =
          int.tryParse(props['bits_per_raw_sample']?.toString() ?? '') ?? 0;
      if (bitsPerSample == 0) {
        bitsPerSample =
            int.tryParse(props['bits_per_sample']?.toString() ?? '') ?? 0;
      }
    }

    if (bitsPerSample == 0 && canReportStoredBitDepth) {
      final sampleFmt = props['sample_fmt']?.toString() ?? '';
      if (sampleFmt.contains('16') ||
          sampleFmt == 's16' ||
          sampleFmt == 's16p') {
        bitsPerSample = 16;
      } else if (sampleFmt.contains('32') ||
          sampleFmt == 'flt' ||
          sampleFmt == 'fltp') {
        bitsPerSample = 32;
      } else if (sampleFmt.contains('24') || sampleFmt == 's24') {
        bitsPerSample = 24;
      }
    }

    return _MediaInfo(
      fileSize: fileSize,
      codecName: codecName,
      codec: formatAudioCodecLabel(codecName, codecLongName),
      container: formatAudioContainerLabel(formatName, formatLongName),
      decodedSampleFormat: decodedSampleFormat,
      sampleRate: sampleRate,
      channels: channels,
      channelLayout: channelLayout,
      bitsPerSample: bitsPerSample,
      duration: duration,
      bitrate: bitrate,
      totalSamples: estimateAudioTotalSamples(
        props: props,
        duration: duration,
        sampleRate: sampleRate,
        channels: channels,
      ),
    );
  }

  Future<_LevelMetrics?> _runFullStreamLevelAnalysis(
    String inputPath, {
    required int requestId,
    required double durationSeconds,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final metadataFile = File(
      '${tempDir.path}/analysis_metrics_'
      '${DateTime.now().microsecondsSinceEpoch}.txt',
    );
    try {
      checkRequest(requestId);
      final session = await jobs.run(
        buildAudioMetricsArguments(
          inputPath: inputPath,
          metadataPath: metadataFile.path,
          durationSeconds: durationSeconds,
        ),
      );

      final returnCode = await session.getReturnCode();
      if (!ReturnCode.isSuccess(returnCode)) {
        return null;
      }

      final metadata = await metadataFile.exists()
          ? await metadataFile.readAsString()
          : '';
      final metadataSummary = parseAudioAnalysisMetadata(metadata);
      final logs = metadataSummary == null
          ? await session.getAllLogsAsString() ?? ''
          : '';
      final summary = metadataSummary ?? parseAudioAstatsSummary(logs);
      if (summary == null) return null;
      final channelStats = metadataSummary?.channelStats.isNotEmpty == true
          ? metadataSummary!.channelStats
          : parseAudioAnalysisChannelStats(logs);
      final clippingSamples = channelStats.fold<int>(0, (sum, stats) {
        if (stats.peakDb == null || stats.peakDb! < -0.1) return sum;
        return sum + stats.peakCount;
      });
      return _LevelMetrics(
        peakDb: summary.peakDb,
        rmsDb: summary.rmsDb,
        integratedLufs: metadataSummary?.integratedLufs,
        truePeakDb: metadataSummary?.truePeakDb,
        clippingSamples: clippingSamples,
        channelStats: channelStats,
      );
    } finally {
      await deleteBestEffort(metadataFile);
    }
  }
}
