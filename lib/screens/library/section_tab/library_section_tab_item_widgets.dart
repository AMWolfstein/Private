part of 'library_section_tab.dart';

extension _LibrarySectionTabItemWidgets on _LibrarySectionTabState {
  Widget _buildSelectionBottomBar(
    BuildContext context,
    ColorScheme colorScheme,
    List<UnifiedLibraryItem> unifiedItems,
    double bottomPadding,
  ) {
    final selectedItems = _selectedItemsFromAll(unifiedItems);
    final selectedCount = selectedItems.length;
    final allSelected =
        selectedCount == unifiedItems.length && unifiedItems.isNotEmpty;

    return LibraryTrackSelectionBar(
      playbackActions: LibrarySelectionPlaybackActions(
        items: selectedItems,
        onClose: _exitSelectionMode,
      ),
      selectedCount: selectedCount,
      allSelected: allSelected,
      onClose: _exitSelectionMode,
      onToggleSelectAll: () {
        if (allSelected) {
          _exitSelectionMode();
        } else {
          _selectAll(unifiedItems);
        }
      },
      bottomPadding: bottomPadding,
      onDelete: () => _deleteSelected(unifiedItems),
    );
  }

  Widget _buildUnifiedLibraryItem(
    BuildContext context,
    UnifiedLibraryItem item,
    ColorScheme colorScheme, {
    required List<UnifiedLibraryItem> libraryItems,
    bool playlistDragEnabled = false,
  }) {
    return LocalSongRow(
      title: item.trackName,
      artist: item.artistName,
      cover: item.localCoverPath,
      explicit: item.localItem.explicit,
      isSelectionMode: _isSelectionMode,
      isSelected: _selectedIds.contains(item.id),
      onSelect: () => _toggleSelection(item.id),
      onLongPress: playlistDragEnabled
          ? null
          : _isSelectionMode
          ? () => _selectRangeTo(item.id, libraryItems)
          : () => _enterSelectionMode(item.id),
      onPlay: () => _playLibraryItem(item, libraryItems),
      playControl: _LibraryPlaybackButton(
        mediaId: _libraryPlaybackMediaId(item),
        playTooltip: context.l10n.a11yPlayTrackByArtist(
          item.trackName,
          item.artistName,
        ),
        onPlay: () => _playLibraryItem(item, libraryItems),
      ),
      onMenu: (anchor) =>
          showCollectionSongMenu(context, ref, item.toTrack(), anchor: anchor),
    );
  }
}

class _LibraryPlaybackButton extends ConsumerWidget {
  const _LibraryPlaybackButton({
    required this.mediaId,
    required this.playTooltip,
    required this.onPlay,
  });

  final String mediaId;
  final String playTooltip;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(mediaItemPlaybackUiProvider(mediaId));
    final icon = playback.isPlaying ? Icons.pause : Icons.play_arrow;
    final tooltip = playback.isPlaying ? context.l10n.actionPause : playTooltip;
    final onPressed = playback.isLoading
        ? null
        : () {
            if (playback.isCurrent) {
              ref
                  .read(musicPlayerControllerProvider)
                  .togglePlayPause(playback.isPlaying);
            } else {
              onPlay();
            }
          };

    final colorScheme = Theme.of(context).colorScheme;
    return IconButton(
      onPressed: onPressed,
      icon: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: colorScheme.onSurfaceVariant, width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(icon, size: 20),
        ),
      ),
      tooltip: tooltip,
      style: IconButton.styleFrom(
        minimumSize: Size.square(context.tokens.minTouchTarget),
      ),
    );
  }
}
