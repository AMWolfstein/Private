import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/core/models/track.dart';
import 'package:sistrum/providers/library_collections_provider.dart';
import 'package:sistrum/services/library/collections/library_collections_database.dart';

part 'library_collections_mutation_1.dart';
part 'library_collections_mutation_2.dart';
part 'library_collections_mutation_3.dart';

class _CollectionsDatabase implements LibraryCollectionsDatabase {
  final loved = <String, Map<String, dynamic>>{};
  final artists = <String, Map<String, dynamic>>{};
  final playlists = <String, Map<String, dynamic>>{};
  final playlistTracks = <String, List<Map<String, dynamic>>>{};
  final playlistReadStarted = Completer<void>();
  final releasePlaylistRead = Completer<void>();
  int playlistReads = 0;
  LibraryPlaylistTracksSnapshot? stagedPlaylistRows;
  Future<LibraryCollectionsSnapshot>? pendingSnapshot;
  final snapshotReadStarted = Completer<void>();
  final events = <String>[];
  final writeStarted = Completer<void>();
  final releaseWrite = Completer<void>();
  bool failNextWrite = false;

  Future<void> _write(String event, void Function() persist) async {
    events.add(event);
    final fail = failNextWrite;
    failNextWrite = false;
    // Only the first write waits, so an unserialized later write can overtake it.
    if (!writeStarted.isCompleted) {
      writeStarted.complete();
      await releaseWrite.future;
    }
    if (fail) throw StateError('database write failed');
    persist();
  }

  @override
  Future<LibraryCollectionsSnapshot> loadSnapshot() async {
    if (!snapshotReadStarted.isCompleted) snapshotReadStarted.complete();
    return pendingSnapshot ??
        Future.value(
          LibraryCollectionsSnapshot(
            lovedRows: loved.values.toList(),
            playlistRows: playlists.values.toList(),
            playlistTrackRows: [
              for (final entry in playlistTracks.entries)
                for (final row in entry.value)
                  {'playlist_id': entry.key, 'track_key': row['track_key']},
            ],
            favoriteArtistRows: artists.values.toList(),
          ),
        );
  }

  Future<List<Map<String, dynamic>>> loadPlaylistTracks(
    String playlistId,
  ) async {
    playlistReads++;
    if (!playlistReadStarted.isCompleted) {
      playlistReadStarted.complete();
      await releasePlaylistRead.future;
    }
    return playlistTracks[playlistId] ?? const [];
  }

  @override
  Future<LibraryPlaylistTracksSnapshot> loadPlaylistTracksSnapshot(
    String playlistId,
  ) async {
    final rows = await loadPlaylistTracks(playlistId);
    return stagedPlaylistRows ?? LibraryPlaylistTracksSnapshot(rows: rows);
  }

  @override
  Future<void> renamePlaylist({
    required String playlistId,
    required String name,
    required String updatedAt,
  }) => _write('rename:$playlistId', () {
    playlists[playlistId] = {
      ...playlists[playlistId]!,
      'name': name,
      'updated_at': updatedAt,
    };
  });

  Future<void> _upsertTrack(
    Map<String, Map<String, dynamic>> rows,
    String collection,
    String key,
    String json,
    String date,
  ) => _write('insert:$collection:$key', () {
    rows[key] = {'track_key': key, 'track_json': json, 'added_at': date};
  });

  @override
  Future<void> upsertLovedEntry({
    required String trackKey,
    required String trackJson,
    required String addedAt,
  }) => _upsertTrack(loved, 'loved', trackKey, trackJson, addedAt);

  @override
  Future<void> deleteLovedEntry(String trackKey) =>
      _write('delete:loved:$trackKey', () => loved.remove(trackKey));

  @override
  Future<void> upsertFavoriteArtistEntry({
    required String artistKey,
    required String artistJson,
    required String addedAt,
  }) => _write('insert:artists:$artistKey', () {
    artists[artistKey] = {
      'artist_key': artistKey,
      'artist_json': artistJson,
      'added_at': addedAt,
    };
  });

  @override
  Future<void> deleteFavoriteArtistEntry(String artistKey) =>
      _write('delete:artists:$artistKey', () => artists.remove(artistKey));

  @override
  Future<void> upsertPlaylist({
    required String id,
    required String name,
    required String createdAt,
    required String updatedAt,
    String? coverImagePath,
  }) => _write('insert:playlist:$id', () {
    playlists[id] = {
      'id': id,
      'name': name,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'cover_image_path': coverImagePath,
    };
  });

  @override
  Future<void> deletePlaylists(List<String> ids) =>
      _write('bulk-playlists:remove', () {
        for (final id in ids) {
          playlists.remove(id);
          playlistTracks.remove(id);
        }
      });

  @override
  Future<void> upsertPlaylistTracksBatch({
    required String playlistId,
    required String playlistUpdatedAt,
    required List<Map<String, String>> tracks,
  }) => _write('batch:$playlistId', () {
    final rows = playlistTracks.putIfAbsent(playlistId, () => []);
    for (final track in tracks) {
      rows.removeWhere((row) => row['track_key'] == track['track_key']);
      rows.add({...track, 'playlist_id': playlistId});
    }
    playlists[playlistId]!['updated_at'] = playlistUpdatedAt;
  });

  @override
  Future<void> upsertLovedTracksBatch(List<Map<String, String>> tracks) =>
      _write('bulk-loved:add', () {
        for (final row in tracks) {
          loved[row['track_key']!] = Map<String, dynamic>.from(row);
        }
      });

  @override
  Future<void> deleteLovedTracks(List<String> keys) =>
      _write('bulk-loved:remove', () {
        for (final key in keys) {
          loved.remove(key);
        }
      });

  @override
  Future<void> deletePlaylistTracks({
    required String playlistId,
    required List<String> trackKeys,
    required String playlistUpdatedAt,
  }) => _write('bulk-playlist:remove', () {
    final keys = trackKeys.toSet();
    playlistTracks[playlistId]!.removeWhere(
      (row) => keys.contains(row['track_key']),
    );
    playlists[playlistId]!['updated_at'] = playlistUpdatedAt;
  });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Track _track(String id) => Track(
  id: id,
  name: 'Song',
  artistName: 'Artist',
  albumName: 'Album',
  duration: 180,
  source: 'example',
);

ProviderContainer _container(_CollectionsDatabase db) {
  final container = ProviderContainer(
    overrides: [
      libraryCollectionsProvider.overrideWith(
        () => LibraryCollectionsNotifier(database: db),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  _registerLibraryCollectionsMutation1();
  _registerLibraryCollectionsMutation2();
  _registerLibraryCollectionsMutation3();
}
