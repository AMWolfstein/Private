import 'dart:typed_data';
import 'package:sistrum/services/playback/autoplay/song_features.dart';

/// Versioned native MFCC/tempo/key descriptor. Raw PCM is never persisted.
class AutoplaySoundProfile {
  const AutoplaySoundProfile(this.values);
  final List<double> values;
  static const dimensions = SongFeatures.length;

  static AutoplaySoundProfile? decode(Object? value) {
    if (value is! List || value.length != dimensions) return null;
    final values = <double>[];
    for (final item in value) {
      if (item is! num || !item.isFinite || item.abs() > 1e6) return null;
      values.add(item.toDouble());
    }
    if (values[SongFeatures.tempo] < 0 ||
        values[SongFeatures.tempo] > 180 ||
        values[SongFeatures.tempoConfidence] < 0 ||
        values[SongFeatures.tempoConfidence] > 1 ||
        values[SongFeatures.key] < 0 ||
        values[SongFeatures.key] > 11 ||
        (values[SongFeatures.mode] != 0 && values[SongFeatures.mode] != 1)) {
      return null;
    }
    return AutoplaySoundProfile(List.unmodifiable(values));
  }

  Float32List get vector => Float32List.fromList(values);
}
