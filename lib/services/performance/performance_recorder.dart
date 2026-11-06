import 'dart:collection';
import 'dart:math' as math;

double? performancePercentile(Iterable<double> values, double percentile) {
  final sorted = values.where((v) => v.isFinite).toList()..sort();
  if (sorted.isEmpty) return null;
  final rank = ((sorted.length - 1) * percentile.clamp(0, 1));
  final lower = rank.floor(), upper = rank.ceil();
  return sorted[lower] + (sorted[upper] - sorted[lower]) * (rank - lower);
}

class PerformanceFrame {
  const PerformanceFrame({
    required this.observedUs,
    required this.engineUs,
    required this.buildMs,
    required this.rasterMs,
    required this.spanMs,
    required this.budgetMs,
    required this.screen,
    this.gapMs,
  });
  final int observedUs, engineUs;
  final double buildMs, rasterMs, spanMs;
  final double? budgetMs, gapMs;
  final String screen;
  bool get slow => budgetMs != null && math.max(buildMs, rasterMs) > budgetMs!;
}

class PerformanceInteraction {
  PerformanceInteraction({
    required this.pointerUs,
    required this.pointerUtc,
    required this.idleMs,
    required this.screen,
    this.pointerEventUs,
  });
  final int? pointerEventUs;
  final int pointerUs;
  final DateTime pointerUtc;
  final double idleMs;
  final String screen;
  int? firstFrameObservedUs, firstFrameEngineUs;
  final frames = <PerformanceFrame>[];
}

/// No rendering, platform calls or persistence. All times in [observedUs] are
/// from one injected monotonic Dart clock. Engine timestamps are kept separate.
class PerformanceRecorder {
  static const maxFrames = 16384;
  bool enabled = false, firstInteraction = false;
  int windowMs = 10000, idleMs = 3000;
  String screen = 'unavailable';
  int? _startedUs, _stoppedUs, _lastInteractionUs, _lastEngineUs;
  final _recent = <String, PerformanceSnapshot>{};
  Map<String, PerformanceSnapshot> get recentSnapshots =>
      UnmodifiableMapView(_recent);
  final _frames = ListQueue<PerformanceFrame>();
  final interactions = ListQueue<PerformanceInteraction>();
  PerformanceInteraction? activeInteraction;
  DateTime? lastInteractionUtc;

  void changeScreen(String value, int nowUs) {
    if (screen == value) return;
    final previous = snapshot(nowUs);
    if (previous.frames.isNotEmpty) {
      _recent.remove(screen);
      if (_recent.length == 8) _recent.remove(_recent.keys.first);
      _recent[screen] = previous;
    }
    screen = value;
    _frames.clear();
    _lastEngineUs = null;
    _startedUs = nowUs;
    if (!enabled) _stoppedUs = nowUs;
  }

  void configure({
    required bool enabled,
    required bool firstInteraction,
    required int windowMs,
    required int idleMs,
    required int nowUs,
  }) {
    final changed = this.enabled != enabled;
    this.enabled = enabled;
    this.firstInteraction = firstInteraction;
    this.windowMs = windowMs.clamp(1000, 60000);
    this.idleMs = idleMs.clamp(500, 30000);
    if (changed) {
      if (enabled) {
        reset(nowUs);
      } else {
        _stoppedUs = nowUs;
        activeInteraction = null;
      }
    }
    if (!firstInteraction) activeInteraction = null;
    prune(nowUs);
  }

  void reset(int nowUs) {
    _frames.clear();
    _recent.clear();
    _stoppedUs = enabled ? null : nowUs;
    interactions.clear();
    activeInteraction = null;
    _startedUs = nowUs;
    _lastInteractionUs = null;
    lastInteractionUtc = null;
    _lastEngineUs = null;
  }

  void prune(int nowUs) {
    if (!enabled && _stoppedUs != null) nowUs = _stoppedUs!;
    while (_frames.isNotEmpty &&
        _frames.first.observedUs < nowUs - windowMs * 1000) {
      _frames.removeFirst();
    }
  }

  /// First event after idle starts one bounded capture. Pointer moves update
  /// activity without changing gesture recognition or scheduling a frame.
  bool pointer(int nowUs, DateTime utc, {int? eventUs}) {
    if (!enabled || !firstInteraction) return false;
    final since = nowUs - (_lastInteractionUs ?? _startedUs ?? nowUs);
    _lastInteractionUs = nowUs;
    lastInteractionUtc = utc;
    if (since < idleMs * 1000 || activeInteraction != null) return false;
    final capture = PerformanceInteraction(
      pointerUs: nowUs,
      pointerEventUs: eventUs,
      pointerUtc: utc,
      idleMs: since / 1000,
      screen: screen,
    );
    if (interactions.length == 8) interactions.removeFirst();
    interactions.add(capture);
    activeInteraction = capture;
    return true;
  }

