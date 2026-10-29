import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/ffmpeg/audio_metadata_mapper.dart';

void main() {
  group('home search logic', () {});

  group('FFmpeg value models', () {});

  group('audio metadata modules', () {
    test('builds Vorbis artist entries without losing other tags', () {
      final entries = AudioMetadataMapper.buildVorbisMetadataEntries({
        'ARTIST': 'First & Second',
        'TITLE': 'Track',
      });

      expect(
        entries.where((entry) => entry.key == 'ARTIST').map((e) => e.value),
        ['First & Second'],
      );
      expect(
        entries.where((entry) => entry.key == 'TITLE').single.value,
        'Track',
      );
      final advisory = AudioMetadataMapper.buildVorbisMetadataEntries({
        'EXPLICIT': 'true',
      }).single;
      expect(advisory.key, 'ITUNESADVISORY');
      expect(advisory.value, '1');
    });
  });
}
