part of 'queue_tab.dart';

class _GroupedLocalAlbum {
  final String albumKey;
  final String albumName;
  final String artistName;
  final String? coverPath;
  final String sampleFilePath;
  final List<LocalLibraryItem> tracks;
  final int? trackCount;
  final AlbumCompleteness? completeness;
  final DateTime latestScanned;
  final String searchKey;

  _GroupedLocalAlbum({
    required this.albumKey,
    required this.albumName,
    required this.artistName,
    this.coverPath,
    required this.sampleFilePath,
    required this.tracks,
    this.trackCount,
    this.completeness,
    required this.latestScanned,
  }) : searchKey = '${albumName.toLowerCase()}|${artistName.toLowerCase()}';

  String get key => albumKey;

  int get displayTrackCount => trackCount ?? tracks.length;
}

class _FilterContentData {
  final List<UnifiedLibraryItem> unifiedItems;
  final List<UnifiedLibraryItem> filteredUnifiedItems;
  final List<_GroupedLocalAlbum> filteredGroupedLocalAlbums;
  final bool showFilteringIndicator;
  final int? totalTrackCountOverride;
  final int? totalAlbumCountOverride;

  const _FilterContentData({
    required this.unifiedItems,
    required this.filteredUnifiedItems,
    required this.filteredGroupedLocalAlbums,
    required this.showFilteringIndicator,
    this.totalTrackCountOverride,
    this.totalAlbumCountOverride,
  });

  int get totalTrackCount =>
      totalTrackCountOverride ?? filteredUnifiedItems.length;
  int get totalAlbumCount =>
      totalAlbumCountOverride ?? filteredGroupedLocalAlbums.length;
}

class _QueueLibraryPageRequest {
  final String filterMode;
  final int limit;
  final int offset;
  final String? filterSource;
  final String? filterQuality;
  final String? filterFormat;
  final String? filterMetadata;
  final String sortMode;
  final bool localLibraryEnabled;
  final QueueLibraryDbCursor? cursor;

  const _QueueLibraryPageRequest({
    required this.filterMode,
    required this.limit,
    required this.offset,
    required this.filterSource,
    required this.filterQuality,
    required this.filterFormat,
    required this.filterMetadata,
    required this.sortMode,
    required this.localLibraryEnabled,
    this.cursor,
  });

  QueueLibraryDbQuery toDbQuery() => QueueLibraryDbQuery(
    limit: limit,
    offset: offset,
    filterMode: filterMode,
    source: filterSource,
    quality: filterQuality,
    format: filterFormat,
    metadata: filterMetadata,
    sortMode: sortMode,
    includeLocal: localLibraryEnabled,
    cursor: cursor,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _QueueLibraryPageRequest &&
          filterMode == other.filterMode &&
          limit == other.limit &&
          offset == other.offset &&
          filterSource == other.filterSource &&
          filterQuality == other.filterQuality &&
          filterFormat == other.filterFormat &&
          filterMetadata == other.filterMetadata &&
          sortMode == other.sortMode &&
          localLibraryEnabled == other.localLibraryEnabled &&
          cursor == other.cursor;

  @override
  int get hashCode => Object.hash(
    filterMode,
    limit,
    offset,
    filterSource,
    filterQuality,
    filterFormat,
    filterMetadata,
    sortMode,
    localLibraryEnabled,
    cursor,
  );
}

class _QueueLibraryCountsRequest {
  final String? filterSource;
  final String? filterQuality;
  final String? filterFormat;
  final String? filterMetadata;
  final bool localLibraryEnabled;

  const _QueueLibraryCountsRequest({
    required this.filterSource,
    required this.filterQuality,
    required this.filterFormat,
    required this.filterMetadata,
    required this.localLibraryEnabled,
  });

  QueueLibraryDbQuery toDbQuery() => QueueLibraryDbQuery(
    source: filterSource,
    quality: filterQuality,
    format: filterFormat,
    metadata: filterMetadata,
    includeLocal: localLibraryEnabled,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _QueueLibraryCountsRequest &&
          filterSource == other.filterSource &&
          filterQuality == other.filterQuality &&
          filterFormat == other.filterFormat &&
          filterMetadata == other.filterMetadata &&
          localLibraryEnabled == other.localLibraryEnabled;

  @override
  int get hashCode => Object.hash(
    filterSource,
    filterQuality,
    filterFormat,
    filterMetadata,
    localLibraryEnabled,
  );
}

class _QueueLibraryPageData {
  final List<UnifiedLibraryItem> items;
  final List<LocalLibraryItem> localItems;
  final List<_GroupedLocalAlbum> groupedLocalAlbums;
  final QueueLibraryDbCursor? nextCursor;

  // Memo of the playlist-excluded list for the newest collections state.
  LibraryCollectionsState? _filteredFrom;
  List<UnifiedLibraryItem>? _filteredItems;

  _QueueLibraryPageData({
    this.items = const [],
    this.localItems = const [],
    this.groupedLocalAlbums = const [],
    this.nextCursor,
  });

