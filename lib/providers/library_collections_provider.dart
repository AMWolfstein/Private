import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sistrum/core/models/library_collections.dart';
import 'package:sistrum/core/models/track.dart';
import 'package:sistrum/services/ffmpeg/ffmpeg_metadata.dart';
import 'package:sistrum/services/ffmpeg/ffmpeg_probe.dart';
import 'package:sistrum/services/library/collections/library_collections_database.dart';
import 'package:sistrum/services/library/collections/library_collections_hydration.dart';
import 'package:sistrum/services/library/collections/library_collections_playlist_covers.dart';
import 'package:sistrum/services/library/collections/library_collections_restore.dart';
import 'package:sistrum/services/library/collections/collection_track_batch.dart';
import 'package:sistrum/utils/logging/logger.dart';

export 'package:sistrum/core/models/library_collections.dart';
export 'package:sistrum/services/library/collections/library_collections_playlist_covers.dart'
    show PlaylistCoverProbe, PlaylistCoverResize;

part 'library_collections_provider_helpers.dart';
part 'library_collections_provider_mutations.dart';

final _log = AppLogger('LibraryCollections');

class LibraryCollectionsNotifier extends Notifier<LibraryCollectionsState> {
  LibraryCollectionsNotifier({
    LibraryCollectionsDatabase? database,
    PlaylistCoverResize? resizeCover,
    PlaylistCoverProbe? probeCover,
  }) : _db = database ?? LibraryCollectionsDatabase.instance,
       _resizeCover = resizeCover ?? FFmpegMetadata.resizeCoverArt,
       _probeCover = probeCover ?? FFmpegProbe.imageDimensions;

  final PlaylistCoverResize _resizeCover;
  final PlaylistCoverProbe _probeCover;
  late final PlaylistCoverFiles _covers = PlaylistCoverFiles(
    probeCover: _probeCover,
    resizeCover: _resizeCover,
  );

  final LibraryCollectionsDatabase _db;
  Future<void>? _loadFuture;
  Object? _loadFailure;
  final Map<String, Future<void>> _playlistLoadFutures = {};
  Future<void> _mutationTail = Future<void>.value();

  LibraryCollectionsState get _current => state;

  set _current(LibraryCollectionsState value) => state = value;

  Ref get _ref => ref;

  @override
  LibraryCollectionsState build() {
    _loadFuture = _load();
    return LibraryCollectionsState();
  }

  Future<void> ensurePlaylistLoaded(String playlistId) async {
    await _ensureLoaded();
    if (!ref.mounted) return;
    final playlist = state.playlistById(playlistId);
    if (playlist == null || playlist.tracksLoaded) return;

    final pending = _playlistLoadFutures[playlistId];
    if (pending != null) return pending;
    final load = () async {
      while (ref.mounted) {
        final loading = state.playlistById(playlistId);
        if (loading == null || loading.tracksLoaded) return;
        final snapshot = await _db.loadPlaylistTracksSnapshot(playlistId);
        late HydratedPlaylistTracks hydrated;
        try {
          if (!ref.mounted) return;
          hydrated = await hydratePlaylistTracksSnapshot(
            snapshot,
            knownKeys: loading.trackKeys,
          );
        } finally {
          await cleanupCollectionRows(
            nativeRowsPath: snapshot.nativeRowsPath,
            nativeRowsDirectory: snapshot.nativeRowsDirectory,
          );
        }
        if (!ref.mounted) return;
        final current = state.playlistById(playlistId);
        if (current == null || current.tracksLoaded) return;
        // Metadata-only edits share the index. A restore/reload can replace it
        // while the worker is running; retry rather than publish stale tracks.
        if (!current.sharesMembershipIndexWith(loading)) continue;
        _replacePlaylistById(
          playlistId,
          (current) => current.withHydratedTracks(
            tracks: hydrated.tracks,
            trackKeys: hydrated.trackKeys,
            membershipUnchanged: hydrated.membershipUnchanged,
          ),
        );
        return;
      }
    }();
    _playlistLoadFutures[playlistId] = load;
    try {
      await load;
    } finally {
      if (identical(_playlistLoadFutures[playlistId], load)) {
        _playlistLoadFutures.remove(playlistId);
      }
    }
  }

  Future<bool> toggleLoved(Track track) => _mutate(() async {
    final key = trackCollectionKey(track);
    if (state.containsLovedKey(key)) {
      await _db.deleteLovedEntry(key);
      if (!ref.mounted) return false;
      state = state.copyWith(
        loved: state.loved
            .where((entry) => entry.key != key)
            .toList(growable: false),
      );
      return false;
    }

    final entry = CollectionTrackEntry(
      key: key,
      track: track,
      addedAt: DateTime.now(),
    );
    await _db.upsertLovedEntry(
      trackKey: key,
      trackJson: jsonEncode(track.toJson()),
      addedAt: entry.addedAt.toIso8601String(),
    );
    if (ref.mounted) {
      state = state.copyWith(loved: [entry, ...state.loved]);
    }
    return true;
  });

