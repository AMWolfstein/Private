import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/audio_metadata_mapper.dart';
import 'package:sistrum/services/id3v23_lyrics.dart';

void main() {
  group('home search logic', () {});

  group('FFmpeg value models', () {});

  group('audio metadata modules', () {
    test('maps shared tags consistently for native, M4A, and ID3 writers', () {
      final metadata = {
        'TITLE': 'Track',
        'ARTIST': 'Artist',
        'ALBUM': 'Album',
        'ALBUM_ARTIST': 'Album Artist',
        'TRACKNUMBER': '3/12',
        'DISCNUMBER': '1/2',
        'DATE': '2026-08-01',
        'GENRE': 'Pop',
        'ISRC': 'TEST12345678',
        'UNSYNCEDLYRICS': 'Lyrics',
        'ORGANIZATION': 'Label',
        'COPYRIGHT': 'Copyright',
        'COMPOSER': 'Composer',
        'COMMENT': 'Comment',
        'ITUNESADVISORY': '1',
        'REPLAYGAIN_TRACK_GAIN': '-5.00 dB',
        'BIT_DEPTH': '24',
      };

      final m4a = AudioMetadataMapper.convertToM4aTags(metadata);
      final m4aIdentity = AudioMetadataMapper.m4aReleaseIdentityFields(
        metadata,
      );
      final id3 = AudioMetadataMapper.convertToId3Tags(metadata);

      expect(m4a['isrc'], 'TEST12345678');
      expect(m4a['lyrics'], 'Lyrics');
      expect(m4aIdentity['explicit'], '1');
      expect(id3['TSRC'], 'TEST12345678');
      expect(id3['ITUNESADVISORY'], '1');
      expect(id3['REPLAYGAIN_TRACK_GAIN'], '-5.00 dB');
      expect(id3['title'], 'Track');
      expect(id3['artist'], 'Artist');
      expect(id3['album'], 'Album');
      expect(id3['track'], '3/12');
      expect(id3['disc'], '1/2');
    });

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

    test('writes one ID3v2.3 USLT frame and replaces it on update', () {
      final audio = Uint8List.fromList([0xff, 0xfb, 0x90, 0x64]);
      final first = Id3v23Lyrics.writeUnsyncedLyrics(audio, 'First lyrics');
      final second = Id3v23Lyrics.writeUnsyncedLyrics(
        first!,
        'Replacement lyrics',
      );

      expect(second, isNotNull);
      expect(second!.sublist(0, 4), [0x49, 0x44, 0x33, 0x03]);
      expect(_sequenceCount(second, ascii.encode('USLT')), 1);
      expect(second.sublist(second.length - audio.length), audio);
    });

    test('leaves unsupported ID3 versions unchanged', () {
      final id3v24 = Uint8List.fromList([
        0x49,
        0x44,
        0x33,
        0x04,
        0,
        0,
        0,
        0,
        0,
        0,
      ]);

      expect(Id3v23Lyrics.writeUnsyncedLyrics(id3v24, 'Lyrics'), isNull);
    });
  });
}

int _sequenceCount(Uint8List bytes, List<int> sequence) {
  var count = 0;
  for (var index = 0; index <= bytes.length - sequence.length; index++) {
    var matches = true;
    for (var offset = 0; offset < sequence.length; offset++) {
      if (bytes[index + offset] != sequence[offset]) {
        matches = false;
        break;
      }
    }
    if (matches) count++;
  }
  return count;
}
