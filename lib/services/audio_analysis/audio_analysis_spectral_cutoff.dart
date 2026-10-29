import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

double? estimateEffectiveSpectralCutoffHz({
  required Uint8List intensity,
  required int width,
  required int height,
  required double maxFrequencyHz,
}) {
  if (width <= 0 ||
      height <= 0 ||
      maxFrequencyHz <= 0 ||
      intensity.length < width * height) {
    return null;
  }

  // Use a high temporal percentile so sustained musical bandwidth wins over
  // silence, while short ultrasonic transients do not define the cutoff.
  // These bytes come from FFmpeg's fixed-hue `color=green` output, where gray
  // value is monotonic with magnitude; display-palette RGB is deliberately not
  // accepted here because its blue noise floor has deceptively large channels.
  final profile = Float64List(height);
  final histogram = Uint32List(256);
  final percentileTarget = math.max(0, (width * 0.90).floor());
  for (var y = 0; y < height; y++) {
    histogram.fillRange(0, histogram.length, 0);
    final rowStart = y * width;
    for (var x = 0; x < width; x++) {
      histogram[intensity[rowStart + x]]++;
    }

    var cumulative = 0;
    for (var value = 0; value < histogram.length; value++) {
      cumulative += histogram[value];
      if (cumulative > percentileTarget) {
        // showspectrumpic stores Nyquist at the top. Reverse it here so array
        // indices increase with frequency, which makes edge detection clearer.
        profile[height - y - 1] = value.toDouble();
        break;
      }
    }
  }

  final hzPerRow = maxFrequencyHz / height;

  // Reject narrow horizontal lines before looking for a bandwidth edge. A
  // median over roughly 500 Hz preserves a broadband step while removing
  // pilots, tones, and isolated noisy bins that occupy only a small fraction
  // of the surrounding band.
  final lineRejectionRadius = math.max(1, (250 / hzPerRow).ceil());
  final broadbandProfile = Float64List(height);
  for (var index = 0; index < height; index++) {
    broadbandProfile[index] = _spectralMedian(
      profile,
      index - lineRejectionRadius,
      index + lineRejectionRadius + 1,
    );
  }

  // Apply only light smoothing after the robust frequency aggregation. This
  // reduces row quantization without letting a high-amplitude line smear into
  // enough adjacent bins to resemble broadband support.
  final smoothingRadius = math.max(1, (50 / hzPerRow).ceil());
  final smoothed = Float64List(height);
  var running = 0.0;
  var windowStart = 0;
  var windowEnd = -1;
  for (var index = 0; index < height; index++) {
    final desiredStart = math.max(0, index - smoothingRadius);
    final desiredEnd = math.min(height - 1, index + smoothingRadius);
    while (windowEnd < desiredEnd) {
      windowEnd++;
      running += broadbandProfile[windowEnd];
    }
    while (windowStart < desiredStart) {
      running -= broadbandProfile[windowStart];
      windowStart++;
    }
    smoothed[index] = running / (windowEnd - windowStart + 1);
  }

  final centralStart = math.max(0, (height * 0.05).floor());
  final centralEnd = math.min(height, (height * 0.95).ceil());
  final central = _sortedSpectralWindow(smoothed, centralStart, centralEnd);
  final lowLevel = _sortedSpectralPercentile(central, 0.10);
  final highLevel = _sortedSpectralPercentile(central, 0.95);
  final dynamicSpan = highLevel - lowLevel;
  if (highLevel < 24) return null;
  if (dynamicSpan < 1) return maxFrequencyHz;

  // Locate a sharp downward edge over roughly 200 Hz, then validate it using
  // wider bands on both sides. This detects codec/low-pass bandwidth edges but
  // rejects a gradual musical roll-off or a narrow ultrasonic pilot.
  final edgeSpanRows = math.max(2, (200 / hzPerRow).ceil());
  final topGuardRows = math.max(edgeSpanRows, (500 / hzPerRow).ceil());
  final minSearchHz = math.max(1000.0, math.min(4000.0, maxFrequencyHz * 0.20));
  final searchStart = math.max(edgeSpanRows, (minSearchHz / hzPerRow).floor());
  final searchEnd = height - edgeSpanRows - topGuardRows;
  final candidateStarts = <int>[];
  for (var start = searchStart; start < searchEnd; start++) {
    final drop = smoothed[start] - smoothed[start + edgeSpanRows];
    if (drop > 0) candidateStarts.add(start);
  }
  candidateStarts.sort((a, b) {
    final aDrop = smoothed[a] - smoothed[a + edgeSpanRows];
    final bDrop = smoothed[b] - smoothed[b + edgeSpanRows];
    return bDrop.compareTo(aDrop);
  });

  // A sharp, frequency-contiguous edge remains meaningful at lower contrast
  // than an arbitrary bright bin. Keep the threshold relative to the measured
  // spectral span, but do not require the old fixed 12-byte difference that
  // caused elevated noise floors to be classified as full-band.
  final minimumDrop = math.max(6.0, dynamicSpan * 0.18);
  final gapRows = math.max(1, (100 / hzPerRow).ceil());
  final supportRows = math.max(3, (1200 / hzPerRow).ceil());
  final stableTailSpread = math.max(4.0, dynamicSpan * 0.06);
  for (final bestStart in candidateStarts) {
    final bestLocalDrop =
        smoothed[bestStart] - smoothed[bestStart + edgeSpanRows];
    if (bestLocalDrop < minimumDrop * 0.60) break;
    final edgeIndex = (bestStart + edgeSpanRows / 2).round();
    final belowEnd = edgeIndex - gapRows;
    final belowStart = math.max(0, belowEnd - supportRows);
    final aboveStart = edgeIndex + gapRows;
    final aboveEnd = math.min(height, aboveStart + supportRows);
    if (belowEnd > belowStart && aboveEnd > aboveStart) {
      final belowLevel = _spectralMedian(smoothed, belowStart, belowEnd);
      final aboveLevel = _spectralMedian(smoothed, aboveStart, aboveEnd);
      if (belowLevel - aboveLevel < minimumDrop) continue;
      // All tail statistics share one sorted window. Rejected local edges do
      // not need to copy and sort the rest of the spectrum at all.
      final tail = _sortedSpectralWindow(smoothed, aboveStart, height);
      final tailLevel = _sortedSpectralPercentile(tail, 0.50);
      if (belowLevel - tailLevel < minimumDrop) continue;
      final tailSpread =
          _sortedSpectralPercentile(tail, 0.80) -
          _sortedSpectralPercentile(tail, 0.20);
      if (tailSpread > stableTailSpread) continue;
      final baseStart = math.max(0, edgeIndex - (3000 / hzPerRow).ceil());
      final baseLevel = _spectralMedian(smoothed, baseStart, belowEnd);
      if (baseLevel - tailLevel >= minimumDrop) {
        final cutoff = (edgeIndex + 0.5) * hzPerRow;
        return cutoff.clamp(0.0, maxFrequencyHz).toDouble();
      }
    }
  }

  // Some masters roll off over several kilohertz instead of ending at one
  // sharp edge. Find the highest sustained band that remains clearly above a
  // stable high-frequency floor so ordinary musical spectral tilt is not
  // mistaken for a low-pass cutoff.
  final tailReferenceLevel = _spectralMedian(
    smoothed,
    (height * 0.90).floor(),
    math.max(1, (height * 0.98).floor()),
  );
  // A gradual cutoff needs stronger contrast than a sharp, contiguous edge.
  // Otherwise an ordinary full-band spectral tilt can eventually cross the
  // high-frequency floor by a few grayscale steps and create an arbitrary
  // cutoff. Require a material transition into the stable tail instead.
  final activeMargin = math.max(12.0, dynamicSpan * 0.25);
  final activeThreshold = tailReferenceLevel + activeMargin;
  for (var edgeIndex = searchEnd - 1; edgeIndex >= searchStart; edgeIndex--) {
    final belowEnd = edgeIndex - gapRows;
    final belowStart = math.max(0, belowEnd - supportRows);
    final aboveStart = edgeIndex + gapRows;
    if (belowEnd <= belowStart || aboveStart >= height) continue;
    final belowLevel = _spectralMedian(smoothed, belowStart, belowEnd);
    if (belowLevel < activeThreshold) continue;
    final tail = _sortedSpectralWindow(smoothed, aboveStart, height);
    final tailLevel = _sortedSpectralPercentile(tail, 0.50);
    if (belowLevel - tailLevel < activeMargin) continue;
    final tailSpread =
        _sortedSpectralPercentile(tail, 0.80) -
        _sortedSpectralPercentile(tail, 0.20);
    if (tailSpread <= stableTailSpread) {
      final cutoffIndex = edgeIndex - supportRows / 2;
      final cutoff = (cutoffIndex + 0.5) * hzPerRow;
      return cutoff.clamp(0.0, maxFrequencyHz).toDouble();
    }
  }

  // A genuinely broadband signal with no stable tail plateau reaches the
  // analysis ceiling. Natural music may retain a pronounced spectral tilt,
  // so require populated baseband and top bands instead of similar levels.
  // Silence and isolated high-frequency lines still return null.
  final basebandLevel = _spectralMedian(
    smoothed,
    (height * 0.05).floor(),
    math.max(1, (height * 0.50).floor()),
  );
  final topBandLevel = _spectralMedian(
    smoothed,
    (height * 0.90).floor(),
    math.max(1, (height * 0.98).floor()),
  );
  final lowerTopBandLevel = _spectralMedian(
    smoothed,
    (height * 0.80).floor(),
    math.max(1, (height * 0.90).floor()),
  );
  final topBandNearPeak = topBandLevel >= highLevel - minimumDrop;
  // A real low-contrast full-band slope can change by less than the tail
  // stability tolerance. Preserve it when the upper octave still trends
  // downward by at least one grayscale step; a low-pass noise plateau remains
  // flat here and must already have passed the validated edge checks above.
  final upperBandSlope = lowerTopBandLevel - topBandLevel;
  final topBandStillSloping =
      upperBandSlope >= math.max(1.0, dynamicSpan * 0.05);
  if (basebandLevel >= 24 &&
      topBandLevel >= 24 &&
      (topBandNearPeak || topBandStillSloping)) {
    return maxFrequencyHz;
  }
  return null;
}

