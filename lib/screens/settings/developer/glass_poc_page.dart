import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/providers/performance/glass_poc_mode_provider.dart';
import 'package:sistrum/providers/settings/display_refresh_provider.dart';
import 'package:sistrum/services/display/display_refresh_rate.dart';
import 'package:sistrum/providers/settings/settings_provider.dart';
import 'package:sistrum/services/performance/glass_benchmark_aggregator.dart';
import 'package:sistrum/services/performance/perf_frame_monitor.dart';
import 'package:sistrum/services/performance/perf_frame_window.dart';
import 'package:sistrum/services/performance/perf_spike_recorder.dart';
import 'package:sistrum/widgets/glass_poc/glass_benchmark_report.dart';
import 'package:sistrum/widgets/glass_poc/app_glass_backdrop_plan.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_renderer_glass.dart';
import 'package:sistrum/services/performance/glass_frame_schedule.dart';
import 'package:sistrum/widgets/glass_poc/glass_benchmark_run.dart';
import 'package:sistrum/widgets/glass_poc/glass_benchmark_runner.dart';
import 'package:sistrum/widgets/glass_poc/glass_display_mode_log.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_auto_scroll.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_mode.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_render_path.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_scene.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_surface.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_hybrid_atlas.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_hybrid_telemetry.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_lens_glass.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_hybrid_config.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_hybrid_controls.dart';

/// Developer-only Glass POC. Shows the same header, scrolling list, mini
/// player and tab bar in each [SistrumGlassMode], over a background that is
/// either static or animated. Nothing here is wired into production screens.
class GlassPocPage extends ConsumerStatefulWidget {
  const GlassPocPage({super.key, this.benchmarkPlan});

  /// Timing of the benchmarks. Tests pass shorter values; the app uses the
  /// 60-second protocol when this is null.
  final GlassBenchmarkPlan? benchmarkPlan;

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
  final List<BackdropKey> _backdropKeys = List.generate(
    4,
    (_) => BackdropKey(),
  );
  String _backdropConfiguration = 'unlaid_out';

  /// Decisions of the mounted Sistrum Hybrid surfaces. Read by the probe, the
  /// benchmark and the copied metrics; written by the surfaces themselves.
  final SistrumHybridTelemetry _hybridTelemetry = SistrumHybridTelemetry();

  /// The run the benchmark applied last, while it runs.
  GlassBenchmarkRun? _currentRun;

  /// Experimental shared backdrop atlas of the stage (Hybrid only). Scroll and
  /// background animation are its declared invalidations.
  final SistrumHybridAtlas _atlas = SistrumHybridAtlas();
  late final Listenable _atlasInvalidations = Listenable.merge([
    _list,
    _background,
  ]);

  /// Keeps the list's state when the atlas wraps or unwraps the backdrop.
  final GlobalKey _listKey = GlobalKey(debugLabel: 'glass-poc-list');

  /// Per surface, in paint order: may it sample the atlas.
  List<bool> _atlasEligible = const [true, true, true, true];
  Timer? _pathTimer;
  late final PerfSpikeRecorder _spikes;
  AppLifecycleListener? _lifecycle;
  SistrumGlassRenderReport? _render;

  /// Hybrid telemetry shown on the path line, refreshed with the probe.
  SistrumHybridTelemetrySnapshot? _renderHybrid;
  SistrumGlassRenderReport? _renderAtStart;
  bool _outlines = false;
  late final GlassBenchmarkRunner _runner;
  late final GlassPocModeNotifier _modeNotifier;
  late final GlassPocSharedBackdropNotifier _sharedNotifier;
  late final GlassPocSceneNotifier _sceneNotifier;
  late final GlassPocScrollSpeedNotifier _speedNotifier;
  late final GlassBenchmarkPlan _standardPlan;

  /// Surface count of the run in progress. Outside a run the scene decides.
  int _benchSurfaces = 4;
  bool _startedMonitor = false;
  bool _disposing = false;

  /// Display-mode changes Android reports while a benchmark runs.
  final GlassDisplayModeLog _displayModes = GlassDisplayModeLog();

  /// Changes of Android's active mode since the page opened, and the last mode
  /// seen (id, Hz). The runner reads the count at each run's start and end.
  int _displayModeChanges = 0;
  (int, double) _lastAndroidMode = (0, 0);

