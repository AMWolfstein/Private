part of 'queue_tab.dart';

extension _QueueTabNavigation on _QueueTabState {
  String _libraryPlaybackMediaId(UnifiedLibraryItem item) {
    return item.localItem?.id ?? item.id;
  }

  /// Plays [item] and queues the rest of the merged library (downloaded + local
  /// in display order) so playback continues to the next track. Honors player
  /// mode and shuffle.
  Future<void> _playLibraryItem(
    UnifiedLibraryItem item,
    List<UnifiedLibraryItem> libraryItems,
  ) async {
    final playableItems = libraryItems
        .where(
          (u) => u.filePath.trim().isNotEmpty && !isCueVirtualPath(u.filePath),
        )
        .toList();
    if (playableItems.isEmpty) return;

    var start = playableItems.indexWhere((u) => u.id == item.id);
    if (start < 0) start = 0;

    try {
      await ref
          .read(playbackProvider.notifier)
          .playMediaQueue(
            playableItems.map(_toPlayableMedia),
            startIndex: start,
          );
    } catch (e) {
      if (mounted) showCannotOpenFileSnackBar(context, e);
    }
  }

  PlayableMedia _toPlayableMedia(UnifiedLibraryItem item) {
    final local = item.localItem;
    if (local != null) return playableFromLocal(local);

    final cover = item.coverUrl ?? item.localCoverPath ?? '';
    String? art;
    if (cover.isNotEmpty) {
      art =
          (cover.startsWith('http') ||
              cover.startsWith('content://') ||
              cover.startsWith('file://'))
          ? cover
          : Uri.file(cover).toString();
    }
    return PlayableMedia(
      id: item.id,
      source: item.filePath,
      title: item.trackName,
      artist: item.artistName,
      album: item.albumName,
      artUri: art,
    );
  }

  void _navigateWithUnfocus(Route<dynamic> route) {
    _searchFocusNode.unfocus();
    Navigator.of(context).push(route).then((_) => _searchFocusNode.unfocus());
  }

  void _navigateToLocalAlbum(_GroupedLocalAlbum album) {
    Future<List<LocalLibraryItem>> loadTracks() async {
      var rows = album.albumKey.isNotEmpty
          ? await LibraryDatabase.instance.getQueueLocalAlbumTracksByKey(
              album.albumKey,
            )
          : await LibraryDatabase.instance.getQueueLocalAlbumTracks(
              album.albumName,
              album.artistName,
            );
      if (rows.isEmpty && album.albumKey.isNotEmpty) {
        rows = await LibraryDatabase.instance.getQueueLocalAlbumTracks(
          album.albumName,
          album.artistName,
        );
      }
      return rows.map(LocalLibraryItem.fromJson).toList(growable: false);
    }

    _navigateWithUnfocus(
      slidePageRoute(
        page: LocalAlbumScreen(
          albumName: album.albumName,
          artistName: album.artistName,
          coverPath: album.coverPath,
          tracks: album.tracks,
          loadTracks: album.tracks.isEmpty && album.displayTrackCount > 0
              ? loadTracks
              : null,
        ),
      ),
    );
  }

  void _openPlaylistById(String playlistId) {
    _navigateWithUnfocus(
      MaterialPageRoute(
        builder: (_) => LibraryTracksFolderScreen(
          mode: LibraryTracksFolderMode.playlist,
          playlistId: playlistId,
        ),
      ),
    );
  }