double _spectralMedian(Float64List values, int start, int end) {
  return _sortedSpectralPercentile(
    _sortedSpectralWindow(values, start, end),
    0.50,
  );
}

Float64List _sortedSpectralWindow(Float64List values, int start, int end) {
  final safeStart = start.clamp(0, values.length).toInt();
  final safeEnd = end.clamp(safeStart, values.length).toInt();
  return values.sublist(safeStart, safeEnd)..sort();
}

double _sortedSpectralPercentile(Float64List sorted, double percentile) {
  if (sorted.isEmpty) return 0;
  final index = ((sorted.length - 1) * percentile)
      .round()
      .clamp(0, sorted.length - 1)
      .toInt();
  return sorted[index];
}

class SpectralCutoffFileParams {
  final String path;
  final int width;
  final int height;
  final double maxFrequencyHz;

  const SpectralCutoffFileParams({
    required this.path,
    required this.width,
    required this.height,
    required this.maxFrequencyHz,
  });
}

double? estimateEffectiveSpectralCutoffFileInIsolate(
  SpectralCutoffFileParams params,
) {
  final expected = params.width * params.height;
  final file = File(params.path);
  if (file.lengthSync() != expected) {
    throw const FormatException('Incomplete spectral cutoff output');
  }
  return estimateEffectiveSpectralCutoffHz(
    intensity: file.readAsBytesSync(),
    width: params.width,
    height: params.height,
    maxFrequencyHz: params.maxFrequencyHz,
  );
}
