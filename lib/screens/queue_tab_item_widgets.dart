part of 'queue_tab.dart';

extension _QueueTabItemWidgets on _QueueTabState {
  Widget _buildSelectionBottomBar(
    BuildContext context,
    ColorScheme colorScheme,
    List<UnifiedLibraryItem> unifiedItems,
    double bottomPadding,
  ) {
    final selectedCount = _selectedIds.length;
    final allSelected =
        selectedCount == unifiedItems.length && unifiedItems.isNotEmpty;

    return LibraryTrackSelectionBar(
      playbackActions: LibrarySelectionPlaybackActions(
        items: _selectedItemsFromAll(unifiedItems),
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
      onConvert: () => _showBatchConvertSheet(context, unifiedItems),
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

  /// When [size] is provided, renders at fixed dimensions (list mode).
  /// When [size] is null, fills the parent container (grid mode).
  Widget _buildUnifiedCoverImage(
    UnifiedLibraryItem item,
    ColorScheme colorScheme, [
    double? size,
  ]) {
    // Scanned SAF tracks also recover artwork after a transient provider error.
    if (item.filePath.startsWith('content://')) {
      return ValueListenableBuilder<int>(
        valueListenable: _embeddedCoverVersion,
        builder: (context, _, child) =>
            _buildUnifiedCoverImageInner(item, colorScheme, size),
      );
    }

    return _buildUnifiedCoverImageInner(item, colorScheme, size);
  }

  Widget _buildUnifiedCoverImageInner(
    UnifiedLibraryItem item,
    ColorScheme colorScheme, [
    double? size,
  ]) {
    final cacheSize = size != null ? (size * 2).toInt() : 200;
    final iconSize = size != null ? size * 0.4 : 32.0;

    Widget buildPlaceholder({bool recoverDocument = true}) {
      if (recoverDocument && item.filePath.startsWith('content://')) {
        final recovered = _resolveDownloadedEmbeddedCoverPath(item.filePath);
        if (recovered != null) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(recovered),
              width: size,
              height: size,
              fit: BoxFit.cover,
              cacheWidth: cacheSize,
              errorBuilder: (_, _, _) =>
                  buildPlaceholder(recoverDocument: false),
            ),
          );
        }
      }
      return Container(
        width: size,
        height: size,
        decoration: size != null
            ? BoxDecoration(
                color: colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              )
            : null,
        color: size != null ? null : colorScheme.secondaryContainer,
        child: Center(
          child: Icon(
            Icons.music_note,
            color: colorScheme.onSecondaryContainer,
            size: iconSize,
          ),
        ),
      );
    }

    Widget fadeInFileImage(Widget child, int? frame, bool wasSync) {
      if (wasSync) return child;
      final backdrop = buildPlaceholder(recoverDocument: false);
      final animated = Stack(
        fit: StackFit.expand,
        children: [
          backdrop,
          AnimatedOpacity(
            opacity: frame == null ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: child,
          ),
        ],
      );
      if (size == null) return animated;
      return SizedBox(width: size, height: size, child: animated);
    }

    if (item.coverUrl != null) {
      return CachedCoverImage(
        imageUrl: item.coverUrl!,
        width: size,
        height: size,
        memCacheWidth: cacheSize,
        borderRadius: BorderRadius.circular(8),
        placeholder: (context, url) => buildPlaceholder(),
        errorWidget: (context, url, error) => buildPlaceholder(),
        fadeInDuration: const Duration(milliseconds: 180),
        fadeOutDuration: const Duration(milliseconds: 90),
      );
    }

    if (item.localCoverPath != null && item.localCoverPath!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(item.localCoverPath!),
          width: size,
          height: size,
          fit: BoxFit.cover,
          cacheWidth: cacheSize,
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
              fadeInFileImage(child, frame, wasSynchronouslyLoaded),
          errorBuilder: (context, error, stackTrace) => buildPlaceholder(),
        ),
      );
    }

    if (size != null) {
      return buildPlaceholder();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: buildPlaceholder(),
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
    final fileExistsListenable = _fileExistsListenable(item.filePath);
    final isSelected = _selectedIds.contains(item.id);
    final date = item.addedAt;
    final dateStr =
        '${shortMonthNames[date.month - 1]} ${date.day}, ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    final quality = item.qualityForMode(_libraryQualityLabelMode);

    return Semantics(
      label: context.l10n.a11yTrackByArtist(item.trackName, item.artistName),
      selected: isSelected,
      child: TrackCard(
        isSelectionMode: _isSelectionMode,
        isSelected: isSelected,
        onTap: _isSelectionMode
            ? () => _toggleSelection(item.id)
            : item.localItem != null
            ? () => _navigateToLocalMetadataScreen(
                item.localItem!,
                navigationItems: localNavigationItems,
                navigationIndex: localNavigationIndex,
              )
            : () => _openFile(
                item.filePath,
                title: item.trackName,
                artist: item.artistName,
                album: item.albumName,
                coverUrl: item.coverUrl ?? item.localCoverPath ?? '',
              ),
        onLongPress: playlistDragEnabled
            ? null
            : _isSelectionMode
            ? () => _selectRangeTo(item.id, libraryItems)
            : () => _enterSelectionMode(item.id),
        leading: Hero(
          tag: 'cover_lib_${item.id}',
          child: _buildUnifiedCoverImage(
            item,
            colorScheme,
            context.tokens.coverList,
          ),
        ),
        title: item.trackName,
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClickableArtistName(
              artistName: item.artistName,
              coverUrl: item.coverUrl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Flexible(
                  child: Text(
                    dateStr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (quality != null && quality.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  _buildLibraryQualityBadge(
                    context,
                    colorScheme,
                    quality,
                    listStyle: true,
                  ),
                ],
              ],
            ),
          ],
        ),
        trailing: ValueListenableBuilder<bool>(
          valueListenable: fileExistsListenable,
          builder: (context, fileExists, child) {
            if (fileExists) {
              return _LibraryPlaybackButton(
                mediaId: _libraryPlaybackMediaId(item),
                playTooltip: context.l10n.a11yPlayTrackByArtist(
                  item.trackName,
                  item.artistName,
                ),
                onPlay: () => _playLibraryItem(item, libraryItems),
              );
            }
            return Tooltip(
              message: context.l10n.queueDownloadedFileMissing,
              child: Icon(
                Icons.error_outline,
                color: colorScheme.error,
                size: 20,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildUnifiedGridItem(
    BuildContext context,
    UnifiedLibraryItem item,
    ColorScheme colorScheme, {
    required List<LocalLibraryItem> localNavigationItems,
    required int? localNavigationIndex,
    required List<UnifiedLibraryItem> libraryItems,
    bool playlistDragEnabled = false,
  }) {
    final fileExistsListenable = _fileExistsListenable(item.filePath);
    final isSelected = _selectedIds.contains(item.id);
    final quality = item.qualityForMode(_libraryQualityLabelMode);

    return TrackGridCard(
      isSelected: _isSelectionMode && isSelected,
      semanticLabel: context.l10n.a11yTrackByArtist(
        item.trackName,
        item.artistName,
      ),
      onTap: _isSelectionMode
          ? () => _toggleSelection(item.id)
          : item.localItem != null
          ? () => _navigateToLocalMetadataScreen(
              item.localItem!,
              navigationItems: localNavigationItems,
              navigationIndex: localNavigationIndex,
            )
          : () => _openFile(
              item.filePath,
              title: item.trackName,
              artist: item.artistName,
              album: item.albumName,
              coverUrl: item.coverUrl ?? item.localCoverPath ?? '',
            ),
      onLongPress: playlistDragEnabled
          ? null
          : _isSelectionMode
          ? () => _selectRangeTo(item.id, libraryItems)
          : () => _enterSelectionMode(item.id),
      cover: Hero(
        tag: 'cover_lib_${item.id}',
        child: _buildUnifiedCoverImage(item, colorScheme),
      ),
      overlays: [
        if (!_isSelectionMode)
          Positioned(
            right: 4,
            top: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer,
                borderRadius: context.tokens.borderRadiusBadge,
              ),
              child: Icon(
                Icons.folder,
                size: 12,
                color: colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        if (quality != null && quality.isNotEmpty)
          Positioned(
            left: 4,
            right: _isSelectionMode ? 4 : 28,
            top: 4,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _buildLibraryQualityBadge(context, colorScheme, quality),
            ),
          ),
        if (!_isSelectionMode)
          Positioned(
            right: 4,
            bottom: 4,
            child: ValueListenableBuilder<bool>(
              valueListenable: fileExistsListenable,
              builder: (context, fileExists, child) {
                if (fileExists) {
                  return _LibraryPlaybackButton(
                    mediaId: _libraryPlaybackMediaId(item),
                    playTooltip: context.l10n.a11yPlayTrackByArtist(
                      item.trackName,
                      item.artistName,
                    ),
                    onPlay: () => _playLibraryItem(item, libraryItems),
                    grid: true,
                  );
                }
                return Tooltip(
                  message: context.l10n.queueDownloadedFileMissing,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.error_outline,
                      color: colorScheme.error,
                      size: 14,
                    ),
                  ),
                );
              },
            ),
          ),
        if (_isSelectionMode)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: isSelected
                    ? colorScheme.primary.withValues(alpha: 0.3)
                    : Colors.transparent,
                borderRadius: context.tokens.borderRadiusThumb,
              ),
            ),
          ),
        if (_isSelectionMode)
          Positioned(
            right: 4,
            top: 4,
            child: AnimatedSelectionCheckbox(
              visible: true,
              selected: isSelected,
              colorScheme: colorScheme,
              size: 24,
              unselectedColor: colorScheme.surface,
            ),
          ),
      ],
      title: item.trackName,
      subtitle: ClickableArtistName(
        artistName: item.artistName,
        coverUrl: item.coverUrl,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _LibraryPlaybackButton extends ConsumerWidget {
  const _LibraryPlaybackButton({
    required this.mediaId,
    required this.playTooltip,
    required this.onPlay,
    this.grid = false,
  });

  final String mediaId;
  final String playTooltip;
  final VoidCallback onPlay;
  final bool grid;

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

    if (grid) {
      return TrackGridPlayButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: icon,
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, color: colorScheme.primary),
      tooltip: tooltip,
      style: IconButton.styleFrom(
        minimumSize: Size.square(context.tokens.minTouchTarget),
        backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.3),
      ),
    );
  }
}
