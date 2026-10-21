part of 'queue_tab.dart';

extension _QueueTabFilterWidgets on _QueueTabState {
  /// Count text left, action buttons right, always on one line; on narrow
  /// widths the buttons scale down instead of truncating the count.
  Widget _countHeaderRow(
    BuildContext context,
    String countText,
    List<Widget> actions,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Text(
            countText,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(mainAxisSize: MainAxisSize.min, children: actions),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterContent({
    required BuildContext context,
    required ColorScheme colorScheme,
    required String filterMode,
    required _FilterContentData filterData,
    required LibraryCollectionsState collectionState,
    required bool hasMoreLibrary,
    required bool isPageLoading,
  }) {
    // Dedicated Library sections use rows; the Library overview uses cards.

    final showFilteringIndicator = filterData.showFilteringIndicator;
    final filteredGroupedLocalAlbums = filterData.filteredGroupedLocalAlbums;
    final unifiedItems = filterData.unifiedItems;
    final allFilteredUnifiedItems = filterData.filteredUnifiedItems;
    final filteredUnifiedItems = allFilteredUnifiedItems;
    final totalTrackCount = filterData.totalTrackCount;
    final totalAlbumCount = filterData.totalAlbumCount;
    final sectionLocale = Localizations.localeOf(context).toLanguageTag();
    String? sectionLabel(UnifiedLibraryItem item) => switch (_sortMode) {
      'a-z' || 'z-a' => librarySectionInitial(item.trackName),
      'artist' ||
      'artist-asc' ||
      'artist-desc' => librarySectionInitial(item.artistName),
      'album' ||
      'album-asc' ||
      'album-desc' => librarySectionInitial(item.albumName),
      'latest' || 'oldest' => librarySectionMonth(item.addedAt, sectionLocale),
      _ => null,
    };

    final localNavigationItems = <LocalLibraryItem>[];
    final localNavigationIndexByUnifiedId = <String, int>{};

    for (final item in allFilteredUnifiedItems) {
      final localItem = item.localItem;
      if (localItem != null) {
        localNavigationIndexByUnifiedId[item.id] = localNavigationItems.length;
        localNavigationItems.add(localItem);
      }
    }

    // Indexes into collectionState.playlists, name-filtered by the search
    // query, for the 'playlists' view.
    final playlistIndexes = <int>[];
    if (filterMode == 'playlists') {
      final query = _searchQuery.trim().toLowerCase();
      for (var i = 0; i < collectionState.playlists.length; i++) {
        if (query.isEmpty ||
            collectionState.playlists[i].name.toLowerCase().contains(query)) {
          playlistIndexes.add(i);
        }
      }
      playlistIndexes.sort((a, b) {
        final first = collectionState.playlists[a];
        final second = collectionState.playlists[b];
        return switch (_sortMode) {
          'a-z' => first.name.toLowerCase().compareTo(
            second.name.toLowerCase(),
          ),
          'z-a' => second.name.toLowerCase().compareTo(
            first.name.toLowerCase(),
          ),
          'oldest' => first.createdAt.compareTo(second.createdAt),
          _ => second.updatedAt.compareTo(first.updatedAt),
        };
      });
    }

    final content = CustomScrollView(
      slivers: [
        if (totalTrackCount > 0 && filterMode == 'all')
          SliverToBoxAdapter(
            child: _countHeaderRow(
              context,
              context.l10n.queueTrackCount(totalTrackCount),
              [
                if (!_isSelectionMode) _buildFilterButton(context),
                if (!_isSelectionMode && filteredUnifiedItems.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => _showCreatePlaylistDialog(context),
                    icon: const Icon(Icons.add, size: 20),
                    label: Text(context.l10n.collectionCreatePlaylist),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ),

        if (filteredGroupedLocalAlbums.isNotEmpty && filterMode == 'albums')
          SliverToBoxAdapter(
            child: _countHeaderRow(
              context,
              context.l10n.queueAlbumCount(totalAlbumCount),
              [_buildFilterButton(context)],
            ),
          ),

        if (filteredGroupedLocalAlbums.isEmpty &&
            filterMode == 'albums' &&
            (_activeFilterCount > 0 ||
                (ref.read(settingsProvider).localLibraryEnabled &&
                    ref.read(localLibraryProvider).totalCount > 0)))
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [const Spacer(), _buildFilterButton(context)],
              ),
            ),
          ),

        if (filterMode == 'all' &&
            totalTrackCount == 0 &&
            !showFilteringIndicator &&
            (_activeFilterCount > 0 || unifiedItems.isNotEmpty))
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  const Spacer(),
                  if (!_isSelectionMode) _buildFilterButton(context),
                ],
              ),
            ),
          ),

        if (filterMode == 'singles' &&
            totalTrackCount == 0 &&
            !showFilteringIndicator &&
            (_activeFilterCount > 0 || unifiedItems.isNotEmpty))
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  const Spacer(),
                  if (!_isSelectionMode) _buildFilterButton(context),
                ],
              ),
            ),
          ),

        if (showFilteringIndicator)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    context.l10n.queueFilteringIndicator,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),

        if (filterMode == 'albums' && filteredGroupedLocalAlbums.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: _AnimatedLibrarySliverGrid(
              maxCrossAxisExtent: _libraryAlbumGridExtent,
              extentListenable: _libraryGridExtentNotifier,
              extentScale: 1.45,
              minExtent: 150,
              maxExtent: 300,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.72,
              delegate: SliverChildBuilderDelegate((context, index) {
                final album = filteredGroupedLocalAlbums[index];
                return KeyedSubtree(
                  key: ValueKey('local_${album.key}'),
                  child: _buildLocalAlbumGridItem(context, album, colorScheme),
                );
              }, childCount: filteredGroupedLocalAlbums.length),
            ),
          ),

        if (filterMode == 'playlists' && playlistIndexes.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _countHeaderRow(
              context,
              context.l10n.queuePlaylistCount(playlistIndexes.length),
              [
                if (!_isPlaylistSelectionMode)
                  TextButton.icon(
                    onPressed: () => _showCreatePlaylistDialog(context),
                    icon: const Icon(Icons.add, size: 20),
                    label: Text(context.l10n.collectionCreatePlaylist),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: _AnimatedLibrarySliverGrid(
              maxCrossAxisExtent: _libraryAlbumGridExtent,
              extentListenable: _libraryGridExtentNotifier,
              extentScale: 1.45,
              minExtent: 150,
              maxExtent: 300,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.72,
              delegate: SliverChildBuilderDelegate((context, index) {
                final playlistIndex = playlistIndexes[index];
                return KeyedSubtree(
                  key: ValueKey(
                    'plgrid_${collectionState.playlists[playlistIndex].id}',
                  ),
                  child: _buildAllTabGridCollectionItem(
                    context: context,
                    colorScheme: colorScheme,
                    entry: _CollectionEntry.playlist(playlistIndex),
                    collectionState: collectionState,
                  ),
                );
              }, childCount: playlistIndexes.length),
            ),
          ),
        ],

        if (filterMode == 'all') ...[
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: wideListInset(context)),
            sliver: SectionedLibrarySliverList<UnifiedLibraryItem>(
              items: filteredUnifiedItems,
              groupingKey: (_sortMode, sectionLocale),
              labelOf: sectionLabel,
              rowBuilder: (context, index) {
                final trackIndex = index;
                if (trackIndex < filteredUnifiedItems.length) {
                  final item = filteredUnifiedItems[trackIndex];
                  return KeyedSubtree(
                    key: ValueKey(item.id),
                    child: _buildUnifiedLibraryItem(
                      context,
                      item,
                      colorScheme,
                      localNavigationItems: localNavigationItems,
                      localNavigationIndex:
                          localNavigationIndexByUnifiedId[item.id],
                      libraryItems: filteredUnifiedItems,
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ],

        if (filterMode == 'singles')
          SliverToBoxAdapter(
            child: _countHeaderRow(
              context,
              context.l10n.queueTrackCount(totalTrackCount),
              [
                if (!_isSelectionMode) _buildFilterButton(context),
                if (!_isSelectionMode && filteredUnifiedItems.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => _showCreatePlaylistDialog(context),
                    icon: const Icon(Icons.add, size: 20),
                    label: Text(context.l10n.collectionCreatePlaylist),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ),

        if (filteredUnifiedItems.isNotEmpty && filterMode == 'singles')
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: wideListInset(context)),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final item = filteredUnifiedItems[index];
                return KeyedSubtree(
                  key: ValueKey(item.id),
                  child: _buildUnifiedLibraryItem(
                    context,
                    item,
                    colorScheme,
                    localNavigationItems: localNavigationItems,
                    localNavigationIndex:
                        localNavigationIndexByUnifiedId[item.id],
                    libraryItems: filteredUnifiedItems,
                  ),
                );
              }, childCount: filteredUnifiedItems.length),
            ),
          ),

        if (totalTrackCount == 0 &&
            (filterMode != 'albums' || filteredGroupedLocalAlbums.isEmpty) &&
            (filterMode != 'playlists' || playlistIndexes.isEmpty) &&
            !showFilteringIndicator &&
            !isPageLoading)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _buildEmptyState(context, colorScheme, filterMode),
          )
        else if (isPageLoading)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ),
          ),

        if (totalTrackCount > 0 ||
            (filterMode == 'albums' && filteredGroupedLocalAlbums.isNotEmpty) ||
            (filterMode == 'playlists' && playlistIndexes.isNotEmpty))
          SliverToBoxAdapter(
            child: SizedBox(height: _isSelectionMode ? 100 : 16),
          ),
        const NavBarSliverSpacer(),
      ],
    );

    final scrollAwareContent = NotificationListener<ScrollNotification>(
      onNotification: (notification) => _handleLibraryScrollNotification(
        notification: notification,
        filterMode: filterMode,
        hasMoreLibrary: hasMoreLibrary,
        isPageLoading: isPageLoading,
      ),
      child: content,
    );

    {
      return LibraryFastScroller(
        bottomPadding: context.navBarBottomInset,
        labelAt: (fraction) => filteredUnifiedItems.isEmpty
            ? null
            : sectionLabel(
                filteredUnifiedItems[(fraction *
                        (filteredUnifiedItems.length - 1))
                    .round()],
              ),
        child: scrollAwareContent,
      );
    }
  }

  Widget _buildEmptyState(
    BuildContext context,
    ColorScheme colorScheme,
    String filterMode,
  ) {
    String message;
    String subtitle;
    IconData icon;

    switch (filterMode) {
      case 'albums':
        message = context.l10n.queueEmptyAlbums;
        subtitle = context.l10n.queueEmptyAlbumsSubtitle;
        icon = Icons.album;
        break;
      case 'singles':
        message = context.l10n.queueEmptySingles;
        subtitle = context.l10n.queueEmptySinglesSubtitle;
        icon = Icons.music_note;
        break;
      case 'playlists':
        message = context.l10n.collectionNoPlaylistsYet;
        subtitle = context.l10n.queueEmptyPlaylistsSubtitle;
        icon = Icons.queue_music;
        break;
      default:
        message = context.l10n.queueEmptyHistory;
        subtitle = context.l10n.queueEmptyHistorySubtitle;
        icon = Icons.history;
    }

    return EmptyState(
      icon: icon,
      title: message,
      message: subtitle,
      // Every empty branch here means "you have not downloaded anything of
      // this kind yet", so the way forward is always search.
      action: FilledButton.icon(
        onPressed: () => ShellNavigationService.requestTab(ShellTab.home),
        icon: const Icon(Icons.search),
        label: Text(context.l10n.navHome),
      ),
    );
  }

  Widget _buildLocalAlbumGridItem(
    BuildContext context,
    _GroupedLocalAlbum album,
    ColorScheme colorScheme,
  ) {
    return LocalLibraryArtworkBuilder(
      coverPath: album.coverPath,
      filePath: album.sampleFilePath,
      builder: (context, coverPath) => _buildAlbumGridItemCore(
        context: context,
        albumName: album.albumName,
        artistName: album.artistName,
        trackCount: album.displayTrackCount,
        completeness: album.completeness,
        colorScheme: colorScheme,
        coverWidget: coverPath != null
            ? Image.file(
                File(coverPath),
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                cacheWidth: 300,
                cacheHeight: 300,
                errorBuilder: (context, error, stackTrace) =>
                    _albumPlaceholder(colorScheme),
              )
            : null,
        badgeColor: colorScheme.tertiaryContainer,
        badgeTextColor: colorScheme.onTertiaryContainer,
        badgeIcon: Icons.folder,
        onTap: () => _navigateToLocalAlbum(album),
      ),
    );
  }

  Widget _albumPlaceholder(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(Icons.album, color: colorScheme.onSurfaceVariant, size: 48),
      ),
    );
  }

  Widget _buildAlbumGridItemCore({
    required BuildContext context,
    required String albumName,
    required String artistName,
    required int trackCount,
    required ColorScheme colorScheme,
    required Widget? coverWidget,
    required Color badgeColor,
    required Color badgeTextColor,
    required IconData badgeIcon,
    required VoidCallback onTap,
    String? coverUrl,
    AlbumCompleteness? completeness,
  }) {
    final completenessLabel = completeness == null
        ? null
        : completeness.status == 'unknown'
        ? context.l10n.libraryAlbumCompletenessUnknown
        : completeness.expected == null
        ? context.l10n.libraryFilterIncompleteAlbums
        : context.l10n.libraryAlbumMissingTracks(
            completeness.present,
            completeness.expected!,
            completeness.expected! - completeness.present,
          );
    return Semantics(
      button: true,
      label: [
        context.l10n.a11yOpenAlbumByArtistTrackCount(
          albumName,
          artistName,
          trackCount,
        ),
        ?completenessLabel,
      ].join('. '),
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: coverWidget ?? _albumPlaceholder(colorScheme),
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Tooltip(
                      message:
                          completenessLabel ??
                          context.l10n.tracksCount(trackCount),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: badgeColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(badgeIcon, size: 12, color: badgeTextColor),
                            const SizedBox(width: 4),
                            Text(
                              completeness?.badge ?? '$trackCount',
                              style: TextStyle(
                                color: badgeTextColor,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              albumName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            ClickableArtistName(
              artistName: artistName,
              coverUrl: coverUrl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<UnifiedLibraryItem> _selectedItemsFromAll(
    List<UnifiedLibraryItem> allItems,
  ) {
    final itemsById = {for (final item in allItems) item.id: item};
    return _selectedIds
        .map((id) => itemsById[id])
        .whereType<UnifiedLibraryItem>()
        .toList(growable: false);
  }
}
