import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/providers/performance/glass_poc_mode_provider.dart';
import 'package:sistrum/services/performance/glass_benchmark_aggregator.dart';
import 'package:sistrum/services/performance/perf_frame_monitor.dart';
import 'package:sistrum/services/performance/perf_frame_window.dart';
import 'package:sistrum/services/performance/perf_spike_recorder.dart';
import 'package:sistrum/widgets/glass_poc/glass_benchmark_report.dart';
import 'package:sistrum/widgets/glass_poc/glass_benchmark_runner.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_auto_scroll.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_mode.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_render_path.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_scene.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_surface.dart';

/// Developer-only Glass POC. Shows the same header, scrolling list, mini
/// player and tab bar in each [SistrumGlassMode], over a background that is
/// either static or animated. Nothing here is wired into production screens.
class GlassPocPage extends ConsumerStatefulWidget {
  const GlassPocPage({
    super.key,
    this.benchmarkPlan = const GlassBenchmarkPlan(),
  });

  /// Timing of the full benchmark. Tests pass shorter values; the app uses the
  /// 60-second protocol.
  final GlassBenchmarkPlan benchmarkPlan;

  @override
  ConsumerState<GlassPocPage> createState() => _GlassPocPageState();
}

class _GlassPocPageState extends ConsumerState<GlassPocPage>
    with TickerProviderStateMixin
    implements GlassPocRunProbe, GlassBenchmarkHost {
  static const double _sideInset = 16;

  late final AnimationController _background = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );
  final ScrollController _list = ScrollController();
  late final SistrumAutoScroller _autoScroll;
  late final PerfFrameMonitor _monitor;
  late final GlassPocRunRegistry _registry;
  final GlobalKey _stageKey = GlobalKey();
  Timer? _pathTimer;
  late final PerfSpikeRecorder _spikes;
  AppLifecycleListener? _lifecycle;
  SistrumGlassRenderReport? _render;
  SistrumGlassRenderReport? _renderAtStart;
  bool _outlines = false;
  late final GlassBenchmarkRunner _runner;
  late final GlassPocModeNotifier _modeNotifier;
  late final GlassPocSharedBackdropNotifier _sharedNotifier;
  late final GlassPocSceneNotifier _sceneNotifier;
  late final GlassPocScrollSpeedNotifier _speedNotifier;
  bool _startedMonitor = false;
  bool _disposing = false;

  @override
  void initState() {
    super.initState();
    _monitor = ref.read(perfFrameMonitorProvider);
    _registry = ref.read(glassPocRunRegistryProvider);
    _modeNotifier = ref.read(glassPocModeProvider.notifier);
    _sharedNotifier = ref.read(glassPocSharedBackdropProvider.notifier);
    _sceneNotifier = ref.read(glassPocSceneProvider.notifier);
    _speedNotifier = ref.read(glassPocScrollSpeedProvider.notifier);
    _autoScroll = SistrumAutoScroller(
      vsync: this,
      controller: _list,
      speed: ref.read(glassPocScrollSpeedProvider),
      onMeasurementStart: _onMeasurementStart,
      measurementReady: _readyToMeasure,
      warmupSeconds:
          widget.benchmarkPlan.warmup.inMicroseconds /
          Duration.microsecondsPerSecond,
    );
    // The POC needs frames to measure. Start the monitor if the HUD has not,
    // and stop it again only if this page started it.
    _startedMonitor = !_monitor.isRunning;
    if (_startedMonitor) _monitor.start();
    _runner = GlassBenchmarkRunner(
      host: this,
      budgetUs:
          1e6 /
          resolvePerfRefreshRate(PerfFrameMonitor.reportedRefreshRate()).hz,
      plan: widget.benchmarkPlan,
      onPhaseChanged: _onRunnerPhaseChanged,
      reportBuilder: _buildReport,
    );
    _registry.attach(_autoScroll, this);
    // Developer diagnostics only: the recorder lives while this page is open.
    _spikes = PerfSpikeRecorder()
      ..budgetUs =
          1e6 /
          resolvePerfRefreshRate(PerfFrameMonitor.reportedRefreshRate()).hz
      ..contextReader = _spikeContext;
    _monitor.spikeRecorder = _spikes;
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        _spikes.noteEvent('app_lifecycle=${state.name}');
        // Leaving the foreground stops a benchmark. It never resumes by itself.
        if (state != AppLifecycleState.resumed) {
          _runner.interrupt('app lifecycle=${state.name}');
        }
      },
    );
    _applyScene(ref.read(glassPocSceneProvider));
    _render = _probeRender();
    // Re-probe while the page is open. Only a changed path rebuilds the page,
    // and the timer is not a ticker, so nothing is drawn while it is idle.
    _pathTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _refreshRender(),
    );
  }

  @override
  SistrumGlassRenderReport renderPath() => _probeRender();

  @override
  SistrumGlassRenderReport? renderPathAtMeasurementStart() => _renderAtStart;

  /// Probes the mounted stage. Its type names are the only evidence the package
  /// gives, so an unmounted or incomplete stage stays unverified.
  SistrumGlassRenderReport _probeRender() {
    final context = _stageKey.currentContext;
    if (context == null) {
      return const SistrumGlassRenderReport.unverified('stage not mounted');
    }
    final mode = ref.read(glassPocModeProvider);
    final scene = ref.read(glassPocSceneProvider);
    return classifySistrumGlassRenderPath(
      mode: mode,
      expectedSurfaces: scene.surfaces,
      census: sistrumGlassCensus(context as Element),
      shaderFiltersSupported: ui.ImageFilter.isShaderFilterSupported,
    );
  }

  /// Sampling waits for a verifiable path, so a blank or fallback render cannot
  /// become a measured sample. Modes the probe cannot verify are not held.
  bool _readyToMeasure() {
    final mode = ref.read(glassPocModeProvider);
    // A benchmark needs the real GPU path. FakeGlass during initialization is
    // not a result, so the run waits for full_gpu (and times out if it never comes).
    if (_runner.isRunning && mode == SistrumGlassMode.newFullGlass) {
      return _probeRender().path == SistrumGlassRenderPath.fullGpu;
    }
    if (!sistrumRenderPathVerifiable(mode)) {
      return true;
    }
    return _probeRender().path != SistrumGlassRenderPath.unverified;
  }

  /// The renderer, path, scene and scroll state at the moment of a spike. The
  /// same fields as the copied report, read only when a spike starts.
  Map<String, String> _spikeContext() {
    final context = <String, String>{};
    for (final line in glassPocReportLines(ref)) {
      final eq = line.indexOf('=');
      if (eq > 0) context[line.substring(0, eq)] = line.substring(eq + 1);
    }
    return context;
  }

  void _onMeasurementStart() {
    _monitor.setCollecting(true);
    _renderAtStart = _probeRender();
    _runner.onMeasurementStarted();
  }

  // -- Benchmark host ------------------------------------------------------

  @override
  GlassBenchmarkConfig captureConfig() => (
    mode: ref.read(glassPocModeProvider),
    sharedBackdrop: ref.read(glassPocSharedBackdropProvider),
    speed: ref.read(glassPocScrollSpeedProvider),
    scene: ref.read(glassPocSceneProvider),
  );

  @override
  void applyRun(SistrumGlassMode mode) {
    _modeNotifier.select(mode);
    _sharedNotifier.set(false);
    _speedNotifier.select(kGlassBenchmarkSpeed);
    _sceneNotifier.select(SistrumGlassScene.scrollingContent);
    _autoScroll.setSpeed(kGlassBenchmarkSpeed);
    // Scene D: no animated background. Begins a fresh run with the warm-up.
    _applyScene(SistrumGlassScene.scrollingContent);
    _renderAtStart = null;
  }

  @override
  void haltRun() => _autoScroll.halt();

  @override
  void restoreConfig(GlassBenchmarkConfig config) {
    _modeNotifier.select(config.mode);
    _sharedNotifier.set(config.sharedBackdrop);
    _speedNotifier.select(config.speed);
    _sceneNotifier.select(config.scene);
    _autoScroll.setSpeed(config.speed);
    _applyScene(config.scene);
    if (config.scene.scrolling) _autoScroll.stop();
    _monitor.setCollecting(true);
    _renderAtStart = null;
  }

  @override
  SistrumScrollStatus? scrollStatus() => _autoScroll.status();

  @override
  void attachAggregator(GlassBenchmarkAggregator? aggregator) =>
      _monitor.benchmarkAggregator = aggregator;

  /// Rebuilds only on phase boundaries (start, each run, end). Per-second
  /// progress goes to the status widget, so the measured stage is not rebuilt.
  void _onRunnerPhaseChanged() {
    if (_disposing || !mounted) return;
    setState(() {});
    final phase = _runner.phase;
    final finished =
        phase == GlassBenchmarkPhase.complete ||
        phase == GlassBenchmarkPhase.failed ||
        phase == GlassBenchmarkPhase.cancelled;
    if (finished && _runner.reportText != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_disposing) _showReport(_runner.reportText!);
      });
    }
  }

  String _buildReport(GlassBenchmarkRunner runner) {
    final rate = resolvePerfRefreshRate(PerfFrameMonitor.reportedRefreshRate());
    return formatGlassBenchmarkReport(
      status: runner.phase.name.toUpperCase(),
      deviceLines: [
        'device_model=not accessible from Dart (needs a native channel; not added to production code)',
        'os=${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
        'dart=${Platform.version.split(' ').first}',
        'build_mode=${kProfileMode ? 'profile' : (kReleaseMode ? 'release' : 'debug')}',
        'refresh_hz=${rate.hz.toStringAsFixed(rate.hz % 1 == 0 ? 0 : 2)} '
            '(${rate.isFallback ? 'fallback' : 'reported'})',
        'frame_budget_ms=${(1000 / rate.hz).toStringAsFixed(2)}',
        'shader_filters_supported=${ui.ImageFilter.isShaderFilterSupported}',
        'rendering_backend=not verifiable from Dart; see shader_filters_supported',
      ],
      plan: widget.benchmarkPlan,
      startedAt: runner.startedAt,
      endedAt: runner.endedAt,
      cancelReason: runner.cancelReason,
      failure: runner.failure,
      results: runner.results,
    );
  }

  void _showReport(String text) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Glass benchmark report'),
        content: SizedBox(
          width: double.maxFinite,
          height: 420,
          child: SingleChildScrollView(
            child: SelectableText(
              text,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: text)),
            child: const Text('Copy Report'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _refreshRender() {
    if (!mounted) return;
    final next = _probeRender();
    if (next != _render) setState(() => _render = next);
  }

  @override
  void dispose() {
    // Stopping and disposing the controllers stops their tickers, so nothing
    // keeps animating after the page leaves the tree.
    _disposing = true;
    // A running benchmark is cancelled first and the POC configuration restored.
    _runner.dispose();
    _pathTimer?.cancel();
    _lifecycle?.dispose();
    if (_startedMonitor) _monitor.stop();
    _monitor.benchmarkAggregator = null;
    if (identical(_monitor.spikeRecorder, _spikes)) {
      _monitor.spikeRecorder = null;
    }
    _registry.detach(_autoScroll);
    _autoScroll.dispose();
    _monitor.setCollecting(true);
    _background.dispose();
    _list.dispose();
    super.dispose();
  }

  /// Applies a scene's animation and scroll state. Leaving a scene stops and
  /// resets what it started, so an inactive scene holds no ticker.
  void _applyScene(SistrumGlassScene scene) {
    if (scene.animated) {
      _background.repeat();
    } else {
      _background
        ..stop()
        ..value = 0;
    }
    if (scene.scrolling) {
      _beginScrollRun();
    } else {
      _autoScroll.halt();
      _monitor.reset();
    }
  }

  /// Begins a fresh Scene D run: moves to offset 0, clears the frame window and
  /// holds frames during warm-up. Sampling starts when warm-up ends.
  void _beginScrollRun() {
    _monitor
      ..reset()
      ..setCollecting(false);
    _renderAtStart = null;
    _autoScroll.restart();
  }

  /// A renderer change keeps the scene and speed. In Scene D it starts a
  /// fresh run; elsewhere it clears the frame window.
  void _startBenchmark() {
    _spikes.noteEvent('benchmark=start');
    _runner.start();
  }

  void _onRendererChanged() {
    if (ref.read(glassPocSceneProvider).scrolling) {
      _beginScrollRun();
    } else {
      _monitor.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(glassPocModeProvider);
    final notifier = ref.read(glassPocModeProvider.notifier);
    final sharedBackdrop = ref.watch(glassPocSharedBackdropProvider);
    final scene = ref.watch(glassPocSceneProvider);
    final speed = ref.watch(glassPocScrollSpeedProvider);
    final running = _runner.isRunning;
    final width = MediaQuery.sizeOf(context).width;
    final barWidth = width - 2 * _sideInset;

    return Scaffold(
      appBar: AppBar(title: const Text('Glass POC')),
      body: Column(
        children: [
          // Controls scroll on short screens, so the measured stage below
          // always keeps the space that is left.
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      _sideInset,
                      8,
                      _sideInset,
                      0,
                    ),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final m in SistrumGlassMode.values)
                          ChoiceChip(
                            label: Text(m.label),
                            selected: mode == m,
                            onSelected: running
                                ? null
                                : (_) {
                                    notifier.select(m);
                                    _spikes.noteEvent('renderer=${m.label}');
                                    _onRendererChanged();
                                    _refreshRender();
                                  },
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      _sideInset,
                      8,
                      _sideInset,
                      0,
                    ),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final sc in SistrumGlassScene.values)
                          ChoiceChip(
                            label: Text(sc.label),
                            selected: scene == sc,
                            onSelected: running
                                ? null
                                : (_) {
                                    _spikes.noteEvent('scene=${sc.code}');
                                    ref
                                        .read(glassPocSceneProvider.notifier)
                                        .select(sc);
                                    _applyScene(sc);
                                  },
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      _sideInset,
                      8,
                      _sideInset,
                      0,
                    ),
                    child: Text(
                      _renderLine(_render),
                      key: const Key('pathLine'),
                    ),
                  ),
                  if (scene.scrolling)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        _sideInset,
                        8,
                        _sideInset,
                        0,
                      ),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final s in SistrumScrollSpeed.values)
                            ChoiceChip(
                              label: Text(s.label),
                              selected: speed == s,
                              onSelected: running
                                  ? null
                                  : (_) {
                                      _spikes.noteEvent('speed=${s.name}');
                                      ref
                                          .read(
                                            glassPocScrollSpeedProvider
                                                .notifier,
                                          )
                                          .select(s);
                                      // A speed change stops, applies and starts a
                                      // fresh run from offset 0.
                                      _autoScroll.setSpeed(s);
                                      _monitor
                                        ..reset()
                                        ..setCollecting(false);
                                      setState(() {});
                                    },
                            ),
                          ActionChip(
                            label: Text(
                              _autoScroll.isRunning
                                  ? 'Stop auto-scroll'
                                  : 'Start auto-scroll',
                            ),
                            onPressed: running
                                ? null
                                : () {
                                    if (_autoScroll.isRunning) {
                                      _autoScroll.stop();
                                    } else {
                                      _autoScroll.start();
                                    }
                                    setState(() {});
                                  },
                          ),
                          ActionChip(
                            label: const Text('Reset benchmark'),
                            onPressed: running
                                ? null
                                : () {
                                    _beginScrollRun();
                                    setState(() {});
                                  },
                          ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      _sideInset,
                      8,
                      _sideInset,
                      0,
                    ),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ActionChip(
                          label: const Text('Run Full Benchmark'),
                          onPressed: running ? null : _startBenchmark,
                        ),
                        if (running)
                          ActionChip(
                            label: const Text('Cancel benchmark'),
                            onPressed: () =>
                                _runner.interrupt('cancelled by user'),
                          ),
                        ActionChip(
                          label: const Text('Copy Report'),
                          onPressed: _runner.reportText == null
                              ? null
                              : () => Clipboard.setData(
                                  ClipboardData(text: _runner.reportText!),
                                ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      _sideInset,
                      4,
                      _sideInset,
                      0,
                    ),
                    child: _BenchmarkStatus(runner: _runner),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      _sideInset,
                      4,
                      _sideInset,
                      0,
                    ),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        ActionChip(
                          label: const Text('Reset metrics'),
                          onPressed: running ? null : () => _monitor.reset(),
                        ),
                        ActionChip(
                          label: Text(
                            'Copy spike log (${_spikes.snapshots.length})',
                          ),
                          onPressed: () {
                            final snapshots = _spikes.snapshots;
                            final text = snapshots.isEmpty
                                ? 'sistrum-perf-spikes\nspikes=0'
                                : [
                                    'sistrum-perf-spikes',
                                    'spikes=${snapshots.length}',
                                    for (final snap in snapshots) snap.toText(),
                                  ].join('\n\n');
                            Clipboard.setData(ClipboardData(text: text));
                            setState(() {});
                          },
                        ),
                        ActionChip(
                          label: const Text('Copy metrics'),
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(
                                text: formatPerfReport(
                                  screen: 'glass-poc',
                                  snapshot: _monitor.currentSnapshot(),
                                  glassMode: glassPocReportLabel(
                                    mode: mode,
                                    sharedBackdrop: sharedBackdrop,
                                    scene: scene,
                                  ),
                                  extraLines: glassPocReportLines(ref),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  SwitchListTile(
                    dense: true,
                    title: const Text(
                      'Shared backdrop group (Reference Glass only)',
                    ),
                    subtitle: const Text(
                      'Comparison: one shared backdrop read for the Reference surfaces',
                    ),
                    value: sharedBackdrop,
                    onChanged: running
                        ? null
                        : (v) => ref
                              .read(glassPocSharedBackdropProvider.notifier)
                              .set(v),
                  ),
                  SwitchListTile(
                    dense: true,
                    title: const Text('Show layout outlines (diagnostic only)'),
                    value: _outlines,
                    onChanged: (v) => setState(() => _outlines = v),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ClipRect(
              key: _stageKey,
              child: SistrumGlassScope(
                mode: mode,
                sharedBackdrop: sharedBackdrop,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: _background,
                        builder: (context, _) => CustomPaint(
                          painter: _PocBackgroundPainter(
                            progress: scene.animated ? _background.value : 0,
                            dark:
                                Theme.of(context).brightness == Brightness.dark,
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: ListView.builder(
                        controller: _list,
                        padding: const EdgeInsets.only(
                          top: _GlassPocPageConstants.headerHeight + 24,
                          bottom: 2 * _GlassPocPageConstants.barHeight + 40,
                        ),
                        itemCount: 60,
                        itemBuilder: (context, i) => Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: _sideInset,
                            vertical: 10,
                          ),
                          child: Text(
                            'Track ${i + 1} — scrolling content under glass',
                          ),
                        ),
                      ),
                    ),
                    if (scene.surfaces == 4)
                      Positioned(
                        top: 8,
                        left: _sideInset,
                        right: _sideInset,
                        child: _PocHeader(mode: mode, outline: _outlines),
                      ),
                    Positioned(
                      left: _sideInset,
                      bottom: 12,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _PocMiniPlayer(
                            mode: mode,
                            width: barWidth,
                            outline: _outlines,
                          ),
                          if (scene.surfaces == 4) ...[
                            const SizedBox(height: 10),
                            _PocTabBar(
                              mode: mode,
                              width: barWidth,
                              outline: _outlines,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The render-path line on the page. Fallback and unverified are stated in
/// words, so a FakeGlass render is never shown as Full Glass.
String _renderLine(SistrumGlassRenderReport? report) {
  if (report == null) return 'glass_render_path=… (probing)';
  final fallback = report.fallback;
  final suffix = switch (report.path) {
    SistrumGlassRenderPath.fakeBackdrop when fallback == true =>
      ' · FALLBACK to FakeGlass: ${report.fallbackReason}',
    SistrumGlassRenderPath.unverified => ' · ${report.unverifiedReason}',
    _ => '',
  };
  return 'glass_render_path=${report.path.wire}$suffix';
}

/// Benchmark status line. It listens to per-second progress on its own, so
/// that updates rebuild this line only, never the measured stage.
class _BenchmarkStatus extends StatelessWidget {
  const _BenchmarkStatus({required this.runner});

  final GlassBenchmarkRunner runner;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<GlassBenchmarkProgress>(
      valueListenable: runner.progress,
      builder: (context, p, _) {
        final text = p.phase == GlassBenchmarkPhase.idle
            ? 'Benchmark: idle. Runs the five modes at 900 px/s, about six minutes.'
            : 'Benchmark ${p.phase.name}: ${(p.modeIndex + 1).clamp(1, p.modeCount)}/${p.modeCount} '
                  '${p.modeLabel} · measured ${(p.measuredMs / 1000).toStringAsFixed(1)} s '
                  '· ${p.message}';
        return Text(text, key: const Key('benchmarkStatus'));
      },
    );
  }
}

class _PocHeader extends StatelessWidget {
  const _PocHeader({required this.mode, required this.outline});

  final SistrumGlassMode mode;
  final bool outline;

  @override
  Widget build(BuildContext context) {
    const size = _GlassPocPageConstants.headerHeight;
    return Row(
      children: [
        SistrumGlassSurface(
          mode: mode,
          width: size,
          height: size,
          borderRadius: size / 2,
          diagnosticOutline: outline,
          child: _PocTap(icon: Icons.arrow_back, onTap: () {}),
        ),
        const Spacer(),
        // One capsule for the trailing group, as in the production header.
        SistrumGlassSurface(
          mode: mode,
          width: size * 2.2,
          height: size,
          borderRadius: size / 2,
          diagnosticOutline: outline,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _PocTap(icon: Icons.search, onTap: () {}),
              _PocTap(icon: Icons.more_horiz, onTap: () {}),
            ],
          ),
        ),
      ],
    );
  }
}

class _PocMiniPlayer extends StatelessWidget {
  const _PocMiniPlayer({
    required this.mode,
    required this.width,
    required this.outline,
  });

  final SistrumGlassMode mode;
  final double width;
  final bool outline;

  @override
  Widget build(BuildContext context) {
    return SistrumGlassSurface(
      mode: mode,
      width: width,
      height: _GlassPocPageConstants.barHeight,
      borderRadius: _GlassPocPageConstants.barHeight / 2,
      diagnosticOutline: outline,
      child: Row(
        children: [
          const SizedBox(width: 16),
          const Icon(Icons.music_note, size: 20),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Mini player', overflow: TextOverflow.ellipsis),
          ),
          _PocTap(icon: Icons.play_arrow, onTap: () {}),
        ],
      ),
    );
  }
}

class _PocTabBar extends StatelessWidget {
  const _PocTabBar({
    required this.mode,
    required this.width,
    required this.outline,
  });

  final SistrumGlassMode mode;
  final double width;
  final bool outline;

  @override
  Widget build(BuildContext context) {
    const icons = [
      Icons.home,
      Icons.library_music,
      Icons.search,
      Icons.bar_chart,
    ];
    return SistrumGlassSurface(
      mode: mode,
      width: width,
      height: _GlassPocPageConstants.barHeight,
      borderRadius: _GlassPocPageConstants.barHeight / 2,
      diagnosticOutline: outline,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (var i = 0; i < icons.length; i++)
            _PocTap(icon: icons[i], onTap: () {}, selected: i == 0),
        ],
      ),
    );
  }
}

/// A fixed-size tappable icon with ink feedback. Surfaces in every mode keep
/// the page's Material ancestor, so the ink still paints.
class _PocTap extends StatelessWidget {
  const _PocTap({
    required this.icon,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurface;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox.square(
          dimension: _GlassPocPageConstants.tapSize,
          child: Icon(icon, color: color, size: 22),
        ),
      ),
    );
  }
}

/// Shared geometry constants, kept in one place so every mode lays out the
/// same surfaces.
abstract final class _GlassPocPageConstants {
  static const double headerHeight = 48;
  static const double barHeight = 56;
  static const double tapSize = 48;
}

/// Simulated artwork: a vertical gradient, drifting discs and fine stripes.
/// The stripes give refraction and blur something visible to act on. With
/// [progress] at 0 the frame is fixed, so static runs are repeatable.
class _PocBackgroundPainter extends CustomPainter {
  const _PocBackgroundPainter({required this.progress, required this.dark});

  final double progress;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final colors = dark
        ? const [Color(0xFF2B1B3D), Color(0xFF0B1A2E)]
        : const [Color(0xFFFFD8A8), Color(0xFFA8D8FF)];
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
        ).createShader(rect),
    );

    final disc = Paint()
      ..color = (dark ? const Color(0xFFE94B6E) : const Color(0xFFCC2E33))
          .withValues(alpha: 0.85);
    final discs = <(double, double, double)>[
      (0.25, 0.20, 90),
      (0.80, 0.45, 70),
      (0.35, 0.70, 120),
    ];
    for (var i = 0; i < discs.length; i++) {
      final (fx, fy, r) = discs[i];
      final angle = progress * 2 * math.pi + i * 1.7;
      final center = Offset(
        size.width * fx + math.cos(angle) * 24,
        size.height * fy + math.sin(angle) * 18,
      );
      canvas.drawCircle(center, r, disc);
    }

    final stripe = Paint()
      ..color = (dark ? Colors.white : Colors.black).withValues(alpha: 0.08);
    for (double y = 0; y < size.height; y += 12) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 2), stripe);
    }
  }

  @override
  bool shouldRepaint(_PocBackgroundPainter old) =>
      old.progress != progress || old.dark != dark;
}
