import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sistrum/services/animated_artwork/animated_artwork_auto_pass.dart';
import 'package:sistrum/services/animated_artwork/animated_artwork_store.dart';
import 'package:sistrum/services/animated_artwork/apple_artwork_client.dart';
import 'package:sistrum/services/artist_images/artist_image_network.dart';

Uint8List _mp4() {
  final bytes = Uint8List(132);
  bytes.setRange(4, 8, 'ftyp'.codeUnits);
  bytes.setRange(60, 64, 'moov'.codeUnits);
  return bytes;
}

String _playlist(String videoUrl) => '''
#EXTM3U
#EXT-X-MAP:URI="$videoUrl",BYTERANGE="32@0"
#EXT-X-BYTERANGE:100@32
#EXTINF:4,
$videoUrl
#EXT-X-ENDLIST
''';

/// A fake Apple catalog and CDN in one client. Every request is recorded so
/// tests can prove what was (not) fetched.
class _Remote {
  _Remote({
    this.albums = const {},
    this.artists = const {},
    this.albumVideos = const {},
    this.searchStatus = 200,
  });

  /// Search term (lowercase) -> catalog album JSON entries.
  final Map<String, List<Map<String, Object?>>> albums;
  final Map<String, List<Map<String, Object?>>> artists;
  final Map<String, Map<String, Object?>> albumVideos;
  final int searchStatus;
  final requests = <String>[];
  final playlists = <String>{};

  http.Client build() => MockClient.streaming((request, _) async {
    final url = request.url.toString();
    requests.add(url);
    if (url == 'https://music.apple.com/us/browse') {
      return http.StreamedResponse(
        Stream.value('devToken=aaa.bbb.ccc'.codeUnits),
        200,
      );
    }
    if (url.contains('/catalog/us/search?')) {
      if (searchStatus != 200) {
        return http.StreamedResponse(const Stream.empty(), searchStatus);
      }
      final term = Uri.parse(url).queryParameters['term']!.toLowerCase();
      final results = <String, Object?>{};
      if (albums.containsKey(term)) {
        results['albums'] = {'data': albums[term]};
      }
      final artistHits = artists[term];
      if (artistHits != null) results['artists'] = {'data': artistHits};
      return _json({'results': results});
    }
    final albumMatch = RegExp(r'/catalog/us/albums/(\d+)\?').firstMatch(url);
    if (albumMatch != null) {
      final video = albumVideos[albumMatch.group(1)!];
      return _json({'data': video == null ? <Object?>[] : <Object?>[video]});
    }
    if (url.endsWith('.m3u8')) {
      playlists.add(url);
      final video = '${url.substring(0, url.lastIndexOf('/') + 1)}video.mp4';
      return http.StreamedResponse(
        Stream.value(_playlist(video).codeUnits),
        200,
      );
    }
    if (url.endsWith('/video.mp4')) {
      final body = _mp4();
      return http.StreamedResponse(
        Stream.value(body),
        200,
        contentLength: body.length,
      );
    }
    return http.StreamedResponse(const Stream.empty(), 404);
  });

  http.StreamedResponse _json(Object body) {
    final bytes = utf8.encode(jsonEncode(body));
    return http.StreamedResponse(Stream.value(bytes), 200, contentLength: bytes.length);
  }

  Map<String, Object?> videoEntry(String key, String url) => {
    'attributes': {
      'editorialVideo': {
        key: {'video': url},
      },
    },
  };
}

