import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sistrum/services/animated_artwork/animated_artwork_download.dart';

const _top = 'https://cdn.example/v/master.m3u8';
const _variantUrl = 'https://cdn.example/v/variant.m3u8';
const _videoUrl = 'https://cdn.example/v/video.mp4';

const _topPlaylist = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=1000,CODECS="hvc1.2.4",RESOLUTION=640x800
https://cdn.example/v/hevc.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=900,CODECS="avc1.640028",RESOLUTION=1200x1600
variant.m3u8
''';

const _singlePlaylist = '''
#EXTM3U
#EXT-X-TARGETDURATION:4
#EXT-X-MAP:URI="video.mp4",BYTERANGE="32@0"
#EXT-X-BYTERANGE:100@32
#EXTINF:4,
video.mp4
#EXT-X-ENDLIST
''';

/// A 132-byte file with an ftyp box at the start and a moov box inside.
Uint8List _mp4({bool ftyp = true, bool moov = true}) {
  final bytes = Uint8List(132);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = (i * 7) & 0xff;
  }
  if (ftyp) bytes.setRange(4, 8, 'ftyp'.codeUnits);
  if (moov) bytes.setRange(60, 64, 'moov'.codeUnits);
  return bytes;
}

MockClient _client({
  String top = _topPlaylist,
  String variant = _singlePlaylist,
  Uint8List? video,
  int videoStatus = 200,
  int? declaredLength,
  Object? error,
  List<http.BaseRequest>? seen,
}) {
  final body = video ?? _mp4();
  return MockClient.streaming((request, _) async {
    seen?.add(request);
    if (error != null) throw error;
    final url = request.url.toString();
    if (url == _top) {
      return http.StreamedResponse(
        Stream.value(top.codeUnits),
        200,
      );
    }
    if (url == _variantUrl) {
      return http.StreamedResponse(Stream.value(variant.codeUnits), 200);
    }
    if (url == _videoUrl) {
      return http.StreamedResponse(
        Stream.value(body),
        videoStatus,
        contentLength: declaredLength ?? body.length,
      );
    }
    return http.StreamedResponse(const Stream.empty(), 404);
  });
}

void main() {
  late Directory dir;
  late File output;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('aa_download_');
    output = File('${dir.path}/out.part');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('downloadAppleMotionVideo', () {
    test('fetches the AVC variant as one complete MP4 with its size', () async {
      final result = await downloadAppleMotionVideo(
        client: _client(),
        playlist: Uri.parse(_top),
        output: output,
      );
      expect(result.bytes, 132);
      expect(result.width, 1200);
      expect(result.height, 1600);
      expect(await output.readAsBytes(), _mp4());
    });

    test('a segmented playlist is unsupported, not concatenated', () async {
      const segmented = '''
