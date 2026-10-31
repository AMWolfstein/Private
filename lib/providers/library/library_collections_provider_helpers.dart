part of 'library_collections_provider.dart';

extension _LibraryCollectionsHelpers on LibraryCollectionsNotifier {
  /// Evaluate membership against the preceding completed write, then publish
  /// only after persistence succeeds. A failed write does not block the next.
  Future<T> _mutate<T>(Future<T> Function() mutation) {
    final operation = _mutationTail.then((_) async {
      await _ensureLoaded();
      if (!_ref.mounted) {
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
    if (!_ref.mounted) return;
    _ref.invalidate(libraryPlaylistPickerSummariesProvider);
  }

  Future<void> _load() async {
    _loadFailure = null;
    try {
      if (!_ref.mounted) return;
      final snapshot = await _db.loadSnapshot();
      try {
        if (!_ref.mounted) return;
        final loaded = await hydrateLibraryCollectionsSnapshot(snapshot);
        if (_ref.mounted) _current = loaded;
      } finally {
        await cleanupCollectionRows(
          nativeRowsPath: snapshot.nativeRowsPath,
          nativeRowsDirectory: snapshot.nativeRowsDirectory,
        );
      }
    } catch (error, stack) {
      _loadFailure = error;
      _log.e('Failed to load library collections', error, stack);
      if (_ref.mounted) _current = _current.copyWith(isLoaded: true);
    }
  }

  Future<void> _ensureLoaded() async {
    if (!_ref.mounted) return;
    if (_current.isLoaded) return;
    await (_loadFuture ?? _load());
  }

  bool _replacePlaylistById(
    String playlistId,
    UserPlaylistCollection Function(UserPlaylistCollection playlist) update,
  ) {
    if (!_ref.mounted) return false;
    final playlist = _current.playlistById(playlistId);
    if (playlist == null) return false;

    final playlistIndex = _current.playlists.indexWhere(
      (p) => p.id == playlistId,
    );
    if (playlistIndex < 0) return false;

    final nextPlaylist = update(playlist);
    if (identical(nextPlaylist, playlist)) return false;

    final updatedPlaylists = [..._current.playlists];
    updatedPlaylists[playlistIndex] = nextPlaylist;
    _current = _current.copyWith(playlists: updatedPlaylists);
    return true;
  }

  Future<void> _removeEntry<T>(
    String key, {
    required bool Function(String key) contains,
    required List<T> Function(LibraryCollectionsState current) select,
    required String Function(T entry) keyOf,
    required LibraryCollectionsState Function(List<T> list) withList,
    required Future<void> Function(String key) dbDelete,
  }) => _mutate(() async {
    if (!contains(key)) return;

    await dbDelete(key);
    if (!_ref.mounted) return;
    _current = withList(
      select(
        _current,
      ).where((entry) => keyOf(entry) != key).toList(growable: false),
    );
  });
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
      if (_ref.mounted) {
        _current = withList(
          select()
              .where((entry) => !keys.contains(entry.key))
              .toList(growable: false),
        );
      }
      return keys.length;
    });
  }
}
