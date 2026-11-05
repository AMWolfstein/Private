import 'dart:typed_data';

/// Reads the renderer, path, scene and scroll state at the moment of a trigger.
typedef PerfSpikeContextReader = Map<String, String> Function();

/// Histogram buckets for frame intervals (time between frame end times), in
/// milliseconds. The last bucket is open-ended.
const List<double> kPerfIntervalBucketsMs = [17, 25, 34, 50, 100];

/// One captured degradation: the frames before and after its trigger window,
/// with summaries computed at capture time. Every timing is Flutter's
/// FrameTiming, not displayed (presented) frame timing.
class PerfSpikeSnapshot {
  const PerfSpikeSnapshot({
    required this.wallClock,
    required this.windowStartEndUs,
    required this.durationMs,
    required this.preSegment,
    required this.postSegment,
    required this.intervalCounts,
    required this.context,
    required this.events,
  });

  /// Wall-clock time when the trigger fired.
  final DateTime wallClock;

  /// Frame end time (engine clock, microseconds) of the first frame of the
  /// trigger window.
  final int windowStartEndUs;

  /// Span from the first trigger-window frame to the last post-window frame.
  final double durationMs;

  final PerfSpikeSegment preSegment;
  final PerfSpikeSegment postSegment;

  /// Counts per [kPerfIntervalBucketsMs] bucket, plus the open bucket.
  final List<int> intervalCounts;

  /// Renderer, path, scene, speed and scroll state at the trigger.
  final Map<String, String> context;

  /// Renderer, scene and lifecycle events that happened near the spike.
  final List<String> events;

  /// Lines for a copied report. Every value is a measured or observed value.
  String toText() {
    final lines = <String>[
      'spike wall_clock=${wallClock.toIso8601String()}',
      'spike duration_ms=${durationMs.toStringAsFixed(0)}',
      'spike window_start_end_us=$windowStartEndUs',
      for (final e in context.entries) 'spike_${e.key}=${e.value}',
      preSegment.toLine('pre'),
      postSegment.toLine('post'),
      'spike_interval_ms=${_intervalText()}',
      for (final e in events) 'spike_event=$e',
    ];
    return lines.join('\n');
  }

  String _intervalText() {
    final labels = <String>[
      for (final b in kPerfIntervalBucketsMs) '<=${b.toStringAsFixed(0)}',
      '>${kPerfIntervalBucketsMs.last.toStringAsFixed(0)}',
    ];
    return [
      for (var i = 0; i < intervalCounts.length; i++)
        '${labels[i]}:${intervalCounts[i]}',
    ].join(',');
  }
}

/// Summary of one segment of frames (before or after the trigger).
class PerfSpikeSegment {
  const PerfSpikeSegment({
    required this.frames,
    required this.exceedancePct,
    required this.buildP50Ms,
    required this.buildP90Ms,
    required this.buildP99Ms,
    required this.rasterP50Ms,
    required this.rasterP90Ms,
    required this.rasterP99Ms,
    required this.spanP90Ms,
  });

  final int frames;

  /// Share of frames whose total span exceeded the budget, percent.
  final double exceedancePct;

  final double buildP50Ms;
  final double buildP90Ms;
  final double buildP99Ms;
  final double rasterP50Ms;
  final double rasterP90Ms;
  final double rasterP99Ms;

  /// P90 of total span (vsync start to raster finish), the value the
  /// exceedance counts against the budget.
  final double spanP90Ms;

  String toLine(String name) =>
      'spike_$name frames=$frames exceedance=${exceedancePct.toStringAsFixed(1)}% '
      'build_ms_p50=${buildP50Ms.toStringAsFixed(2)} '
      'build_ms_p90=${buildP90Ms.toStringAsFixed(2)} '
      'build_ms_p99=${buildP99Ms.toStringAsFixed(2)} '
      'raster_ms_p50=${rasterP50Ms.toStringAsFixed(2)} '
      'raster_ms_p90=${rasterP90Ms.toStringAsFixed(2)} '
      'raster_ms_p99=${rasterP99Ms.toStringAsFixed(2)} '
      'span_ms_p90=${spanP90Ms.toStringAsFixed(2)}';
}

enum _SpikeState { armed, capturing, disarmed }

/// Captures sustained frame-budget degradation for the developer POC.
///
/// A spike is "sustained" when at least [triggerOverBudget] of the last
/// [windowFrames] frames exceed the budget. The recorder then keeps the
/// [preFrames] frames before the trigger and [postFrames] frames after it. It
/// re-arms only after the window falls to [rearmOverBudget] or fewer.
///
/// Hot path: [onFrame] writes into preallocated buffers. Allocation happens only
/// when a spike starts and when it is finished, never per frame.
class PerfSpikeRecorder {
  PerfSpikeRecorder({
    this.preFrames = 120,
    this.postFrames = 120,
    this.windowFrames = 30,
    this.triggerOverBudget = 15,
    this.rearmOverBudget = 3,
    this.maxSnapshots = 8,
    this.maxEvents = 32,
  }) : assert(triggerOverBudget > rearmOverBudget),
       _ringBuild = Int64List(preFrames),
       _ringRaster = Int64List(preFrames),
       _ringSpan = Int64List(preFrames),
       _ringEnd = Int64List(preFrames),
       _windowOver = Uint8List(windowFrames);