  @override
  void initState() {
    super.initState();
    _monitor = ref.read(perfFrameMonitorProvider);
    _registry = ref.read(glassPocRunRegistryProvider);
    _modeNotifier = ref.read(glassPocModeProvider.notifier);
    _sharedNotifier = ref.read(glassPocSharedBackdropProvider.notifier);
    _sceneNotifier = ref.read(glassPocSceneProvider.notifier);
    _speedNotifier = ref.read(glassPocScrollSpeedProvider.notifier);
    _standardPlan = widget.benchmarkPlan ?? GlassBenchmarkPlan();
    _autoScroll = SistrumAutoScroller(
      vsync: this,
      controller: _list,
      speed: ref.read(glassPocScrollSpeedProvider),
      onMeasurementStart: _onMeasurementStart,
      measurementReady: _readyToMeasure,
      warmupSeconds:
          _standardPlan.warmup.inMicroseconds / Duration.microsecondsPerSecond,
    );
    // The POC needs frames to measure. Start the monitor if the HUD has not,
    // and stop it again only if this page started it.
    _startedMonitor = !_monitor.isRunning;
    if (_startedMonitor) _monitor.start();
    _runner = GlassBenchmarkRunner(
      host: this,
      backdropConfiguration: () => _backdropConfiguration,
      budgetUs:
          1e6 /
          resolvePerfRefreshRate(PerfFrameMonitor.reportedRefreshRate()).hz,
      plan: _standardPlan,
      onPhaseChanged: _onRunnerPhaseChanged,
      reportBuilder: _buildReport,
    );
    _registry.attach(_autoScroll, this);
    ref.listenManual(displayRefreshProvider, (_, state) {
      // Counted for the whole page, so a run can compare its start and end.
      if (state.activeModeId != 0 &&
          (state.activeModeId != _lastAndroidMode.$1 ||
              state.activeModeHz != _lastAndroidMode.$2)) {
        if (_lastAndroidMode.$1 != 0) _displayModeChanges++;
        _lastAndroidMode = (state.activeModeId, state.activeModeHz);
      }
      if (!_runner.isRunning) return;
      _displayModes.onState(
        state,
        'phase=${_runner.phase.name} mode=${ref.read(glassPocModeProvider).name} '
        'surfaces=$_benchSurfaces',
      );
    });
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
    if (mode == SistrumGlassMode.sistrumHybrid) {
      // From the surfaces' own decisions: no tree walk, no type names.
      return classifyHybridRenderPath(
        expectedSurfaces: _currentSurfaces(),
        snapshot: _hybridSnapshot(),
      );
    }
    return classifySistrumGlassRenderPath(
      mode: mode,
      expectedSurfaces: _currentSurfaces(),
      census: sistrumGlassCensus(context as Element),
      shaderFiltersSupported: ui.ImageFilter.isShaderFilterSupported,
    );
  }

  SistrumHybridTelemetrySnapshot _hybridSnapshot() => _hybridTelemetry.snapshot(
    program: SistrumLensProgram.state,
    atlas: _atlas.stats,
  );

  @override
  SistrumHybridTelemetrySnapshot? hybridTelemetry() =>
      ref.read(glassPocModeProvider) == SistrumGlassMode.sistrumHybrid
      ? _hybridSnapshot()
      : null;

  /// Glass surfaces on the stage: the run's count during a benchmark, otherwise
  /// the scene's.
  int _currentSurfaces() => _runner.isRunning
      ? _benchSurfaces
      : ref.read(glassPocSceneProvider).surfaces;

