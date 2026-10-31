import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/audio_analysis/audio_analysis_store.dart';
import 'package:sistrum/widgets/audio_analysis/audio_analysis_widget.dart';

part 'audio_analysis_codecs.dart';
part 'audio_analysis_cutoffs.dart';

void main() {
  _registerAudioAnalysisCodecs();
  _registerAudioAnalysisCutoffs();
}

({Uint8List intensity, int width, int height, double maxFrequencyHz})
_noisySpectrum(int seed) {
  final width = [17, 83, 200, 400][seed % 4];
  final height = [31, 128, 399, 800][(seed ~/ 4) % 4];
  final maxFrequencyHz = [
    8000.0,
    22050.0,
    24000.0,
    48000.0,
    96000.0,
  ][(seed ~/ 16) % 5];
  final intensity = Uint8List(width * height);
  var random = seed + 1;
  final mode = (seed ~/ 80) % 5;
  for (var y = 0; y < height; y++) {
    final frequency = (height - y - 1) / (height - 1);
    for (var x = 0; x < width; x++) {
      random = (1664525 * random + 1013904223) & 0xffffffff;
      final noise = (random >> 24) % 13;
      final base = switch (mode) {
        0 => frequency < 0.68 ? 120 : 24,
        1 => frequency < 0.65 ? (160 - frequency * 170).round() : 24,
        2 => (140 - frequency * 110).round(),
        3 => 16 + (random >> 20) % 170,
        _ =>
          frequency < 0.35
              ? 90
              : frequency < 0.73
              ? 64
              : 35,
      };
      // Five percent broadband transients remain below the temporal P90.
      intensity[y * width + x] = x < width ~/ 20
          ? 255
          : (base + noise).clamp(0, 255);
    }
  }
  return (
    intensity: intensity,
    width: width,
    height: height,
    maxFrequencyHz: maxFrequencyHz,
  );
}

Uint8List _blankIntensity(int width, int height, {int value = 0}) {
  final intensity = Uint8List(width * height);
  if (value > 0) intensity.fillRange(0, intensity.length, value);
  return intensity;
}

void _paintFrequencyBand(
  Uint8List values, {
  required int width,
  required int height,
  required double maxFrequencyHz,
  required double lowHz,
  required double highHz,
  required int intensity,
  int startColumn = 0,
  int? endColumn,
}) {
  final columnEnd = endColumn ?? width;
  for (var y = 0; y < height; y++) {
    final frequency = (height - y - 0.5) / height * maxFrequencyHz;
    if (frequency < lowHz || frequency > highHz) continue;
    for (var x = startColumn; x < columnEnd; x++) {
      values[y * width + x] = intensity;
    }
  }
}

void _paintNaturalSpectralTilt(
  Uint8List values, {
  required int width,
  required int height,
  required int lowFrequencyIntensity,
  required int nyquistIntensity,
}) {
  final span = lowFrequencyIntensity - nyquistIntensity;
  for (var y = 0; y < height; y++) {
    final normalizedFrequency = (height - y - 0.5) / height;
    final intensity =
        (lowFrequencyIntensity -
                span * normalizedFrequency * normalizedFrequency)
            .round()
            .clamp(0, 255);
    for (var x = 0; x < width; x++) {
      values[y * width + x] = intensity;
    }
  }
}

void _paintFrequencySlope(
  Uint8List values, {
  required int width,
  required int height,
  required double maxFrequencyHz,
  required double lowHz,
  required double highHz,
  required int lowIntensity,
  required int highIntensity,
}) {
  final frequencySpan = highHz - lowHz;
  for (var y = 0; y < height; y++) {
    final frequency = (height - y - 0.5) / height * maxFrequencyHz;
    if (frequency < lowHz || frequency > highHz) continue;
    final progress = (frequency - lowHz) / frequencySpan;
    final intensity = (lowIntensity + (highIntensity - lowIntensity) * progress)
        .round()
        .clamp(0, 255);
    for (var x = 0; x < width; x++) {
      values[y * width + x] = intensity;
    }
  }
}
