import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sistrum/providers/performance/glass_poc_mode_provider.dart';
import 'package:sistrum/providers/performance/perf_hud_settings_provider.dart';
import 'package:sistrum/services/performance/perf_frame_monitor.dart';
import 'package:sistrum/services/performance/perf_frame_window.dart';
import 'package:sistrum/widgets/performance/perf_hud_geometry.dart';

/// How often the visible numbers refresh. Percentiles are computed only then.
const Duration kPerfHudRefresh = Duration(milliseconds: 750);

const double _compactWidth = 176;
const double _expandedWidth = 300;
const double _compactHeight = 44;

/// Floating developer HUD, mounted once above the app's navigator. It owns
/// its own timer and state; the app root never rebuilds for it.
class PerfHudOverlay extends ConsumerStatefulWidget {
  const PerfHudOverlay({super.key});

  @override
  ConsumerState<PerfHudOverlay> createState() => _PerfHudOverlayState();
}

class _PerfHudOverlayState extends ConsumerState<PerfHudOverlay> {
  late final PerfFrameMonitor _monitor;
  Timer? _refreshTimer;
  Timer? _copiedTimer;
  PerfWindowSnapshot? _snapshot;
  String _route = 'unknown';
  Size _panelSize = const Size(_compactWidth, _compactHeight);
  Offset? _dragOffset;
  bool _copied = false;
  final GlobalKey _panelKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _monitor = ref.read(perfFrameMonitorProvider);
    final enabled = ref.read(perfHudSettingsProvider).enabled;
    if (enabled) _startMonitoring();
  }

  @override
  void dispose() {
    _stopMonitoring();
    _copiedTimer?.cancel();
    super.dispose();
  }

  void _startMonitoring() {
    _monitor.start();
    _refreshTimer ??= Timer.periodic(kPerfHudRefresh, (_) => _refresh());
    _refresh();
  }

  void _stopMonitoring() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _monitor.stop();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _snapshot = _monitor.currentSnapshot();
      _route =
          GoRouter.maybeOf(context)?.routeInformationProvider.value.uri.path ??
          'unknown';
    });
  }

  void _syncEnabled(bool enabled) {
    if (enabled) {
      _startMonitoring();
    } else {
      _stopMonitoring();
      _dragOffset = null;
      setState(() {});
    }
  }

  void _measurePanel() {
    final box = _panelKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !mounted) return;
    final size = box.size;
    if (size != _panelSize) setState(() => _panelSize = size);
  }

  EdgeInsets _safeInsets(MediaQueryData media) => EdgeInsets.fromLTRB(
    math.max(media.viewPadding.left, media.padding.left),
    math.max(media.viewPadding.top, media.padding.top),
    math.max(media.viewPadding.right, media.padding.right),
    math.max(media.viewPadding.bottom, media.padding.bottom),
  );

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(
      perfHudSettingsProvider.select((settings) => settings.enabled),
      (_, enabled) => _syncEnabled(enabled),
    );
    final settings = ref.watch(perfHudSettingsProvider);
    if (!settings.enabled) return const SizedBox.shrink();

    WidgetsBinding.instance.addPostFrameCallback((_) => _measurePanel());
    final media = MediaQuery.of(context);
    final safe = _safeInsets(media);
    final screen = media.size;
    final panel = Size(
      settings.compact ? _compactWidth : _expandedWidth,
      _panelSize.height,
    );
    final saved = settings.position;
    final requested =
        _dragOffset ?? (saved == null ? null : Offset(saved.dx, saved.dy));
    final offset = requested == null
        ? defaultPerfHudOffset(panel: panel, screen: screen, safe: safe)
        : clampPerfHudOffset(
            offset: requested,
            panel: panel,
            screen: screen,
            safe: safe,
          );

    return Stack(
      children: [
        Positioned(
          left: offset.dx,
          top: offset.dy,
          width: panel.width,
          child: _panel(
            opacity: settings.opacity,
            child: settings.compact
                ? _compactBody(context)
                : _expandedBody(context),
          ),
        ),
      ],
    );
  }

  Widget _panel({required double opacity, required Widget child}) {
    return GestureDetector(
      key: _panelKey,
      behavior: HitTestBehavior.opaque,
      onTap: () {
        final compact = ref.read(perfHudSettingsProvider).compact;
        ref.read(perfHudSettingsProvider.notifier).setCompact(!compact);
      },
      onPanUpdate: (details) {
        final media = MediaQuery.of(context);
        final settings = ref.read(perfHudSettingsProvider);
        final panel = Size(
          settings.compact ? _compactWidth : _expandedWidth,
          _panelSize.height,
        );
        final current =
            _dragOffset ??
            (settings.position == null
                ? defaultPerfHudOffset(
                    panel: panel,
                    screen: media.size,
                    safe: _safeInsets(media),
                  )
                : Offset(settings.position!.dx, settings.position!.dy));
        setState(() {
          _dragOffset = clampPerfHudOffset(
            offset: current + details.delta,
            panel: panel,
            screen: media.size,
            safe: _safeInsets(media),
          );
        });
      },
      onPanEnd: (_) {
        final drop = _dragOffset;
        _dragOffset = null;
        if (drop != null) {
          ref
              .read(perfHudSettingsProvider.notifier)
              .setPosition(drop.dx, drop.dy);
        }
        setState(() {});
      },
      child: Container(
        key: const ValueKey('perf-hud-body'),
        decoration: BoxDecoration(
          color: const Color(0xFF101418).withValues(alpha: opacity),
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        child: child,
      ),
    );
  }

  TextStyle get _mono => const TextStyle(
    fontFamily: 'monospace',
    fontSize: 12,
    height: 1.3,
    color: Colors.white,
  );

  String _ms(double? value) => value == null ? 'n/a' : value.toStringAsFixed(2);

  Widget _compactBody(BuildContext context) {
    final snap = _snapshot;
    final fps = snap?.fpsEstimate;
    final jank = snap?.exceedancePct;
    return SizedBox(
      height: _compactHeight - 12,
      child: Row(
        children: [
          const Icon(Icons.drag_indicator, size: 16, color: Colors.white70),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'FPS ${fps == null ? 'n/a' : fps.toStringAsFixed(0)}  '
              'J ${jank == null ? 'n/a' : jank.toStringAsFixed(1)}%',
              style: _mono,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _expandedBody(BuildContext context) {
    final snap = _snapshot;
    final settings = ref.watch(perfHudSettingsProvider);
    final monitor = _monitor;
    final hzLabel = snap == null
        ? 'n/a'
        : '${snap.hz.toStringAsFixed(snap.hz % 1 == 0 ? 0 : 2)} Hz'
              '${snap.hzIsFallback ? ' (fallback)' : ''}';
    final lines = <String>[
      'FPS (estimated)   ${snap?.fpsEstimate == null ? 'n/a' : snap!.fpsEstimate!.toStringAsFixed(1)}',
      'Budget exceeded   ${snap?.exceedancePct == null ? 'n/a' : '${snap!.exceedancePct!.toStringAsFixed(1)}%'}',
      'Frames   ${snap?.frames ?? 0} (total ${snap?.totalFrames ?? 0})',
      'Refresh   $hzLabel',
      'Budget   ${snap == null ? 'n/a' : '${snap.budgetMs.toStringAsFixed(2)} ms'}',
      'Build   p50 ${_ms(snap?.buildP50Ms)}  p90 ${_ms(snap?.buildP90Ms)}  p99 ${_ms(snap?.buildP99Ms)}',
      'Raster  p50 ${_ms(snap?.rasterP50Ms)}  p90 ${_ms(snap?.rasterP90Ms)}  p99 ${_ms(snap?.rasterP99Ms)}',
      'Window   ${snap?.windowMs == null ? 'n/a' : '${(snap!.windowMs! / 1000).toStringAsFixed(1)} s'}',
      'Route   $_route',
      'Glass   ${ref.watch(glassPocModeProvider).label}',
      'Monitoring   ${monitor.isRunning ? 'on' : 'off'}',
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.drag_indicator, size: 18, color: Colors.white70),
            const SizedBox(width: 4),
            const Expanded(
              child: Text(
                'Performance HUD',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  fontSize: 13,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Close',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 18, color: Colors.white),
              onPressed: () =>
                  ref.read(perfHudSettingsProvider.notifier).setEnabled(false),
            ),
          ],
        ),
        for (final line in lines) Text(line, style: _mono),
        const SizedBox(height: 6),
        Wrap(
          spacing: 4,
          children: [
            TextButton(
              onPressed: () {
                monitor.reset();
                _refresh();
              },
              child: const Text('Reset'),
            ),
            TextButton(
              onPressed: _copyReport,
              child: Text(_copied ? 'Copied' : 'Copy'),
            ),
            TextButton(
              onPressed: () => ref
                  .read(perfHudSettingsProvider.notifier)
                  .setCompact(!settings.compact),
              child: const Text('Compact'),
            ),
          ],
        ),
      ],
    );
  }

  void _copyReport() {
    final snap = _snapshot;
    if (snap == null) return;
    Clipboard.setData(
      ClipboardData(
        text: formatPerfReport(
          screen: _route,
          snapshot: snap,
          glassMode: ref.read(glassPocModeProvider).label,
        ),
      ),
    );
    setState(() => _copied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }
}
