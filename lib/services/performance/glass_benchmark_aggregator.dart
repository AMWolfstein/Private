import 'dart:typed_data';

/// Frames kept for one measured interval. At 120 Hz a 60 s interval needs about
/// 7,200 frames, so this leaves room. Frames beyond it are counted as overflow
/// and the interval is marked incomplete, never silently dropped.
const int kGlassBenchmarkMaxFrames = 16384;

/// Sustained-episode rule, shared with the spike recorder: at least
/// [kGlassBenchmarkEpisodeTrigger] of the last [kGlassBenchmarkEpisodeWindow]
/// frames over budget starts an episode; it ends at or below
/// [kGlassBenchmarkEpisodeRearm].
const int kGlassBenchmarkEpisodeWindow = 30;
const int kGlassBenchmarkEpisodeTrigger = 15;
const int kGlassBenchmarkEpisodeRearm = 3;

/// Episodes kept per renderer, worst first.
const int kGlassBenchmarkWorstEpisodes = 5;

/// An interval between consecutive frame end times longer than this many
/// budgets is a frame-production gap.
const double kGlassBenchmarkGapBudgets = 2;

/// Interval buckets (ms) for the frame-interval histogram. The last bucket is
/// open-ended.
const List<double> kGlassBenchmarkIntervalBucketsMs = [17, 25, 34, 50, 100];

/// Minimum observed share of the measured interval for a run to count as
/// complete. Below this, callbacks were missing for a large part of the run.
const double kGlassBenchmarkMinCoverage = 0.9;

/// One sustained degradation episode inside a measured interval.
class GlassBenchmarkEpisode {
  const GlassBenchmarkEpisode({
    required this.startMs,
    required this.durationMs,
    required this.frames,
    required this.maxSpanMs,
    required this.maxBuildMs,
    required this.maxRasterMs,
    required this.maxGapMs,
    required this.boundaryTurns,
    required this.openAtEnd,
  });

  /// Start, relative to the first measured frame end.
  final double startMs;

  /// Frame-end span of the episode (first to last frame end inside it).
  final double durationMs;

  /// Frames inside the episode.
  final int frames;

  final double maxSpanMs;
  final double maxBuildMs;
  final double maxRasterMs;

  /// Largest frame-production interval inside the episode, or null when it had
  /// fewer than two frames.
  final double? maxGapMs;

  /// Boundary turns that happened while the episode was open.
  final int boundaryTurns;

  /// True when the measured interval ended before the episode did.
  final bool openAtEnd;

  /// Root cause is never established by this instrument.
  String get cause => 'unverified';
}

/// Whole-interval statistics for one measured renderer run. Percentiles use
/// nearest rank over every kept frame.
class GlassBenchmarkSummary {
  const GlassBenchmarkSummary({
    required this.frames,
    required this.overflow,
    required this.elapsedMs,
    required this.observedMs,
    required this.budgetMs,
    required this.buildP50Ms,
    required this.buildP90Ms,
    required this.buildP99Ms,
    required this.rasterP50Ms,
    required this.rasterP90Ms,
    required this.rasterP99Ms,
    required this.spanP50Ms,
    required this.spanP90Ms,
    required this.spanP99Ms,
    required this.maxSpanMs,
    required this.exceedancePct,
    required this.estimatedProductionFps,
    required this.intervalCounts,
    required this.gapCount,
    required this.maxGapMs,
    required this.gapTotalMs,
    required this.episodeCount,
    required this.worstEpisodes,
  });

  final int frames;

  /// Frames received after the buffer was full. They are not in the
  /// percentiles, so a non-zero value makes the interval incomplete.
  final int overflow;

  /// Monotonic time of the measured interval (Stopwatch), in milliseconds.
  final double elapsedMs;

  /// Engine time from the first to the last observed frame end, in ms.
  final double observedMs;

  final double budgetMs;

  final double? buildP50Ms;
  final double? buildP90Ms;
  final double? buildP99Ms;
  final double? rasterP50Ms;
  final double? rasterP90Ms;
  final double? rasterP99Ms;

