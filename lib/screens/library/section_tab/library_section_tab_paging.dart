part of 'library_section_tab.dart';

extension _LibrarySectionTabPaging on _LibrarySectionTabState {
  /// Plays every song matching the current filters and sort, in order or
  /// shuffled, paging through the library with the cursor the list uses.
  Future<void> _playAllSongs({bool shuffle = false}) async {
    final clock = Stopwatch()..start();
    final items = <LocalLibraryItem>[];
    LibraryBrowseDbCursor? cursor;
    try {
      do {
        final page = await ref
            .read(libraryDatabaseProvider)
            .getBrowseTrackPage(
              LibraryBrowseDbQuery(
                limit: 500,
                quality: _filterQuality,
                format: _filterFormat,
                metadata: _filterMetadata,
                sortMode: _sortMode,
                cursor: cursor,
              ),
            );
        for (final row in page.rows) {
          if (row['source'] != 'local') continue;
          final item = LocalLibraryItem.fromEnvelope(row);
          if (isCueVirtualPath(item.filePath)) continue;
          items.add(item);
        }
        cursor = page.nextCursor;
      } while (cursor != null);
      _librarySectionLog.d(
        'Read ${items.length} songs for play all in ${clock.elapsedMilliseconds} ms (shuffle: $shuffle)',
      );
      if (items.isEmpty || !mounted) return;
      if (shuffle) items.shuffle(Random());
      await ref.read(musicPlayerControllerProvider).setShuffle(shuffle);
      await ref.read(playbackProvider.notifier).playLocalItems(items);
      _librarySectionLog.d(
        'Play all started after ${clock.elapsedMilliseconds} ms (shuffle: $shuffle)',
      );
    } catch (e) {
      if (mounted) showCannotOpenFileSnackBar(context, e);
    }
  }

  int _libraryPageOffsetFor(String filterMode) =>
      _libraryPageOffsetByFilter[filterMode] ?? 0;

  void _resetLibraryOffsets() {
    _libraryPageOffsetByFilter.clear();
  }

  void _resetLibraryPaging() {
    _resetLibraryOffsets();
    _browseLibraryPageDataCache.clear();
    _isSelectionMode = false;
    _selectedIds.clear();
    _selectionAnchorId = null;
    _hideSelectionOverlay();
  }

