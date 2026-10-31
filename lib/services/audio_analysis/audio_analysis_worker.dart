import 'dart:async';
import 'dart:ui' as ui;

import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_session.dart';
import 'package:sistrum/services/audio_analysis/audio_analysis_jobs.dart';
import 'package:sistrum/services/audio_analysis/audio_analysis_runner.dart';
import 'package:sistrum/services/audio_analysis/audio_analysis_store.dart';
import 'package:sistrum/services/native/native_data_jobs.dart';

/// Cache access for [AudioAnalysisController]. [ProcessAudioAnalysisArtifacts]
/// is the on-disk store; tests supply an in-memory one.
abstract interface class AudioAnalysisArtifacts {
  Future<AudioAnalysisData?> loadAnalysis(String path);
  Future<void> saveAnalysis(String path, AudioAnalysisData data);
  Future<void> clearAnalysis(String path);
  Future<ui.Image?> loadSpectrogram(String path, {required int channel});
  Future<void> saveSpectrogram(
    String path,
    ui.Image image, {
    required int channel,
  });

  /// Keeps [path]'s entry from being trimmed until the returned callback runs.
  void Function() retain(String path);
  void trim();
}

/// Native and FFmpeg analysis work for [AudioAnalysisController]. Cancellation
/// is per request: [invalidate] stops superseded work and [cancelNative]
/// cancels native jobs that are still running.
abstract interface class AudioAnalysisWorker {
  Future<AudioAnalysisRunResult> analyze(String path, int requestId);
  Future<GeneratedSpectrogram> spectrogram(
    String path, {
    required int requestId,
    required int channel,
    double? durationSeconds,
    int? sampleRate,
    int? channels,
  });
  void invalidate();
  void cancelNative();
  void dispose();
}

/// Production cache access: the on-disk store in `audio_analysis_store.dart`.
final class ProcessAudioAnalysisArtifacts implements AudioAnalysisArtifacts {
  const ProcessAudioAnalysisArtifacts();

  @override
  Future<AudioAnalysisData?> loadAnalysis(String path) =>
      loadAudioAnalysisFromCache(path);

  @override
  Future<void> saveAnalysis(String path, AudioAnalysisData data) =>
      saveAudioAnalysisToCache(path, data);

  @override
  Future<void> clearAnalysis(String path) => clearAudioAnalysisCache(path);

  @override
  Future<ui.Image?> loadSpectrogram(String path, {required int channel}) =>
      loadSpectrogramFromCache(path, channel: channel);

  @override
  Future<void> saveSpectrogram(
    String path,
    ui.Image image, {
    required int channel,
  }) => saveSpectrogramToCache(path, image, channel: channel);

  @override
  void Function() retain(String path) =>
      audioAnalysisCacheBudget.retain(audioAnalysisCacheKey(path));

  @override
  void trim() => unawaited(trimAudioAnalysisCache());
}

/// Production worker: FFmpeg sessions run through [AudioAnalysisRunner].
final class FfmpegAudioAnalysisWorker implements AudioAnalysisWorker {
  FfmpegAudioAnalysisWorker._({
    required this.jobs,
    required this.nativeRequests,
    required AudioAnalysisRunner runner,
  }) : _runner = runner;

  factory FfmpegAudioAnalysisWorker({
    required void Function(int requestId) checkRequest,
  }) {
    final jobs = AudioAnalysisJobs<FFmpegSession>(
      start: (arguments) async {
        final completed = Completer<FFmpegSession>();
        final session = await FFmpegKit.executeWithArgumentsAsync(
          arguments,
          completed.complete,
        );
        final id = session.getSessionId();
        if (id == null) {
          // Never pass null to cancel: FFmpegKit interprets it as cancel-all.
          await completed.future;
          throw StateError('Analysis session has no ID');
        }
        return (id: id, completed: completed.future);
      },
      cancel: (id) => FFmpegKit.cancel(id),
    );
    final nativeRequests = <String>{};
    return FfmpegAudioAnalysisWorker._(
      jobs: jobs,
      nativeRequests: nativeRequests,
      runner: AudioAnalysisRunner(
        jobs: jobs,
        nativeRequests: nativeRequests,
        checkRequest: checkRequest,
      ),
    );
  }

  final AudioAnalysisJobs<FFmpegSession> jobs;
  final Set<String> nativeRequests;
  final AudioAnalysisRunner _runner;

  @override
  Future<AudioAnalysisRunResult> analyze(String path, int requestId) =>
      _runner.runAnalysis(path, requestId);

  @override
  Future<GeneratedSpectrogram> spectrogram(
    String path, {
    required int requestId,
    required int channel,
    double? durationSeconds,
    int? sampleRate,
    int? channels,
  }) => _runner.generateSpectrogramForFile(
    path,
    requestId: requestId,
    channel: channel,
    durationSeconds: durationSeconds,
    sampleRate: sampleRate,
    channels: channels,
  );

  @override
  void invalidate() => jobs.invalidate();

  @override
  void cancelNative() {
    for (final request in nativeRequests) {
      unawaited(_cancelNativeRequest(request));
    }
  }

  Future<void> _cancelNativeRequest(String request) async {
    try {
      await NativeDataJobs.cancel(request);
    } catch (_) {
      // Await the owned worker before temp cleanup even if cancellation fails.
    }
  }

  @override
  void dispose() => jobs.dispose();
}