  /// One selection is one mutation: mixed selections add only missing tracks,
  /// fully loved selections remove them, and observers see one committed state.
  Future<({bool removed, int count})> toggleLovedTracks(
    Iterable<Track> tracks,
  ) => _mutate(() async {
    final selected = tracks.toList(growable: false);
    if (selected.isEmpty) return (removed: false, count: 0);
    if (selected.every(state.isLoved)) {
      final keys = selected.map(trackCollectionKey).toSet();
      await _db.deleteLovedTracks(keys.toList(growable: false));
      if (ref.mounted) {
        state = state.copyWith(
          loved: state.loved
              .where((entry) => !keys.contains(entry.key))
              .toList(growable: false),
        );
      }
      return (removed: true, count: keys.length);
    }

    final now = DateTime.now();
    final prepared = await prepareCollectionTrackBatch(
      tracks: selected,
      existingKeys: state.loved.map((entry) => entry.key).toSet(),
      addedAt: now,
    );
    try {
      if (!ref.mounted || prepared.entries.isEmpty) {
        return (removed: false, count: 0);
      }
      final rowsPath = prepared.rowsPath;
      if (rowsPath != null) {
        await _db.upsertLovedTracksFile(
          addedAt: now.toIso8601String(),
          rowsPath: rowsPath,
          expectedCount: prepared.entries.length,
        );
      } else {
        await _db.upsertLovedTracksBatch(prepared.rows);
      }
      if (ref.mounted) {
        // The latest added track appears first, matching the original
        // per-track inserts and the database's DESC rowid tie-breaker.
        state = state.copyWith(
          loved: [...prepared.entries.reversed, ...state.loved],
        );
      }
      return (removed: false, count: prepared.entries.length);
    } finally {
      await prepared.dispose();
    }
  });

  Future<int> removeLovedTracks(Iterable<String> trackKeys) =>
      _removeTrackEntries(
        trackKeys,
        contains: (key) => state.containsLovedKey(key),
        select: () => state.loved,
        withList: (list) => state.copyWith(loved: list),
        dbDelete: _db.deleteLovedTracks,
      );

  /// Remove references to deleted local rows, including imported playlist
  /// occurrences. ISRC is a recording key, not a file identity: another local
  /// copy with the same ISRC must remain in its collections.
  Future<void> removeLocalLibraryTracks(Iterable<String> localIds) {
    final selected = localIds.toSet();
    if (selected.isEmpty) return Future<void>.value();
    final localKeys = {for (final id in selected) 'local:$id'};
    final occurrencePrefix = RegExp(r'^occurrence:\d+:');
    bool matches(CollectionTrackEntry entry) =>
        (entry.track.source == 'local' && selected.contains(entry.track.id)) ||
        localKeys.contains(entry.key.replaceFirst(occurrencePrefix, ''));

    return _mutate(() async {
      if (_loadFailure != null) {
        await _load();
        if (_loadFailure != null) {
          throw StateError(
            'Cannot remove deleted tracks from unreadable collections',
          );
        }
      }
      if (!ref.mounted) {
        throw StateError('Library collections provider was disposed');
      }
      final lovedKeys = state.loved
          .where(matches)
          .map((entry) => entry.key)
          .toList();
      if (lovedKeys.isNotEmpty) {
        await _db.deleteLovedTracks(lovedKeys);
        if (!ref.mounted) {
          throw StateError('Library collections provider was disposed');
        }
        final removed = lovedKeys.toSet();
        state = state.copyWith(
          loved: state.loved
              .where((entry) => !removed.contains(entry.key))
              .toList(),
        );
      }

      // Lazy playlist summaries contain membership keys but not the local row
      // IDs inside ISRC/occurrence entries. Resolve those before matching.
      final playlistIds = state.playlists
          .map((playlist) => playlist.id)
          .toList();
      for (final playlistId in playlistIds) {
        await ensurePlaylistLoaded(playlistId);
        if (!ref.mounted) {
          throw StateError('Library collections provider was disposed');
        }
        final playlist = state.playlistById(playlistId);
        if (playlist == null) continue;
        final keys = playlist.tracks
            .where(matches)
            .map((entry) => entry.key)
            .toSet();
        if (keys.isEmpty) continue;
        final now = DateTime.now();
        await _db.deletePlaylistTracks(
          playlistId: playlistId,
          trackKeys: keys.toList(),
          playlistUpdatedAt: now.toIso8601String(),
        );
        if (!ref.mounted) {
          throw StateError('Library collections provider was disposed');
        }
        _replacePlaylistById(
          playlistId,
          (current) => current.copyWith(
            tracks: current.tracks
                .where((entry) => !keys.contains(entry.key))
                .toList(),
            updatedAt: now,
          ),
        );
        _invalidatePlaylistPickerSummaries();
      }
    });
  }