  bool get isEmpty =>
      items.isEmpty && localItems.isEmpty && groupedLocalAlbums.isEmpty;

  factory _QueueLibraryPageData.combine(List<_QueueLibraryPageData> pages) {
    if (pages.isEmpty) return _QueueLibraryPageData();
    if (pages.length == 1) return pages.first;

    final items = <UnifiedLibraryItem>[];
    final localItems = <LocalLibraryItem>[];
    final groupedLocalAlbums = <_GroupedLocalAlbum>[];

    for (final page in pages) {
      items.addAll(page.items);
      localItems.addAll(page.localItems);
      groupedLocalAlbums.addAll(page.groupedLocalAlbums);
    }

    return _QueueLibraryPageData(
      items: items,
      localItems: localItems,
      groupedLocalAlbums: groupedLocalAlbums,
      nextCursor: pages.last.nextCursor,
    );
  }

  _FilterContentData toFilterContentData(
    LibraryCollectionsState collectionState, {
    int? totalTrackCount,
    int? totalAlbumCount,
    bool includePlaylistTracks = false,
  }) {
    // OPT-PERF-001: reuse the filtered list while the collection state is the
    // same instance, so section grouping does not rerun on every build.
    List<UnifiedLibraryItem> filteredItems;
    if (includePlaylistTracks || !collectionState.hasPlaylistTracks) {
      filteredItems = items;
    } else if (identical(collectionState, _filteredFrom)) {
      filteredItems = _filteredItems!;
    } else {
      filteredItems = items
          .where(
            (item) => !collectionState.isTrackInAnyPlaylist(item.collectionKey),
          )
          .toList(growable: false);
      _filteredFrom = collectionState;
      _filteredItems = filteredItems;
    }
    return _FilterContentData(
      unifiedItems: items,
      filteredUnifiedItems: filteredItems,
      filteredGroupedLocalAlbums: groupedLocalAlbums,
      showFilteringIndicator: false,
      totalTrackCountOverride: totalTrackCount,
      totalAlbumCountOverride: totalAlbumCount,
    );
  }
}

final _queueLibraryPageProvider = FutureProvider.autoDispose
    .family<_QueueLibraryPageData, _QueueLibraryPageRequest>((
      ref,
      request,
    ) async {
      if (request.localLibraryEnabled) {
        ref.watch(
          localLibraryProvider.select((state) => state.loadedIndexVersion),
        );
      }
      // Playlists render from libraryCollectionsProvider, not the DB.
      if (request.filterMode == 'playlists') {
        return _QueueLibraryPageData();
      }
      final dbQuery = request.toDbQuery();
      if (request.filterMode == 'albums') {
        final page = await LibraryDatabase.instance.getQueueAlbumPageResult(
          dbQuery,
        );
        final rows = page.rows;
        final groupedLocalAlbums = <_GroupedLocalAlbum>[];
        for (final row in rows) {
          if (row['queue_source'] != 'local') continue;
          final latestMillis = (row['sort_added'] as num?)?.toInt() ?? 0;
          final latest = DateTime.fromMillisecondsSinceEpoch(latestMillis);
          groupedLocalAlbums.add(
            _GroupedLocalAlbum(
              albumKey: row['album_key'] as String? ?? '',
              albumName: row['album_name'] as String? ?? '',
              artistName: row['artist_name'] as String? ?? '',
              coverPath: row['cover_path'] as String?,
              sampleFilePath: row['sample_file_path'] as String? ?? '',
              tracks: const [],
              trackCount: (row['track_count'] as num?)?.toInt() ?? 0,
              completeness: AlbumCompleteness.fromRow(row),
              latestScanned: latest,
            ),
          );
        }
        return _QueueLibraryPageData(
          groupedLocalAlbums: groupedLocalAlbums,
          nextCursor: page.nextCursor,
        );
      }

      final page = await LibraryDatabase.instance.getQueueTrackPageResult(
        dbQuery,
      );
      final rows = page.rows;
      final items = <UnifiedLibraryItem>[];
      final localItems = <LocalLibraryItem>[];
      for (final row in rows) {
        if (row['source'] != 'local') continue;
        final itemJson = Map<String, dynamic>.from(row['item'] as Map);
        final item = LocalLibraryItem.fromJson(itemJson);
        localItems.add(item);
        items.add(UnifiedLibraryItem.fromLocalLibrary(item));
      }
      return _QueueLibraryPageData(
        items: items,
        localItems: localItems,
        nextCursor: page.nextCursor,
      );
    });

final _queueLibraryCountsProvider = FutureProvider.autoDispose
    .family<QueueLibraryCounts, _QueueLibraryCountsRequest>((
      ref,
      request,
    ) async {
      if (request.localLibraryEnabled) {
        ref.watch(
          localLibraryProvider.select((state) => state.loadedIndexVersion),
        );
      }
      return LibraryDatabase.instance.getQueueCounts(request.toDbQuery());
    });
