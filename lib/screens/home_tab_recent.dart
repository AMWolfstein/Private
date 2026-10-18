part of 'home_tab.dart';

extension _HomeTabRecentUI on _HomeTabState {
  List<Widget> _buildRecentAccess(ColorScheme colorScheme) {
    final items = ref.watch(recentAccessViewProvider).uniqueItems;

    return [
      SliverToBoxAdapter(
        child: _buildRecentAccessHeader(items, colorScheme),
      ),
      if (items.isNotEmpty)
        SliverPadding(
          padding:
              const EdgeInsets.fromLTRB(16, 0, 16, 8) +
              EdgeInsets.symmetric(horizontal: wideListInset(context)),
          sliver: SliverList.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return KeyedSubtree(
                key: ValueKey('${item.type.name}:${item.id}'),
                child: _buildRecentAccessItem(item, colorScheme),
              );
            },
          ),
        ),
    ];
  }

  Widget _buildRecentAccessHeader(
    List<RecentAccessItem> items,
    ColorScheme colorScheme,
  ) {
    return Padding(
      padding:
          EdgeInsets.fromLTRB(16, 16, 16, items.isEmpty ? 8 : 0) +
          EdgeInsets.symmetric(horizontal: wideListInset(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                context.l10n.homeRecent,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              if (items.isNotEmpty)
                TextButton(
                  onPressed: () => _confirmClearHistory(),
                  child: Text(
                    context.l10n.dialogClearAll,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colorScheme.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.history,
                      size: 48,
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      context.l10n.recentEmpty,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmClearHistory() async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => AppAlertDialog(
        title: Text(dialogContext.l10n.dialogClearAll),
        content: Text(dialogContext.l10n.recentClearAllMessage),
        actions: [
          AppDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(dialogContext.l10n.dialogCancel),
          ),
          AppDialogAction(
            filled: true,
            isDestructive: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(dialogContext.l10n.dialogClearAll),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(recentAccessProvider.notifier).clearHistory();
  }

  Widget _buildRecentAccessItem(
    RecentAccessItem item,
    ColorScheme colorScheme,
  ) {
    final IconData typeIcon;
    final String typeLabel;
    switch (item.type) {
      case RecentAccessType.artist:
        typeIcon = Icons.person;
        typeLabel = context.l10n.recentTypeArtist;
      case RecentAccessType.album:
        typeIcon = Icons.album;
        typeLabel = context.l10n.recentTypeAlbum;
      case RecentAccessType.track:
        typeIcon = Icons.music_note;
        typeLabel = context.l10n.recentTypeSong;
      case RecentAccessType.playlist:
        typeIcon = Icons.playlist_play;
        typeLabel = context.l10n.recentTypePlaylist;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        onTap: () => _navigateToRecentItem(item),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: [
              _DownloadedOrRemoteCover(
                downloadedFilePath: null,
                imageUrl: item.imageUrl,
                width: 56,
                height: 56,
                borderRadius: BorderRadius.circular(
                  item.type == RecentAccessType.artist ? 28 : 4,
                ),
                fallbackIcon: typeIcon,
                colorScheme: colorScheme,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.subtitle != null && item.subtitle!.isNotEmpty
                          ? '$typeLabel • ${item.subtitle}'
                          : typeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: context.l10n.actionDismiss,
                icon: Icon(
                  Icons.close,
                  size: 20,
                  color: colorScheme.onSurfaceVariant,
                ),
                onPressed: () =>
                    ref.read(recentAccessProvider.notifier).removeItem(item),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _navigateToRecentItem(RecentAccessItem item) async {
    _searchFocusNode.unfocus();

    switch (item.type) {
      case RecentAccessType.artist:
        _openArtist(item.name);
        return;
      case RecentAccessType.album:
        final rows = await LibraryDatabase.instance.getAll();
        final artist = item.subtitle ?? '';
        final tracks = rows
            .map(LocalLibraryItem.fromJson)
            .where(
              (track) =>
                  track.albumName == item.name &&
                  (artist.isEmpty ||
                      track.artistName == artist ||
                      track.albumArtist == artist),
            )
            .toList();
        if (!mounted) return;
        if (tracks.isEmpty) {
          _showSnack(item.name);
          return;
        }
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => LocalAlbumScreen(
              albumName: item.name,
              artistName: artist,
              coverPath: tracks.first.coverPath,
              tracks: tracks,
            ),
          ),
        );
        return;
      case RecentAccessType.track:
        final localItem = await ref
            .read(localLibraryProvider.notifier)
            .findExistingAsync(
              id: item.id,
              trackName: item.name,
              artistName: item.subtitle,
            );
        if (!mounted) return;
        if (localItem == null) {
          _showSnack(item.name);
          return;
        }
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TrackMetadataScreen(localItem: localItem),
          ),
        );
        return;
      case RecentAccessType.playlist:
        if (item.id.trim().isEmpty) {
          _showSnack(context.l10n.recentPlaylistInfo(item.name));
          return;
        }
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => LibraryTracksFolderScreen(
              mode: LibraryTracksFolderMode.playlist,
              playlistId: item.id,
            ),
          ),
        );
        return;
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
