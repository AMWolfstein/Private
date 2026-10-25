part of 'queue_tab.dart';

extension _QueueTabItemWidgets on _QueueTabState {
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
      onReplayGain: ({required remove}) =>
          _runBatchReplayGain(unifiedItems, remove: remove),
      onDelete: () => _deleteSelected(unifiedItems),
    );
  }

  Widget _buildFilterButton(BuildContext context) {
    return GestureDetector(
      onLongPress: _activeFilterCount > 0 ? _resetFilters : null,
      child: TextButton.icon(
        onPressed: () => _showFilterSheet(context),
        icon: Badge(
          isLabelVisible: _activeFilterCount > 0,
          label: Text('$_activeFilterCount'),
          child: const Icon(Icons.filter_list, size: 18),
        ),
        label: Text(context.l10n.libraryFilterTitle),
        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
      ),
    );
  }

  Widget _buildUnifiedLibraryItem(
    BuildContext context,
    UnifiedLibraryItem item,
    ColorScheme colorScheme, {
    required List<LocalLibraryItem> localNavigationItems,
    required int? localNavigationIndex,
    required List<UnifiedLibraryItem> libraryItems,
    bool playlistDragEnabled = false,
  }) {
    return LocalSongRow(
      title: item.trackName,
      artist: item.artistName,
      cover: item.localCoverPath ?? item.coverUrl,
      explicit: item.localItem?.explicit ?? false,
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