  void observeInteractionFrame(int nowUs, int engineUs) {
    final capture = activeInteraction;
    if (!enabled ||
        capture == null ||
        nowUs < capture.pointerUs ||
        nowUs - capture.pointerUs > 1000000 ||
        capture.firstFrameObservedUs != null) {
      return;
    }
    capture.firstFrameObservedUs = nowUs;
    capture.firstFrameEngineUs = engineUs;
  }

  void finishInteraction() => activeInteraction = null;

  void addFrame({
    required int observedUs,
    required int engineUs,
    required double buildMs,
    required double rasterMs,
    required double spanMs,
    required double? budgetMs,
  }) {
    if (!enabled) return;
    final previous = _lastEngineUs;
    // Never subtract Dart receipt time from engine event time.
    final gap = previous != null && engineUs > previous
        ? (engineUs - previous) / 1000
        : null;
    if (previous == null || engineUs > previous) {
      _lastEngineUs = engineUs;
    }
    final frame = PerformanceFrame(
      observedUs: observedUs,
      engineUs: engineUs,
      buildMs: buildMs,
      rasterMs: rasterMs,
      spanMs: spanMs,
      budgetMs: budgetMs,
      gapMs: gap,
      screen: screen,
    );
    if (_frames.length == maxFrames) _frames.removeFirst();
    _frames.add(frame);
    prune(observedUs);
    // Release FrameTimings can arrive after the observation timer closes.
    // Retain matching late samples in at most eight engine-bounded captures.
    if (firstInteraction) {
      for (final capture in interactions) {
        final first = capture.firstFrameEngineUs;
        if (first != null &&
            engineUs >= first &&
            engineUs - first <=
                1000000 - (capture.firstFrameObservedUs! - capture.pointerUs) &&
            capture.frames.length < 512) {
          capture.frames.add(frame);
        }
      }
    }
  }

  PerformanceSnapshot snapshot(int nowUs) {
    if (!enabled) nowUs = _stoppedUs ?? nowUs;
    prune(nowUs);
    return PerformanceSnapshot(
      frames: List.unmodifiable(_frames.where((f) => f.screen == screen)),
      durationMs: _startedUs != null
          ? math.min(
              windowMs.toDouble(),
              math.max(0, (nowUs - (_startedUs ?? nowUs)) / 1000),
            )
          : 0,
      screen: screen,
    );
  }
}

class PerformanceSnapshot {
  PerformanceSnapshot({
    required this.frames,
    required this.durationMs,
    required this.screen,
  });
  final List<PerformanceFrame> frames;
  final double durationMs;
  final String screen;
  double? get fps => durationMs > 0 ? frames.length * 1000 / durationMs : null;
  int get slow => frames.where((f) => f.slow).length;
  int get classified => frames.where((f) => f.budgetMs != null).length;
  double? get jankPercent => classified > 0 ? slow * 100 / classified : null;
  late final Map<String, List<double>> _sorted = {
    'build': frames.map((f) => f.buildMs).toList()..sort(),
    'raster': frames.map((f) => f.rasterMs).toList()..sort(),
    'span': frames.map((f) => f.spanMs).toList()..sort(),
    'gap': frames.where((f) => f.gapMs != null).map((f) => f.gapMs!).toList()
      ..sort(),
  };
  double? percentile(String series, double p) {
    final values = _sorted[series];
    if (values == null || values.isEmpty) return null;
    final rank = (values.length - 1) * p.clamp(0, 1);
    return values[rank.floor()] +
        (values[rank.ceil()] - values[rank.floor()]) * (rank - rank.floor());
  }
}

/// Android-reported facts, not physical presentation measurements.
class PerformanceDisplay {
  PerformanceDisplay([Map<Object?, Object?>? values])
    : values = Map.unmodifiable(values ?? {});
  final Map<Object?, Object?> values;
  double? number(String key) {
    final n = values[key];
    return n is num && n.isFinite && n > 0 ? n.toDouble() : null;
  }

  double? get hz => number('active_hz');
  double? get budgetMs => hz == null ? null : 1000 / hz!;
  int? get transitions => (values['transition_count'] as num?)?.toInt();
  List<Object?> get changes =>
      (values['changes'] as List?)?.cast<Object?>() ?? const [];
}