  final int preFrames;
  final int postFrames;
  final int windowFrames;
  final int triggerOverBudget;
  final int rearmOverBudget;
  final int maxSnapshots;
  final int maxEvents;

  /// Budget for the span comparison, in microseconds. Set from the HUD's
  /// resolved refresh rate (budget = 1e6 / hz).
  double budgetUs = 1e6 / 60;

  /// Supplies renderer, path, scene and scroll state at the moment of a
  /// trigger. Called once per spike, never per frame.
  PerfSpikeContextReader? contextReader;

  final Int64List _ringBuild;
  final Int64List _ringRaster;
  final Int64List _ringSpan;
  final Int64List _ringEnd;
  int _ringNext = 0;
  int _ringCount = 0;

  final Uint8List _windowOver;
  int _windowNext = 0;
  int _windowCount = 0;
  int _overCount = 0;

  _SpikeState _state = _SpikeState.armed;

  // Trigger-time copies, allocated when a spike starts.
  Int64List? _preBuild;
  Int64List? _preRaster;
  Int64List? _preSpan;
  Int64List? _preEnd;
  Int64List? _postBuild;
  Int64List? _postRaster;
  Int64List? _postSpan;
  Int64List? _postEnd;
  int _postCount = 0;
  Map<String, String> _context = const {};
  DateTime? _wallClock;
  int _firstWindowEndUs = 0;

  final List<PerfSpikeSnapshot> _snapshots = [];
  final List<(int, String)> _events = [];

  /// Stored snapshots, oldest first.
  List<PerfSpikeSnapshot> get snapshots => List.unmodifiable(_snapshots);

  /// Whether a spike is being captured right now.
  bool get capturing => _state == _SpikeState.capturing;

  /// Records a renderer, scene, scroll or lifecycle event. The time is the last
  /// frame's end time, so events line up with frames; before any frame it is 0.
  void noteEvent(String text) {
    final at = _ringCount == 0
        ? 0
        : _ringEnd[(_ringNext - 1 + preFrames) % preFrames];
    if (_events.length == maxEvents) _events.removeAt(0);
    _events.add((at, text));
  }

  /// Drops frames and in-flight capture from the previous configuration. Stored
  /// snapshots stay, each already labelled with its own configuration.
  void reset() {
    _ringNext = 0;
    _ringCount = 0;
    _windowNext = 0;
    _windowCount = 0;
    _overCount = 0;
    _windowOver.fillRange(0, _windowOver.length, 0);
    _state = _SpikeState.armed;
    _preBuild = _preRaster = _preSpan = _preEnd = null;
    _postBuild = _postRaster = _postSpan = _postEnd = null;
    _postCount = 0;
    _context = const {};
    _wallClock = null;
    _firstWindowEndUs = 0;
  }

  void onFrame({
    required int buildUs,
    required int rasterUs,
    required int spanUs,
    required int endUs,
  }) {
    // Pre-ring: the most recent [preFrames] frames.
    _ringBuild[_ringNext] = buildUs;
    _ringRaster[_ringNext] = rasterUs;
    _ringSpan[_ringNext] = spanUs;
    _ringEnd[_ringNext] = endUs;
    _ringNext = (_ringNext + 1) % preFrames;
    if (_ringCount < preFrames) _ringCount++;

    // Trigger window: running count of over-budget frames.
    final over = spanUs > budgetUs ? 1 : 0;
    if (_windowCount == windowFrames) {
      _overCount -= _windowOver[_windowNext];
    } else {
      _windowCount++;
    }
    _windowOver[_windowNext] = over;
    _overCount += over;
    _windowNext = (_windowNext + 1) % windowFrames;

    switch (_state) {
      case _SpikeState.armed:
        if (_windowCount == windowFrames && _overCount >= triggerOverBudget) {
          _startCapture(endUs);
        }
      case _SpikeState.capturing:
        _appendPost(buildUs, rasterUs, spanUs, endUs);
        if (_postCount == postFrames) _finishCapture();
      case _SpikeState.disarmed:
        if (_overCount <= rearmOverBudget) _state = _SpikeState.armed;
    }
  }

