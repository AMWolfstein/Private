part of 'library_section_tab.dart';

extension _LibrarySectionTabFilterWidgets on _LibrarySectionTabState {
  /// Count and independently wrapping actions keep their full text and targets.
  Widget _countHeaderRow(
    BuildContext context,
    String countText,
    List<Widget> actions,
  ) {
    // A Wrap instead of a FittedBox: at large text the actions move to their
    // own line instead of shrinking below a 48dp target and below 1x text.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 4,
        children: [
          Text(
            countText,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          ...actions,
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
    required Object? error,
    required VoidCallback onRetry,
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

    // Indexes into collectionState.playlists for the 'playlists' view.
    final playlistIndexes = <int>[];
    if (filterMode == 'playlists') {
      for (var i = 0; i < collectionState.playlists.length; i++) {
        playlistIndexes.add(i);
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
        if (error != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: ErrorCard(
                error: error.toString(),
                colorScheme: colorScheme,
                onRetry: onRetry,
              ),
            ),
          ),

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
                ref.read(localLibraryProvider).totalCount > 0))
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
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverList.builder(
              itemCount: playlistIndexes.length,
              itemBuilder: (context, index) => _buildPlaylistCollectionRow(
                context: context,
                colorScheme: colorScheme,
                playlistIndex: playlistIndexes[index],
                collectionState: collectionState,
                filteredUnifiedItems: allFilteredUnifiedItems,
              ),
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
                    libraryItems: filteredUnifiedItems,
                  ),
                );
              }, childCount: filteredUnifiedItems.length),
            ),
          ),

        if (error == null &&
            totalTrackCount == 0 &&
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
