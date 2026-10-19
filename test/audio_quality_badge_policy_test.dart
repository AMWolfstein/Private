import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/models/unified_library_item.dart';
import 'package:spotiflac_android/services/library_database.dart';
import 'package:spotiflac_android/utils/audio_quality_badge_policy.dart';

void main() {
  test('Library local cards retain labels for legacy Opus rows', () {
    final local = UnifiedLibraryItem.fromLocalLibrary(
      LocalLibraryItem(
        id: 'local-song',
        trackName: 'Song',
        artistName: 'Artist',
        albumName: 'Album',
        filePath: '/music/Song.opus',
        scannedAt: DateTime(2026),
      ),
    );
    expect(local.displayQuality, 'OPUS');
  });

  group('Library audio quality badge color', () {
    test('keeps legacy 24-bit labels highlighted', () {
      expect(shouldHighlightAudioQualityBadge('24-bit/96kHz'), isTrue);
      expect(shouldHighlightAudioQualityBadge('FLAC 24bit-48kHz'), isTrue);
      expect(shouldHighlightAudioQualityBadge('24/192kHz'), isTrue);
    });

    test('highlights only measured bitrates above 900 kbps', () {
      expect(shouldHighlightAudioQualityBadge('900kbps'), isFalse);
      expect(shouldHighlightAudioQualityBadge('901kbps'), isTrue);
      expect(shouldHighlightAudioQualityBadge('FLAC 1760 kbps'), isTrue);
      expect(shouldHighlightAudioQualityBadge('1.76 Mbps'), isTrue);
    });

    test('leaves normal lossy bitrate labels neutral', () {
      expect(shouldHighlightAudioQualityBadge('AAC 320kbps'), isFalse);
      expect(shouldHighlightAudioQualityBadge('OPUS 256k'), isFalse);
      expect(shouldHighlightAudioQualityBadge('16-bit/44.1kHz'), isFalse);
    });
  });

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

  group('Library grid audio quality label', () {
    test('keeps both parts of detailed bit-depth labels', () {
      expect(
        formatLibraryGridAudioQualityLabel('16-bit/44.1kHz'),
        '16-bit/44.1kHz',
      );
      expect(
        formatLibraryGridAudioQualityLabel('16-bit/1411kbps'),
        '16-bit/1411kbps',
      );
      expect(isDetailedLibraryAudioQualityLabel('16-bit/44.1kHz'), isTrue);
    });

    test('keeps bitrate-only grid labels compact', () {
      expect(formatLibraryGridAudioQualityLabel('FLAC 1760kbps'), '1760k');
      expect(formatLibraryGridAudioQualityLabel('Bitrate 1760kbps'), '1760k');
      expect(isDetailedLibraryAudioQualityLabel('FLAC 1760kbps'), isFalse);
    });
  });
}
