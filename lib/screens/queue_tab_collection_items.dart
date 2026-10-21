part of 'queue_tab.dart';

extension _QueueTabCollectionItemWidgets on _QueueTabState {
  Widget _buildCollectionGridItem({
    required BuildContext context,
    required ColorScheme colorScheme,
    IconData? icon,
    Color? iconColor,
    Color? iconBgColor,
    Widget? coverWidget,
    required String title,
    required int count,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    final cover =
        coverWidget ??
        Container(
          decoration: BoxDecoration(
            color: iconBgColor ?? colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon ?? Icons.folder,
            color: iconColor ?? Colors.white,
            size: 40,
          ),
        );

    return Semantics(
      button: true,
      label: context.l10n.a11yOpenItemCount(title, count),
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: cover,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
            ),
            Text(
              context.l10n.itemCount(count),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAllTabGridCollectionItem({
    required BuildContext context,
    required ColorScheme colorScheme,
    required _CollectionEntry entry,
    required LibraryCollectionsState collectionState,
    List<UnifiedLibraryItem> filteredUnifiedItems = const [],
  }) {
    switch (entry.type) {
      case _CollectionEntryType.loved:
        return _buildCollectionGridItem(
          context: context,
          colorScheme: colorScheme,
          icon: Icons.favorite,
          iconColor: Colors.white,
          iconBgColor: const Color(0xFF8C67AC),
          title: context.l10n.collectionLoved,
          count: collectionState.lovedCount,
          onTap: _openLovedFolder,
        );
      case _CollectionEntryType.favoriteArtists:
        return _buildCollectionGridItem(
          context: context,
          colorScheme: colorScheme,
          icon: Icons.person,
          iconColor: Colors.white,
          iconBgColor: const Color(0xFFE91E63),
          title: context.l10n.collectionFavoriteArtists,
          count: collectionState.favoriteArtistCount,
          onTap: _openFavoriteArtistsFolder,
        );
      case _CollectionEntryType.playlist:
        final playlist = collectionState.playlists[entry.playlistIndex];
        final isSelected = _selectedPlaylistIds.contains(playlist.id);
        return DragTarget<UnifiedLibraryItem>(
          onWillAcceptWithDetails: (_) => !_isPlaylistSelectionMode,
          onAcceptWithDetails: (details) {
            _onTrackDroppedOnPlaylist(
              context,
              details.data,
              playlist.id,
              playlist.name,
              allItems: filteredUnifiedItems,
            );
          },
          builder: (context, candidateData, rejectedData) {
            final isHovering = candidateData.isNotEmpty;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: isHovering
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colorScheme.primary, width: 2),
                      color: colorScheme.primary.withValues(alpha: 0.1),
                    )
                  : null,
              child: Stack(
                children: [
                  _buildCollectionGridItem(
                    context: context,
                    colorScheme: colorScheme,
                    coverWidget: _buildPlaylistCover(
                      context,
                      playlist,
                      colorScheme,
                    ),
                    title: playlist.name,
                    count: playlist.trackCount,
                    onTap: _isPlaylistSelectionMode
                        ? () => _togglePlaylistSelection(playlist.id)
                        : () => _openPlaylistById(playlist.id),
                    onLongPress: _isPlaylistSelectionMode
                        ? () => _togglePlaylistSelection(playlist.id)
                        : () => _enterPlaylistSelectionMode(playlist.id),
                  ),
                  if (_isPlaylistSelectionMode)
                    Positioned(
                      left: 0,
                      top: 0,
                      right: 0,
                      child: IgnorePointer(
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? colorScheme.primary.withValues(alpha: 0.3)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (_isPlaylistSelectionMode)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: IgnorePointer(
                        child: AnimatedSelectionCheckbox(
                          visible: true,
                          selected: isSelected,
                          colorScheme: colorScheme,
                          size: 20,
                          unselectedColor: colorScheme.surface.withValues(
                            alpha: 0.85,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
    }
  }
}
