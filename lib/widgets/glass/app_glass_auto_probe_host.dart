import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/services/glass/app_glass_auto_probe.dart';

/// Lets Auto glass measure the device instead of trusting its class alone.
///
/// While Auto has no finished result for this build, it samples the raster
/// time of real frames, after a warm-up from the first rendered one. A p90 above
/// [AppGlassAutoSampler.thresholdMs] steps full glass down to lite and
/// measures again; lite steps down to Level 1. Each step is saved, so a
/// restart resumes where it stopped. Otherwise it registers nothing.
class AppGlassAutoProbeHost extends ConsumerStatefulWidget {
  const AppGlassAutoProbeHost({super.key, required this.child});

  final Widget child;

  /// Samplers currently collecting frame timings; tests read it.
  @visibleForTesting
  static int debugActiveSamplers = 0;

  @override
  ConsumerState<AppGlassAutoProbeHost> createState() =>
      _AppGlassAutoProbeHostState();
}

class _AppGlassAutoProbeHostState extends ConsumerState<AppGlassAutoProbeHost> {
  AppGlassAutoSampler? _sampler;

  void _sync(bool measuring) {
    if (!measuring) {
      _stop();
      return;
    }
    if (_sampler != null) return;
    // Only rasterized frames are reported, and the sampler skips its warm-up
    // from the first of them: startup itself is never measured.
    _sampler = AppGlassAutoSampler();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    AppGlassAutoProbeHost.debugActiveSamplers++;
  }

  void _stop() {
    if (_sampler == null) return;
    _sampler = null;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    AppGlassAutoProbeHost.debugActiveSamplers--;
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      final sampler = _sampler;
      if (sampler == null || !mounted) return;
      final p90 = sampler.add(
        rasterMs: timing.rasterDuration.inMicroseconds / 1000,
        vsyncMicros: timing.timestampInMicroseconds(FramePhase.vsyncStart),
      );
      if (p90 != null) {
        // The rest of this batch predates the decision.
        _decide(p90);
        return;
      }
    }
  }

  void _decide(double p90) {
    final current = ref.read(appGlassAutoStepProvider);
    final next = AppGlassAutoSampler.stepDown(current, p90);
    // Lite is measured again before it is kept; Level 1 is the floor.
    final done = next == null || next == AppGlassAutoStep.liteFrosted;
    _stop();
    ref
        .read(appGlassAutoResultProvider.notifier)
        .record(
          AppGlassAutoResult(
            build: appGlassAutoBuild(),
            step: next ?? current,
            done: done,
            p90: p90,
          ),
        );
    // A new step starts a fresh window, after its own warm-up.
    if (!done) _sync(true);
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final measuring =
        ref.watch(
          appGlassAutoStatusProvider(MediaQuery.highContrastOf(context)),
        ) ==
        AppGlassAutoStatus.measuring;
    _sync(measuring);
    return widget.child;
  }
}
