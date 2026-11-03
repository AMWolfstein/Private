import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sistrum/services/artist_images/artist_image_auto_pass.dart';
import 'package:sistrum/services/artist_images/artist_image_network.dart';
import 'package:sistrum/services/artist_images/artist_image_store.dart';
import 'package:sistrum/services/artist_images/deezer_artist_search.dart';

const _portrait =
    'https://cdns-images.dzcdn.net/images/artist/abc/1000x1000.jpg';
final _bytes = Uint8List.fromList([1, 2, 3, 4]);

DeezerArtist _artist({int id = 42, String name = 'Sample Artist'}) =>
    DeezerArtist(id: id, name: name, pictureUrl: _portrait, fans: 1, albums: 1);

ArtistImageStore _store(Directory dir, {ArtistImageState? state}) =>
    ArtistImageStore(
      state: state ?? MemoryArtistImageState(),
      directory: () async => dir,
    );

/// A Deezer search that returns [artists] for every query, and an image
/// response for the portrait address.
MockClient _client({
  List<Map<String, Object?>> artists = const [],
  int searchStatus = 200,
  String imageType = 'image/jpeg',
  List<String>? searchedNames,
}) => MockClient((request) async {
  if (request.url.host == 'api.deezer.com') {
    searchedNames?.add(request.url.queryParameters['q'] ?? '');
    if (searchStatus != 200) return http.Response('busy', searchStatus);
    return http.Response(jsonEncode({'data': artists}), 200);
  }
  return http.Response.bytes(_bytes, 200, headers: {'content-type': imageType});
});