  Future<void> _showCreatePlaylistDialog(BuildContext context) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final String? playlistName;
    try {
      playlistName = await showAppDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AppAlertDialog(
            title: Text(dialogContext.l10n.collectionCreatePlaylist),
            content: Form(
              key: formKey,
              child: TextFormField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: dialogContext.l10n.collectionPlaylistNameHint,
                ),
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty) {
                    return dialogContext.l10n.collectionPlaylistNameRequired;
                  }
                  return null;
                },
                onFieldSubmitted: (_) {
                  if (formKey.currentState?.validate() != true) return;
                  Navigator.of(dialogContext).pop(controller.text.trim());
                },
              ),
            ),
            actions: [
              AppDialogAction(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(dialogContext.l10n.dialogCancel),
              ),
              AppDialogAction(
                filled: true,
                isDefault: true,
                onPressed: () {
                  if (formKey.currentState?.validate() != true) return;
                  Navigator.of(dialogContext).pop(controller.text.trim());
                },
                child: Text(dialogContext.l10n.actionCreate),
              ),
            ],
          );
        },
      );
    } finally {
      controller.dispose();
    }

    if (playlistName == null || playlistName.isEmpty || !context.mounted) {
      return;
    }
    try {
      await ref
          .read(libraryCollectionsProvider.notifier)
          .createPlaylist(playlistName);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.friendlyError(error))));
    }
  }

  /// Pass a finite [size] (e.g. 56) for list view, or `null` for grid view
  /// where the widget should expand to fill its parent.
  Widget _buildPlaylistCover(
    BuildContext context,
    UserPlaylistCollection playlist,
    ColorScheme colorScheme, [
    double? size,
  ]) {
    final borderRadius = BorderRadius.circular(8);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheExtent = size != null
        ? (size * dpr).round().clamp(64, 1024)
        : 420;
    final placeholder = _playlistIconFallback(colorScheme, size);

    final customCoverPath = playlist.coverImagePath;
    if (customCoverPath != null && customCoverPath.isNotEmpty) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: Image.file(
          File(customCoverPath),
          width: size,
          height: size,
          fit: BoxFit.cover,
          cacheWidth: cacheExtent,
          gaplessPlayback: true,
          filterQuality: FilterQuality.low,
          frameBuilder: (_, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded || frame != null) return child;
            return placeholder;
          },
          errorBuilder: (_, _, _) => placeholder,
        ),
      );
    }

    final firstCoverUrl =
        playlist.tracks
            .where(
              (e) => e.track.coverUrl != null && e.track.coverUrl!.isNotEmpty,
            )
            .map((e) => e.track.coverUrl!)
            .firstOrNull ??
        playlist.previewCover;

    if (firstCoverUrl != null) {
      // Guard against local file paths that may have been stored as coverUrl
      return LocalCoverImage(
        url: firstCoverUrl,
        width: size,
        height: size,
        borderRadius: borderRadius,
        localCacheWidth: cacheExtent,
        fadeInDuration: Duration.zero,
        placeholder: (_) => placeholder,
      );
    }

    return placeholder;
  }

  /// Icon fallback for playlists with no cover.
  /// When [size] is null the container expands to fill its parent (grid view)
  /// and uses a fixed icon size.
  Widget _playlistIconFallback(ColorScheme colorScheme, [double? size]) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF5085A5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.queue_music,
        color: Colors.white,
        size: size != null ? size * 0.5 : 40,
      ),
    );
  }

  /// Handle a track being dropped onto a playlist.
  /// When selection mode is active and the dragged item is among the selected,
  /// all selected tracks are added to the playlist.
  Future<void> _onTrackDroppedOnPlaylist(
    BuildContext context,
    UnifiedLibraryItem item,
    String playlistId,
    String playlistName, {
    List<UnifiedLibraryItem> allItems = const [],
  }) async {
    final notifier = ref.read(libraryCollectionsProvider.notifier);

    if (_isSelectionMode &&
        _selectedIds.isNotEmpty &&
        _selectedIds.contains(item.id)) {
      final selectedItems = allItems
          .where((e) => _selectedIds.contains(e.id))
          .toList();
      if (selectedItems.isEmpty) {
        selectedItems.add(item);
      }

      final batchResult = await notifier.addTracksToPlaylist(
        playlistId,
        selectedItems.map((selected) => selected.toTrack()),
      );
      final addedCount = batchResult.addedCount;
      final alreadyCount = batchResult.alreadyInPlaylistCount;

      if (!context.mounted) return;
      final message = addedCount > 0
          ? alreadyCount > 0
                ? context.l10n.collectionAddedTracksToPlaylistWithExisting(
                    addedCount,
                    playlistName,
                    alreadyCount,
                  )
                : context.l10n.collectionAddedTracksToPlaylist(
                    addedCount,
                    playlistName,
                  )
          : context.l10n.collectionAlreadyInPlaylist(playlistName);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      _exitSelectionMode();
      return;
    }

    final track = item.toTrack();
    final added = await notifier.addTrackToPlaylist(playlistId, track);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added
              ? context.l10n.collectionAddedToPlaylist(playlistName)
              : context.l10n.collectionAlreadyInPlaylist(playlistName),
        ),
      ),
    );
  }
}
