import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/playback/autoplay/autoplay_sound_profile.dart';

void main() {
  test('old, malformed and nonfinite feature layouts are rejected', () {
    expect(AutoplaySoundProfile.decode(List.filled(6, .5)), isNull);
    expect(AutoplaySoundProfile.decode(List.filled(42, double.nan)), isNull);
    final values = List.filled(42, 0.0);
    expect(AutoplaySoundProfile.decode(values)!.values, values);
    values[13] = 12;
    expect(AutoplaySoundProfile.decode(values), isNull);
  });
}