  void _loadMoreLibraryItems({
    required String filterMode,
    required bool hasMoreLibrary,
  }) {
    if (_libraryPageLoadScheduled) return;
    _libraryPageLoadScheduled = true;
    _setState(() {
      if (hasMoreLibrary) {
        _libraryPageOffsetByFilter[filterMode] =
            _libraryPageOffsetFor(filterMode) +
            _LibrarySectionTabState._libraryPageSize;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _libraryPageLoadScheduled = false;
    });
  }

  LibraryBrowseCounts _resolveLibraryBrowseCounts(
    AsyncValue<LibraryBrowseCounts> value,
    _LibraryBrowseCountsRequest request, {
    LibraryBrowseCounts? nonEmptyFallback,
  }) {
    return value.maybeWhen(
      data: (counts) {
        final cached = _browseLibraryCountsCache[request];
        final resolved = resolveLibraryBrowseCountsSnapshot(
          current: counts,
          cached: cached,
          nonEmptyFallback: nonEmptyFallback,
        );
        _browseLibraryCountsCache[request] = resolved;
        _trimLibraryBrowseCountsCache();
        return resolved;
      },
      orElse: () =>
          _browseLibraryCountsCache[request] ??
          nonEmptyFallback ??
          const LibraryBrowseCounts(
            allTrackCount: 0,
            albumCount: 0,
            singleTrackCount: 0,
          ),
    );
  }

  /// [nonEmptyFallback] is non-null when an in-memory snapshot is available;
  /// it is only invoked when no cached or live page has content.
  _LibraryBrowsePageData _resolveLibraryBrowsePageData(
    AsyncValue<_LibraryBrowsePageData>? value,
    _LibraryBrowsePageRequest request, {
    _LibraryBrowsePageData Function()? nonEmptyFallback,
  }) {
    void storePage(_LibraryBrowsePageData data) {
      final cached = _cachedLibraryBrowsePageAt(request, request.offset);
      if (shouldRetainLibraryBrowsePageSnapshot(
        currentIsEmpty: data.isEmpty,
        cachedHasContent: cached != null && !cached.isEmpty,
        nonEmptyFallbackAvailable: nonEmptyFallback != null,
      )) {
        return;
      }
      final staleRequests = _browseLibraryPageDataCache.keys
          .where(
            (cachedRequest) =>
                cachedRequest.offset == request.offset &&
                cachedRequest != request &&
                _sameLibraryBrowsePageScope(cachedRequest, request),
          )
          .toList(growable: false);
      for (final staleRequest in staleRequests) {
        _browseLibraryPageDataCache.remove(staleRequest);
      }
      _browseLibraryPageDataCache[request] = data;
      _trimLibraryBrowsePageDataCache(protectedRequest: request);
    }

    final liveData = value?.asData?.value;
    if (liveData != null) {
      storePage(liveData);
    }

    final pages = <_LibraryBrowsePageData>[];
    for (
      var offset = 0;
      offset <= request.offset;
      offset += _LibrarySectionTabState._libraryPageSize
    ) {
      final page = _cachedLibraryBrowsePageAt(request, offset);
      if (page != null) pages.add(page);
    }

    final combined = _combinedLibraryBrowseDataFor(pages);
    if (combined.isEmpty && nonEmptyFallback != null) {
      return nonEmptyFallback();
    }
    return combined;
  }

  /// Reuses the combined instance while its pages are the identical cached
  /// instances, keeping the filtered-list memo stable across builds.
  _LibraryBrowsePageData _combinedLibraryBrowseDataFor(
    List<_LibraryBrowsePageData> pages,
  ) {
    final cachedKey = _combinedLibraryBrowsePages;
    var identicalPages = cachedKey != null && cachedKey.length == pages.length;
    if (identicalPages) {
      for (var i = 0; i < pages.length; i++) {
        if (!identical(cachedKey[i], pages[i])) {
          identicalPages = false;
          break;
        }
      }
    }
    if (identicalPages) return _combinedLibraryBrowseData!;
    final combined = _LibraryBrowsePageData.combine(pages);
    _combinedLibraryBrowsePages = List.of(pages);
    _combinedLibraryBrowseData = combined;
    return combined;
  }

  void _trimLibraryBrowseCountsCache() {
    const maxCountEntries = 24;
    while (_browseLibraryCountsCache.length > maxCountEntries) {
      _browseLibraryCountsCache.remove(_browseLibraryCountsCache.keys.first);
    }
  }

  bool _isProtectedLibraryBrowsePage(
    _LibraryBrowsePageRequest request,
    _LibraryBrowsePageRequest protectedRequest,
  ) {
    return _sameLibraryBrowsePageScope(request, protectedRequest) &&
        request.limit == protectedRequest.limit &&
        request.offset <= protectedRequest.offset;
  }

  bool _sameLibraryBrowsePageScope(
    _LibraryBrowsePageRequest a,
    _LibraryBrowsePageRequest b,
  ) {
    return a.filterMode == b.filterMode &&
        a.limit == b.limit &&
        a.filterQuality == b.filterQuality &&
        a.filterFormat == b.filterFormat &&
        a.filterMetadata == b.filterMetadata &&
        a.sortMode == b.sortMode;
  }

  _LibraryBrowsePageData? _cachedLibraryBrowsePageAt(
    _LibraryBrowsePageRequest request,
    int offset,
  ) {
    for (final entry in _browseLibraryPageDataCache.entries) {
      if (entry.key.offset == offset &&
          _sameLibraryBrowsePageScope(entry.key, request)) {
        return entry.value;
      }
    }
    return null;
  }

  void _trimLibraryBrowsePageDataCache({
    required _LibraryBrowsePageRequest protectedRequest,
  }) {
    const maxPageEntries = 96;
    while (_browseLibraryPageDataCache.length > maxPageEntries) {
      final removableKey = _browseLibraryPageDataCache.keys
          .where(
            (request) =>
                !_isProtectedLibraryBrowsePage(request, protectedRequest),
          )
          .firstOrNull;
      if (removableKey == null) break;
      _browseLibraryPageDataCache.remove(removableKey);
    }
  }

  bool _handleLibraryScrollNotification({
    required ScrollNotification notification,
    required String filterMode,
    required bool hasMoreLibrary,
    required bool isPageLoading,
  }) {
    if (isPageLoading || !hasMoreLibrary || notification.depth != 0) {
      return false;
    }

    final metrics = notification.metrics;
    if (metrics.maxScrollExtent <= 0) return false;
    final threshold = metrics.maxScrollExtent * 0.7;
    final nearEnd =
        metrics.pixels >= threshold ||
        metrics.extentAfter <= metrics.viewportDimension * 1.5;
    if (!nearEnd) return false;

    _loadMoreLibraryItems(
      filterMode: filterMode,
      hasMoreLibrary: hasMoreLibrary,
    );
    return false;
  }
}
