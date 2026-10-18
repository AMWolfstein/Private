part of 'queue_tab.dart';

extension _QueueTabCollectionItemWidgets on _QueueTabState {
  Widget _buildLibraryQualityBadge(
    BuildContext context,
    ColorScheme colorScheme,
    String quality, {
    bool listStyle = false,
  }) {
    final tokens = context.tokens;
    final isHighlightedQuality = shouldHighlightAudioQualityBadge(quality);
    final displayQuality = listStyle
        ? quality
        : formatLibraryGridAudioQualityLabel(quality);
    final isDetailed = isDetailedLibraryAudioQualityLabel(displayQuality);
    final label = Text(
      displayQuality,
      maxLines: 1,
      softWrap: false,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: isHighlightedQuality
            ? listStyle
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onPrimary
            : colorScheme.onSurfaceVariant,
        fontSize: isDetailed ? tokens.badgeFontSize - 1 : tokens.badgeFontSize,
        fontWeight: listStyle ? FontWeight.w500 : FontWeight.w600,
      ),
    );
    return Container(
      padding: tokens.badgePadding,
      decoration: BoxDecoration(
        color: isHighlightedQuality
            ? listStyle
                  ? colorScheme.primaryContainer
                  : colorScheme.primary
            : colorScheme.surfaceContainerHighest,
        borderRadius: tokens.borderRadiusBadge,
      ),
      child: !listStyle && isDetailed
          ? FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: label,
            )
          : label,
    );
  }

  Widget _buildCollectionListItem({
    required BuildContext context,
    required ColorScheme colorScheme,
    IconData? icon,
    Color? iconColor,
    Color? iconBgColor,
    Widget? coverWidget,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    final cover =
        coverWidget ??
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: context.isMornye
                ? iconBgColor ?? colorScheme.surfaceContainerHighest
                : colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon ?? Icons.folder,
            color: context.isMornye
                ? iconColor ?? Colors.white
                : colorScheme.onSecondaryContainer,
            size: 28,
          ),
        );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              SizedBox(width: 56, height: 56, child: cover),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: colorScheme.onSurfaceVariant,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

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
            color: context.isMornye
                ? iconBgColor ?? colorScheme.surfaceContainerHighest
                : colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon ?? Icons.folder,
            color: context.isMornye
                ? iconColor ?? Colors.white
                : colorScheme.onSecondaryContainer,
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

  List<_CollectionEntry> _getVisibleCollectionEntries(
    LibraryCollectionsState collectionState,
  ) {
    final entries = <_CollectionEntry>[];
    if (collectionState.lovedCount > 0) {
      entries.add(_CollectionEntry.loved);
    }
    if (collectionState.favoriteArtistCount > 0) {
      entries.add(_CollectionEntry.favoriteArtists);
    }
    for (var i = 0; i < collectionState.playlists.length; i++) {
      entries.add(_CollectionEntry.playlist(i));
    }
    return entries;
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

  Widget _buildAllTabListCollectionItem({
    required BuildContext context,
    required ColorScheme colorScheme,
    required _CollectionEntry entry,
    required LibraryCollectionsState collectionState,
    List<UnifiedLibraryItem> filteredUnifiedItems = const [],
  }) {
    switch (entry.type) {
      case _CollectionEntryType.loved:
        return _buildCollectionListItem(
          context: context,
          colorScheme: colorScheme,
          icon: Icons.favorite,
          iconColor: Colors.white,
          iconBgColor: const Color(0xFF8C67AC),
          title: context.l10n.collectionLoved,
          subtitle:
              '${context.l10n.collectionFoldersTitle} • ${collectionState.lovedCount} ${collectionState.lovedCount == 1 ? 'track' : 'tracks'}',
          onTap: _openLovedFolder,
        );
      case _CollectionEntryType.favoriteArtists:
        return _buildCollectionListItem(
          context: context,
          colorScheme: colorScheme,
          icon: Icons.person,
          iconColor: Colors.white,
          iconBgColor: const Color(0xFFE91E63),
          title: context.l10n.collectionFavoriteArtists,
          subtitle:
              '${context.l10n.collectionFoldersTitle} • ${context.l10n.collectionArtistCount(collectionState.favoriteArtistCount)}',
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
              child: Row(
                children: [
                  if (_isPlaylistSelectionMode)
                    Semantics(
                      button: true,
                      checked: isSelected,
                      label: playlist.name,
                      child: GestureDetector(
                        onTap: () => _togglePlaylistSelection(playlist.id),
                        behavior: HitTestBehavior.opaque,
                        child: ConstrainedBox(
                          constraints: BoxConstraints.tightFor(
                            width: context.tokens.minTouchTarget,
                            height: context.tokens.minTouchTarget,
                          ),
                          child: Center(
                            child: AnimatedSelectionCheckbox(
                              visible: true,
                              selected: isSelected,
                              colorScheme: colorScheme,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: _buildCollectionListItem(
                      context: context,
                      colorScheme: colorScheme,
                      coverWidget: _buildPlaylistCover(
                        context,
                        playlist,
                        colorScheme,
                        56,
                      ),
                      title: playlist.name,
                      subtitle:
                          '${playlist.trackCount} ${playlist.trackCount == 1 ? 'track' : 'tracks'}',
                      onTap: _isPlaylistSelectionMode
                          ? () => _togglePlaylistSelection(playlist.id)
                          : () => _openPlaylistById(playlist.id),
                      onLongPress: _isPlaylistSelectionMode
                          ? () => _togglePlaylistSelection(playlist.id)
                          : () => _enterPlaylistSelectionMode(playlist.id),
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