Map<String, Object?> _entry(String name, {int id = 42}) => {
  'id': id,
  'name': name,
  'picture_xl': _portrait,
  'nb_fan': 1,
  'nb_album': 1,
};

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('artist_images_test'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test(
    'a saved photo is a file in the folder and is recorded as auto',
    () async {
      final store = _store(dir);
      await store.savePhoto(
        key: artistImageKey('Sample Artist'),
        artist: _artist(),
        bytes: _bytes,
        status: ArtistImageStatus.auto,
      );

      final records = await store.readAll();
      final record = records[artistImageKey('Sample Artist')]!;
      expect(record.status, ArtistImageStatus.auto);
      final file = await store.fileFor(record);
      expect(file, isNotNull);
      expect(file!.readAsBytesSync(), _bytes);
      expect(await store.sizeBytes(), _bytes.length);
    },
  );

  test('a replaced photo removes the old file', () async {
    final store = _store(dir);
    final key = artistImageKey('Sample Artist');
    await store.savePhoto(
      key: key,
      artist: _artist(id: 1),
      bytes: _bytes,
      status: ArtistImageStatus.auto,
    );
    await store.savePhoto(
      key: key,
      artist: _artist(id: 2),
      bytes: _bytes,
      status: ArtistImageStatus.manual,
    );

    final files = dir
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .toList();
    expect(files, [(await store.readAll())[key]!.fileName]);
  });

  test(
    'resetting removes the photo but keeps the artist from being searched again',
    () async {
      final store = _store(dir);
      final key = artistImageKey('Sample Artist');
      await store.savePhoto(
        key: key,
        artist: _artist(),
        bytes: _bytes,
        status: ArtistImageStatus.manual,
      );

      await store.recordWithoutPhoto(key, ArtistImageStatus.reset);

      final record = (await store.readAll())[key]!;
      expect(record.status, ArtistImageStatus.reset);
      expect(record.hasPhoto, isFalse);
      expect(await store.fileFor(record), isNull);
      expect(dir.listSync().whereType<File>(), isEmpty);
    },
  );

  test('clear removes every photo and every record', () async {
    final store = _store(dir);
    await store.savePhoto(
      key: 'a',
      artist: _artist(),
      bytes: _bytes,
      status: ArtistImageStatus.auto,
    );
    await store.recordWithoutPhoto('b', ArtistImageStatus.notFound);

    await store.clearAll();

    expect(await store.readAll(), isEmpty);
    expect(await store.sizeBytes(), 0);
  });

  test('artist names share one key regardless of case and punctuation', () {
    expect(artistImageKey('AC/DC'), artistImageKey('ac dc'));
    expect(
      artistImageKey('  Sample   Artist '),
      artistImageKey('sample artist'),
    );
  });

  test('the background pass saves exact matches and records misses', () async {
    final store = _store(dir);
    final searched = <String>[];
    final result = await runArtistImageAutoPass(
      names: ['Sample Artist', 'Various Artists', 'Sample Artist', 'Nobody'],
      store: store,
      client: _client(
        artists: [_entry('Sample Artist')],
        searchedNames: searched,
      ),
      policy: ArtistImageNetwork.wifi,
      readNetwork: () async => ArtistNetworkKind.wifi,
      stillEnabled: () => true,
      pause: Duration.zero,
    );

    expect(result.saved, 1);
    expect(result.notFound, 1);
    expect(result.stopped, isNull);
    expect(searched, [
      'Sample Artist',
      'Nobody',
    ], reason: 'duplicates and Various Artists are skipped');
    final records = await store.readAll();
    expect(
      records[artistImageKey('Sample Artist')]!.status,
      ArtistImageStatus.auto,
    );
    expect(
      records[artistImageKey('Nobody')]!.status,
      ArtistImageStatus.notFound,
    );
  });

  test('a near match is not used automatically', () async {
    final store = _store(dir);
    await runArtistImageAutoPass(
      names: ['Sample'],
      store: store,
      client: _client(artists: [_entry('Sample Artist')]),
      policy: ArtistImageNetwork.wifi,
      readNetwork: () async => ArtistNetworkKind.wifi,
      stillEnabled: () => true,
      pause: Duration.zero,
    );
    expect(
      (await store.readAll())[artistImageKey('Sample')]!.status,
      ArtistImageStatus.notFound,
    );
  });

  test(
    'a network the setting does not allow stops the pass before any request',
    () async {
      final store = _store(dir);
      final searched = <String>[];
      final result = await runArtistImageAutoPass(
        names: ['Sample Artist'],
        store: store,
        client: _client(
          artists: [_entry('Sample Artist')],
          searchedNames: searched,
        ),
        policy: ArtistImageNetwork.wifi,
        readNetwork: () async => ArtistNetworkKind.cellular,
        stillEnabled: () => true,
        pause: Duration.zero,
      );
      expect(result.stopped, ArtistImageAutoStop.networkNotAllowed);
      expect(searched, isEmpty);
      expect(await store.readAll(), isEmpty);
    },
  );

  test(
    'a Deezer outage stops the pass and records nothing for that artist',
    () async {
      final store = _store(dir);
      final result = await runArtistImageAutoPass(
        names: ['Sample Artist', 'Other'],
        store: store,
        client: _client(searchStatus: 503),
        policy: ArtistImageNetwork.both,
        readNetwork: () async => ArtistNetworkKind.wifi,
        stillEnabled: () => true,
        pause: Duration.zero,
      );
      expect(result.stopped, ArtistImageAutoStop.outage);
      expect(await store.readAll(), isEmpty);
    },
  );

  test('a response that is not an image is an outage, not a photo', () async {
    final store = _store(dir);
    final result = await runArtistImageAutoPass(
      names: ['Sample Artist'],
      store: store,
      client: _client(
        artists: [_entry('Sample Artist')],
        imageType: 'text/html',
      ),
      policy: ArtistImageNetwork.wifi,
      readNetwork: () async => ArtistNetworkKind.wifi,
      stillEnabled: () => true,
      pause: Duration.zero,
    );
    expect(result.stopped, ArtistImageAutoStop.outage);
    expect(await store.readAll(), isEmpty);
  });

  test('an artist already recorded is not searched again', () async {
    final state = MemoryArtistImageState();
    await state.put(
      const ArtistImageRecord(
        artistKey: 'sample artist',
        status: ArtistImageStatus.reset,
      ),
    );
    final searched = <String>[];
    await runArtistImageAutoPass(
      names: ['Sample Artist'],
      store: _store(dir, state: state),
      client: _client(
        artists: [_entry('Sample Artist')],
        searchedNames: searched,
      ),
      policy: ArtistImageNetwork.wifi,
      readNetwork: () async => ArtistNetworkKind.wifi,
      stillEnabled: () => true,
      pause: Duration.zero,
    );
    expect(searched, isEmpty);
  });

  test('turning the feature off stops the pass', () async {
    final result = await runArtistImageAutoPass(
      names: ['Sample Artist'],
      store: _store(dir),
      client: _client(artists: [_entry('Sample Artist')]),
      policy: ArtistImageNetwork.wifi,
      readNetwork: () async => ArtistNetworkKind.wifi,
      stillEnabled: () => false,
      pause: Duration.zero,
    );
    expect(result.stopped, ArtistImageAutoStop.disabled);
  });
}
