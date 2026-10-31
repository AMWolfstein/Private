part of 'library_collections_provider.dart';

extension LibraryCollectionsMutations on LibraryCollectionsNotifier {
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
    if (_current.containsFavoriteArtistKey(key)) {
      await _db.deleteFavoriteArtistEntry(key);
      if (!_ref.mounted) return false;
      _current = _current.copyWith(
        favoriteArtists: _current.favoriteArtists
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
    if (_ref.mounted) {
      _current = _current.copyWith(
        favoriteArtists: [entry, ..._current.favoriteArtists],
      );
    }
    return true;
  });
  Future<void> removeFavoriteArtist(String artistKey) => _removeEntry(
    artistKey,
    contains: (key) => _current.containsFavoriteArtistKey(key),
    select: (current) => current.favoriteArtists,
    keyOf: (entry) => entry.key,
    withList: (list) => _current.copyWith(favoriteArtists: list),
    dbDelete: _db.deleteFavoriteArtistEntry,
  );
  Future<void> renamePlaylist(String playlistId, String newName) =>
      _mutate(() async {
        final trimmed = newName.trim();
        if (trimmed.isEmpty) return;
        final playlist = _current.playlistById(playlistId);
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
  Future<bool> addTrackToPlaylist(String playlistId, Track track) => _mutate(
    () async {
      var playlist = _current.playlistById(playlistId);
      if (playlist == null) return false;

      final key = trackCollectionKey(track);
      if (playlist.containsTrackKey(key)) return false;
      await ensurePlaylistLoaded(playlistId);
      if (!_ref.mounted) return false;
      playlist = _current.playlistById(playlistId);
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
  Future<void> setPlaylistCover(
    String playlistId,
    String sourceFilePath,
  ) => _mutate(() async {
    final playlist = _current.playlistById(playlistId);
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
      if (!_current.playlists.any(
        (p) => p.coverImagePath == previousCoverPath,
      )) {
        await _covers.deletePrivatePlaylistCover(previousCoverPath);
      }
    }
  });
  Future<void> removePlaylistCover(String playlistId) => _mutate(() async {
    final playlist = _current.playlistById(playlistId);
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
    final playlists = List<UserPlaylistCollection>.of(_current.playlists);
    for (final playlist in playlists) {
      var path = playlist.coverImagePath;
      if (path == null || path.isEmpty) continue;
      try {
        if (await _covers.playlistCoverNeedsNormalization(path)) {
          await setPlaylistCover(playlist.id, path);
          path = _current.playlistById(playlist.id)?.coverImagePath ?? path;
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
    final previous = _current.playlists
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
