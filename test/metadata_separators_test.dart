import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/models/metadata_separators.dart';
import 'package:sistrum/models/settings.dart';
import 'package:sistrum/services/ffmpeg/audio_metadata_mapper.dart';

void main() {
  test(
    'old settings preserve source formatting and new settings round trip',
    () {
      expect(AppSettings.fromJson({}).metadataSeparators.isDefault, isTrue);
      const separators = MetadataSeparators(
        artist: '; ',
        albumArtist: ' / ',
        composer: ' | ',
        genre: ', ',
      );
      final settings = const AppSettings(metadataSeparators: separators);
      expect(
        AppSettings.fromJson(settings.toJson()).metadataSeparators.toJson(),
        separators.toJson(),
      );
      expect(
        settings
            .copyWith(playbackNormalization: true)
            .metadataSeparators
            .toJson(),
        separators.toJson(),
      );
    },
  );

  test(
    'formats lists without splitting names or altering unrelated fields',
    () {
      for (final name in [
        'AC/DC',
        'R&B',
        'Florence and the Machine',
        'Simon & Garfunkel',
        'Malcolm X',
      ]) {
        expect(formatMetadataTagValue(name, '; '), name);
      }
      expect(formatMetadataTagValue(' A, B ; C ', '; '), 'A; B; C');
      expect(formatMetadataTagValue(' A, B ', ''), ' A, B ');
      for (final invalid in ['\n', '\x00', 'abcdefghijklmnopq']) {
        expect(MetadataSeparators.fromJson({'artist': invalid}).artist, '');
        expect(formatMetadataTagValue('A, B', invalid), 'A, B');
      }
    },
  );

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
