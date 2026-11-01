import 'dart:math' as math;
import 'dart:typed_data';

/// Compact acoustic summary of 24 seconds of decoded mono PCM at 11025 Hz.
/// No audio, paths or tags are part of the descriptor. Ratios describe timbre,
/// loudness and movement; they do not claim to recognize genre or musical key.
class AutoplaySoundProfile {
  const AutoplaySoundProfile(this.values);
  final List<double> values;
  static const dimensions = 6;

  static AutoplaySoundProfile? decode(Object? value) {
    if (value is! List || value.length != dimensions) return null;
    final values = <double>[];
    for (final item in value) {
      if (item is! num || !item.isFinite || item < 0 || item > 1) return null;
      values.add(item.toDouble());
    }
    return AutoplaySoundProfile(List.unmodifiable(values));
  }

  double similarity(AutoplaySoundProfile other) {
    var distance = 0.0;
    for (var i = 0; i < dimensions; i++) {
      final delta = values[i] - other.values[i];
      distance += delta * delta;
    }
    return math.exp(-4 * distance / dimensions);
  }
}

AutoplaySoundProfile? analyzeAutoplaySoundPcm(Uint8List pcm) {
  if (pcm.length < 11025 * 2 * 3 || pcm.length > 11025 * 2 * 25) return null;
  final samples = ByteData.sublistView(pcm);
  var low = 0.0, mid = 0.0, previous = 0.0;
  var bass = 0.0, body = 0.0, treble = 0.0, power = 0.0;
  var crossings = 0, count = 0;
  final envelopes = <double>[];
  var framePower = 0.0;
  const frameSamples = 1102;
  for (var i = 0; i < pcm.length ~/ 2; i++) {
    final sample = samples.getInt16(i * 2, Endian.little) / 32768;
    low += 0.075 * (sample - low);
    mid += 0.45 * (sample - mid);
    bass += low * low;
    body += (mid - low) * (mid - low);
    treble += (sample - mid) * (sample - mid);
    final energy = sample * sample;
    power += energy;
    framePower += energy;
    if ((sample >= 0) != (previous >= 0)) crossings++;
    previous = sample;
    count++;
    if (count % frameSamples == 0) {
      envelopes.add(math.sqrt(framePower / frameSamples));
      framePower = 0;
    }
  }
  if (power / count < 1e-8 || envelopes.isEmpty) return null;
  final total = math.max(1e-12, bass + body + treble);
  final rms = math.sqrt(power / count);
  var flux = 0.0;
  for (var i = 1; i < envelopes.length; i++) {
    flux += (envelopes[i] - envelopes[i - 1]).abs();
  }
  final mean = envelopes.reduce((a, b) => a + b) / envelopes.length;
  final variance =
      envelopes.fold(0.0, (sum, e) => sum + (e - mean) * (e - mean)) /
      envelopes.length;
  double unit(double value) => value.clamp(0.0, 1.0);
  return AutoplaySoundProfile(
    List.unmodifiable([
      unit(bass / total),
      unit(body / total),
      unit(treble / total),
      unit((20 * math.log(rms) / math.ln10 + 60) / 60),
      unit(crossings / count * 2),
      unit(
        (math.sqrt(variance) + flux / envelopes.length) /
            math.max(0.01, mean) /
            3,
      ),
    ]),
  );
}

/// Unknown summaries are neutral. A bounded acoustic contribution cannot
/// overwhelm recency, duplicate suppression or explicit listening feedback.
double autoplaySoundAdjustment(
  String source,
  List<String> context,
  Map<String, AutoplaySoundProfile> profiles,
) {
  final candidate = profiles[source];
  if (candidate == null) return 0;
  var weighted = 0.0, weights = 0.0;
  for (var i = 0; i < context.length; i++) {
    final profile = profiles[context[i]];
    if (profile == null) continue;
    final weight = 1 / (i + 1);
    weighted += weight * candidate.similarity(profile);
    weights += weight;
  }
  return weights == 0 ? 0 : 6 * (weighted / weights - 0.5);
}
