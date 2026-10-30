import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/utils/scan/audio_quality_badge_policy.dart';

void main() {
  group('standard Library audio quality labels', () {
    test('uses measured bitrate instead of stale stored metadata', () {
      expect(
        buildLibraryAudioQualityLabel(
          format: 'opus',
          bitrateKbps: 256,
          storedQuality: 'OPUS 320kbps',
        ),
        'OPUS 256kbps',
      );
      expect(
        buildLibraryAudioQualityLabel(format: 'flac', bitrateKbps: 1760),
        'FLAC 1760kbps',
      );
    });
    test('uses a stored bitrate while measurement is unavailable', () {
      expect(
        buildLibraryAudioQualityLabel(
          format: 'opus',
          storedQuality: 'OPUS 320kbps',
        ),
        'OPUS 320kbps',
      );
      expect(
        buildLibraryAudioQualityLabel(
          format: 'flac',
          storedQuality: 'FLAC 1.411 Mbps',
        ),
        'FLAC 1411kbps',
      );
    });
    test(
      'legacy lossy files retain a codec badge without invented quality',
      () {
        expect(
          buildLibraryAudioQualityLabel(
            filePath: '/music/Song.opus',
            storedQuality: '16-bit/44.1kHz',
          ),
          'OPUS',
        );
        expect(
          buildLibraryAudioQualityLabel(
            filePath: 'content://music/document/42',
            fileName: 'Song.OPUS',
          ),
          'OPUS',
        );
        expect(
          buildLibraryAudioQualityLabel(
            format: 'flac',
            storedQuality: '24-bit/96kHz',
          ),
          isNull,
        );
      },
    );
  });
}
