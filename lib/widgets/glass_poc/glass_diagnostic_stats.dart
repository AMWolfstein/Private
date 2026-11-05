import 'dart:math' as math;

/// Summary of one metric over the valid repeats of one configuration. Only
/// valid runs are passed in: invalid, cancelled and not-run runs never enter
/// these statistics.
class GlassRepeatStats {
  const GlassRepeatStats({
    required this.values,
    required this.median,
    required this.min,
    required this.max,
  });

  /// Builds the statistics, or null when [values] is empty.
  static GlassRepeatStats? of(List<double> values) {
    if (values.isEmpty) return null;
    final sorted = [...values]..sort();
    final n = sorted.length;
    final median = n.isOdd
        ? sorted[n ~/ 2]
        : (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
    return GlassRepeatStats(
      values: List.unmodifiable(values),
      median: median,
      min: sorted.first,
      max: sorted.last,
    );
  }

  final List<double> values;
  final double median;
  final double min;
  final double max;

  /// Spread between the best and worst repeat.
  double get range => max - min;

  /// Sample coefficient of variation in percent. Null with fewer than two
  /// repeats or a zero mean.
  double? get cvPercent {
    if (values.length < 2) return null;
    final mean = values.reduce((a, b) => a + b) / values.length;
    if (mean == 0) return null;
    var sum = 0.0;
    for (final v in values) {
      sum += (v - mean) * (v - mean);
    }
    final sd = math.sqrt(sum / (values.length - 1));
    return sd / mean.abs() * 100;
  }
}

/// True when [values] (in run order) rises strictly from one median to the
/// next, and every repeat of the higher configuration is above every repeat of
/// the lower one. That is the evidence a scaling claim needs; a rise of the
/// medians alone is not.
bool glassStepsSeparated(GlassRepeatStats lower, GlassRepeatStats higher) =>
    higher.median > lower.median && higher.min > lower.max;
