import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/playback/core/playback_metadata.dart';

MediaItem _item(Map<String, dynamic>? extras) =>
    MediaItem(id: 'item', title: 'Title', extras: extras);

void main() {
  group('playbackAudioMetadataFromMediaItem', () {
    test('returns nothing when the item has no extras', () {
      expect(playbackAudioMetadataFromMediaItem(_item(null)), isEmpty);
      expect(playbackAudioMetadataFromMediaItem(_item({})), isEmpty);
    });

    test('keeps only usable technical fields', () {
      final metadata = playbackAudioMetadataFromMediaItem(
        _item({
          'bit_depth': '24',
          'sample_rate': 96000,
          'bitrate': 0,
          'format': ' flac ',
          'explicit': 'true',
        }),
      );
      expect(metadata, {
        'bit_depth': 24,
        'sample_rate': 96000,
        'format': 'flac',
        'explicit': true,
      });
    });

    test('drops a blank format', () {
      final metadata = playbackAudioMetadataFromMediaItem(
        _item({'format': '   ', 'bitrate': 320000}),
      );
      expect(metadata, {'bitrate': 320000});
    });
  });

  group('mergePlaybackFileMetadata', () {
    test('keeps known queue quality when the probe reports zero', () {
      final merged = mergePlaybackFileMetadata(
        {
          'bit_depth': 16,
          'sample_rate': 44100,
          'bitrate': 900,
          'format': 'flac',
        },
        {'bit_depth': 0, 'sample_rate': 96000, 'bitrate': null, 'format': ''},
      );
      expect(merged['bit_depth'], 16);
      expect(merged['sample_rate'], 96000);
      expect(merged['bitrate'], 900);
      expect(merged['format'], 'flac');
    });

    test('prefers the probed format when it is present', () {
      final merged = mergePlaybackFileMetadata(
        {'format': 'flac'},
        {'format': 'alac'},
      );
      expect(merged['format'], 'alac');
    });
  });

  group('readPlaybackFileMetadataWithRetry', () {
    const instant = [Duration.zero, Duration.zero, Duration.zero];

    test('returns a clean first response without retrying', () async {
      var calls = 0;
      final metadata = await readPlaybackFileMetadataWithRetry(
        '/a.flac',
        retryDelays: instant,
        reader: (_) async {
          calls++;
          return {'lyrics': ''};
        },
      );
      expect(metadata, {'lyrics': ''});
      expect(calls, 1);
    });

    test('retries a thrown error until a later read succeeds', () async {
      var calls = 0;
      final metadata = await readPlaybackFileMetadataWithRetry(
        '/a.flac',
        retryDelays: instant,
        reader: (_) async {
          calls++;
          if (calls < 2) throw StateError('bridge not ready');
          return {'bit_depth': 24};
        },
      );
      expect(metadata, {'bit_depth': 24});
      expect(calls, 2);
    });

    test('treats an error field like a thrown error', () async {
      var calls = 0;
      final metadata = await readPlaybackFileMetadataWithRetry(
        '/a.flac',
        retryDelays: instant,
        reader: (_) async {
          calls++;
          return calls == 1 ? {'error': 'cold start'} : {'bit_depth': 16};
        },
      );
      expect(metadata, {'bit_depth': 16});
      expect(calls, 2);
    });

    test('rethrows the last error after every attempt fails', () async {
      var calls = 0;
      await expectLater(
        readPlaybackFileMetadataWithRetry(
          '/a.flac',
          retryDelays: instant,
          reader: (_) async {
            calls++;
            return {'error': 'still failing $calls'};
          },
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'still failing 3',
          ),
        ),
      );
      expect(calls, 3);
    });

    test('an empty delay list still makes one attempt', () async {
      var calls = 0;
      await expectLater(
        readPlaybackFileMetadataWithRetry(
          '/a.flac',
          retryDelays: const [],
          reader: (_) async {
            calls++;
            throw StateError('nope');
          },
        ),
        throwsStateError,
      );
      expect(calls, 1);
    });
  });
}
