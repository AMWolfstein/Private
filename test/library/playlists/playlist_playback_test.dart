import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/core/models/local_library_item.dart';
import 'package:sistrum/core/models/settings.dart';
import 'package:sistrum/core/models/track.dart';
import 'package:sistrum/providers/library/library_collections_provider.dart';
import 'package:sistrum/providers/library/local_library_provider.dart';
import 'package:sistrum/providers/library/local_library_cover_providers.dart';
import 'package:sistrum/providers/playback/music_player_provider.dart';
import 'package:sistrum/providers/playback/playback_provider.dart';
import 'package:sistrum/providers/settings/settings_provider.dart';
import 'package:sistrum/screens/library/collections/library_collection_tracks_screen.dart';
import 'package:sistrum/services/playback/music_player/music_player_service.dart';
import '../../support/material_test_theme.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/widgets/library/track_card.dart';
import 'package:sistrum/widgets/header/album_play_actions.dart';

part 'playlist_playback_1.dart';
part 'playlist_playback_2.dart';

final _tracks = [
  for (final name in ['First', 'Unavailable', 'Selected', 'Last'])
    Track(
      id: name,
      name: name,
      artistName: 'Artist',
      albumName: 'Album',
      duration: 180,
    ),
];

class _Settings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings(localLibraryShowDuplicates: true);
}

class _Handler extends Fake implements MusicPlayerHandler {}

class _Player extends MusicPlayerController {
  bool available = true;
  bool? shuffle;

  @override
  Future<void> setShuffle(bool enabled) async => shuffle = enabled;
  List<PlayableMedia> queue = [];
  int? index;

  @override
  Future<MusicPlayerHandler?> ensureInitialized() async =>
      available ? _Handler() : null;

  @override
  Future<void> playAll(
    List<PlayableMedia> items, {
    int initialIndex = 0,
  }) async {
    queue = items;
    index = initialIndex;
  }
}

class _Playback extends PlaybackController {
  final List<List<String>> resolvedRequests = [];
  final Map<String, String?> paths = {
    'First': 'content://library/first',
    'Selected': 'content://library/selected',
    'Last': 'content://library/last',
  };

  @override
  Future<List<LocalLibraryItem?>> resolveLocalTracks(List<Track> tracks) async {
    resolvedRequests.add(tracks.map((track) => track.id).toList());
    return [for (final track in tracks) _item(track)];
  }

  LocalLibraryItem? _item(Track track) {
    final path = paths[track.id];
    if (path == null) return null;
    return LocalLibraryItem(
      id: track.id,
      trackName: track.name,
      artistName: track.artistName,
      albumName: track.albumName,
      filePath: path,
      scannedAt: DateTime(2026),
      bitDepth: 24,
      sampleRate: 96000,
      bitrate: 1411,
      format: 'flac',
      genre: 'Jazz',
    );
  }
}

class _Collections extends LibraryCollectionsNotifier {
  @override
  LibraryCollectionsState build() => LibraryCollectionsState(
    isLoaded: true,
    playlists: [
      UserPlaylistCollection(
        id: 'playlist',
        name: 'Playlist',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        tracks: [
          for (final track in _tracks)
            CollectionTrackEntry(
              key: track.id,
              track: track,
              addedAt: DateTime(2026),
            ),
        ],
      ),
    ],
  );

  @override
  Future<void> ensurePlaylistLoaded(String playlistId) async {}
}

class _RemovalCollections extends _Collections {
  _RemovalCollections(this._record);
  final void Function(String, List<String>) _record;

  @override
  LibraryCollectionsState build() {
    final initial = super.build();
    final tracks = initial.playlists.single.tracks;
    return initial.copyWith(loved: tracks);
  }

  Future<int> _remove(String kind, Iterable<String> keys) async {
    final selected = keys.toSet();
    _record(kind, selected.toList());
    List<CollectionTrackEntry> keep(List<CollectionTrackEntry> entries) =>
        entries.where((entry) => !selected.contains(entry.key)).toList();
    state = switch (kind) {
      'loved' => state.copyWith(loved: keep(state.loved)),
      _ => state.copyWith(
        playlists: [
          state.playlists.single.copyWith(
            tracks: keep(state.playlists.single.tracks),
          ),
        ],
      ),
    };
    return selected.length;
  }

  @override
  Future<int> removeLovedTracks(Iterable<String> keys) =>
      _remove('loved', keys);

  @override
  Future<int> removeTracksFromPlaylist(String id, Iterable<String> keys) =>
      _remove('playlist', keys);
}

class _FailingRemovalCollections extends _Collections {
  final error = StateError('remove failed');

  @override
  Future<int> removeLovedTracks(Iterable<String> keys) async => throw error;

  @override
  Future<int> removeTracksFromPlaylist(
    String id,
    Iterable<String> keys,
  ) async => throw error;
}

class _SingleLovedCollections extends _Collections {
  @override
  LibraryCollectionsState build() => LibraryCollectionsState(
    isLoaded: true,
    loved: [
      CollectionTrackEntry(
        key: 'First',
        track: _tracks.first,
        addedAt: DateTime(2026),
      ),
    ],
  );

  void clearLoved() => state = state.copyWith(loved: []);
  void restoreLoved() => state = build();
}

class _Library extends LocalLibraryNotifier {
  @override
  LocalLibraryState build() => LocalLibraryState();
}

class _PlaylistLibrary extends LocalLibraryNotifier {
  @override
  LocalLibraryState build() => LocalLibraryState();
}

void main() {
  _registerPlaylistPlayback1();
  _registerPlaylistPlayback2();
}