  /// Total span: vsync start to raster finish, as FrameTiming reports it. This
  /// is what the frame-budget exceedance counts. It is not display presentation.
  final double? spanP50Ms;
  final double? spanP90Ms;
  final double? spanP99Ms;
  final double? maxSpanMs;

  /// Percent of frames whose total span exceeded the budget.
  final double? exceedancePct;

  /// (frames - 1) over observed time. Estimated frame production from Flutter
  /// callbacks. It is not Android display FPS.
  final double? estimatedProductionFps;

  /// Counts per [kGlassBenchmarkIntervalBucketsMs] bucket, plus the open one.
  final List<int> intervalCounts;

  /// Intervals longer than [kGlassBenchmarkGapBudgets] budgets.
  final int gapCount;
  final double maxGapMs;
  final double gapTotalMs;

  final int episodeCount;

  /// The worst [kGlassBenchmarkWorstEpisodes] episodes, longest first.
  final List<GlassBenchmarkEpisode> worstEpisodes;

  /// Share of the measured interval covered by normal frame flow, 0 to 1:
  /// observed time minus the intervals longer than two budgets, over the
  /// monotonic elapsed time. A stall (no callbacks) removes its time from the
  /// numerator, so it lowers coverage instead of counting as 60 FPS.
  double get coverage => elapsedMs <= 0
      ? 0
      : ((observedMs - gapTotalMs) / elapsedMs).clamp(0, 1).toDouble();
}

/// Streams the frames of one measured interval into bounded buffers. It is fed
/// from the FrameTiming callback, only between [begin] and [end]. It keeps no
/// rolling window and never reuses frames from a previous interval.
class GlassBenchmarkAggregator {
  GlassBenchmarkAggregator({
    required this.budgetUs,
    required this.turnsReader,
    int capacity = kGlassBenchmarkMaxFrames,
  }) : _capacity = capacity,
       _build = Int64List(capacity),
       _raster = Int64List(capacity),
       _span = Int64List(capacity),
       _end = Int64List(capacity),
       _windowOver = Uint8List(kGlassBenchmarkEpisodeWindow),
       _intervalCounts = List<int>.filled(
         kGlassBenchmarkIntervalBucketsMs.length + 1,
         0,
       );

  /// Budget in microseconds, 1e6 / hz.
  final double budgetUs;

  /// Read only at episode boundaries, so turns can be attributed to episodes
  /// without per-frame work.
  final int Function() turnsReader;

  final int _capacity;
  final Int64List _build;
  final Int64List _raster;
  final Int64List _span;
  final Int64List _end;
  int _count = 0;
  int _overflow = 0;
  bool _active = false;

  int _firstEndUs = 0;
  int _lastEndUs = 0;
  int _exceeded = 0;
  int _maxSpanUs = 0;

  final List<int> _intervalCounts;
  int _gapCount = 0;
  int _maxGapUs = 0;
  int _gapTotalUs = 0;

  // Sliding count of over-budget frames for the episode rule.
  final Uint8List _windowOver;
  final Int64List _windowEndUs = Int64List(kGlassBenchmarkEpisodeWindow);
  int _windowNext = 0;
  int _windowCount = 0;
  int _overCount = 0;

  bool _inEpisode = false;
  int _episodeStartUs = 0;
  int _episodeFrames = 0;
  int _episodeMaxSpanUs = 0;
  int _episodeMaxBuildUs = 0;
  int _episodeMaxRasterUs = 0;
  int _episodeMaxGapUs = 0;
  int _episodeTurnsAtStart = 0;
  int _episodeLastEndUs = 0;
  int _episodeCount = 0;
  final List<GlassBenchmarkEpisode> _worst = [];

  bool get active => _active;
  int get frameCount => _count;

