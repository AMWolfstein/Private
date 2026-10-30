import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/audio_analysis/audio_analysis_jobs.dart';
import 'package:sistrum/services/audio_analysis/audio_analysis_runner.dart';

/// Counts native work so a cancelled run can be shown to start none.
class _CountingJobs {
  int starts = 0;

  AudioAnalysisJobs<FFmpegSession> get jobs => AudioAnalysisJobs<FFmpegSession>(
    start: (arguments) async {
      starts++;
      throw StateError('native work should not start');
    },
    cancel: (_) async {},
  );
}

void main() {
  test(
    'a run for a request that is no longer current is cancelled first',
    () async {
      final native = _CountingJobs();
      final seen = <int>[];
      final runner = AudioAnalysisRunner(
        jobs: native.jobs,
        nativeRequests: <String>{},
        checkRequest: (requestId) {
          seen.add(requestId);
          throw const AudioAnalysisCancelled();
        },
      );

      await expectLater(
        runner.runAnalysis('/music/song.flac', 7),
        throwsA(isA<AudioAnalysisCancelled>()),
      );
      expect(seen, [7]);
      expect(native.starts, 0);
    },
  );

  test(
    'a spectrogram for a stale request is cancelled before any decode',
    () async {
      final native = _CountingJobs();
      final runner = AudioAnalysisRunner(
        jobs: native.jobs,
        nativeRequests: <String>{},
        checkRequest: (_) => throw const AudioAnalysisCancelled(),
      );

      await expectLater(
        runner.generateSpectrogramForFile(
          '/music/song.flac',
          requestId: 3,
          channel: -1,
        ),
        throwsA(isA<AudioAnalysisCancelled>()),
      );
      expect(native.starts, 0);
    },
  );
}
