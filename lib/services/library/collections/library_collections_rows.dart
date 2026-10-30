import 'dart:convert';

import 'package:sistrum/models/library_collections.dart';
import 'package:sistrum/models/track.dart';

const _workerJsonThreshold = 64 * 1024;

List<UserPlaylistCollection> _decodePlaylistRows(
  List<Map<String, dynamic>> rows,
  Map<String, Set<String>> trackKeysByPlaylist,
) {
  final playlists = <UserPlaylistCollection>[];
  for (final row in rows) {
    final id = row['id'] as String?;
    if (id == null || id.isEmpty) continue;
    final createdAtRaw = row['created_at'] as String?;
    final updatedAtRaw = row['updated_at'] as String?;
    final createdAt = DateTime.tryParse(createdAtRaw ?? '') ?? DateTime.now();
    final updatedAt = DateTime.tryParse(updatedAtRaw ?? '') ?? createdAt;
    String? previewCover;
    final previewTrackJson = row['preview_track_json'] as String?;
    if (previewTrackJson != null && previewTrackJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(previewTrackJson);
        if (decoded is Map) previewCover = decoded['coverUrl']?.toString();
      } catch (_) {}
    }
    playlists.add(
      UserPlaylistCollection(
        id: id,
        name: row['name'] as String? ?? '',
        coverImagePath: row['cover_image_path'] as String?,
        createdAt: createdAt,
        updatedAt: updatedAt,
        tracks: const [],
        previewCover: previewCover,
        tracksLoaded: false,
        trackKeys: trackKeysByPlaylist[id],
      ),
    );
  }

  return playlists;
}

class HydratedPlaylistTracks {
  const HydratedPlaylistTracks({
    required this.tracks,
    required this.trackKeys,
    required this.membershipUnchanged,
  });

  final List<CollectionTrackEntry> tracks;
  final Set<String> trackKeys;
  final bool membershipUnchanged;
}

typedef PlaylistHydrationRequest = ({
  List<Map<String, dynamic>> rows,
  Set<String> knownKeys,
});

HydratedPlaylistTracks decodePlaylistTracks(PlaylistHydrationRequest request) {
  final tracks = _decodeTrackRows(request.rows).toList(growable: false);
  final keys = tracks.map((entry) => entry.key).toSet();
  return HydratedPlaylistTracks(
    tracks: tracks,
    trackKeys: keys,
    membershipUnchanged:
        keys.length == request.knownKeys.length &&
        keys.every(request.knownKeys.contains),
  );
}

List<CollectionTrackEntry> _decodeTrackRows(List<Map<String, dynamic>> rows) =>
    [for (final row in rows) ?_parseTrackRow(row)];

CollectionTrackEntry? _parseTrackRow(Map<String, dynamic> row) {
  final key = row['track_key'] as String?;
  final trackJson = row['track_json'] as String?;
  if (key == null || key.isEmpty || trackJson == null || trackJson.isEmpty) {
    return null;
  }
  try {
    final decoded = jsonDecode(trackJson);
    if (decoded is! Map) return null;
    return CollectionTrackEntry(
      key: key,
      track: Track.fromJson(Map<String, dynamic>.from(decoded)),
      addedAt:
          DateTime.tryParse(row['added_at'] as String? ?? '') ?? DateTime.now(),
    );
  } catch (_) {
    return null;
  }
}

CollectionArtistEntry? _parseArtistRow(Map<String, dynamic> row) {
  final key = row['artist_key'] as String?;
  final artistJson = row['artist_json'] as String?;
  if (key == null || key.isEmpty || artistJson == null || artistJson.isEmpty) {
    return null;
  }
  try {
    final decoded = jsonDecode(artistJson);
    if (decoded is! Map) return null;
    final map = Map<String, dynamic>.from(decoded);
    return CollectionArtistEntry.fromJson({
      ...map,
      'key': key,
      'addedAt': map['addedAt'] ?? row['added_at'],
    });
  } catch (_) {
    return null;
  }
}

bool hasLargeJson(List<Map<String, dynamic>> rows) {
  var length = 0;
  for (final row in rows) {
    for (final column in ['track_json', 'artist_json', 'preview_track_json']) {
      final value = row[column];
      if (value is String) length += value.length;
    }
    if (length >= _workerJsonThreshold) return true;
  }
  return false;
}

enum CollectionRows {
  playlistTracks,
  loved,
  artists,
  membership,
  playlists,
  backupTracks,
}

class CollectionHydrationAccumulator {
  final playlistTracks = <CollectionTrackEntry>[];
  final backupTracks = <String, List<CollectionTrackEntry>>{};
  final loved = <CollectionTrackEntry>[];
  final artists = <CollectionArtistEntry>[];
  final playlistRows = <Map<String, dynamic>>[];
  final trackKeysByPlaylist = <String, Set<String>>{};

  void add(CollectionRows kind, List<Map<String, dynamic>> rows) {
    switch (kind) {
      case CollectionRows.backupTracks:
        for (final row in rows) {
          final id = row['playlist_id'] as String?;
          final track = _parseTrackRow(row);
          if (id != null && track != null) {
            backupTracks.putIfAbsent(id, () => []).add(track);
          }
        }
      case CollectionRows.playlistTracks:
        playlistTracks.addAll(_decodeTrackRows(rows));
      case CollectionRows.loved:
        loved.addAll(_decodeTrackRows(rows));
      case CollectionRows.artists:
        for (final row in rows) {
          final artist = _parseArtistRow(row);
          if (artist != null) artists.add(artist);
        }
      case CollectionRows.playlists:
        playlistRows.addAll(rows);
      case CollectionRows.membership:
        for (final row in rows) {
          final id = row['playlist_id'] as String?;
          final key = row['track_key'] as String?;
          if (id == null || id.isEmpty || key == null || key.isEmpty) continue;
          trackKeysByPlaylist.putIfAbsent(id, () => {}).add(key);
        }
    }
  }

  LibraryCollectionsState finish({bool completePlaylists = false}) =>
      LibraryCollectionsState(
        loved: loved,
        favoriteArtists: artists,
        playlists: [
          for (final playlist in _decodePlaylistRows(
            playlistRows,
            trackKeysByPlaylist,
          ))
            completePlaylists
                ? playlist.copyWith(
                    tracks: backupTracks[playlist.id] ?? const [],
                    tracksLoaded: true,
                  )
                : playlist,
        ],
        isLoaded: true,
      );
}
