import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/models/app_glass.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/widgets/glass/app_artwork_glass.dart';
import 'package:sistrum/widgets/glass/app_backdrop_groups.dart';
import 'package:sistrum/widgets/glass/app_floating_header.dart';

/// Build and raster statistics over a window of frames.
@immutable
class AppFrameStats {
  const AppFrameStats({
    required this.frames,
    required this.refreshRate,
    required this.build,
    required this.raster,
    required this.jankPercent,
  });

  /// Summarises frame durations in milliseconds. A frame is janky when its
  /// build or raster phase exceeds one refresh interval of [refreshRate].
  factory AppFrameStats.from({
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
    return AppFrameStats(
      frames: buildMs.length,
      refreshRate: refreshRate,
      build: AppPhaseStats.of(buildMs),
      raster: AppPhaseStats.of(rasterMs),
      jankPercent: buildMs.isEmpty ? 0 : janky * 100 / buildMs.length,
    );
  }

  final int frames;
  final double refreshRate;
  final AppPhaseStats build;
  final AppPhaseStats raster;
  final double jankPercent;

  /// The one-line copy summary sent back for tuning.
  String summary({required String glass}) =>
      'sistrum-hud $glass hz=${refreshRate.round()} frames=$frames '
      'build=${build.format()} raster=${raster.format()} '
      'jank=${jankPercent.toStringAsFixed(1)}%';
}

@immutable
class AppPhaseStats {
  const AppPhaseStats(this.average, this.p90, this.p99);

  factory AppPhaseStats.of(List<double> values) {
    if (values.isEmpty) return const AppPhaseStats(0, 0, 0);
    final sorted = [...values]..sort();
    double percentile(double p) =>
        sorted[math.min(sorted.length - 1, (p * sorted.length).ceil() - 1)];
    final sum = sorted.fold<double>(0, (total, value) => total + value);
    return AppPhaseStats(
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
class AppPerformanceHudHost extends ConsumerWidget {
  const AppPerformanceHudHost({super.key, required this.child});

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
      children: [child, if (enabled) const AppPerformanceHud()],
    );
  }
}

/// A small floating overlay with rolling frame-timing statistics.
///
/// It starts at the top left, away from the Home avatar, and moves by its
/// title row. The statistics pass touches through to the app; minimized it
/// is a pill that keeps collecting.
class AppPerformanceHud extends ConsumerStatefulWidget {
  const AppPerformanceHud({super.key});

  /// Frames kept in the rolling window.
  static const window = 300;

  /// Timings callbacks currently registered by HUDs; tests read it.
  @visibleForTesting
  static int debugRegisteredCallbacks = 0;

  // Kept across toggles, so the HUD returns where it was left.
  static Offset? _position;
  static bool _minimized = false;

  @visibleForTesting
  static void debugResetPlacement() {
    _position = null;
    _minimized = false;
  }

  @override
  ConsumerState<AppPerformanceHud> createState() =>
      _AppPerformanceHudState();
}

class _AppPerformanceHudState extends ConsumerState<AppPerformanceHud> {
  final _build = <double>[];
  final _raster = <double>[];
  int _unshown = 0;
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    AppPerformanceHud.debugRegisteredCallbacks++;
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
    AppPerformanceHud.debugRegisteredCallbacks--;
    super.dispose();
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      _build.add(timing.buildDuration.inMicroseconds / 1000);
      _raster.add(timing.rasterDuration.inMicroseconds / 1000);
    }
    final overflow = _build.length - AppPerformanceHud.window;
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

  /// Backdrop reads in the last composited frame, over every view.
  int _reads() {
    var reads = 0;
    for (final view in RendererBinding.instance.renderViews) {
      // The layer tree is protected API; this debug HUD only reads the
      // composited backdrop counter and never mutates the layer.
      // ignore: invalid_use_of_protected_member
      reads += appCountBackdropReads(view.layer).total;
    }
    return reads;
  }

  String _glass(BuildContext context) {
    final quality = ref.read(appGlassQualityProvider);
    final level = ref.read(appGlassLevelProvider);
    final clarity = ref.read(appGlassClarityLevelProvider);
    final renderer = quality == AppGlassQuality.auto
        ? '${level.name}, ${ref.read(appGlassAutoStatusProvider(MediaQuery.highContrastOf(context))).name}'
        : level.name;
    final sampler = ref.read(appBarSamplerDisabledProvider)
        ? 'off'
        : appLiquidChromeEnabled(context, ref)
        ? 'on'
        : 'n/a';
    final band = ref.read(appHeaderBandBlurDisabledProvider) ? 'off' : 'on';
    // How long the player's artwork ground took: decode + compose + blur.
    final ground = AppGroundBuilder.lastPlayer.value;
    final groundText = ground == null
        ? 'n/a'
        : '${ground.total.inMilliseconds}ms'
              '(decode ${ground.decode.inMilliseconds})';
    return 'quality=${quality.name}($renderer) level=$clarity '
        'reads=${_reads()} sampler=$sampler bandblur=$band '
        'ground=$groundText';
  }

  void _move(Offset delta) => setState(() {
    // Store the clamped position so overshooting an edge does not leave the
    // HUD stuck until the drag is reversed.
    AppPerformanceHud._position = _clamped(
      (AppPerformanceHud._position ?? _defaultPosition) + delta,
    );
  });

