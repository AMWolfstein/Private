import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/playback/audio/replaygain_write_result.dart';

void main() {
  group('ReplayGainIntegrity', () {
    test('keeps a write whose audio hash and size agree', () {
      expect(
        ReplayGainIntegrity.check(
          beforeHash: 'aa',
          afterHash: 'aa',
          sizeBefore: 1000,
          sizeAfter: 1200,
        ),
        isNull,
      );
    });

    test('restores when the audio hash differs or is unknown', () {
      expect(
        ReplayGainIntegrity.check(
          beforeHash: 'aa',
          afterHash: 'bb',
          sizeBefore: 1000,
          sizeAfter: 1000,
        ),
        ReplayGainWriteFailure.audioChanged,
      );
      expect(
        ReplayGainIntegrity.check(
          beforeHash: null,
          afterHash: 'aa',
          sizeBefore: 1000,
          sizeAfter: 1000,
        ),
        ReplayGainWriteFailure.verificationFailed,
      );
    });

    test('restores when the size moves by more than tags explain', () {
      expect(
        ReplayGainIntegrity.check(
          beforeHash: 'aa',
          afterHash: 'aa',
          sizeBefore: 100 * 1024 * 1024,
          sizeAfter: 90 * 1024 * 1024,
        ),
        ReplayGainWriteFailure.audioChanged,
      );
    });
  });
}
