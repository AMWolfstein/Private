import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sistrum/services/animated_artwork/apple_artwork_client.dart';
import 'package:sistrum/services/artist_images/artist_image_auto_pass.dart';
import 'package:sistrum/services/artist_images/artist_image_network.dart';
import 'package:sistrum/services/artist_images/artist_image_store.dart';

final _bytes = Uint8List.fromList([1, 2, 3]);

http.Response _image() =>
    http.Response.bytes(_bytes, 200, headers: {'content-type': 'image/jpeg'});

http.Response _deezer(List<Map<String, Object?>> data) =>
    http.Response(jsonEncode({'data': data}), 200);

/// An Apple client whose catalog answers with [artists] (or fails when null).
AppleArtworkClient _apple({
  List<Map<String, Object?>>? artists,
  required List<String> imageRequests,
}) => AppleArtworkClient(
  attempts: 1,
  pause: (_) async {},
  client: MockClient((request) async {
    final url = request.url.toString();
    if (artists == null) return http.Response('down', 503);
    if (url == 'https://music.apple.com/us/browse') {
      return http.Response('devToken=a.b.c', 200);
    }
    if (url.startsWith('https://amp-api.music.apple.com/')) {
      return http.Response(
        jsonEncode({
          'results': {'artists': {'data': artists}},
        }),
        200,
      );
    }
    imageRequests.add(url);
    return _image();
  }),
);

void main() {
  late Directory directory;
  late MemoryArtistImageState state;
  late ArtistImageStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('photo-sources-');
    state = MemoryArtistImageState();
    store = ArtistImageStore(state: state, directory: () async => directory);
  });
  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  Future<ArtistImageAutoResult> run({
    required http.Client deezer,
    AppleArtworkClient? apple,
  }) => runArtistImageAutoPass(
    names: const ['Akon'],
    store: store,
    client: deezer,
    apple: apple,
    policy: ArtistImageNetwork.wifi,
    readNetwork: () async => ArtistNetworkKind.wifi,
    stillEnabled: () => true,
    pause: Duration.zero,
  );

  final appleAkon = {
    'id': '77',
    'attributes': {
      'name': 'Akon',
      'artwork': {'url': 'https://is1.test/{w}x{h}bb.jpg'},
    },
  };

  test('Apple is tried first and its 1000 px photo is saved', () async {
    final images = <String>[];
    var deezerCalls = 0;
    final deezer = MockClient((request) async {
      if (request.url.host == 'api.deezer.com') {
        deezerCalls++;
        return _deezer([]);
      }
      // The photo itself is downloaded through the pass's client.
      images.add(request.url.toString());
      return _image();
    });
    addTearDown(deezer.close);

    final result = await run(
      deezer: deezer,
      apple: _apple(artists: [appleAkon], imageRequests: []),
    );

    expect(result.saved, 1);
    expect(deezerCalls, 0);
    expect(images, ['https://is1.test/1000x1000bb.jpg']);
    final record = (await store.readAll())['akon']!;
    expect(record.deezerId, isNull);
    expect(record.fileName, isNotNull);
  });

  test('Apple being down falls back to Deezer', () async {
    final deezer = MockClient(
      (request) async =>
          request.url.host == 'api.deezer.com'
              ? _deezer([
                  {
                    'id': 9,
                    'name': 'Akon',
                    'picture_xl': 'https://image.test/deezer.jpg',
                  },
                ])
              : _image(),
    );
    addTearDown(deezer.close);

    final result = await run(
      deezer: deezer,
      apple: _apple(imageRequests: []),
    );

    expect(result.saved, 1);
    expect((await store.readAll())['akon']!.deezerId, 9);
  });

  test('Apple with no portrait falls back to Deezer', () async {
    final deezer = MockClient(
      (request) async =>
          request.url.host == 'api.deezer.com'
              ? _deezer([
                  {
                    'id': 9,
                    'name': 'Akon',
                    'picture_xl': 'https://image.test/deezer.jpg',
                  },
                ])
              : _image(),
    );
    addTearDown(deezer.close);

    final result = await run(
      deezer: deezer,
      apple: _apple(
        artists: [
          {'id': '77', 'attributes': {'name': 'Akon'}},
        ],
        imageRequests: [],
      ),
    );

    expect(result.saved, 1);
    expect((await store.readAll())['akon']!.deezerId, 9);
  });

  test('Apple down and Deezer down stops the pass without recording', () async {
    final deezer = MockClient((request) async => http.Response('x', 500));
    addTearDown(deezer.close);

    final result = await run(
      deezer: deezer,
      apple: _apple(imageRequests: []),
    );

    expect(result.stopped, ArtistImageAutoStop.outage);
    expect(await store.readAll(), isEmpty);
  });

  test('Apple down and Deezer without a match is not recorded', () async {
    final deezer = MockClient((request) async => _deezer([]));
    addTearDown(deezer.close);

    final result = await run(
      deezer: deezer,
      apple: _apple(imageRequests: []),
    );

    expect(result.notFound, 0);
    expect(result.stopped, isNull);
    expect(await store.readAll(), isEmpty);
  });
}
