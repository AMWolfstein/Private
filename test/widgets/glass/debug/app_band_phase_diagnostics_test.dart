import 'dart:ui' show FrameTiming;

import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/widgets/glass/debug/app_band_phase_diagnostics.dart';

const _interval = 16667; // 60 Hz, microseconds.

FrameTiming _timing(int frame, double rasterMs) {
  final vsync = frame * _interval;
  final raster = (rasterMs * 1000).round();
  return FrameTiming(
    vsyncStart: vsync,
    buildStart: vsync + 100,
    buildFinish: vsync + 2000,
    rasterStart: vsync + 2100,
    rasterFinish: vsync + 2100 + raster,
    rasterFinishWallTime: vsync + 2100 + raster,
    frameNumber: frame,
  );
}

void main() {
  late AppBandPhaseDiagnostics diagnostics;

  setUp(() {
    diagnostics = AppBandPhaseDiagnostics.instance
      ..enabled = true
      ..clearPage()
      ..reset();
  });

  tearDown(() {
    diagnostics
      ..enabled = false
      ..clearPage()
      ..reset();
  });

  /// Builds frame [frame] (target = its vsync + one interval) in the current
  /// state.
  void build(int frame) =>
      diagnostics.debugRecordFrame(frame * _interval + _interval);

  test('splits raster by band phase and scrolling', () {
    // Hidden, idle.
    build(1);
    // Scrolling: the band fades in over two frames, then holds.
    diagnostics
      ..noteScrolling(true)
      ..noteBand(0.4);
    build(2);
    diagnostics.noteBand(1);
    build(3); // reaches 1: still the transition's last frame.
    build(4); // held at 1: stable.
    diagnostics.noteScrolling(false);
    build(5); // stable, idle.

    diagnostics.addTimings([
      _timing(1, 4),
      _timing(2, 20),
      _timing(3, 22),
      _timing(4, 9),
      _timing(5, 5),
    ], refreshRate: 60);

    final rows = {
      for (final (bucket, stats) in diagnostics.stats(refreshRate: 60))
        appBandBucketLabel(bucket): stats,
    };
    expect(rows.keys, [
      'hidden',
      'transition+scroll',
      'stable',
      'stable+scroll',
    ]);
    expect(rows['transition+scroll']!.frames, 2);
    expect(rows['transition+scroll']!.p99, 22);
    expect(rows['transition+scroll']!.rasterJankPercent, 100);
    expect(rows['stable+scroll']!.p50, 9);
    expect(rows['stable']!.rasterJankPercent, 0);
    expect(diagnostics.unmatched, 0);
  });

  test('a frame drawn without a Dart frame takes the phase then in effect', () {
    diagnostics.noteBand(1);
    build(1);
    build(2); // stable from here
    // Frames 3 and 4 have no Dart frame: a new video frame redrew the scene.
    diagnostics.addTimings([
      _timing(2, 6),
      _timing(3, 7),
      _timing(4, 8),
    ], refreshRate: 60);
    expect(diagnostics.unmatched, 2);
    final rows = diagnostics.stats(refreshRate: 60);
    expect(rows.single.$1.phase, AppBandPhase.stable);
    expect(rows.single.$2.frames, 3);
  });

  test('records nothing while disabled', () {
    diagnostics.enabled = false;
    diagnostics.noteBand(1);
    expect(diagnostics.currentBucket.phase, AppBandPhase.hidden);
    diagnostics.addTimings([_timing(1, 30)], refreshRate: 60);
    expect(diagnostics.stats(refreshRate: 60), isEmpty);
  });
}
