import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/audio_analysis/audio_analysis_spectral_cutoff.dart';

const _width = 400;
const _height = 800;
const _maxHz = 22050.0;

/// Builds a spectrogram whose gray level for frequency bin [f] is
/// `levelAt(f)`. Row 0 of the image is the top (Nyquist), as FFmpeg writes it.
Uint8List _spectrogram(int Function(int frequencyBin) levelAt) {
  final bytes = Uint8List(_width * _height);
  for (var y = 0; y < _height; y++) {
    final frequencyBin = _height - y - 1;
    final level = levelAt(frequencyBin);
    bytes.fillRange(y * _width, (y + 1) * _width, level);
  }
  return bytes;
}

double? _estimate(Uint8List intensity) => estimateEffectiveSpectralCutoffHz(
  intensity: intensity,
  width: _width,
  height: _height,
  maxFrequencyHz: _maxHz,
);

void main() {
  test('invalid dimensions or a short buffer give no estimate', () {
    final bytes = _spectrogram((_) => 150);
    expect(
      estimateEffectiveSpectralCutoffHz(
        intensity: bytes,
        width: 0,
        height: _height,
        maxFrequencyHz: _maxHz,
      ),
      isNull,
    );
    expect(
      estimateEffectiveSpectralCutoffHz(
        intensity: bytes.sublist(0, 100),
        width: _width,
        height: _height,
        maxFrequencyHz: _maxHz,
      ),
      isNull,
    );
  });

  test('silence has no bandwidth to measure', () {
    expect(_estimate(_spectrogram((_) => 0)), isNull);
  });

  test('a flat full-band spectrum reaches the analysis ceiling', () {
    expect(_estimate(_spectrogram((_) => 150)), _maxHz);
  });

  test('a sharp low-pass edge is found near its frequency', () {
    // Content up to half the Nyquist frequency, then a floor.
    final cutoffBin = _height ~/ 2;
    final cutoff = _estimate(_spectrogram((f) => f < cutoffBin ? 180 : 10));
    expect(cutoff, isNotNull);
    expect(cutoff!, inInclusiveRange(_maxHz * 0.4, _maxHz * 0.6));
  });

  test('a lone bright line does not look like bandwidth', () {
    final line = _spectrogram((f) => f == 300 ? 255 : 10);
    expect(_estimate(line), isNull);
  });

  group('file entry point', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('cutoff'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('reads the intensity file and estimates the same cutoff', () {
      final bytes = _spectrogram((f) => f < _height ~/ 2 ? 180 : 10);
      final file = File('${dir.path}/cutoff.gray')..writeAsBytesSync(bytes);
      final fromFile = estimateEffectiveSpectralCutoffFileInIsolate(
        SpectralCutoffFileParams(
          path: file.path,
          width: _width,
          height: _height,
          maxFrequencyHz: _maxHz,
        ),
      );
      expect(fromFile, _estimate(bytes));
    });

    test('a truncated intensity file is rejected as incomplete', () {
      final file = File('${dir.path}/short.gray')
        ..writeAsBytesSync(Uint8List(100));
      expect(
        () => estimateEffectiveSpectralCutoffFileInIsolate(
          SpectralCutoffFileParams(
            path: file.path,
            width: _width,
            height: _height,
            maxFrequencyHz: _maxHz,
          ),
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
