import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/providers/runtime_profile_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';

/// Build and raster statistics over a window of frames.
@immutable
class MornyeFrameStats {
  const MornyeFrameStats({
    required this.frames,
    required this.refreshRate,
    required this.build,
    required this.raster,
    required this.jankPercent,
  });

  /// Summarises frame durations in milliseconds. A frame is janky when its
  /// build or raster phase exceeds one refresh interval of [refreshRate].
  factory MornyeFrameStats.from({
    required List<double> buildMs,
    required List<double> rasterMs,
    required double refreshRate,
  }) {
    assert(buildMs.length == rasterMs.length);
    final budget = 1000 / refreshRate;
    var janky = 0;
    for (var i = 0; i < buildMs.length; i++) {
      if (buildMs[i] > budget || rasterMs[i] > budget) janky++;
    }
    return MornyeFrameStats(
      frames: buildMs.length,
      refreshRate: refreshRate,
      build: MornyePhaseStats.of(buildMs),
      raster: MornyePhaseStats.of(rasterMs),
      jankPercent: buildMs.isEmpty ? 0 : janky * 100 / buildMs.length,
    );
  }

  final int frames;
  final double refreshRate;
  final MornyePhaseStats build;
  final MornyePhaseStats raster;
  final double jankPercent;

  /// The one-line copy summary sent back for tuning.
  String summary({required String glass}) =>
      'mornye-hud $glass hz=${refreshRate.round()} frames=$frames '
      'build=${build.format()} raster=${raster.format()} '
      'jank=${jankPercent.toStringAsFixed(1)}%';
}

@immutable
class MornyePhaseStats {
  const MornyePhaseStats(this.average, this.p90, this.p99);

  factory MornyePhaseStats.of(List<double> values) {
    if (values.isEmpty) return const MornyePhaseStats(0, 0, 0);
    final sorted = [...values]..sort();
    double percentile(double p) =>
        sorted[math.min(sorted.length - 1, (p * sorted.length).ceil() - 1)];
    final sum = sorted.fold<double>(0, (total, value) => total + value);
    return MornyePhaseStats(
      sum / sorted.length,
      percentile(0.90),
      percentile(0.99),
    );
  }

  final double average;
  final double p90;
  final double p99;

  /// avg/p90/p99 in milliseconds.
  String format() =>
      [average, p90, p99].map((ms) => ms.toStringAsFixed(1)).join('/');
}

/// Places the performance HUD over the app when the developer option is on.
/// Off, the HUD is not in the tree and no timings callback is registered.
class MornyePerformanceHudHost extends ConsumerWidget {
  const MornyePerformanceHudHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(
      settingsProvider.select(
        (s) => s.developerOptionsUnlocked && s.performanceHudEnabled,
      ),
    );
    // A constant Stack keeps the app's element tree when toggling.
    return Stack(
      fit: StackFit.passthrough,
      textDirection: TextDirection.ltr,
      children: [child, if (enabled) const MornyePerformanceHud()],
    );
  }
}

/// A small floating overlay with rolling frame-timing statistics.
class MornyePerformanceHud extends ConsumerStatefulWidget {
  const MornyePerformanceHud({super.key});

  /// Frames kept in the rolling window.
  static const window = 300;

  /// Timings callbacks currently registered by HUDs; tests read it.
  @visibleForTesting
  static int debugRegisteredCallbacks = 0;

  @override
  ConsumerState<MornyePerformanceHud> createState() =>
      _MornyePerformanceHudState();
}

class _MornyePerformanceHudState extends ConsumerState<MornyePerformanceHud> {
  final _build = <double>[];
  final _raster = <double>[];
  int _unshown = 0;
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    MornyePerformanceHud.debugRegisteredCallbacks++;
    // Refresh at most twice a second, so the HUD barely measures itself.
    _refresh = Timer.periodic(const Duration(milliseconds: 500), (_) {
      // The HUD's own repaint is one frame; wait for real activity.
      if (_unshown > 1 && mounted) setState(() => _unshown = 0);
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    MornyePerformanceHud.debugRegisteredCallbacks--;
    super.dispose();
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      _build.add(timing.buildDuration.inMicroseconds / 1000);
      _raster.add(timing.rasterDuration.inMicroseconds / 1000);
    }
    final overflow = _build.length - MornyePerformanceHud.window;
    if (overflow > 0) {
      _build.removeRange(0, overflow);
      _raster.removeRange(0, overflow);
    }
    _unshown += timings.length;
  }

  void _reset() => setState(() {
    _build.clear();
    _raster.clear();
    _unshown = 0;
  });

  String _glass() {
    final quality = ref.read(mornyeGlassQualityProvider);
    final level = ref.read(mornyeGlassLevelProvider);
    final clarity = ref.read(mornyeGlassClarityLevelProvider);
    return 'quality=${quality.name}(${level.name}) level=$clarity';
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild when the glass settings change, so the line stays current.
    ref.watch(mornyeGlassQualityProvider);
    ref.watch(mornyeGlassLevelProvider);
    ref.watch(mornyeGlassClarityLevelProvider);
    final refreshRate = View.of(context).display.refreshRate;
    final stats = MornyeFrameStats.from(
      buildMs: _build,
      rasterMs: _raster,
      refreshRate: refreshRate > 0 ? refreshRate : 60,
    );
    final glass = _glass();
    const style = TextStyle(
      color: Colors.white,
      fontSize: 11,
      height: 1.3,
      fontFamily: 'monospace',
      fontFeatures: [FontFeature.tabularFigures()],
    );
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 4,
      right: 8,
      child: RepaintBoundary(
        child: Material(
          type: MaterialType.transparency,
          child: DecoratedBox(
            key: const ValueKey('mornye-performance-hud'),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 4, 4),
              child: DefaultTextStyle(
                style: style,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(glass),
                    Text(
                      '${stats.frames} frames @ ${stats.refreshRate.round()} Hz',
                    ),
                    Text('build  ${stats.build.format()} ms'),
                    Text('raster ${stats.raster.format()} ms'),
                    Text('jank   ${stats.jankPercent.toStringAsFixed(1)}%'),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: _reset,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            minimumSize: const Size(48, 36),
                          ),
                          child: const Text('Reset'),
                        ),
                        TextButton(
                          onPressed: () => Clipboard.setData(
                            ClipboardData(text: stats.summary(glass: glass)),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            minimumSize: const Size(48, 36),
                          ),
                          child: const Text('Copy'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
