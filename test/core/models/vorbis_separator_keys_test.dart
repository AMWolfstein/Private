import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/ffmpeg/audio_metadata_mapper.dart';

void main() {
  test(
    'custom joined artist tags override Vorbis splitting per field only',
    () {
      final fields = {
        'ARTIST': 'A; B',
        'ALBUMARTIST': 'C, D',
        'COMPOSER': 'E | F',
        'artist_separator': '; ',
      };
      final entries = AudioMetadataMapper.buildVorbisMetadataEntries(fields);
      expect(
        entries
            .where((entry) => entry.key == 'ARTIST')
            .map((entry) => entry.value),
        ['A; B'],
      );
      expect(
        entries
            .where((entry) => entry.key == 'ALBUMARTIST')
            .map((entry) => entry.value),
        ['C, D'],
      );
      expect(entries.any((entry) => entry.key.endsWith('_separator')), isFalse);
    },
  );
}
