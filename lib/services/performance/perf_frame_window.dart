import 'dart:typed_data';

/// Frames kept in the rolling window unless a caller asks for another size.
const int kPerfWindowFrames = 300;

/// Refresh rate assumed when the display does not report a usable one.
const double kPerfFallbackHz = 60;

/// Refresh rate and whether it came from the display or the fallback.
typedef PerfRefreshRate = ({double hz, bool isFallback});

/// Resolves the display refresh rate. Values outside 20–360 Hz are treated as
/// unknown, because engines report 0 when the display cannot say.
PerfRefreshRate resolvePerfRefreshRate(double? reportedHz) {
  if (reportedHz != null &&
      reportedHz.isFinite &&
      reportedHz >= 20 &&
      reportedHz <= 360) {
    return (hz: reportedHz, isFallback: false);
  }
  return (hz: kPerfFallbackHz, isFallback: true);
}

/// Derived statistics over one rolling window. Null means "not measurable"
/// (for example, percentiles of an empty window), never zero.
class PerfWindowSnapshot {
  const PerfWindowSnapshot({
    required this.frames,
    required this.totalFrames,
    required this.hz,
    required this.hzIsFallback,
    required this.budgetMs,
    required this.buildP50Ms,
    required this.buildP90Ms,
    required this.buildP99Ms,
    required this.rasterP50Ms,
    required this.rasterP90Ms,
    required this.rasterP99Ms,
    required this.exceedancePct,
    required this.fpsEstimate,
    required this.windowMs,
  });

  /// Frames currently in the window (at most the window capacity).
  final int frames;

  /// Frames measured since the last reset, including ones already rolled out.
  final int totalFrames;

  final double hz;
  final bool hzIsFallback;

  /// Frame budget for [hz] in milliseconds (1000 / hz).
  final double budgetMs;

  final double? buildP50Ms;
  final double? buildP90Ms;
  final double? buildP99Ms;
  final double? rasterP50Ms;
  final double? rasterP90Ms;
  final double? rasterP99Ms;

  /// Percentage of window frames whose total span (vsync start to raster
  /// finish, as reported by FrameTiming) exceeded the budget.
  final double? exceedancePct;

  /// Frames per second estimated from the spacing of frame end times. Not a
  /// display measurement.
  final double? fpsEstimate;

  /// Time from the oldest to the newest frame end in the window.
  final double? windowMs;
}

/// Bounded ring buffer of frame timings, in microseconds. Adding a frame does
/// not allocate; percentiles are computed only when a snapshot is taken.
class PerfFrameWindow {
  PerfFrameWindow({this.capacity = kPerfWindowFrames})
    : assert(capacity > 0),
      _buildUs = Int64List(capacity),
      _rasterUs = Int64List(capacity),
      _spanUs = Int64List(capacity),
      _endUs = Int64List(capacity);

  final int capacity;
  final Int64List _buildUs;
  final Int64List _rasterUs;
  final Int64List _spanUs;
  final Int64List _endUs;
  int _next = 0;
  int _count = 0;
  int _totalFrames = 0;

  int get count => _count;
  int get totalFrames => _totalFrames;

  void add({
    required int buildUs,
    required int rasterUs,
    required int spanUs,
    required int endUs,
  }) {
    _buildUs[_next] = buildUs;
    _rasterUs[_next] = rasterUs;
    _spanUs[_next] = spanUs;
    _endUs[_next] = endUs;
    _next = (_next + 1) % capacity;
    if (_count < capacity) _count++;
    _totalFrames++;
  }

  void reset() {
    _next = 0;
    _count = 0;
    _totalFrames = 0;
  }