  /// Starts a fresh interval. All state from any earlier interval is cleared.
  void begin() {
    _count = 0;
    _overflow = 0;
    _firstEndUs = 0;
    _lastEndUs = 0;
    _exceeded = 0;
    _maxSpanUs = 0;
    _intervalCounts.fillRange(0, _intervalCounts.length, 0);
    _gapCount = 0;
    _maxGapUs = 0;
    _gapTotalUs = 0;
    _windowOver.fillRange(0, _windowOver.length, 0);
    _windowNext = 0;
    _windowCount = 0;
    _overCount = 0;
    _inEpisode = false;
    _episodeCount = 0;
    _worst.clear();
    _active = true;
  }

  /// Stops collecting. Any open episode is closed as "open at end".
  void end() {
    if (!_active) return;
    if (_inEpisode) _closeEpisode(openAtEnd: true);
    _active = false;
  }

  /// Discards the interval without a summary (used on cancellation).
  void discard() {
    _active = false;
    _inEpisode = false;
    _count = 0;
  }

  void onFrame({
    required int buildUs,
    required int rasterUs,
    required int spanUs,
    required int endUs,
  }) {
    if (!_active) return;

    if (_count == 0) {
      _firstEndUs = endUs;
    } else {
      final gap = endUs - _lastEndUs;
      if (gap > 0) {
        _recordInterval(gap);
        if (gap > budgetUs * kGlassBenchmarkGapBudgets) {
          _gapCount++;
          _gapTotalUs += gap;
          if (gap > _maxGapUs) _maxGapUs = gap;
        }
        if (_inEpisode && gap > _episodeMaxGapUs) _episodeMaxGapUs = gap;
      }
    }
    _lastEndUs = endUs;

    if (_count < _capacity) {
      _build[_count] = buildUs;
      _raster[_count] = rasterUs;
      _span[_count] = spanUs;
      _end[_count] = endUs;
      _count++;
    } else {
      _overflow++;
    }

    if (spanUs > budgetUs) _exceeded++;
    if (spanUs > _maxSpanUs) _maxSpanUs = spanUs;

    _updateEpisode(buildUs, rasterUs, spanUs, endUs);
  }

  void _recordInterval(int gapUs) {
    final ms = gapUs / 1000;
    var bucket = kGlassBenchmarkIntervalBucketsMs.length;
    for (var b = 0; b < kGlassBenchmarkIntervalBucketsMs.length; b++) {
      if (ms <= kGlassBenchmarkIntervalBucketsMs[b]) {
        bucket = b;
        break;
      }
    }
    _intervalCounts[bucket]++;
  }

  void _updateEpisode(int buildUs, int rasterUs, int spanUs, int endUs) {
    final over = spanUs > budgetUs ? 1 : 0;
    if (_windowCount == kGlassBenchmarkEpisodeWindow) {
      _overCount -= _windowOver[_windowNext];
    } else {
      _windowCount++;
    }
    _windowOver[_windowNext] = over;
    _windowEndUs[_windowNext] = endUs;
    _overCount += over;
    _windowNext = (_windowNext + 1) % kGlassBenchmarkEpisodeWindow;

    if (!_inEpisode) {
      if (_windowCount == kGlassBenchmarkEpisodeWindow &&
          _overCount >= kGlassBenchmarkEpisodeTrigger) {
        _inEpisode = true;
        // With the window full, the slot about to be overwritten holds its
        // oldest frame, so the episode starts at that frame's end.
        _episodeStartUs = _windowEndUs[_windowNext];
        _episodeFrames = 0;
        _episodeMaxSpanUs = 0;
        _episodeMaxBuildUs = 0;
        _episodeMaxRasterUs = 0;
        _episodeMaxGapUs = 0;
        _episodeTurnsAtStart = turnsReader();
      }
    }
    if (_inEpisode) {
      _episodeFrames++;
      _episodeLastEndUs = endUs;
      if (spanUs > _episodeMaxSpanUs) _episodeMaxSpanUs = spanUs;
      if (buildUs > _episodeMaxBuildUs) _episodeMaxBuildUs = buildUs;
      if (rasterUs > _episodeMaxRasterUs) _episodeMaxRasterUs = rasterUs;
      if (_overCount <= kGlassBenchmarkEpisodeRearm) {
        _closeEpisode(openAtEnd: false);
      }
    }
  }