  Future<String> createPlaylist(String name) => _mutate(() async {
    final now = DateTime.now();
    final id = 'pl_${now.microsecondsSinceEpoch}';
    final trimmedName = name.trim();

    final playlist = UserPlaylistCollection(
      id: id,
      name: trimmedName,
      createdAt: now,
      updatedAt: now,
      tracks: const [],
    );

    await _db.upsertPlaylist(
      id: id,
      name: trimmedName,
      coverImagePath: null,
      createdAt: now.toIso8601String(),
      updatedAt: now.toIso8601String(),
    );
    if (!ref.mounted) return id;
    state = state.copyWith(playlists: [playlist, ...state.playlists]);
    _invalidatePlaylistPickerSummaries();
    return id;
  });

  Future<int> deletePlaylists(Iterable<String> playlistIds) {
    final selected = playlistIds.toSet();
    return _mutate(() async {
      final ids = selected
          .where((id) => state.playlistById(id) != null)
          .toSet();
      if (ids.isEmpty) return 0;
      await _db.deletePlaylists(ids.toList(growable: false));
      if (ref.mounted) {
        state = state.copyWith(
          playlists: state.playlists
              .where((playlist) => !ids.contains(playlist.id))
              .toList(growable: false),
        );
        _invalidatePlaylistPickerSummaries();
      }
      return ids.length;
    });
  }

  Future<PlaylistAddBatchResult> addTracksToPlaylist(
    String playlistId,
    Iterable<Track> tracks, {
    bool preserveOccurrences = false,
  }) => _mutate(() async {
    await ensurePlaylistLoaded(playlistId);
    if (!ref.mounted) {
      return const PlaylistAddBatchResult(
        addedCount: 0,
        alreadyInPlaylistCount: 0,
      );
    }
    final playlist = state.playlistById(playlistId);
    if (playlist == null) {
      return const PlaylistAddBatchResult(
        addedCount: 0,
        alreadyInPlaylistCount: 0,
      );
    }

    final now = DateTime.now();
    final prepared = await prepareCollectionTrackBatch(
      tracks: tracks,
      existingKeys: playlist.trackKeys,
      addedAt: now,
      preserveOccurrences: preserveOccurrences,
    );
    try {
      if (!ref.mounted || prepared.entries.isEmpty) {
        return PlaylistAddBatchResult(
          addedCount: 0,
          alreadyInPlaylistCount: prepared.duplicates,
        );
      }
      final rowsPath = prepared.rowsPath;
      if (rowsPath != null) {
        await _db.upsertPlaylistTracksFile(
          playlistId: playlistId,
          playlistUpdatedAt: now.toIso8601String(),
          rowsPath: rowsPath,
          expectedCount: prepared.entries.length,
        );
      } else {
        await _db.upsertPlaylistTracksBatch(
          playlistId: playlistId,
          playlistUpdatedAt: now.toIso8601String(),
          tracks: prepared.rows,
        );
      }
      final changed = _replacePlaylistById(playlistId, (current) {
        return current.copyWith(
          // Append in playlist order, matching the ASC snapshot ordering.
          tracks: [...current.tracks, ...prepared.entries],
          updatedAt: now,
        );
      });
      if (changed) _invalidatePlaylistPickerSummaries();
      return PlaylistAddBatchResult(
        addedCount: changed ? prepared.entries.length : 0,
        alreadyInPlaylistCount: prepared.duplicates,
      );
    } finally {
      await prepared.dispose();
    }
  });

  Future<int> removeTracksFromPlaylist(
    String playlistId,
    Iterable<String> trackKeys,
  ) {
    final selected = trackKeys.toSet();
    return _mutate(() async {
      var playlist = state.playlistById(playlistId);
      if (playlist == null || !selected.any(playlist.containsTrackKey)) {
        return 0;
      }
      await ensurePlaylistLoaded(playlistId);
      if (!ref.mounted) return 0;
      playlist = state.playlistById(playlistId);
      if (playlist == null) return 0;
      final keys = selected.where(playlist.containsTrackKey).toSet();
      if (keys.isEmpty) return 0;

      final now = DateTime.now();
      await _db.deletePlaylistTracks(
        playlistId: playlistId,
        trackKeys: keys.toList(growable: false),
        playlistUpdatedAt: now.toIso8601String(),
      );
      _replacePlaylistById(
        playlistId,
        (current) => current.copyWith(
          tracks: current.tracks
              .where((entry) => !keys.contains(entry.key))
              .toList(growable: false),
          updatedAt: now,
        ),
      );
      _invalidatePlaylistPickerSummaries();
      return keys.length;
    });
  }
}

final libraryCollectionsProvider =
    NotifierProvider<LibraryCollectionsNotifier, LibraryCollectionsState>(
      LibraryCollectionsNotifier.new,
    );

final libraryPlaylistPickerSummariesProvider = FutureProvider.autoDispose
    .family<List<PlaylistPickerSummary>, PlaylistPickerSummaryRequest>((
      ref,
      request,
    ) async {
      final db = LibraryCollectionsDatabase.instance;
      return db.loadPlaylistPickerSummaries(request.trackKeys);
    });