  PerfWindowSnapshot snapshot({
    required double hz,
    required bool hzIsFallback,
  }) {
    final budgetUs = 1e6 / hz;
    final n = _count;
    final budgetMs = budgetUs / 1000;
    if (n == 0) {
      return PerfWindowSnapshot(
        frames: 0,
        totalFrames: _totalFrames,
        hz: hz,
        hzIsFallback: hzIsFallback,
        budgetMs: budgetMs,
        buildP50Ms: null,
        buildP90Ms: null,
        buildP99Ms: null,
        rasterP50Ms: null,
        rasterP90Ms: null,
        rasterP99Ms: null,
        exceedancePct: null,
        fpsEstimate: null,
        windowMs: null,
      );
    }
    final start = (_next - n + capacity) % capacity;
    final build = Int64List(n);
    final raster = Int64List(n);
    var overBudget = 0;
    for (var i = 0; i < n; i++) {
      final index = (start + i) % capacity;
      build[i] = _buildUs[index];
      raster[i] = _rasterUs[index];
      if (_spanUs[index] > budgetUs) overBudget++;
    }
    final oldestEnd = _endUs[start];
    final newestEnd = _endUs[(_next - 1 + capacity) % capacity];
    final windowUs = newestEnd - oldestEnd;
    build.sort();
    raster.sort();
    return PerfWindowSnapshot(
      frames: n,
      totalFrames: _totalFrames,
      hz: hz,
      hzIsFallback: hzIsFallback,
      budgetMs: budgetMs,
      buildP50Ms: _percentileMs(build, 50),
      buildP90Ms: _percentileMs(build, 90),
      buildP99Ms: _percentileMs(build, 99),
      rasterP50Ms: _percentileMs(raster, 50),
      rasterP90Ms: _percentileMs(raster, 90),
      rasterP99Ms: _percentileMs(raster, 99),
      exceedancePct: overBudget * 100 / n,
      fpsEstimate: n >= 2 && windowUs > 0 ? (n - 1) * 1e6 / windowUs : null,
      windowMs: n >= 2 && windowUs > 0 ? windowUs / 1000 : null,
    );
  }
}

/// Nearest-rank percentile of an ascending list of microseconds, in ms.
double? _percentileMs(Int64List sorted, int percent) {
  if (sorted.isEmpty) return null;
  final rank = (percent * sorted.length / 100).ceil().clamp(1, sorted.length);
  return sorted[rank - 1] / 1000;
}

String _fmt(double? value, int digits) =>
    value == null ? 'n/a' : value.toStringAsFixed(digits);

/// A single structured text report for sharing. Only measured values appear,
/// and the estimated FPS is labelled as such.
String formatPerfReport({
  required String screen,
  required PerfWindowSnapshot snapshot,
  String? glassMode,
  List<String> extraLines = const [],
}) {
  final hz = snapshot.hz % 1 == 0
      ? snapshot.hz.toInt().toString()
      : snapshot.hz.toStringAsFixed(2);
  return [
    'sistrum-perf',
    'screen=$screen',
    'hz=$hz',
    'hz_source=${snapshot.hzIsFallback ? 'fallback' : 'reported'}',
    'budget=${_fmt(snapshot.budgetMs, 2)}ms',
    'frames=${snapshot.frames}',
    'frames_total=${snapshot.totalFrames}',
    'window=rolling',
    'window_ms=${_fmt(snapshot.windowMs, 0)}',
    'build_ms_p50=${_fmt(snapshot.buildP50Ms, 2)}',
    'build_ms_p90=${_fmt(snapshot.buildP90Ms, 2)}',
    'build_ms_p99=${_fmt(snapshot.buildP99Ms, 2)}',
    'raster_ms_p50=${_fmt(snapshot.rasterP50Ms, 2)}',
    'raster_ms_p90=${_fmt(snapshot.rasterP90Ms, 2)}',
    'raster_ms_p99=${_fmt(snapshot.rasterP99Ms, 2)}',
    'frame_budget_exceedance=${_fmt(snapshot.exceedancePct, 1)}%',
    'fps_estimate=${_fmt(snapshot.fpsEstimate, 1)} (estimated)',
    if (glassMode != null) 'glass_mode=$glassMode',
    ...extraLines,
  ].join('\n');
}
