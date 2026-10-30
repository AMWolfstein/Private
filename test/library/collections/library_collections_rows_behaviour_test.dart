import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/core/models/library_collections.dart';
import 'package:sistrum/core/models/track.dart';
import 'package:sistrum/services/library/collections/library_collections_rows.dart';

String _trackJson(String id) => jsonEncode(
  Track(
    id: id,
    name: 'Name $id',
    artistName: 'Artist',
    albumName: 'Album',
    duration: 200,
  ).toJson(),
);

Map<String, dynamic> _trackRow(
  String key, {
  String? playlistId,
  String? addedAt,
}) => {
  'playlist_id': ?playlistId,
  'track_key': key,
  'track_json': _trackJson(key),
  'added_at': ?addedAt,
};

void main() {
  group('playlist rows with membership keys', () {
    test('membership rows index track keys per playlist and skip blanks', () {
      final acc = CollectionHydrationAccumulator()
        ..add(CollectionRows.membership, [
          {'playlist_id': 'p1', 'track_key': 'k1'},
          {'playlist_id': 'p1', 'track_key': 'k2'},
          {'playlist_id': '', 'track_key': 'k3'},
          {'playlist_id': 'p2', 'track_key': null},
        ]);

      expect(acc.trackKeysByPlaylist.keys, ['p1']);
      expect(acc.trackKeysByPlaylist['p1'], {'k1', 'k2'});
    });

    test('playlist rows decode name, cover, dates and membership', () {
      final acc = CollectionHydrationAccumulator()
        ..add(CollectionRows.membership, [
          {'playlist_id': 'p1', 'track_key': 'k1'},
        ])
        ..add(CollectionRows.playlists, [
          {
            'id': 'p1',
            'name': 'Mix',
            'cover_image_path': '/covers/mix.jpg',
            'created_at': '2024-01-02T00:00:00Z',
            'updated_at': '2024-02-03T00:00:00Z',
            'preview_track_json': jsonEncode({'coverUrl': 'https://img/c.png'}),
          },
          {'id': '', 'name': 'skipped'},
          {'id': 'bad-preview', 'preview_track_json': 'not json'},
          {'name': 'no id'},
        ]);

      final state = acc.finish();
      expect(state.isLoaded, isTrue);
      expect(state.playlists.map((p) => p.id), ['p1', 'bad-preview']);

      final mix = state.playlists.first;
      expect(mix.name, 'Mix');
      expect(mix.coverImagePath, '/covers/mix.jpg');
      expect(mix.previewCover, 'https://img/c.png');
      expect(mix.createdAt, DateTime.parse('2024-01-02T00:00:00Z'));
      expect(mix.updatedAt, DateTime.parse('2024-02-03T00:00:00Z'));
      expect(mix.tracksLoaded, isFalse);
      expect(mix.containsTrackKey('k1'), isTrue);
      expect(mix.containsTrackKey('k2'), isFalse);

      final bad = state.playlists.last;
      expect(bad.name, '');
      expect(bad.previewCover, isNull);
      expect(bad.updatedAt, bad.createdAt);
    });

    test('a complete playlist load attaches backup tracks', () {
      final acc = CollectionHydrationAccumulator()
        ..add(CollectionRows.playlists, [
          {'id': 'p1', 'name': 'Mix'},
          {'id': 'p2', 'name': 'Empty'},
        ])
        ..add(CollectionRows.backupTracks, [
          {..._trackRow('t1'), 'playlist_id': 'p1'},
          {'playlist_id': 'p1', 'track_key': '', 'track_json': 'x'},
        ]);

      final state = acc.finish(completePlaylists: true);
      final mix = state.playlists.firstWhere((p) => p.id == 'p1');
      final empty = state.playlists.firstWhere((p) => p.id == 'p2');

      expect(mix.tracksLoaded, isTrue);
      expect(mix.tracks.map((e) => e.key), ['t1']);
      expect(empty.tracksLoaded, isTrue);
      expect(empty.tracks, isEmpty);
    });
  });

  group('track and artist rows', () {
    test('loved and playlist track rows drop invalid entries', () {
      final acc = CollectionHydrationAccumulator()
        ..add(CollectionRows.loved, [
          _trackRow('L1', addedAt: '2024-05-01T00:00:00Z'),
          {'track_key': '', 'track_json': _trackJson('x')},
          {'track_key': 'L2', 'track_json': 'not json'},
          {'track_key': 'L3', 'track_json': '[1, 2]'},
          {'track_key': 'L4'},
        ])
        ..add(CollectionRows.playlistTracks, [_trackRow('P1')]);

      final state = acc.finish();
      expect(state.loved.map((e) => e.key), ['L1']);
      expect(
        state.loved.single.addedAt,
        DateTime.parse('2024-05-01T00:00:00Z'),
      );
      expect(acc.playlistTracks.map((e) => e.key), ['P1']);
    });

    test('artist rows decode entries and drop malformed ones', () {
      final entry = CollectionArtistEntry(
        key: 'a1',
        artistId: 'ar1',
        providerId: null,
        name: 'Artist One',
        addedAt: DateTime.utc(2024, 1, 1),
      );
      final acc = CollectionHydrationAccumulator()
        ..add(CollectionRows.artists, [
          {'artist_key': 'a1', 'artist_json': jsonEncode(entry.toJson())},
          {'artist_key': '', 'artist_json': jsonEncode(entry.toJson())},
          {'artist_key': 'a2', 'artist_json': 'not json'},
        ]);

      final artists = acc.finish().favoriteArtists;
      expect(artists.map((a) => a.key), ['a1']);
      expect(artists.single.name, 'Artist One');
      expect(artists.single.addedAt, DateTime.utc(2024, 1, 1));
    });
  });

  group('decodePlaylistTracks', () {
    test('reports unchanged membership only when the key sets match', () {
      final rows = [_trackRow('k1'), _trackRow('k2')];

      final same = decodePlaylistTracks((rows: rows, knownKeys: {'k1', 'k2'}));
      expect(same.tracks.map((e) => e.key), ['k1', 'k2']);
      expect(same.trackKeys, {'k1', 'k2'});
      expect(same.membershipUnchanged, isTrue);

      final grown = decodePlaylistTracks((rows: rows, knownKeys: {'k1'}));
      expect(grown.membershipUnchanged, isFalse);

      final swapped = decodePlaylistTracks((
        rows: rows,
        knownKeys: {'k1', 'k3'},
      ));
      expect(swapped.membershipUnchanged, isFalse);
    });
  });

  group('hasLargeJson', () {
    test('is false below 64 KiB of JSON text and true at the threshold', () {
      expect(
        hasLargeJson([
          {'track_json': 'x' * 1000},
        ]),
        isFalse,
      );
      expect(
        hasLargeJson([
          {'track_json': 'x' * (64 * 1024 - 1)},
        ]),
        isFalse,
      );
      expect(
        hasLargeJson([
          {'track_json': 'x' * (64 * 1024)},
        ]),
        isTrue,
      );
    });

    test('adds up JSON columns across rows and ignores non-string values', () {
      final rows = [
        {'track_json': 'x' * 40000, 'artist_json': null},
        {'preview_track_json': 'y' * 30000, 'track_json': 42},
      ];
      expect(hasLargeJson(rows), isTrue);
      expect(hasLargeJson([rows.first]), isFalse);
    });
  });
}
