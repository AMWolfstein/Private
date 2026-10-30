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

  /// Evaluate membership against the preceding completed write, then publish
  /// only after persistence succeeds. A failed write does not block the next.
  Future<T> _mutate<T>(Future<T> Function() mutation) {
    final operation = _mutationTail.then((_) async {
      await _ensureLoaded();
      if (!ref.mounted) {
        throw StateError('Library collections provider was disposed');
      }
      return mutation();
    });
    _mutationTail = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return operation;
  }

  void _invalidatePlaylistPickerSummaries() {
    if (!ref.mounted) return;
    ref.invalidate(libraryPlaylistPickerSummariesProvider);
  }

  @override
  LibraryCollectionsState build() {
    _loadFuture = _load();
    return LibraryCollectionsState();
  }

  Future<void> _load() async {
    _loadFailure = null;
    try {
      if (!ref.mounted) return;
      final snapshot = await _db.loadSnapshot();
      try {
        if (!ref.mounted) return;
        final loaded = await hydrateLibraryCollectionsSnapshot(snapshot);
        if (ref.mounted) state = loaded;
      } finally {
        await cleanupCollectionRows(
          nativeRowsPath: snapshot.nativeRowsPath,
          nativeRowsDirectory: snapshot.nativeRowsDirectory,
        );
      }
    } catch (error, stack) {
      _loadFailure = error;
      _log.e('Failed to load library collections', error, stack);
      if (ref.mounted) state = state.copyWith(isLoaded: true);
    }
  }

  Future<void> _ensureLoaded() async {
    if (!ref.mounted) return;
    if (state.isLoaded) return;
    await (_loadFuture ?? _load());
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

  bool _replacePlaylistById(
    String playlistId,
    UserPlaylistCollection Function(UserPlaylistCollection playlist) update,
  ) {
    if (!ref.mounted) return false;
    final playlist = state.playlistById(playlistId);
    if (playlist == null) return false;

    final playlistIndex = state.playlists.indexWhere((p) => p.id == playlistId);
    if (playlistIndex < 0) return false;

    final nextPlaylist = update(playlist);
    if (identical(nextPlaylist, playlist)) return false;

    final updatedPlaylists = [...state.playlists];
    updatedPlaylists[playlistIndex] = nextPlaylist;
    state = state.copyWith(playlists: updatedPlaylists);
    return true;
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

  Future<bool> toggleFavoriteArtist({
    required String artistId,
    required String? providerId,
    required String name,
    String? imageUrl,
  }) => _mutate(() async {
    final key = artistCollectionKey(artistId: artistId, providerId: providerId);
    final sourceSeparator = key.indexOf(':');
    final source = sourceSeparator > 0 ? key.substring(0, sourceSeparator) : '';
    final trimmedProviderId = providerId?.trim();
    final effectiveProviderId =
        trimmedProviderId != null && trimmedProviderId.isNotEmpty
        ? trimmedProviderId
        : (source.isNotEmpty && source != 'builtin' ? source : null);
    if (state.containsFavoriteArtistKey(key)) {
      await _db.deleteFavoriteArtistEntry(key);
      if (!ref.mounted) return false;
      state = state.copyWith(
        favoriteArtists: state.favoriteArtists
            .where((entry) => entry.key != key)
            .toList(growable: false),
      );
      return false;
    }

    final entry = CollectionArtistEntry(
      key: key,
      artistId: collectionArtistId(artistId),
      providerId: effectiveProviderId,
      name: name,
      imageUrl: imageUrl,
      addedAt: DateTime.now(),
    );
    await _db.upsertFavoriteArtistEntry(
      artistKey: key,
      artistJson: jsonEncode(entry.toJson()),
      addedAt: entry.addedAt.toIso8601String(),
    );
    if (ref.mounted) {
      state = state.copyWith(
        favoriteArtists: [entry, ...state.favoriteArtists],
      );
    }
    return true;
  });

  Future<void> _removeEntry<T>(
    String key, {
    required bool Function(String key) contains,
    required List<T> Function(LibraryCollectionsState state) select,
    required String Function(T entry) keyOf,
    required LibraryCollectionsState Function(List<T> list) withList,
    required Future<void> Function(String key) dbDelete,
  }) => _mutate(() async {
    if (!contains(key)) return;

    await dbDelete(key);
    if (!ref.mounted) return;
    state = withList(
      select(
        state,
      ).where((entry) => keyOf(entry) != key).toList(growable: false),
    );
  });

  Future<void> removeFavoriteArtist(String artistKey) => _removeEntry(
    artistKey,
    contains: (key) => state.containsFavoriteArtistKey(key),
    select: (state) => state.favoriteArtists,
    keyOf: (entry) => entry.key,
    withList: (list) => state.copyWith(favoriteArtists: list),
    dbDelete: _db.deleteFavoriteArtistEntry,
  );

  Future<int> _removeTrackEntries(
    Iterable<String> trackKeys, {
    required bool Function(String key) contains,
    required List<CollectionTrackEntry> Function() select,
    required LibraryCollectionsState Function(List<CollectionTrackEntry>)
    withList,
    required Future<void> Function(List<String>) dbDelete,
  }) {
    final selected = trackKeys.toSet();
    return _mutate(() async {
      final keys = selected.where(contains).toSet();
      if (keys.isEmpty) return 0;
      await dbDelete(keys.toList(growable: false));
      if (ref.mounted) {
        state = withList(
          select()
              .where((entry) => !keys.contains(entry.key))
              .toList(growable: false),
        );
      }
      return keys.length;
    });
  }

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

  Future<void> renamePlaylist(String playlistId, String newName) =>
      _mutate(() async {
        final trimmed = newName.trim();
        if (trimmed.isEmpty) return;
        final playlist = state.playlistById(playlistId);
        if (playlist == null || playlist.name == trimmed) return;

        final now = DateTime.now();
        await _db.renamePlaylist(
          playlistId: playlistId,
          name: trimmed,
          updatedAt: now.toIso8601String(),
        );
        _replacePlaylistById(playlistId, (playlist) {
          return playlist.copyWith(name: trimmed, updatedAt: now);
        });
        _invalidatePlaylistPickerSummaries();
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

  Future<bool> addTrackToPlaylist(String playlistId, Track track) => _mutate(
    () async {
      var playlist = state.playlistById(playlistId);
      if (playlist == null) return false;

      final key = trackCollectionKey(track);
      if (playlist.containsTrackKey(key)) return false;
      await ensurePlaylistLoaded(playlistId);
      if (!ref.mounted) return false;
      playlist = state.playlistById(playlistId);
      if (playlist == null) return false;

      final now = DateTime.now();
      final entry = CollectionTrackEntry(key: key, track: track, addedAt: now);
      await _db.upsertPlaylistTrack(
        playlistId: playlistId,
        trackKey: key,
        trackJson: jsonEncode(track.toJson()),
        addedAt: entry.addedAt.toIso8601String(),
        playlistUpdatedAt: now.toIso8601String(),
      );
      final changed = _replacePlaylistById(playlistId, (playlist) {
        if (playlist.containsTrackKey(key)) return playlist;
        return playlist.copyWith(
          tracks: [...playlist.tracks, entry],
          updatedAt: now,
        );
      });
      if (!changed) return false;
      _invalidatePlaylistPickerSummaries();
      return true;
    },
  );

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

  Future<void> setPlaylistCover(
    String playlistId,
    String sourceFilePath,
  ) => _mutate(() async {
    final playlist = state.playlistById(playlistId);
    if (playlist == null) return;

    final previousCoverPath = playlist.coverImagePath;
    final destPath = await _covers.normalizePlaylistCoverFile(sourceFilePath);

    final now = DateTime.now();
    try {
      await _db.updatePlaylistCover(
        playlistId: playlistId,
        coverImagePath: destPath,
        updatedAt: now.toIso8601String(),
      );
    } catch (_) {
      await _covers.deletePrivatePlaylistCover(destPath);
      rethrow;
    }
    _replacePlaylistById(playlistId, (playlist) {
      if (playlist.coverImagePath == destPath) return playlist;
      return playlist.copyWith(coverImagePath: () => destPath, updatedAt: now);
    });
    _invalidatePlaylistPickerSummaries();
    if (previousCoverPath != null && previousCoverPath != destPath) {
      if (!state.playlists.any((p) => p.coverImagePath == previousCoverPath)) {
        await _covers.deletePrivatePlaylistCover(previousCoverPath);
      }
    }
  });

  Future<void> removePlaylistCover(String playlistId) => _mutate(() async {
    final playlist = state.playlistById(playlistId);
    if (playlist == null || playlist.coverImagePath == null) return;

    final path = playlist.coverImagePath;
    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }

    final now = DateTime.now();
    await _db.updatePlaylistCover(
      playlistId: playlistId,
      coverImagePath: null,
      updatedAt: now.toIso8601String(),
    );
    _replacePlaylistById(playlistId, (playlist) {
      if (playlist.coverImagePath == null) return playlist;
      return playlist.copyWith(coverImagePath: () => null, updatedAt: now);
    });
    _invalidatePlaylistPickerSummaries();
  });

  Future<String> exportCollectionsJson() => _mutate(() async {
    final snapshot = await _db.exportBackupSnapshot();
    return exportCollectionsBackupSnapshot(snapshot);
  });

  /// Returns cover file references for the streaming ZIP backup format. The
  /// backup writer reads each file directly instead of materializing every
  /// image as base64 in memory.
  Future<Map<String, Map<String, String>>> exportPlaylistCoverFiles() async {
    await _ensureLoaded();
    final covers = <String, Map<String, String>>{};
    final playlists = List<UserPlaylistCollection>.of(state.playlists);
    for (final playlist in playlists) {
      var path = playlist.coverImagePath;
      if (path == null || path.isEmpty) continue;
      try {
        if (await _covers.playlistCoverNeedsNormalization(path)) {
          await setPlaylistCover(playlist.id, path);
          path = state.playlistById(playlist.id)?.coverImagePath ?? path;
        }
        final file = File(path);
        if (!await file.exists() || await file.length() == 0) continue;
        covers[playlist.id] = {
          'ext': p.extension(path).toLowerCase(),
          'path': path,
        };
      } catch (_) {
        // Skip unreadable cover; the rest of the backup still succeeds.
      }
    }
    return covers;
  }

  /// Replaces all collections (loved, playlists, favorite artists)
  /// with the contents of a backup. [collectionsJson] uses the
  /// [LibraryCollectionsState.toJson] shape; [coverImages] is the map produced
  /// from a backup. Cover images are rewritten into this device's
  /// covers directory and their paths fixed up before persisting.
  Future<void> restoreFromBackup(
    Map<String, dynamic> collectionsJson, {
    Map<String, dynamic>? coverImages,
  }) => _mutate(() async {
    final normalized = Map<String, dynamic>.from(collectionsJson);
    final coversDir = await _covers.playlistCoversDir();
    final prepared = <String>[];
    final previous = state.playlists
        .map((p) => p.coverImagePath)
        .whereType<String>()
        .toSet();
    var committed = false;
    try {
      await rewriteBackupPlaylistCovers(
        normalized: normalized,
        coverImages: coverImages,
        coversDir: coversDir,
        covers: _covers,
        prepared: prepared,
      );

      await _db.replaceAllFromBackup(normalized);
      committed = true;
      for (final path in previous.difference(prepared.toSet())) {
        await _covers.deletePrivatePlaylistCover(path);
      }
      await _load();
      _invalidatePlaylistPickerSummaries();
    } finally {
      if (!committed) {
        for (final path in prepared) {
          await _covers.deletePrivatePlaylistCover(path);
        }
      }
    }
  });
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
