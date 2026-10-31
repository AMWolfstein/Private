part of 'library_collection_tracks_screen.dart';

extension _LibraryCollectionTracksScreenStatePart1
    on _LibraryCollectionTracksScreenState {
  /// Exports the collection as an .m3u8 shared via the system sheet. Tracks
  /// without a resolvable local file are skipped; SAF entries are written
  /// relative to the download tree root.
  Future<void> _exportAsM3u8(
    BuildContext context,
    String title,
    List<CollectionTrackEntry> entries,
  ) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final tracks = entries.map((e) => e.track).toList(growable: false);
      final paths = await ref
          .read(playbackProvider.notifier)
          .resolveTrackFilePaths(tracks);

      final exportEntries = <M3uExportEntry>[];
      for (var i = 0; i < tracks.length; i++) {
        final path = paths[i];
        if (path == null || isCueVirtualPath(path)) continue;
        final entryPath = M3uPlaylistService.exportPathFor(path);
        if (entryPath == null) continue;
        exportEntries.add(M3uExportEntry(track: tracks[i], path: entryPath));
      }

      if (exportEntries.isEmpty) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.collectionExportM3uNone)),
        );
        return;
      }

      final file = await M3uPlaylistService.writeExportEntries(
        title,
        exportEntries,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            l10n.collectionExportM3uDone(exportEntries.length, tracks.length),
          ),
        ),
      );
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: title),
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.collectionExportM3uFailed)),
      );
    }
  }

  IconData _modeIcon() {
    return switch (widget.mode) {
      LibraryCollectionMode.loved => Icons.favorite,
      LibraryCollectionMode.playlist => Icons.queue_music,
    };
  }

  /// Find the first available cover URL from entries.
  String? _firstRawCoverUrl(List<CollectionTrackEntry> entries) {
    for (final entry in entries) {
      final cover = resolveRawCoverUrl(entry.track);
      if (cover != null && cover.isNotEmpty) {
        return cover;
      }
    }
    return null;
  }

  Future<void> _removeSelected(List<CollectionTrackEntry> entries) async {
    final keysToRemove = selectedIds.toSet();
    if (keysToRemove.isEmpty) return;

    final count = keysToRemove.length;
    final notifier = ref.read(libraryCollectionsProvider.notifier);

    try {
      switch (widget.mode) {
        case LibraryCollectionMode.loved:
          await notifier.removeLovedTracks(keysToRemove);
          break;
        case LibraryCollectionMode.playlist:
          if (widget.playlistId != null) {
            await notifier.removeTracksFromPlaylist(
              widget.playlistId!,
              keysToRemove,
            );
          }
          break;
      }
    } catch (error) {
      if (!mounted) return;
      final message = context.friendlyError(error);
      // The bar is painted over the snackbar, so leave selection mode first,
      // like the success path, or the error stays hidden behind the panel.
      exitSelectionMode();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    if (!mounted) return;
    exitSelectionMode();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.collectionRemovedTracks(count))),
    );
  }

  LocalLibraryCoverBatchRequest _coverBatchRequest(
    List<CollectionTrackEntry> entries,
  ) {
    return LocalLibraryCoverBatchRequest(
      entries
          .map(
            (entry) => LocalLibraryCoverRequest(
              isrc: entry.track.isrc?.trim(),
              trackName: entry.track.name,
              artistName: entry.track.artistName,
            ),
          )
          .toList(growable: false),
    );
  }

  void _addSelectedToPlaylist(List<CollectionTrackEntry> entries) {
    final selectedTracks = entries
        .where((e) => selectedIds.contains(e.key))
        .map((e) => e.track)
        .toList(growable: false);
    if (selectedTracks.isEmpty) return;

    showAddTracksToPlaylistSheet(context, ref, selectedTracks);
  }

  Widget _buildPage(BuildContext context, String? coverSource) {
    final colorScheme = Theme.of(context).colorScheme;
    ref.watch(localLibraryProvider.select((s) => s.loadedIndexVersion));
    final List<CollectionTrackEntry> entries;

    switch (widget.mode) {
      case LibraryCollectionMode.loved:
        playlist = null;
        entries = ref.watch(
          libraryCollectionsProvider.select((state) => state.loved),
        );
        break;
      case LibraryCollectionMode.playlist:
        final playlistId = widget.playlistId;
        playlist = playlistId == null
            ? null
            : ref.watch(
                libraryCollectionsProvider.select(
                  (state) => state.playlistById(playlistId),
                ),
              );
        entries = playlist?.tracks ?? const <CollectionTrackEntry>[];
        break;
    }

    _folderData.update(entries);
    pruneSelection(_folderData.keys);

    final title = switch (widget.mode) {
      LibraryCollectionMode.loved => context.l10n.collectionLoved,
      LibraryCollectionMode.playlist =>
        playlist?.name ?? context.l10n.collectionPlaylist,
    };

    final emptyTitle = switch (widget.mode) {
      LibraryCollectionMode.loved => context.l10n.collectionLovedEmptyTitle,
      LibraryCollectionMode.playlist =>
        context.l10n.collectionPlaylistEmptyTitle,
    };

    final emptySubtitle = switch (widget.mode) {
      LibraryCollectionMode.loved => context.l10n.collectionLovedEmptySubtitle,
      LibraryCollectionMode.playlist =>
        context.l10n.collectionPlaylistEmptySubtitle,
    };
    final folderTracks = _folderData.tracks;
    final loading =
        !ref.watch(
          libraryCollectionsProvider.select((state) => state.isLoaded),
        ) ||
        (widget.mode == LibraryCollectionMode.playlist &&
            playlist?.tracksLoaded == false);

    final bottomPadding = isSelectionMode
        ? MediaQuery.paddingOf(context).bottom
        : 0.0;

    return CollectionScaffold(
      scrollController: scrollController,
      isSelectionMode: isSelectionMode,
      onExitSelectionMode: exitSelectionMode,
      selectionBar: _buildSelectionBottomBar(
        context,
        colorScheme,
        entries,
        bottomPadding,
      ),
      appBar: _buildAppBar(
        context,
        colorScheme,
        title,
        entries,
        playlist,
        coverSource,
      ),
      slivers: [
        if (loading)
          const SliverToBoxAdapter(child: TrackListSkeleton())
        else if (entries.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: CollectionEmptyFolderState(
              title: emptyTitle,
              subtitle: emptySubtitle,
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: wideListInset(context)),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final entry = entries[index];
                final isSelected = selectedIds.contains(entry.key);
                return KeyedSubtree(
                  key: ValueKey(entry.key),
                  // Collection contents must remain visible even when route
                  // or tab transitions pause animation tickers.
                  child: CollectionTrackTile(
                    entry: entry,
                    mode: widget.mode,
                    playlistId: widget.playlistId,
                    folderTracks: folderTracks,
                    trackIndex: index,
                    isSelectionMode: isSelectionMode,
                    isSelected: isSelected,
                    onTap: isSelectionMode
                        ? () => toggleSelection(entry.key)
                        : null,
                    onLongPress: isSelectionMode
                        ? null
                        : () => enterSelectionMode(entry.key),
                  ),
                );
              }, childCount: entries.length),
            ),
          ),
        if (!loading && entries.isNotEmpty)
          buildTrackListFooter(
            context,
            colorScheme,
            folderTracks,
            excludeEpochReleaseDate: true,
          ),
      ],
    );
  }

  Widget _buildSelectionBottomBar(
    BuildContext context,
    ColorScheme colorScheme,
    List<CollectionTrackEntry> entries,
    double bottomPadding,
  ) {
    final selectedCount = selectedIds.length;
    final allSelected = selectedCount == entries.length && entries.isNotEmpty;

    return SelectionBottomBar(
      selectedCount: selectedCount,
      allSelected: allSelected,
      onClose: exitSelectionMode,
      onToggleSelectAll: () {
        if (allSelected) {
          exitSelectionMode();
        } else {
          selectAll(entries.map((e) => e.key));
        }
      },
      bottomPadding: bottomPadding,
      children: [
        Row(
          children: [
            Expanded(
              child: SelectionActionButton(
                icon: Icons.playlist_add,
                label:
                    '${context.l10n.collectionAddToPlaylist} ($selectedCount)',
                onPressed: selectedCount > 0
                    ? () => _addSelectedToPlaylist(entries)
                    : null,
                colorScheme: colorScheme,
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),

        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: selectedCount > 0
                ? () => _removeSelected(entries)
                : null,
            icon: const Icon(Icons.remove_circle_outline),
            label: Text(
              selectedCount > 0
                  ? '${widget.mode == LibraryCollectionMode.playlist ? context.l10n.collectionRemoveFromPlaylist : context.l10n.collectionRemoveFromFolder} ($selectedCount)'
                  : widget.mode == LibraryCollectionMode.playlist
                  ? context.l10n.collectionRemoveFromPlaylist
                  : context.l10n.collectionRemoveFromFolder,
            ),
            style: FilledButton.styleFrom(
              backgroundColor: selectedCount > 0
                  ? colorScheme.error
                  : colorScheme.surfaceContainerHighest,
              foregroundColor: selectedCount > 0
                  ? colorScheme.onError
                  : colorScheme.onSurfaceVariant,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickCoverImage() async {
    final playlistId = widget.playlistId;
    if (playlistId == null) return;

    Directory? materializedDir;
    try {
      final picked = await FilePicker.pickFile(type: FileType.image);
      if (picked == null) return;

      var sourcePath = picked.path;
      if (sourcePath == null || sourcePath.isEmpty) {
        materializedDir = await Directory.systemTemp.createTemp(
          'sistrum_playlist_cover_',
        );
        final pickedExtension = p.extension(picked.name);
        final materializedFile = File(
          p.join(
            materializedDir.path,
            'selected_cover${pickedExtension.isEmpty ? '.img' : pickedExtension}',
          ),
        );
        await materializedFile.writeAsBytes(
          await picked.readAsBytes(),
          flush: true,
        );
        sourcePath = materializedFile.path;
      }

      await ref
          .read(libraryCollectionsProvider.notifier)
          .setPlaylistCover(playlistId, sourcePath);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.friendlyError(error))));
    } finally {
      try {
        if (materializedDir != null && await materializedDir.exists()) {
          await materializedDir.delete(recursive: true);
        }
      } catch (_) {
        // The cover has already been normalized into app storage.
      }
    }
  }
}