void main() {
  late Directory dir;
  late AnimatedArtworkStore store;
  late AnimatedArtworkState state;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('aa_pass_');
    state = MemoryAnimatedArtworkState();
    store = AnimatedArtworkStore(
      state: state,
      directory: () async => Directory('${dir.path}/animated_artwork'),
    );
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  const abbey = AnimatedArtworkTarget.album(
    title: 'Abbey Road',
    albumArtist: 'The Beatles',
  );
  const nina = AnimatedArtworkTarget.artist(artistName: 'Nina Simone');

  Future<AnimatedArtworkAutoResult> run(
    _Remote remote,
    List<AnimatedArtworkTarget> targets, {
    ArtistImageNetwork policy = ArtistImageNetwork.wifi,
    ArtistNetworkKind network = ArtistNetworkKind.wifi,
    bool Function()? enabled,
    bool Function(AnimatedArtworkTarget)? isLocked,
    int batchSize = 5,
    void Function()? onChanged,
    DateTime Function()? clock,
    Duration retryAfter = kAnimatedArtworkRetryAfter,
  }) {
    final client = remote.build();
    final api = AppleArtworkClient(
      client: client,
      attempts: 1,
      pause: (_) async {},
    );
    return runAnimatedArtworkAutoPass(
      targets: targets,
      store: store,
      api: api,
      downloadClient: client,
      policy: policy,
      readNetwork: () async => network,
      stillEnabled: enabled ?? () => true,
      pause: Duration.zero,
      batchSize: batchSize,
      onChanged: onChanged,
      isLocked: isLocked,
      clock: clock,
      retryAfter: retryAfter,
    );
  }

  _Remote abbeyRoadRemote({int? trackCount}) => _Remote(
    albums: {
      'abbey road the beatles': [
        {
          'id': '1',
          'attributes': {
            'name': 'Abbey Road',
            'artistName': 'The Beatles',
            'trackCount': ?trackCount,
          },
        },
      ],
    },
    albumVideos: {
      '1': {
        'attributes': {
          'editorialVideo': {
            'motionDetailTall': {
              'video': 'https://video.example/abbey/master.m3u8',
            },
          },
        },
      },
    },
  );

  test('an exact album match saves the tall video once', () async {
    final remote = abbeyRoadRemote();
    final result = await run(remote, [abbey]);

    expect(result.stopped, isNull);
    expect(result.progress.saved, 1);
    expect(result.progress.total, 1);
    final record = await store.recordFor(
      AnimatedArtworkKind.album,
      abbey.key,
    );
    expect(record?.hasVideo, isTrue);
    expect(record?.remoteId, 'apple:album:1:motionDetailTall');
  });

  test('an entity that already has a video sends no request', () async {
    final remote = abbeyRoadRemote();
    await run(remote, [abbey]);
    remote.requests.clear();

    final result = await run(remote, [abbey]);
    expect(result.progress.skipped, 1);
    expect(remote.requests, isEmpty);
  });

  test('a recent miss is not searched again, an old one is', () async {
    final remote = _Remote();
    await run(remote, [nina]);
    expect(
      (await store.recordFor(AnimatedArtworkKind.artist, nina.key))?.status,
      AnimatedArtworkStatus.notFound,
    );

    remote.requests.clear();
    final soon = await run(remote, [nina]);
    expect(soon.progress.skipped, 1);
    expect(remote.requests, isEmpty);

    final later = await run(
      remote,
      [nina],
      clock: () => DateTime.now().add(kAnimatedArtworkRetryAfter + const Duration(days: 1)),
    );
    expect(later.progress.skipped, 0);
    expect(remote.requests, isNotEmpty);
  });

  test('a different track count is a different edition and is not matched', () async {
    final remote = abbeyRoadRemote(trackCount: 20);
    final result = await run(
      remote,
      [
        const AnimatedArtworkTarget.album(
          title: 'Abbey Road',
          albumArtist: 'The Beatles',
          trackCount: 17,
        ),
      ],
    );
    expect(result.progress.saved, 0);
    expect(result.progress.notFound, 1);
    expect(
      remote.requests.where((u) => u.contains('/albums/1?')),
      isEmpty,
      reason: 'no video is fetched for a rejected edition',
    );
  });

  test('two exact catalog releases are ambiguous and recorded as a miss', () async {
    final remote = _Remote(
      albums: {
        'live band': [
          {'id': '1', 'attributes': {'name': 'Live', 'artistName': 'Band'}},
          {'id': '2', 'attributes': {'name': 'Live', 'artistName': 'Band'}},
        ],
      },
    );
    final result = await run(remote, [
      const AnimatedArtworkTarget.album(title: 'Live', albumArtist: 'Band'),
    ]);
    expect(result.progress.notFound, 1);
    expect(result.progress.saved, 0);
  });

  test('no exact artist match is recorded as a miss without a download', () async {
    final remote = _Remote(
      artists: {
        'nina simone': [
          {'id': '5', 'attributes': {'name': 'Nina Simone Band'}},
        ],
      },
    );
    final result = await run(remote, [nina]);
    expect(result.progress.notFound, 1);
    expect(remote.playlists, isEmpty);
  });

  test('a network the setting does not allow stops before any request', () async {
    final remote = abbeyRoadRemote();
    final result = await run(
      remote,
      [abbey],
      policy: ArtistImageNetwork.wifi,
      network: ArtistNetworkKind.cellular,
    );
    expect(result.stopped, AnimatedArtworkAutoStop.networkNotAllowed);
    expect(remote.requests, isEmpty);
  });

  test('turning the setting off keeps every saved video and its file', () async {
    final remote = abbeyRoadRemote();
    await run(remote, [abbey]);
    final before = await store.recordFor(AnimatedArtworkKind.album, abbey.key);
    final file = await store.fileFor(before!);
    expect(file, isNotNull);

    final result = await run(remote, [abbey], enabled: () => false);
    expect(result.stopped, AnimatedArtworkAutoStop.disabled);

    final after = await store.recordFor(AnimatedArtworkKind.album, abbey.key);
    expect(after?.hasVideo, isTrue);
    expect(await store.fileFor(after!), isNotNull);
  });

  test('turning the setting off stops the pass', () async {
    final remote = abbeyRoadRemote();
    final result = await run(
      remote,
      [abbey],
      enabled: () => false,
    );
    expect(result.stopped, AnimatedArtworkAutoStop.disabled);
    expect(remote.requests, isEmpty);
  });

  test('three failing catalog requests in a row end the pass as an outage', () async {
    final remote = _Remote(searchStatus: 500);
    final targets = [
      const AnimatedArtworkTarget.album(title: 'A', albumArtist: 'X'),
      const AnimatedArtworkTarget.album(title: 'B', albumArtist: 'X'),
      const AnimatedArtworkTarget.album(title: 'C', albumArtist: 'X'),
      const AnimatedArtworkTarget.album(title: 'D', albumArtist: 'X'),
    ];
    final result = await run(remote, targets);
    expect(result.stopped, AnimatedArtworkAutoStop.outage);
    expect(result.progress.failed, kAnimatedArtworkMaxNetworkFailures);
    expect(await store.readAll(), isEmpty,
        reason: 'an outage records nothing, so a later pass retries');
  });

  test('a manual choice in progress leaves that entity alone', () async {
    final remote = abbeyRoadRemote();
    final result = await run(
      remote,
      [abbey],
      isLocked: (target) => target.key == abbey.key,
    );
    expect(result.progress.saved, 0);
    expect(remote.requests, isEmpty);
  });

  test('progress is published in bounded batches, not only at the end', () async {
    final remote = _Remote();
    final targets = List.generate(
      6,
      (i) => AnimatedArtworkTarget.artist(artistName: 'Artist $i'),
    );
    var changed = 0;
    final reports = <AnimatedArtworkProgress>[];
    final client = remote.build();
    final result = await runAnimatedArtworkAutoPass(
      targets: targets,
      store: store,
      api: AppleArtworkClient(client: client, attempts: 1, pause: (_) async {}),
      downloadClient: client,
      policy: ArtistImageNetwork.wifi,
      readNetwork: () async => ArtistNetworkKind.wifi,
      stillEnabled: () => true,
      pause: Duration.zero,
      batchSize: 5,
      onChanged: () => changed++,
      onProgress: reports.add,
    );

    expect(result.progress.completed, 6);
    expect(result.progress.notFound, 6);
    // Five changes publish the first batch; the remaining one publishes at
    // the end of the pass.
    expect(changed, 2);
    expect(reports.last.completed, 6);
    expect(reports.map((p) => p.completed).toSet().length, greaterThan(2));
  });

  test('a duplicate entity in one pass is only looked up once', () async {
    final remote = abbeyRoadRemote();
    final result = await run(remote, [abbey, abbey]);
    expect(result.progress.saved, 1);
    expect(result.progress.skipped, 1);
    expect(remote.requests.where((u) => u.contains('search?')).length, 1);
  });
}
