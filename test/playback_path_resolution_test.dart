import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/providers/playback_provider.dart';
import 'package:spotiflac_android/services/library_database.dart';

class _Library extends Fake implements LibraryDatabase {
  _Library(this.pathForIndex);

  final String Function(int index) pathForIndex;

  @override
  Future<List<Map<String, dynamic>?>> findExistingBatch(
    List<LocalLibraryBatchLookupRequest> requests,
  ) async => [
    for (var index = 0; index < requests.length; index++)
      {'filePath': pathForIndex(index)},
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.zarz.spotiflac/backend');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  List<Track> tracks(int count) => [
    for (var index = 0; index < count; index++)
      Track(
        id: '$index',
        name: 'Track $index',
        artistName: 'Artist',
        albumName: 'Album',
        duration: 180,
      ),
  ];

  test('large SAF queues use bounded batches and deduplicate paths', () async {
    final paths = [
      for (var index = 0; index < 131; index++)
        'content://music/${index % 130}',
    ];
    final batches = <List<String>>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'safExistsBatch');
      final uris = List<String>.from(
        jsonDecode((call.arguments as Map)['uris_json'] as String) as List,
      );
      batches.add(uris);
      return jsonEncode({for (final uri in uris) uri: 'found'});
    });
    final container = ProviderContainer(
      overrides: [
        playbackProvider.overrideWith(
          () => PlaybackController(library: _Library((index) => paths[index])),
        ),
      ],
    );
    addTearDown(container.dispose);

    final resolved = await container
        .read(playbackProvider.notifier)
        .resolveTrackFilePaths(tracks(131));

    expect(resolved, paths);
    expect(batches.map((batch) => batch.length), [64, 64, 2]);
  });
}