  void _closeEpisode({required bool openAtEnd}) {
    _inEpisode = false;
    _episodeCount++;
    final durationUs = _episodeLastEndUs - _episodeStartUs;
    final episode = GlassBenchmarkEpisode(
      startMs: (_episodeStartUs - _firstEndUs) / 1000,
      durationMs: durationUs / 1000,
      frames: _episodeFrames,
      maxSpanMs: _episodeMaxSpanUs / 1000,
      maxBuildMs: _episodeMaxBuildUs / 1000,
      maxRasterMs: _episodeMaxRasterUs / 1000,
      maxGapMs: _episodeFrames >= 2 ? _episodeMaxGapUs / 1000 : null,
      boundaryTurns: turnsReader() - _episodeTurnsAtStart,
      openAtEnd: openAtEnd,
    );
    _keepWorst(episode);
  }

  /// Keeps the worst episodes: longest first, ties by larger max span. Only
  /// [kGlassBenchmarkWorstEpisodes] are retained, so memory stays bounded.
  void _keepWorst(GlassBenchmarkEpisode episode) {
    var at = _worst.length;
    while (at > 0 && _worseThan(episode, _worst[at - 1])) {
      at--;
    }
    if (at >= kGlassBenchmarkWorstEpisodes) return;
    _worst.insert(at, episode);
    if (_worst.length > kGlassBenchmarkWorstEpisodes) _worst.removeLast();
  }

  bool _worseThan(GlassBenchmarkEpisode a, GlassBenchmarkEpisode b) {
    if (a.durationMs != b.durationMs) return a.durationMs > b.durationMs;
    return a.maxSpanMs > b.maxSpanMs;
  }

  /// Summary of the interval. [elapsedUs] is the Stopwatch time of the whole
  /// measured interval, which is monotonic and independent of frame callbacks.
  GlassBenchmarkSummary summary({required int elapsedUs}) {
    final n = _count;
    final build = _sorted(_build, n);
    final raster = _sorted(_raster, n);
    final span = _sorted(_span, n);
    final observedUs = n >= 2 ? _lastEndUs - _firstEndUs : 0;
    return GlassBenchmarkSummary(
      frames: n,
      overflow: _overflow,
      elapsedMs: elapsedUs / 1000,
      observedMs: observedUs / 1000,
      budgetMs: budgetUs / 1000,
      buildP50Ms: _pct(build, 50),
      buildP90Ms: _pct(build, 90),
      buildP99Ms: _pct(build, 99),
      rasterP50Ms: _pct(raster, 50),
      rasterP90Ms: _pct(raster, 90),
      rasterP99Ms: _pct(raster, 99),
      spanP50Ms: _pct(span, 50),
      spanP90Ms: _pct(span, 90),
      spanP99Ms: _pct(span, 99),
      maxSpanMs: n == 0 ? null : _maxSpanUs / 1000,
      exceedancePct: n == 0 ? null : _exceeded * 100 / n,
      estimatedProductionFps: n >= 2 && observedUs > 0
          ? (n - 1) * 1e6 / observedUs
          : null,
      intervalCounts: List<int>.unmodifiable(_intervalCounts),
      gapCount: _gapCount,
      maxGapMs: _maxGapUs / 1000,
      gapTotalMs: _gapTotalUs / 1000,
      episodeCount: _episodeCount,
      worstEpisodes: List<GlassBenchmarkEpisode>.unmodifiable(_worst),
    );
  }
}

/// Copies the first [count] values and sorts them. Runs once per interval, at
/// its end, so the allocation is outside the frame callback.
Int64List _sorted(Int64List values, int count) {
  final copy = Int64List.fromList(values.sublist(0, count));
  copy.sort();
  return copy;
}

double? _pct(Int64List sorted, int percent) {
  if (sorted.isEmpty) return null;
  final rank = (percent * sorted.length / 100).ceil().clamp(1, sorted.length);
  return sorted[rank - 1] / 1000;
}