  void _startCapture(int triggerEndUs) {
    _state = _SpikeState.capturing;
    _wallClock = DateTime.now();
    _context = contextReader?.call() ?? const {};
    _preBuild = Int64List(_ringCount);
    _preRaster = Int64List(_ringCount);
    _preSpan = Int64List(_ringCount);
    _preEnd = Int64List(_ringCount);
    // Copy the ring oldest to newest.
    final start = (_ringNext - _ringCount + preFrames) % preFrames;
    for (var i = 0; i < _ringCount; i++) {
      final index = (start + i) % preFrames;
      _preBuild![i] = _ringBuild[index];
      _preRaster![i] = _ringRaster[index];
      _preSpan![i] = _ringSpan[index];
      _preEnd![i] = _ringEnd[index];
    }
    _firstWindowEndUs = _preEnd![_ringCount - windowFrames];
    _postBuild = Int64List(postFrames);
    _postRaster = Int64List(postFrames);
    _postSpan = Int64List(postFrames);
    _postEnd = Int64List(postFrames);
    _postCount = 0;
    // The trigger frame itself is the last pre frame.
    assert(triggerEndUs == _preEnd![_ringCount - 1]);
  }

  void _appendPost(int build, int raster, int span, int end) {
    _postBuild![_postCount] = build;
    _postRaster![_postCount] = raster;
    _postSpan![_postCount] = span;
    _postEnd![_postCount] = end;
    _postCount++;
  }

  void _finishCapture() {
    final preBuild = _preBuild!;
    final preRaster = _preRaster!;
    final preSpan = _preSpan!;
    final preEnd = _preEnd!;
    final postBuild = _postBuild!;
    final postRaster = _postRaster!;
    final postSpan = _postSpan!;
    final postEnd = _postEnd!;
    final endUs = postEnd[postEnd.length - 1];
    final durationMs = (endUs - _firstWindowEndUs) / 1000;

    // Intervals between consecutive frame end times over pre and post.
    final intervals = List<int>.filled(kPerfIntervalBucketsMs.length + 1, 0);
    void countIntervals(Int64List ends, int count) {
      for (var i = 1; i < count; i++) {
        final ms = (ends[i] - ends[i - 1]) / 1000;
        var bucket = kPerfIntervalBucketsMs.length;
        for (var b = 0; b < kPerfIntervalBucketsMs.length; b++) {
          if (ms <= kPerfIntervalBucketsMs[b]) {
            bucket = b;
            break;
          }
        }
        intervals[bucket]++;
      }
    }

    countIntervals(preEnd, preEnd.length);
    countIntervals(postEnd, _postCount);

    _snapshots.add(
      PerfSpikeSnapshot(
        wallClock: _wallClock!,
        windowStartEndUs: _firstWindowEndUs,
        durationMs: durationMs,
        preSegment: _segment(preBuild, preRaster, preSpan, preBuild.length),
        postSegment: _segment(postBuild, postRaster, postSpan, _postCount),
        intervalCounts: intervals,
        context: _context,
        events: [
          for (final (at, text) in _events)
            if (at >= _firstWindowEndUs && at <= endUs)
              '${(at - _firstWindowEndUs) / 1000} ms: $text',
        ],
      ),
    );
    if (_snapshots.length > maxSnapshots) _snapshots.removeAt(0);
    _state = _SpikeState.disarmed;
    _preBuild = _preRaster = _preSpan = _preEnd = null;
    _postBuild = _postRaster = _postSpan = _postEnd = null;
    _postCount = 0;
  }

  PerfSpikeSegment _segment(
    Int64List build,
    Int64List raster,
    Int64List span,
    int count,
  ) {
    if (count == 0) {
      return const PerfSpikeSegment(
        frames: 0,
        exceedancePct: 0,
        buildP50Ms: double.nan,
        buildP90Ms: double.nan,
        buildP99Ms: double.nan,
        rasterP50Ms: double.nan,
        rasterP90Ms: double.nan,
        rasterP99Ms: double.nan,
        spanP90Ms: double.nan,
      );
    }
    var over = 0;
    for (var i = 0; i < count; i++) {
      if (span[i] > budgetUs) over++;
    }
    final b = _sorted(build, count);
    final r = _sorted(raster, count);
    final s = _sorted(span, count);
    return PerfSpikeSegment(
      frames: count,
      exceedancePct: over * 100 / count,
      buildP50Ms: _pct(b, 50),
      buildP90Ms: _pct(b, 90),
      buildP99Ms: _pct(b, 99),
      rasterP50Ms: _pct(r, 50),
      rasterP90Ms: _pct(r, 90),
      rasterP99Ms: _pct(r, 99),
      spanP90Ms: _pct(s, 90),
    );
  }
}

/// Nearest-rank percentile over a sorted copy of the first [count] values.
Int64List _sorted(Int64List values, int count) {
  final copy = Int64List.fromList(values.sublist(0, count));
  copy.sort();
  return copy;
}

double _pct(Int64List sorted, int percent) {
  final rank = (percent * sorted.length / 100).ceil().clamp(1, sorted.length);
  return sorted[rank - 1] / 1000;
}
