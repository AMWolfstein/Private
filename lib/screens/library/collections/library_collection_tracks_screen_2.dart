part of 'library_collection_tracks_screen.dart';

extension _LibraryCollectionTracksScreenStatePart2
    on _LibraryCollectionTracksScreenState {
  Future<void> _removeCoverImage() async {
    final playlistId = widget.playlistId;
    if (playlistId == null) return;

    try {
      await ref
          .read(libraryCollectionsProvider.notifier)
          .removePlaylistCover(playlistId);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.friendlyError(error))));
    }
  }

  Widget _buildAppBar(
    BuildContext context,
    ColorScheme colorScheme,
    String title,
    List<CollectionTrackEntry> entries,
    UserPlaylistCollection? playlist,
    String? coverSource,
  ) {
    final expandedHeight = calculateExpandedHeight(context);
    final customCoverPath = playlist?.coverImagePath;
    final isPlaylistMode = widget.mode == LibraryCollectionMode.playlist;
    final coverUrl = coverSource;
    final hasCustomCover =
        customCoverPath != null && customCoverPath.isNotEmpty;
    final hasCoverUrl = coverUrl != null;

    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = (MediaQuery.sizeOf(context).width * dpr).round().clamp(
      320,
      2048,
    );
    final coverFallback = Container(
      color: colorScheme.surfaceContainerHighest,
      child: Icon(_modeIcon(), size: 80, color: colorScheme.onSurfaceVariant),
    );
    Widget squarePlaceholder() => Container(
      color: colorScheme.surfaceContainerHighest,
      child: Icon(_modeIcon(), size: 48, color: colorScheme.onSurfaceVariant),
    );

    final Widget background = hasCustomCover
        ? Image.file(
            File(customCoverPath),
            fit: BoxFit.cover,
            cacheWidth: cacheWidth,
            filterQuality: FilterQuality.low,
            gaplessPlayback: true,
            frameBuilder: (_, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded || frame != null) {
                return child;
              }
              return coverFallback;
            },
            errorBuilder: (_, _, _) => coverFallback,
          )
        : hasCoverUrl
        ? LocalCoverImage(
            url: coverUrl,
            fit: BoxFit.cover,
            localCacheWidth: cacheWidth,
            fadeInDuration: Duration.zero,
            placeholder: (_) => Container(color: colorScheme.surface),
          )
        : coverFallback;

    return AlbumDetailHeader(
      title: title,
      immersive: context.isAppTheme,
      squareArtwork: true,
      appBarTitle: isSelectionMode
          ? context.l10n.selectionSelected(selectedIds.length)
          : null,
      expandedHeight: expandedHeight,
      showTitleInAppBar: showTitleInAppBar,
      background: background,
      paletteSource: coverSource,
      blurAndScrimBackground: hasCustomCover || hasCoverUrl,
      coverBuilder: (context, coverSize) {
        if (hasCustomCover) {
          return Image.file(
            File(customCoverPath),
            fit: BoxFit.cover,
            width: coverSize,
            height: coverSize,
            cacheWidth: cacheWidth,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => squarePlaceholder(),
          );
        }
        if (hasCoverUrl) {
          return LocalCoverImage(
            url: coverUrl,
            fit: BoxFit.cover,
            width: coverSize,
            height: coverSize,
            localCacheWidth: cacheWidth,
            placeholder: (_) => squarePlaceholder(),
          );
        }
        return squarePlaceholder();
      },
      meta: entries.isNotEmpty
          ? HeaderMetaRow(
              items: [
                HeaderMetaItem(
                  context.l10n.tracksCount(entries.length),
                  icon: _modeIcon(),
                ),
              ],
            )
          : null,
      actions: !isSelectionMode && entries.isNotEmpty
          ? _buildPlayAllCenterButton(entries)
          : null,
      appBarActions: [
        if (!isSelectionMode && entries.isNotEmpty)
          IconButton(
            icon: Icon(appIconFor(Icons.ios_share)),
            tooltip: context.l10n.collectionExportM3u,
            onPressed: () => _exportAsM3u8(context, title, entries),
          ),
        if (isPlaylistMode && !isSelectionMode) ...[
          IconButton(
            icon: Icon(appIconFor(Icons.edit_outlined)),
            tooltip: context.l10n.collectionRenamePlaylist,
            onPressed: () {
              final id = widget.playlistId ?? playlist?.id;
              if (id == null || id.isEmpty) return;
              _showRenamePlaylistDialog(context, id, playlist?.name ?? title);
            },
          ),
          IconButton(
            icon: Icon(appIconFor(Icons.camera_alt_outlined)),
            tooltip: context.l10n.collectionPlaylistChangeCover,
            onPressed: () => _showCoverOptionsSheet(context, hasCustomCover),
          ),
        ],
      ],
      leading: isSelectionMode
          ? HeaderCircleButton(
              icon: Icons.close,
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: exitSelectionMode,
            )
          : null,
    );
  }

  Widget _buildPlayAllCenterButton(List<CollectionTrackEntry> entries) {
    final tracks = entries.map((e) => e.track).toList(growable: false);
    final current = ref.watch(currentMediaItemProvider).asData?.value;
    final source = current?.extras?['source'];
    final inQueue =
        current != null &&
        tracks.any((track) => track.id == current.id || track.id == source);
    final playing = inQueue && ref.watch(playbackPlayingProvider);
    return LocalCollectionActions(
      tracks: tracks,
      isPlaying: playing,
      onPlay: inQueue
          ? () =>
                ref.read(musicPlayerControllerProvider).togglePlayPause(playing)
          : () => _playAll(tracks),
      onShuffle: () => _playAll(tracks, shuffle: true),
    );
  }

  Future<void> _playAll(List<Track> tracks, {bool shuffle = false}) async {
    if (tracks.isEmpty) return;
    try {
      final queue = tracks.toList();
      if (shuffle) queue.shuffle(Random());
      await ref.read(musicPlayerControllerProvider).setShuffle(shuffle);
      await ref.read(playbackProvider.notifier).playTrackList(queue);
    } catch (e) {
      if (mounted) showCannotOpenFileSnackBar(context, e);
    }
  }

  void _showCoverOptionsSheet(BuildContext context, bool hasCustomCover) {
    final colorScheme = Theme.of(context).colorScheme;

    showAppModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: colorScheme.surfaceContainerHigh,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppSheetHandle(),
            const SizedBox(height: 16),
            AppSheetOption(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 4,
              ),
              leading: Icon(
                appIconFor(Icons.image_outlined),
                color: colorScheme.primary,
              ),
              title: Text(context.l10n.collectionPlaylistChangeCover),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickCoverImage();
              },
            ),
            if (hasCustomCover)
              AppSheetOption(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 4,
                ),
                leading: Icon(
                  appIconFor(Icons.delete_outline),
                  color: colorScheme.primary,
                ),
                title: Text(context.l10n.collectionPlaylistRemoveCover),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _removeCoverImage();
                },
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _showRenamePlaylistDialog(
    BuildContext context,
    String playlistId,
    String currentName,
  ) async {
    final controller = TextEditingController(text: currentName);
    final formKey = GlobalKey<FormState>();

    final String? nextName;
    try {
      nextName = await showAppDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AppAlertDialog(
            title: Text(dialogContext.l10n.collectionRenamePlaylist),
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
                onPressed: () {
                  if (formKey.currentState?.validate() != true) return;
                  Navigator.of(dialogContext).pop(controller.text.trim());
                },
                child: Text(dialogContext.l10n.dialogSave),
              ),
            ],
          );
        },
      );
    } finally {
      controller.dispose();
    }

    if (nextName == null || nextName.trim().isEmpty || !context.mounted) {
      return;
    }

    try {
      await ref
          .read(libraryCollectionsProvider.notifier)
          .renamePlaylist(playlistId, nextName.trim());
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.friendlyError(error))));
      return;
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.collectionPlaylistRenamed)),
    );
  }
}