  Offset get _defaultPosition =>
      Offset(8, MediaQuery.paddingOf(context).top + 4);

  /// Keeps at least the title row on screen.
  Offset _clamped(Offset position) {
    final screen = MediaQuery.sizeOf(context);
    return Offset(
      position.dx.clamp(0, math.max(0, screen.width - 48)),
      position.dy.clamp(0, math.max(0, screen.height - 36)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild when the glass settings change, so the line stays current.
    ref.watch(appGlassQualityProvider);
    ref.watch(appGlassLevelProvider);
    ref.watch(appGlassClarityLevelProvider);
    ref.watch(appGlassAutoResultProvider);
    final samplerOff = ref.watch(appBarSamplerDisabledProvider);
    final bandBlurOff = ref.watch(appHeaderBandBlurDisabledProvider);
    final refreshRate = View.of(context).display.refreshRate;
    final stats = AppFrameStats.from(
      buildMs: _build,
      rasterMs: _raster,
      refreshRate: refreshRate > 0 ? refreshRate : 60,
    );
    final glass = _glass(context);
    final settings = ref.read(settingsProvider.notifier);
    const style = TextStyle(
      color: Colors.white,
      fontSize: 11,
      height: 1.3,
      fontFamily: 'monospace',
      fontFeatures: [FontFeature.tabularFigures()],
    );
    final buttonStyle = TextButton.styleFrom(
      foregroundColor: Colors.white,
      minimumSize: const Size(48, 36),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      textStyle: const TextStyle(fontSize: 12),
    );
    final position = _clamped(
      AppPerformanceHud._position ?? _defaultPosition,
    );
    final minimized = AppPerformanceHud._minimized;
    final Widget body = minimized
        ? Semantics(
            button: true,
            label: 'Expand performance HUD',
            child: GestureDetector(
              key: const ValueKey('sistrum-performance-hud-pill'),
              behavior: HitTestBehavior.opaque,
              onTap: () =>
                  setState(() => AppPerformanceHud._minimized = false),
              // The tap competes for the pointer; keep the slop in the move.
              dragStartBehavior: DragStartBehavior.down,
              onPanUpdate: (details) => _move(details.delta),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 36, minWidth: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  child: Text(
                    'R ${stats.raster.average.toStringAsFixed(1)} · '
                    'J ${stats.jankPercent.toStringAsFixed(0)}%',
                    style: style,
                  ),
                ),
              ),
            ),
          )
        : Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 4, 4),
            child: DefaultTextStyle(
              style: style,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The handle: drag to move, the button minimizes.
                  GestureDetector(
                    key: const ValueKey('sistrum-performance-hud-handle'),
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (details) => _move(details.delta),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.drag_indicator,
                          size: 16,
                          color: Colors.white70,
                        ),
                        const SizedBox(width: 4),
                        const Text('HUD'),
                        const SizedBox(width: 24),
                        // Above the Navigator there is no Overlay for a
                        // tooltip; the label carries the name instead.
                        Semantics(
                          label: 'Minimize performance HUD',
                          child: IconButton(
                            key: const ValueKey(
                              'sistrum-performance-hud-minimize',
                            ),
                            onPressed: () => setState(
                              () => AppPerformanceHud._minimized = true,
                            ),
                            color: Colors.white,
                            iconSize: 18,
                            constraints: const BoxConstraints.tightFor(
                              width: 40,
                              height: 36,
                            ),
                            icon: const Icon(Icons.remove),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Statistics never take touches from the app beneath.
                  IgnorePointer(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(glass),
                        Text(
                          '${stats.frames} frames @ '
                          '${stats.refreshRate.round()} Hz',
                        ),
                        Text('build  ${stats.build.format()} ms'),
                        Text('raster ${stats.raster.format()} ms'),
                        Text('jank   ${stats.jankPercent.toStringAsFixed(1)}%'),
                      ],
                    ),
                  ),
                  Wrap(
                    children: [
                      TextButton(
                        key: const ValueKey('sistrum-performance-hud-sampler'),
                        onPressed: () =>
                            settings.setBarSamplerDisabled(!samplerOff),
                        style: buttonStyle,
                        child: Text(
                          samplerOff ? 'Sampler: off' : 'Sampler: on',
                        ),
                      ),
                      TextButton(
                        key: const ValueKey('sistrum-performance-hud-band'),
                        onPressed: () =>
                            settings.setHeaderBandBlurDisabled(!bandBlurOff),
                        style: buttonStyle,
                        child: Text(
                          bandBlurOff ? 'Band blur: off' : 'Band blur: on',
                        ),
                      ),
                      TextButton(
                        onPressed: _reset,
                        style: buttonStyle,
                        child: const Text('Reset'),
                      ),
                      TextButton(
                        onPressed: () => Clipboard.setData(
                          ClipboardData(text: stats.summary(glass: glass)),
                        ),
                        style: buttonStyle,
                        child: const Text('Copy'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
    return Positioned(
      left: position.dx,
      top: position.dy,
      child: RepaintBoundary(
        child: Material(
          type: MaterialType.transparency,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            // A decoration takes the hits inside its shape; behind the body
            // it lets the statistics pass taps through to the app.
            child: Stack(
              key: const ValueKey('sistrum-performance-hud'),
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(
                          minimized ? 18 : 10,
                        ),
                      ),
                    ),
                  ),
                ),
                body,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