  /// Sampling waits for a verifiable path, so a blank or fallback render cannot
  /// become a measured sample. Modes the probe cannot verify are not held.
  bool _readyToMeasure() {
    final mode = ref.read(glassPocModeProvider);
    // A benchmark needs the real GPU path. FakeGlass during initialization is
    // not a result, so the run waits for full_gpu (and times out if it never comes).
    if (_runner.isRunning && mode == SistrumGlassMode.newFullGlass) {
      return _probeRender().path == SistrumGlassRenderPath.fullGpu;
    }
    // A Hybrid matrix run measures only its variant's path: Full waits for the
    // lens (blur while the program loads is not a Full result).
    final run = _currentRun;
    if (_runner.isRunning && run != null && run.effectiveHybridConfig != null) {
      final report = _probeRender();
      return report.fallback == false &&
          report.path == expectedGlassRenderPathForRun(run);
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
    hybrid: ref.read(glassPocHybridProvider),
  );

  @override
  void applyRun(GlassBenchmarkRun run) {
    _benchSurfaces = run.surfaces;
    _currentRun = run;
    final hybridConfig = run.effectiveHybridConfig;
    if (hybridConfig != null) {
      // Fixed run settings, whatever the controls held before the run.
      ref.read(glassPocHybridProvider.notifier).update((_) => hybridConfig);
    }
    _modeNotifier.select(run.mode);
    _sharedNotifier.set(false);
    _speedNotifier.select(run.effectiveSpeed);
    _sceneNotifier.select(SistrumGlassScene.scrollingContent);
    _autoScroll.setSpeed(run.effectiveSpeed);
    // Scene D: no animated background. Begins a fresh run with the warm-up.
    _applyScene(SistrumGlassScene.scrollingContent);
    _renderAtStart = null;
  }

  @override
  void haltRun() => _autoScroll.halt();

  @override
  void restoreConfig(GlassBenchmarkConfig config) {
    _currentRun = null;
    ref.read(glassPocHybridProvider.notifier).update((_) => config.hybrid);
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
  ({int beginFrames, int timings}) frameCounts() => _monitor.frameCounts;

  @override
  void attachAggregator(GlassBenchmarkAggregator? aggregator) =>
      _monitor.benchmarkAggregator = aggregator;

  @override
  void attachSchedule(GlassFrameScheduleRecorder? recorder) =>
      _monitor.benchmarkSchedule = recorder;

  @override
  double reportedRefreshHz() =>
      resolvePerfRefreshRate(PerfFrameMonitor.reportedRefreshRate()).hz;

  @override
  DisplayRefreshState androidDisplay() => ref.read(displayRefreshProvider);

  @override
  int displayModeChangeCount() => _displayModeChanges;

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
    if (finished) _displayModes.end();
    if (finished && _runner.reportText != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_disposing) {
          _showReport(_runner.reportText!, diagnostic: _runner.plan.diagnostic);
        }
      });
    }
  }

  String _buildReport(GlassBenchmarkRunner runner) {
    final rate = resolvePerfRefreshRate(PerfFrameMonitor.reportedRefreshRate());
    final nominal = nominalDisplayRefresh(
      android: ref.read(displayRefreshProvider),
      flutterHz: PerfFrameMonitor.reportedRefreshRate(),
    );
    final status = runner.phase.name.toUpperCase();
    final deviceLines = [
      'device_model=not accessible from Dart (needs a native channel; not added to production code)',
      'os=${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      'dart=${Platform.version.split(' ').first}',
      'build_mode=${kProfileMode ? 'profile' : (kReleaseMode ? 'release' : 'debug')}',
      'refresh_hz=${rate.hz.toStringAsFixed(rate.hz % 1 == 0 ? 0 : 2)} '
          '(${rate.isFallback ? 'fallback' : 'reported'})',
      'nominal_refresh_hz=${nominal.hz.toStringAsFixed(2)} '
          '(${nominal.source.name}; Android active mode when available)',
      'frame_budget_ms=${(1000 / nominal.hz).toStringAsFixed(2)}',
      'shader_filters_supported=${ui.ImageFilter.isShaderFilterSupported}',
      'rendering_backend=not verifiable from Dart; see shader_filters_supported',
      ...glassDisplayRefreshLines(
        preferenceHz: ref.read(settingsProvider).displayRefreshRate,
        state: ref.read(displayRefreshProvider),
        log: _displayModes,
      ),
    ];
    if (runner.plan.hybridSharedAb) {
      return formatGlassHybridSharedAbReport(
        status: status,
        deviceLines: deviceLines,
        plan: runner.plan,
        startedAt: runner.startedAt,
        endedAt: runner.endedAt,
        cancelReason: runner.cancelReason,
        failure: runner.failure,
        results: runner.results,
      );
    }
    if (runner.plan.hybridMatrix) {
      return formatGlassHybridMatrixReport(
        status: status,
        deviceLines: deviceLines,
        plan: runner.plan,
        startedAt: runner.startedAt,
        endedAt: runner.endedAt,
        cancelReason: runner.cancelReason,
        failure: runner.failure,
        results: runner.results,
      );
    }
    if (runner.plan.diagnostic) {
      return formatGlassDiagnosticReport(
        status: status,
        deviceLines: deviceLines,
        reportedHz: nominal.hz,
        plan: runner.plan,
        startedAt: runner.startedAt,
        endedAt: runner.endedAt,
        cancelReason: runner.cancelReason,
        failure: runner.failure,
        results: runner.results,
      );
    }
    return formatGlassBenchmarkReport(
      status: status,
      deviceLines: deviceLines,
      plan: runner.plan,
      startedAt: runner.startedAt,
      endedAt: runner.endedAt,
      cancelReason: runner.cancelReason,
      failure: runner.failure,
      results: runner.results,
    );
  }

  void _showReport(String text, {required bool diagnostic}) {
    final copyLabel = diagnostic ? 'Copy Diagnostic Report' : 'Copy Report';
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          diagnostic ? 'Glass diagnostic report' : 'Glass benchmark report',
        ),
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
            child: Text(copyLabel),
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
    final hybrid = hybridTelemetry();
    if (next != _render || hybrid != _renderHybrid) {
      setState(() {
        _render = next;
        _renderHybrid = hybrid;
      });
    }
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
    _atlas.dispose();
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
    _displayModes.begin(ref.read(displayRefreshProvider));
    _runner.start(plan: _standardPlan);
  }

  void _startDiagnostic() {
    _spikes.noteEvent('benchmark=diagnostic start');
    _displayModes.begin(ref.read(displayRefreshProvider));
    _runner.start(plan: GlassBenchmarkPlan.diagnostic(timing: _standardPlan));
  }

  void _startHybridMatrix() {
    _spikes.noteEvent('benchmark=hybrid matrix start');
    _displayModes.begin(ref.read(displayRefreshProvider));
    _runner.start(plan: GlassBenchmarkPlan.hybridMatrix(timing: _standardPlan));
  }

  /// Shared off/on with the current Hybrid controls, at 400 and 900 px/s.
  void _startHybridSharedAb() {
    _spikes.noteEvent('benchmark=hybrid shared A/B start');
    _displayModes.begin(ref.read(displayRefreshProvider));
    _runner.start(
      plan: GlassBenchmarkPlan.hybridSharedAb(
        config: ref.read(glassPocHybridProvider),
        timing: _standardPlan,
      ),
    );
  }

  /// Atlas off/on with the current Hybrid controls, at 400 and 900 px/s.
  void _startHybridAtlasAb() {
    _spikes.noteEvent('benchmark=hybrid atlas A/B start');
    _displayModes.begin(ref.read(displayRefreshProvider));
    _runner.start(
      plan: GlassBenchmarkPlan.hybridSharedAb(
        config: ref.read(glassPocHybridProvider),
        timing: _standardPlan,
        atlas: true,
      ),
    );
  }

  void _startHybridRefractionAb() {
    _spikes.noteEvent('benchmark=hybrid refraction compare start');
    _displayModes.begin(ref.read(displayRefreshProvider));
    _runner.start(
      plan: GlassBenchmarkPlan.hybridRefraction(
        config: ref.read(glassPocHybridProvider),
        timing: _standardPlan,
      ),
    );
  }

  void _startHybridAtlasResolutionSweep() {
    _spikes.noteEvent('benchmark=hybrid atlas resolution sweep start');
    _displayModes.begin(ref.read(displayRefreshProvider));
    _runner.start(
      plan: GlassBenchmarkPlan.hybridAtlasResolution(
        config: ref.read(glassPocHybridProvider),
        timing: _standardPlan,
      ),
    );
  }

  void _startBackdropSharing() {
    _spikes.noteEvent('benchmark=shared backdrop A/B start');
    _displayModes.begin(ref.read(displayRefreshProvider));
    _runner.start(
      plan: GlassBenchmarkPlan.backdropSharing(timing: _standardPlan),
    );
  }

  /// Same paint order and sizes as the Stack below. Account conservatively for
  /// the package's blur, dispersion and refraction sampling reach, not only
  /// silhouette overlap. No shadows are requested by our renderer adapter.
  List<BackdropKey?> _planBackdrop(
    BoxConstraints constraints,
    SistrumGlassMode mode,
    int surfaces,
    double barWidth,
    SistrumHybridConfig hybrid,
  ) {
    const h = _GlassPocPageConstants.headerHeight;
    const b = _GlassPocPageConstants.barHeight;
    final width = constraints.maxWidth;
    final height = constraints.maxHeight;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final boxes = <Rect>[
      if (surfaces == 4) ...[
        Rect.fromLTWH(rtl ? width - _sideInset - h : _sideInset, 8, h, h),
        Rect.fromLTWH(
          rtl ? _sideInset : width - _sideInset - h * 2.2,
          8,
          h * 2.2,
          h,
        ),
      ],
      Rect.fromLTWH(
        _sideInset,
        height - 12 - (surfaces >= 2 ? b * 2 + 10 : b),
        barWidth,
        b,
      ),
      if (surfaces >= 2)
        Rect.fromLTWH(_sideInset, height - 12 - b, barWidth, b),
    ];
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final hybridShared =
        mode == SistrumGlassMode.sistrumHybrid && hybrid.sharesBackdrop;
    final hybridAtlas =
        mode == SistrumGlassMode.sistrumHybrid && hybrid.usesAtlas;
    final settings = sistrumRendererGlassSettings(dark: dark);
    // Conservative envelope of the pinned package: contour is 0.75 dp;
    // preset frost scales by at most 1.78 and has a 5.8-device-pixel floor.
    // Use public settings only; never depend on @internal package getters.
    final outset = 2 + 1 / dpr;
    final frost = math.max(
      math.max(settings.frost * 1.78, 2.1),
      5.8 / math.max(dpr, 2),
    );
    final shrink = settings.backdropShrink.clamp(0.0, 0.75);
    final paintBounds = [for (final box in boxes) box.inflate(outset)];
    final samples = [
      for (final box in boxes)
        hybridShared || hybridAtlas
            // Hybrid reach: the blur kernel (3 sigma) plus the largest lens
            // shift (half the rim band) plus a pixel of rounding.
            ? box.inflate(
                hybrid.blurSigma * 3 +
                    (hybrid.isGenuineRefraction
                        ? kSistrumLensRefraction * kSistrumLensBandLogical / 2
                        : 0) +
                    1 +
                    1 / dpr,
              )
            : box.inflate(
                outset +
                    frost * 3 +
                    1 / dpr +
                    math.max(0.001, settings.refractionAmount) *
                        (1 + settings.dispersion.abs() * 0.5) +
                    (1 / (1 - shrink) - 1) * box.longestSide / 2,
              ),
    ];
    final shared =
        mode == SistrumGlassMode.newFullGlassSharedBackdrop || hybridShared;
    var assignments = shared
        ? appGlassBackdropGroups(
            paintBounds: paintBounds,
            samplingBounds: samples,
          )
        : List.generate(boxes.length, (i) => i);
    // The atlas holds the backdrop painted before any glass, so a surface may
    // use it only when nothing painted earlier (glass included) enters its
    // blur reach: exactly the planner's first group.
    final atlasGroups = hybridAtlas
        ? appGlassBackdropGroups(
            paintBounds: paintBounds,
            samplingBounds: samples,
          )
        : null;
    _atlasEligible = [
      for (var i = 0; i < boxes.length; i++)
        atlasGroups?[i] == 0 || !hybridAtlas,
    ];
    if (hybridShared && hybrid.isGenuineRefraction) {
      // Two equal lens filters on one key would be rendered once over the
      // whole screen. Equal lens uniforms mean equal size and radius.
      assignments = appGlassSplitEqualFilters(assignments, [
        for (final box in boxes) '${box.width}x${box.height}',
      ]);
    }
    _backdropConfiguration =
        'groups=${assignments.join(',')}; '
        'roles=${surfaces == 4
            ? 'back,trailing,mini,tab'
            : surfaces == 2
            ? 'mini,tab'
            : 'mini'}; '
        'stage=${width}x$height; dpr=$dpr; rtl=$rtl; dark=$dark'
        '${hybridAtlas ? '; atlas_eligible=${_atlasEligible.map((e) => e ? 1 : 0).join(',')}' : ''}';
    _runner.observeBackdropConfiguration(_backdropConfiguration);
    return [
      for (final group in assignments) shared ? _backdropKeys[group] : null,
    ];
  }

  /// The stage stack. With the atlas on it is its own repaint boundary, so
  /// the atlas surfaces' per-frame repaint stays inside the stage, painted
  /// after the backdrop boundary in the same pass.
  Widget _atlasStage({required bool atlasOn, required List<Widget> children}) {
    final stack = Stack(children: children);
    return atlasOn ? RepaintBoundary(child: stack) : stack;
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
    final hybrid = ref.watch(glassPocHybridProvider);
    final scene = ref.watch(glassPocSceneProvider);
    final surfaces = _runner.isRunning ? _benchSurfaces : scene.surfaces;
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
                      _renderLine(_render, hybrid: _renderHybrid),
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
                        ActionChip(
                          label: const Text('Run Diagnostic Repeats'),
                          onPressed: running ? null : _startDiagnostic,
                        ),
                        ActionChip(
                          label: const Text('Run Shared Backdrop A/B'),
                          onPressed: running ? null : _startBackdropSharing,
                        ),
                        ActionChip(
                          key: const Key('hybridSharedAb'),
                          label: const Text('Run Hybrid Shared A/B (current)'),
                          onPressed: running ? null : _startHybridSharedAb,
                        ),
                        ActionChip(
                          key: const Key('hybridAtlasAb'),
                          label: const Text('Run Hybrid Atlas A/B (current)'),
                          onPressed: running ? null : _startHybridAtlasAb,
                        ),
                        ActionChip(
                          key: const Key('hybridRefractionAb'),
                          label: const Text('Run Refraction OFF/Edge/Full'),
                          onPressed: running ? null : _startHybridRefractionAb,
                        ),
                        ActionChip(
                          key: const Key('hybridAtlasResolutionSweep'),
                          label: const Text('Run Atlas Resolution sweep'),
                          onPressed: running
                              ? null
                              : _startHybridAtlasResolutionSweep,
                        ),
                        ActionChip(
                          key: const Key('hybridMatrix'),
                          label: const Text('Run Hybrid A–E Matrix'),
                          onPressed: running ? null : _startHybridMatrix,
                        ),
                        if (running)
                          ActionChip(
                            label: const Text('Cancel benchmark'),
                            onPressed: () =>
                                _runner.interrupt('cancelled by user'),
                          ),
                        ActionChip(
                          label: Text(
                            _runner.plan.backdropSharing
                                ? 'Copy Shared Backdrop Report'
                                : _runner.plan.diagnostic
                                ? 'Copy Diagnostic Report'
                                : 'Copy Report',
                          ),
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
                  if (mode == SistrumGlassMode.sistrumHybrid)
                    SistrumHybridControls(running: running),
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                final keys = _planBackdrop(
                  constraints,
                  mode,
                  surfaces,
                  barWidth,
                  hybrid,
                );
                final atlasOn =
                    mode == SistrumGlassMode.sistrumHybrid && hybrid.usesAtlas;
                _atlas.configure(
                  requested:
                      mode == SistrumGlassMode.sistrumHybrid &&
                      hybrid.sharedAtlas,
                  unsupportedReason: hybrid.atlasUnsupportedReason,
                  sigma: hybrid.blurSigma,
                  resolution: hybrid.atlasResolution,
                  edgeRefraction: hybrid.usesAtlasEdge,
                  chromatic: hybrid.chromaticAberration,
                  invalidations: _atlasInvalidations,
                );
                final background = Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _background,
                    builder: (context, _) => CustomPaint(
                      painter: _PocBackgroundPainter(
                        progress: scene.animated ? _background.value : 0,
                        dark: Theme.of(context).brightness == Brightness.dark,
                      ),
                    ),
                  ),
                );
                final list = Positioned.fill(
                  child: ListView.builder(
                    key: _listKey,
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
                );
                return ClipRect(
                  key: _stageKey,
                  child: SistrumHybridAtlasScope(
                    atlas: _atlas,
                    child: SistrumHybridTelemetryScope(
                      telemetry: _hybridTelemetry,
                      child: SistrumHybridConfigScope(
                        config: hybrid,
                        child: SistrumGlassScope(
                          mode: mode,
                          sharedBackdrop: sharedBackdrop,
                          child: _atlasStage(
                            atlasOn: atlasOn,
                            children: [
                              // Atlas on: the content under the glass is one
                              // repaint boundary the atlas records. Off: as before.
                              if (atlasOn)
                                Positioned.fill(
                                  child: SistrumAtlasBackdrop(
                                    key: _atlas.backdropKey,
                                    child: Stack(children: [background, list]),
                                  ),
                                )
                              else ...[
                                background,
                                list,
                              ],
                              if (surfaces == 4)
                                Positioned(
                                  top: 8,
                                  left: _sideInset,
                                  right: _sideInset,
                                  child: _PocHeader(
                                    mode: mode,
                                    outline: _outlines,
                                    backdropKeys: keys.take(2).toList(),
                                    atlasEligible: _atlasEligible
                                        .take(2)
                                        .toList(),
                                  ),
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
                                      backdropKey: keys[surfaces == 4 ? 2 : 0],
                                      atlasEligible:
                                          _atlasEligible[surfaces == 4 ? 2 : 0],
                                    ),
                                    if (surfaces >= 2) ...[
                                      const SizedBox(height: 10),
                                      _PocTabBar(
                                        mode: mode,
                                        width: barWidth,
                                        outline: _outlines,
                                        backdropKey:
                                            keys[surfaces == 4 ? 3 : 1],
                                        atlasEligible:
                                            _atlasEligible[surfaces == 4
                                                ? 3
                                                : 1],
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
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// The render-path line on the page. Fallback and unverified are stated in
/// words, so a FakeGlass render is never shown as Full Glass.
String _renderLine(
  SistrumGlassRenderReport? report, {
  SistrumHybridTelemetrySnapshot? hybrid,
}) {
  if (report == null) return 'glass_render_path=… (probing)';
  final fallback = report.fallback;
  final suffix = switch (report.path) {
    SistrumGlassRenderPath.fakeBackdrop when fallback == true =>
      ' · FALLBACK to FakeGlass: ${report.fallbackReason}',
    SistrumGlassRenderPath.unverified => ' · ${report.unverifiedReason}',
    _ when fallback == true => ' · FALLBACK: ${report.fallbackReason}',
    _ => '',
  };
  final hybridText = hybrid == null
      ? ''
      : ' · backdrop_reads=${hybrid.backdropReads}'
            ' shader_filters=${hybrid.shaderFilters}'
            ' shared=${hybrid.sharedBackdropActive}'
            ' lens_program=${hybrid.program?.status.wire ?? 'unknown'}';
  return 'glass_render_path=${report.path.wire}$suffix$hybridText';
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
  const _PocHeader({
    required this.mode,
    required this.outline,
    required this.backdropKeys,
    this.atlasEligible = const [true, true],
  });

  final SistrumGlassMode mode;
  final bool outline;
  final List<BackdropKey?> backdropKeys;
  final List<bool> atlasEligible;

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
          backdropKey: backdropKeys[0],
          atlasEligible: atlasEligible[0],
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
          backdropKey: backdropKeys[1],
          atlasEligible: atlasEligible[1],
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
    this.backdropKey,
    this.atlasEligible = true,
  });

  final SistrumGlassMode mode;
  final double width;
  final bool outline;
  final BackdropKey? backdropKey;
  final bool atlasEligible;

  @override
  Widget build(BuildContext context) {
    return SistrumGlassSurface(
      mode: mode,
      width: width,
      height: _GlassPocPageConstants.barHeight,
      borderRadius: _GlassPocPageConstants.barHeight / 2,
      diagnosticOutline: outline,
      backdropKey: backdropKey,
      atlasEligible: atlasEligible,
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
    this.backdropKey,
    this.atlasEligible = true,
  });

  final SistrumGlassMode mode;
  final double width;
  final bool outline;
  final BackdropKey? backdropKey;
  final bool atlasEligible;

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
      backdropKey: backdropKey,
      atlasEligible: atlasEligible,
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