String formatPerformanceReport({
  required PerformanceSnapshot snapshot,
  required PerformanceDisplay display,
  required String build,
  required String abi,
  required String flutterHz,
  required bool enabled,
  required List<PerformanceInteraction> interactions,
  DateTime? lastInteractionUtc,
  String glassConfiguration = 'unavailable',
  bool? motionArtworkEnabled,
}) {
  String value(num? n) =>
      n == null || !n.isFinite ? 'unavailable' : n.toStringAsFixed(2);
  final last = interactions.lastOrNull;
  final out = <String>[
    'mornye-performance',
    'build=$build',
    'abi=$abi',
    'screen=${snapshot.screen}',
    'monitoring=$enabled',
    'requested_hz=${value(display.number('requested_hz'))}',
    'requested_mode_id=${display.values['requested_mode_id'] ?? 'unavailable'}',
    'request_supported=${display.values['request_supported'] ?? 'unavailable'}',
    'reported_hz=${value(display.hz)}',
    'android_display_refresh_hz=${value(display.number('display_hz'))}',
    'flutter_reported_hz=$flutterHz',
    'display_mode_id=${display.values['active_mode_id'] ?? 'unavailable'}',
    'supported_hz=${display.values['supported_hz'] ?? 'unavailable'}',
    'frame_budget_ms=${value(display.budgetMs)}',
    'display_snapshot=latest_native_event_at_export; archived_frames_keep_their_own_budgets',
    'frame_budget_source=${display.hz == null ? 'unavailable' : 'android_active_mode'}',
    'frames=${snapshot.frames.length}',
    'window_ms=${value(snapshot.durationMs)}',
    'fps_rendered=${value(snapshot.fps)}',
    'fps_definition=FrameTiming samples received per rolling elapsed second; includes idle',
    for (final series in ['build', 'raster', 'span', 'gap'])
      for (final p in [0.50, 0.90, 0.95, 0.99])
        '${series == 'gap' ? 'frame_gap' : series}_ms_p${(p * 100).round()}=${value(snapshot.percentile(series, p))}',
    'longest_frame_gap_ms=${value(snapshot.percentile('gap', 1))}',
    'jank_percent=${value(snapshot.jankPercent)}',
    'budget_exceedance_percent=${value(snapshot.jankPercent)}',
    'slow_frames=${snapshot.slow}',
    'classified_frames=${snapshot.classified}',
    'jank_definition=build_or_raster_exceeds_reported_budget_at_callback_delivery',
    'idle_policy=low_frame_count_and_idle_gaps_are_not_jank',
    'span_budget_exceedance_percent=${value(snapshot.classified == 0 ? null : snapshot.frames.where((f) => f.budgetMs != null && f.spanMs > f.budgetMs!).length * 100 / snapshot.classified)}',
    'window_mixed_refresh=${snapshot.frames.map((f) => f.budgetMs).toSet().length > 1}',
    'idle_duration_ms=${value(last?.idleMs)}',
    'last_interaction_utc=${lastInteractionUtc?.toIso8601String() ?? 'unavailable'}',
    'first_pointer_event_us=${last?.pointerEventUs ?? 'unavailable'}',
    'first_pointer_observed_us=${last?.pointerUs ?? 'unavailable'}',
    'first_observed_engine_frame_us=${last?.firstFrameEngineUs ?? 'unavailable'}',
    'first_observed_frame_us=${last?.firstFrameObservedUs ?? 'unavailable'}',
    'first_interaction_frame_delay_ms=${value(last?.firstFrameObservedUs == null ? null : (last!.firstFrameObservedUs! - last.pointerUs) / 1000)}',
    'interaction_delay_definition=pointer_callback_delivery_to_first_observed_post_frame_callback; NOT_pointer_to_photon',
    'interaction_capture_ms=1000',
    'interaction_history_count=${interactions.length}',
    'interaction_frames=${last?.frames.length ?? 0}',
    'interaction_slow_frames=${last?.frames.where((f) => f.slow).length ?? 0}',
    'refresh_transition_count=${display.transitions ?? 'unavailable'}',
    'refresh_transition_scope=activity_lifetime_or_last_manual_reset; bounded_event_history=32',
    'display_changes=${display.changes}',
    'glass_mode=original_mornye',
    'glass_configuration=$glassConfiguration',
    'glass_configuration_scope=current_preferences_at_export',
    'motion_artwork_enabled=${motionArtworkEnabled ?? 'unavailable'}',
    'animated_background=unavailable',
    'screen_attribution=timing_callback_delivery; unnamed_routes_unavailable',
    'presentation_latency=unavailable',
    'limitations=FrameTiming is batched; callback observation is not display presentation. '
        'Build+raster is not presentation latency. Interaction timing association uses '
        'raw engine frame timestamps after an observed post-frame callback; '
        'missing/unmatched timings remain unavailable. Budget changes are attributed at delivery.',
  ];
  for (var i = 0; i < interactions.length; i++) {
    final capture = interactions[i];
    out.add(
      'interaction_$i=${capture.pointerUtc.toIso8601String()}; screen=${capture.screen}; idle_ms=${value(capture.idleMs)}',
    );
    out.add(
      'interaction_${i}_nearby_display_changes=${display.changes.where((event) {
        if (event is! Map || event['at_ms'] is! num) return false;
        final delta = (event['at_ms'] as num) - capture.pointerUtc.millisecondsSinceEpoch;
        return delta >= -500 && delta <= 1500;
      }).toList()}',
    );
    for (final frame in capture.frames) {
      out.add(
        'interaction_${i}_frame=engine_us:${frame.engineUs},screen:${frame.screen},build_ms:${value(frame.buildMs)},raster_ms:${value(frame.rasterMs)},span_ms:${value(frame.spanMs)},gap_ms:${value(frame.gapMs)},slow:${frame.slow}',
      );
    }
  }
  return out.join('\n');
}
