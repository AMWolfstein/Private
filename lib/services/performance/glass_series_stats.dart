import 'dart:typed_data';

/// Bounded, allocation-free collection of one timing series. [add] only writes
/// into a preallocated buffer; sorting happens once, in [stats].
class GlassSeriesBuffer {
  GlassSeriesBuffer(this.capacity) : _values = Int64List(capacity);

  final int capacity;
  final Int64List _values;
  int _count = 0;

  /// Values that did not fit. They are not in the percentiles, and the report
  /// says so.
  int overflow = 0;

  int get count => _count;

  void add(int value) {
    if (_count < capacity) {
      _values[_count++] = value;
    } else {
      overflow++;
    }
  }

  void reset() {
    _count = 0;
    overflow = 0;
  }

  /// Percentiles of the kept values, in the buffer's unit, using nearest rank.
  /// Null when the series is empty.
  GlassSeriesStats stats({double scale = 1000}) {
    if (_count == 0) {
      return GlassSeriesStats(
        count: 0,
        overflow: overflow,
        p50: null,
        p90: null,
        p99: null,
        max: null,
      );
    }
    final sorted = Int64List.fromList(_values.sublist(0, _count))..sort();
    double at(double percent) {
      final rank = (percent * sorted.length / 100).ceil().clamp(
        1,
        sorted.length,
      );
      return sorted[rank - 1] / scale;
    }

    return GlassSeriesStats(
      count: _count,
      overflow: overflow,
      p50: at(50),
      p90: at(90),
      p99: at(99),
      max: sorted.last / scale,
    );
  }
}

/// Percentiles of one series, in milliseconds when built with the default
/// scale. Null values mean the series had no samples.
class GlassSeriesStats {
  const GlassSeriesStats({
    required this.count,
    required this.overflow,
    required this.p50,
    required this.p90,
    required this.p99,
    required this.max,
  });

  final int count;
  final int overflow;
  final double? p50;
  final double? p90;
  final double? p99;
  final double? max;
}
