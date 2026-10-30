import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/core/models/library_collections.dart';
import 'package:sistrum/core/models/track.dart';
import 'package:sistrum/services/library/collections/library_collections_rows.dart';
import 'package:sistrum/services/library/collections/library_collections_worker.dart';

Map<String, dynamic> _trackRow(String key, String name) => {
  'track_key': key,
  'track_json': jsonEncode(
    Track(
      id: key,
      name: name,
      artistName: 'Artist',
      albumName: 'Album',
      duration: 180,
    ).toJson(),
  ),
  'added_at': '2026-01-01T00:00:00.000Z',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the snapshot worker builds loved songs from streamed rows', () async {
    final state = await hydrateRowsInWorker<LibraryCollectionsState>(
      rows: {
        CollectionRows.loved: [
          _trackRow('a', 'First'),
          _trackRow('b', 'Second'),
        ],
      },
    );
    expect(state.isLoaded, isTrue);
    expect(state.loved.map((entry) => entry.key), ['a', 'b']);
    expect(state.loved.first.track.name, 'First');
  });

  test('the snapshot worker streams batches larger than one page', () async {
    final many = [for (var i = 0; i < 300; i++) _trackRow('k$i', 'Song $i')];
    final state = await hydrateRowsInWorker<LibraryCollectionsState>(
      rows: {CollectionRows.loved: many},
    );
    expect(state.loved, hasLength(300));
    expect(state.loved.last.key, 'k299');
  });

  test('the playlist worker reports whether membership is unchanged', () async {
    final unchanged = await hydrateRowsInWorker<HydratedPlaylistTracks>(
      rows: {
        CollectionRows.playlistTracks: [_trackRow('x', 'Only')],
      },
      knownKeys: {'x'},
    );
    expect(unchanged.tracks.map((entry) => entry.key), ['x']);
    expect(unchanged.membershipUnchanged, isTrue);

    final changed = await hydrateRowsInWorker<HydratedPlaylistTracks>(
      rows: {
        CollectionRows.playlistTracks: [_trackRow('x', 'Only')],
      },
      knownKeys: {'y'},
    );
    expect(changed.membershipUnchanged, isFalse);
  });
}
