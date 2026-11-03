import 'dart:async';
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
import 'package:sistrum/services/library/browse/library_tag_credits.dart';

const artist = DeezerArtist(
  id: 1,
  name: 'Artist',
  pictureUrl: 'https://image.test/one.jpg',
  fans: 0,
  albums: 1,
);
const manual = DeezerArtist(
  id: 2,
  name: 'Artist',
  pictureUrl: 'https://image.test/two.jpg',
  fans: 0,
  albums: 1,
);
final bytes = Uint8List.fromList([1, 2, 3]);
http.Response searchResult() => http.Response(
  jsonEncode({
    'data': [
      {'id': 1, 'name': 'Artist', 'picture_xl': artist.pictureUrl},
    ],
  }),
  200,
);

class FailingState extends MemoryArtistImageState {
  bool fail = false;
  @override
  Future<void> put(ArtistImageRecord record) async {
    if (fail) throw StateError('database write failed');
    await super.put(record);
  }
}

void main() {
  late Directory directory;
  late MemoryArtistImageState state;
  late ArtistImageStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('deezer-review-');
    state = MemoryArtistImageState();
    store = ArtistImageStore(state: state, directory: () async => directory);
  });
  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });
  Future<ArtistImageAutoResult> run(
    http.Client client,
    bool Function() enabled,
  ) => runArtistImageAutoPass(
    names: ['Artist'],
    store: store,
    client: client,
    policy: ArtistImageNetwork.wifi,
    readNetwork: () async => ArtistNetworkKind.wifi,
    stillEnabled: enabled,
    pause: Duration.zero,
  );

  test('disabling during a search prevents publishing its photo', () async {
    final entered = Completer<void>(), release = Completer<void>();
    var enabled = true;
    final client = MockClient((request) async {
      if (request.url.host == 'api.deezer.com') {
        entered.complete();
        await release.future;
        return searchResult();
      }
      return http.Response.bytes(
        bytes,
        200,
        headers: {'content-type': 'image/jpeg'},
      );
    });
    addTearDown(client.close);
    final pending = run(client, () => enabled);
    await entered.future;
    enabled = false;
    release.complete();
    final result = await pending;
    expect(result.saved, 0);
    expect(await store.readAll(), isEmpty);
    expect(result.stopped, ArtistImageAutoStop.disabled);
  });
  test(
    'manual selection made while searching wins over the automatic response',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      final client = MockClient((request) async {
        if (request.url.host == 'api.deezer.com') {
          entered.complete();
          await release.future;
          return searchResult();
        }
        return http.Response.bytes(
          bytes,
          200,
          headers: {'content-type': 'image/jpeg'},
        );
      });
      addTearDown(client.close);
      final pending = run(client, () => true);
      await entered.future;
      await store.savePhoto(
        key: 'artist',
        deezerId: manual.id,
        bytes: bytes,
        status: ArtistImageStatus.manual,
      );
      release.complete();
      await pending;
      expect(
        (await store.readAll())['artist']!.status,
        ArtistImageStatus.manual,
      );
      expect((await store.readAll())['artist']!.deezerId, 2);
    },
  );
  test(
    'resetting one alias preserves another alias photo for the same Deezer ID',
    () async {
      await store.savePhoto(
        key: 'arabic name',
        deezerId: artist.id,
        bytes: bytes,
        status: ArtistImageStatus.manual,
      );
      await store.savePhoto(
        key: 'latin name',
        deezerId: artist.id,
        bytes: bytes,
        status: ArtistImageStatus.manual,
      );
      await store.recordWithoutPhoto('arabic name', ArtistImageStatus.reset);
      final other = (await store.readAll())['latin name']!;
      expect(other.hasPhoto, isTrue);
      expect(await store.fileFor(other), isNotNull);
    },
  );
  test('failed database replacement preserves the previous photo', () async {
    final failing = FailingState();
    store = ArtistImageStore(state: failing, directory: () async => directory);
    await store.savePhoto(
      key: 'artist',
      deezerId: artist.id,
      bytes: bytes,
      status: ArtistImageStatus.manual,
    );
    failing.fail = true;
    await expectLater(
      store.savePhoto(
        key: 'artist',
        deezerId: manual.id,
        bytes: bytes,
        status: ArtistImageStatus.manual,
      ),
      throwsStateError,
    );
    final previous = (await store.readAll())['artist']!;
    expect(previous.deezerId, 1);
    expect(await store.fileFor(previous), isNotNull);
  });
  test('invalid API body stops with outage and is retried later', () async {
    final client = MockClient((_) async => http.Response('{}', 200));
    addTearDown(client.close);
    final result = await run(client, () => true);
    expect(result.notFound, 0);
    expect(result.stopped, ArtistImageAutoStop.outage);
    expect(await store.readAll(), isEmpty);
  });
  test(
    'reset during a search keeps album fallback and suppresses automatic replacement',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      final client = MockClient((request) async {
        if (request.url.host == 'api.deezer.com') {
          entered.complete();
          await release.future;
          return searchResult();
        }
        return http.Response.bytes(
          bytes,
          200,
          headers: {'content-type': 'image/jpeg'},
        );
      });
      addTearDown(client.close);
      final pending = run(client, () => true);
      await entered.future;
      await store.recordWithoutPhoto('artist', ArtistImageStatus.reset);
      release.complete();
      await pending;
      expect(
        (await store.readAll())['artist']!.status,
        ArtistImageStatus.reset,
      );
    },
  );
  test(
    'Clear invalidates an in-flight search before it can repopulate the cache',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      final client = MockClient((_) async {
        entered.complete();
        await release.future;
        return searchResult();
      });
      addTearDown(client.close);
      final pending = run(client, () => true);
      await entered.future;
      await store.clearAll();
      release.complete();
      await pending;
      expect(await store.readAll(), isEmpty);
    },
  );
  test(
    'legacy shared files remain until their final reference is reset',
    () async {
      final photo = await File(
        '${directory.path}/legacy.jpg',
      ).writeAsBytes(bytes);
      await state.put(
        const ArtistImageRecord(
          artistKey: 'a',
          status: ArtistImageStatus.manual,
          fileName: 'legacy.jpg',
        ),
      );
      await state.put(
        const ArtistImageRecord(
          artistKey: 'b',
          status: ArtistImageStatus.manual,
          fileName: 'legacy.jpg',
        ),
      );
      await store.recordWithoutPhoto('a', ArtistImageStatus.reset);
      expect(await photo.exists(), isTrue);
      await store.recordWithoutPhoto('b', ArtistImageStatus.reset);
      expect(await photo.exists(), isFalse);
    },
  );
  test(
    'network policy is rechecked between search and image download',
    () async {
      var network = ArtistNetworkKind.wifi;
      var imageRequests = 0;
      final client = MockClient((request) async {
        if (request.url.host == 'api.deezer.com') {
          network = ArtistNetworkKind.cellular;
          return searchResult();
        }
        imageRequests++;
        return http.Response.bytes(
          bytes,
          200,
          headers: {'content-type': 'image/jpeg'},
        );
      });
      addTearDown(client.close);
      final result = await runArtistImageAutoPass(
        names: ['Artist'],
        store: store,
        client: client,
        policy: ArtistImageNetwork.wifi,
        readNetwork: () async => network,
        stillEnabled: () => true,
        pause: Duration.zero,
      );
      expect(result.stopped, ArtistImageAutoStop.networkNotAllowed);
      expect(imageRequests, 0);
      expect(await store.readAll(), isEmpty);
    },
  );
  test('batch publication occurs before the pass finishes', () async {
    final entered = Completer<void>(), release = Completer<void>();
    var notifications = 0;
    final client = MockClient((request) async {
      if (request.url.queryParameters['q'] == 'Later') {
        entered.complete();
        await release.future;
        return http.Response('{"data":[]}', 200);
      }
      if (request.url.host == 'api.deezer.com') return searchResult();
      return http.Response.bytes(
        bytes,
        200,
        headers: {'content-type': 'image/jpeg'},
      );
    });
    addTearDown(client.close);
    final pending = runArtistImageAutoPass(
      names: ['Artist', 'Later'],
      store: store,
      client: client,
      policy: ArtistImageNetwork.wifi,
      readNetwork: () async => ArtistNetworkKind.wifi,
      stillEnabled: () => true,
      pause: Duration.zero,
      batchSize: 1,
      onChanged: () => notifications++,
    );
    await entered.future;
    expect(notifications, 1);
    expect((await store.readAll())['artist']!.hasPhoto, isTrue);
    release.complete();
    await pending;
    expect(notifications, 2);
  });
  test(
    'collaboration extraction uses separators and protects Keep together names',
    () {
      final names = splitTagCredits(
        'AC/DC; Artist A; Artist B',
        TagCreditField.artist,
        const TagCreditRules(
          artistDelimiters: [';', '/'],
          keepTogether: ['AC/DC'],
        ),
      );
      expect(names, ['AC/DC', 'Artist A', 'Artist B']);
    },
  );
}
