import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/playback/autoplay/autoplay_sound_profile.dart';

Uint8List tone(double frequency, {double volume = 0.5}) {
  final bytes = ByteData(11025 * 2 * 4);
  for (var i = 0; i < bytes.lengthInBytes ~/ 2; i++) {
    bytes.setInt16(
      i * 2,
      (sin(2 * pi * frequency * i / 11025) * volume * 32767).round(),
      Endian.little,
    );
  }
  return bytes.buffer.asUint8List();
}

void main() {
  test('decoded timbre distinguishes tones and tolerates gain differences', () {
    final bass = analyzeAutoplaySoundPcm(tone(110))!;
    final same = analyzeAutoplaySoundPcm(tone(110, volume: 0.3))!;
    final treble = analyzeAutoplaySoundPcm(tone(4000))!;
    expect(bass.similarity(same), greaterThan(bass.similarity(treble)));
    expect(bass.similarity(bass), 1);
    expect(bass.values.every((v) => v.isFinite && v >= 0 && v <= 1), true);
    expect(AutoplaySoundProfile.decode(bass.values)!.values, bass.values);
  });
  test('silence, oversized PCM and invalid summaries are neutral', () {
    expect(analyzeAutoplaySoundPcm(Uint8List(11025 * 8)), isNull);
    expect(analyzeAutoplaySoundPcm(Uint8List(11025 * 2 * 26)), isNull);
    expect(AutoplaySoundProfile.decode([double.nan]), isNull);
    expect(
      AutoplaySoundProfile.decode(List.filled(6, double.infinity)),
      isNull,
    );
    expect(autoplaySoundAdjustment('missing', ['seed'], {}), 0);
    final a = analyzeAutoplaySoundPcm(tone(110))!;
    final b = analyzeAutoplaySoundPcm(tone(4000))!;
    final profiles = {'seed': a, 'similar': a, 'different': b};
    expect(
      autoplaySoundAdjustment('similar', ['seed'], profiles),
      greaterThan(autoplaySoundAdjustment('different', ['seed'], profiles)),
    );
    expect(autoplaySoundAdjustment('similar', ['unknown'], profiles), 0);
  });
}