#EXTM3U
#EXTINF:4,
seg1.m4s
#EXTINF:4,
seg2.m4s
#EXT-X-ENDLIST
''';
      await expectLater(
        downloadAppleMotionVideo(
          client: _client(variant: segmented),
          playlist: Uri.parse(_top),
          output: output,
        ),
        throwsA(
          isA<AnimatedVideoDownloadException>().having(
            (e) => e.failure,
            'failure',
            AnimatedVideoFailure.unsupportedMedia,
          ),
        ),
      );
      expect(output.existsSync(), isFalse);
    });

    test('a frame larger than the bound is rejected before any fetch', () async {
      const huge = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=1,CODECS="avc1.640028",RESOLUTION=8000x8000
variant.m3u8
''';
      final seen = <http.BaseRequest>[];
      await expectLater(
        downloadAppleMotionVideo(
          client: _client(top: huge, seen: seen),
          playlist: Uri.parse(_top),
          output: output,
        ),
        throwsA(
          isA<AnimatedVideoDownloadException>().having(
            (e) => e.failure,
            'failure',
            AnimatedVideoFailure.tooLarge,
          ),
        ),
      );
      expect(seen.map((r) => r.url.toString()), [_top]);
    });

    test('a file over the byte limit is refused and removed', () async {
      await expectLater(
        downloadAppleMotionVideo(
          client: _client(),
          playlist: Uri.parse(_top),
          output: output,
          maxBytes: 100,
        ),
        throwsA(
          isA<AnimatedVideoDownloadException>().having(
            (e) => e.failure,
            'failure',
            AnimatedVideoFailure.tooLarge,
          ),
        ),
      );
      expect(output.existsSync(), isFalse);
    });

    test('a file without an ftyp box is an invalid container', () async {
      await expectLater(
        downloadAppleMotionVideo(
          client: _client(video: _mp4(ftyp: false)),
          playlist: Uri.parse(_top),
          output: output,
        ),
        throwsA(
          isA<AnimatedVideoDownloadException>().having(
            (e) => e.failure,
            'failure',
            AnimatedVideoFailure.invalidContainer,
          ),
        ),
      );
      expect(output.existsSync(), isFalse);
    });

    test('a file without a moov box is an invalid container', () async {
      await expectLater(
        downloadAppleMotionVideo(
          client: _client(video: _mp4(moov: false)),
          playlist: Uri.parse(_top),
          output: output,
        ),
        throwsA(
          isA<AnimatedVideoDownloadException>().having(
            (e) => e.failure,
            'failure',
            AnimatedVideoFailure.invalidContainer,
          ),
        ),
      );
    });

    test('a short body is incomplete and nothing is published', () async {
      await expectLater(
        downloadAppleMotionVideo(
          client: _client(video: _mp4().sublist(0, 100)),
          playlist: Uri.parse(_top),
          output: output,
        ),
        throwsA(
          isA<AnimatedVideoDownloadException>().having(
            (e) => e.failure,
            'failure',
            AnimatedVideoFailure.incomplete,
          ),
        ),
      );
      expect(output.existsSync(), isFalse);
    });

    test('an HTTP error on the video is a network failure', () async {
      await expectLater(
        downloadAppleMotionVideo(
          client: _client(videoStatus: 403),
          playlist: Uri.parse(_top),
          output: output,
        ),
        throwsA(
          isA<AnimatedVideoDownloadException>().having(
            (e) => e.failure,
            'failure',
            AnimatedVideoFailure.network,
          ),
        ),
      );
    });

    test('a socket failure is a network failure', () async {
      await expectLater(
        downloadAppleMotionVideo(
          client: _client(error: const SocketException('reset')),
          playlist: Uri.parse(_top),
          output: output,
        ),
        throwsA(
          isA<AnimatedVideoDownloadException>().having(
            (e) => e.failure,
            'failure',
            AnimatedVideoFailure.network,
          ),
        ),
      );
    });

    test('a cancelled request stops before the playlist is read', () async {
      final seen = <http.BaseRequest>[];
      await expectLater(
        downloadAppleMotionVideo(
          client: _client(seen: seen),
          playlist: Uri.parse(_top),
          output: output,
          isCancelled: () => true,
        ),
        throwsA(
          isA<AnimatedVideoDownloadException>().having(
            (e) => e.failure,
            'failure',
            AnimatedVideoFailure.cancelled,
          ),
        ),
      );
      expect(seen, isEmpty);
    });

    test('only https playlists are followed', () async {
      const insecure = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=1,CODECS="avc1.640028",RESOLUTION=100x100
http://cdn.example/v/variant.m3u8
''';
      await expectLater(
        downloadAppleMotionVideo(
          client: _client(top: insecure),
          playlist: Uri.parse(_top),
          output: output,
        ),
        throwsA(isA<AnimatedVideoDownloadException>()),
      );
    });
  });

  group('importAnimatedVideoStream', () {
    test('copies a valid picked file from its byte stream', () async {
      final bytes = _mp4();
      final result = await importAnimatedVideoStream(
        source: Stream.fromIterable([
          bytes.sublist(0, 50),
          bytes.sublist(50),
        ]),
        output: output,
        declaredLength: bytes.length,
      );
      expect(result.bytes, bytes.length);
      expect(await output.readAsBytes(), bytes);
    });

    test('a length that differs from the declared size is incomplete', () async {
      await expectLater(
        importAnimatedVideoStream(
          source: Stream.value(_mp4()),
          output: output,
          declaredLength: 500,
        ),
        throwsA(
          isA<AnimatedVideoDownloadException>().having(
            (e) => e.failure,
            'failure',
            AnimatedVideoFailure.incomplete,
          ),
        ),
      );
      expect(output.existsSync(), isFalse);
    });

    test('a declared size over the limit is refused before reading', () async {
      await expectLater(
        importAnimatedVideoStream(
          source: const Stream.empty(),
          output: output,
          declaredLength: kAnimatedArtworkMaxBytes + 1,
        ),
        throwsA(
          isA<AnimatedVideoDownloadException>().having(
            (e) => e.failure,
            'failure',
            AnimatedVideoFailure.tooLarge,
          ),
        ),
      );
      expect(output.existsSync(), isFalse);
    });

    test('a picked file that is not an MP4 is rejected and removed', () async {
      await expectLater(
        importAnimatedVideoStream(
          source: Stream.value(Uint8List.fromList(List.filled(64, 1))),
          output: output,
        ),
        throwsA(
          isA<AnimatedVideoDownloadException>().having(
            (e) => e.failure,
            'failure',
            AnimatedVideoFailure.invalidContainer,
          ),
        ),
      );
      expect(output.existsSync(), isFalse);
    });
  });
}
