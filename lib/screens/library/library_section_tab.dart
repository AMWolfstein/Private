import 'package:sistrum/models/local_library_item.dart';
import 'package:sistrum/widgets/library/library_fast_scroller.dart';
import 'package:sistrum/widgets/library/library_section_list.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math' show Random;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:sistrum/widgets/primitives/app_alert_dialog.dart';
import 'package:sistrum/widgets/primitives/app_choice_chip.dart';
import 'package:sistrum/widgets/library/local_track_batch_actions.dart';
import 'package:sistrum/navigation/shell_navigation.dart';
import 'package:sistrum/widgets/status/error_card.dart';
import 'package:sistrum/theme/app_tokens.dart';
import 'package:sistrum/widgets/primitives/app_bottom_sheet.dart';
import 'package:sistrum/widgets/primitives/app_sliver_header.dart';
import 'package:sistrum/widgets/header/album_play_actions.dart'
    show AlbumPlayActions;
import 'package:sistrum/widgets/primitives/app_snack_bar.dart';
import 'package:sistrum/widgets/library/library_track_selection_bar.dart';
import 'package:sistrum/widgets/library/library_selection_playback_actions.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/utils/adaptive_layout.dart';
import 'package:sistrum/utils/nav_bar_inset.dart';
import 'package:sistrum/utils/file_access.dart';
import 'package:sistrum/utils/library_format_filters.dart';
import 'package:sistrum/utils/ordered_range_selection.dart';
import 'package:sistrum/models/track.dart';
import 'package:sistrum/models/unified_library_item.dart';
import 'package:sistrum/providers/library_collections_provider.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/providers/local_library_provider.dart';
import 'package:sistrum/providers/playback_provider.dart';
import 'package:sistrum/providers/music_player_provider.dart';
import 'package:sistrum/services/playback/music_player_service.dart';
import 'package:sistrum/services/library/library_database.dart';
import 'package:sistrum/services/library/album_completeness.dart';
import 'package:sistrum/widgets/library/batch_track_actions.dart';
import 'package:sistrum/widgets/library/local_song_row.dart';
import 'package:sistrum/widgets/library/local_song_menu.dart';
import 'package:sistrum/widgets/cached_cover_image.dart';
import 'package:sistrum/widgets/library/local_library_artwork_builder.dart';
import 'package:sistrum/screens/library/library_collection_tracks_screen.dart';
import 'package:sistrum/screens/library/local_album_screen.dart';
import 'package:sistrum/screens/library/app_library_screen.dart';
import 'package:sistrum/screens/library/library_browse_refresh_policy.dart';
import 'package:sistrum/navigation/detail_navigation.dart';
import 'package:sistrum/widgets/animation_utils.dart';
import 'package:sistrum/widgets/animation_indicators.dart';
import 'package:sistrum/widgets/selection/selection_bottom_bar.dart';
import 'package:sistrum/providers/library_database_provider.dart';

part 'library_section_tab_helpers.dart';
part 'library_section_tab_selection.dart';
part 'library_section_tab_navigation.dart';
part 'library_section_tab_collection_items.dart';
part 'library_section_tab_filter_widgets.dart';
part 'library_section_tab_album_grid.dart';
part 'library_section_tab_empty_state.dart';
part 'library_section_tab_batch_actions.dart';
part 'library_section_tab_item_widgets.dart';

class LibrarySectionTab extends ConsumerStatefulWidget {
  final String? librarySection;

  const LibrarySectionTab({super.key, this.librarySection});

  @override
  ConsumerState<LibrarySectionTab> createState() => _LibrarySectionTabState();
}

class _LibrarySectionTabState extends ConsumerState<LibrarySectionTab> {
  static const int _libraryPageSize = 300;

  static const double _libraryGridDefaultExtent = 126;

  // Version counter to trigger targeted cover image rebuilds
  // without rebuilding the entire widget tree via setState.

  bool _isSelectionMode = false;

  final Set<String> _selectedIds = {};
  String? _selectionAnchorId;
  final SelectionOverlayController _selectionOverlay =
      SelectionOverlayController();
  List<UnifiedLibraryItem> _selectionOverlayItems = const [];
  double _selectionOverlayBottomPadding = 0;

  /// Keeps the selection overlays hidden while a modal launched from the
  /// selection toolbar is open, so they don't reappear over its animation.
  bool _suppressSelectionOverlay = false;

  bool _isPlaylistSelectionMode = false;
  final Set<String> _selectedPlaylistIds = {};
  final SelectionOverlayController _playlistSelectionOverlay =
      SelectionOverlayController();
  List<UserPlaylistCollection> _playlistSelectionOverlayItems = const [];
  double _playlistSelectionOverlayBottomPadding = 0;
  String? _filterQuality;
  String? _filterFormat;
  String? _filterMetadata;
  String _sortMode = 'latest';
  final ValueNotifier<double> _libraryGridExtentNotifier = ValueNotifier(
    _libraryGridDefaultExtent,
  );
  double get _libraryGridExtent => _libraryGridExtentNotifier.value;

  final Map<String, int> _libraryPageOffsetByFilter = {};
  bool _libraryPageLoadScheduled = false;
  final Map<_LibraryBrowseCountsRequest, LibraryBrowseCounts>
  _browseLibraryCountsCache = {};
  final Map<_LibraryBrowsePageRequest, _LibraryBrowsePageData>
  _browseLibraryPageDataCache = {};

  // OPT-PERF-001: combined multi-page data is rebuilt per build otherwise,
  // which would defeat the page data's filtered-list memo. Reuse the combined
  // instance while its pages are the identical cached instances.
  List<_LibraryBrowsePageData>? _combinedLibraryBrowsePages;
  _LibraryBrowsePageData? _combinedLibraryBrowseData;

  double get _libraryAlbumGridExtent =>
      (_libraryGridExtent * 1.45).clamp(150.0, 300.0);

  /// setState is @protected, so the extension part files route rebuilds
  /// through this forwarder.
  void _setState(VoidCallback fn) => setState(fn);

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _libraryGridExtentNotifier.dispose();
    _hideSelectionOverlay();
    _hidePlaylistSelectionOverlay();
    super.dispose();
  }

  /// Plays every song matching the current filters and sort, in order or
  /// shuffled, paging through the library with the cursor the list uses.
  Future<void> _playAllSongs({bool shuffle = false}) async {
    final tracks = <Track>[];
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
          tracks.add(UnifiedLibraryItem.fromLocalLibrary(item).toTrack());
        }
        cursor = page.nextCursor;
      } while (cursor != null);
      if (tracks.isEmpty || !mounted) return;
      if (shuffle) tracks.shuffle(Random());
      await ref.read(musicPlayerControllerProvider).setShuffle(shuffle);
      await ref.read(playbackProvider.notifier).playTrackList(tracks);
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
    setState(() {
      if (hasMoreLibrary) {
        _libraryPageOffsetByFilter[filterMode] =
            _libraryPageOffsetFor(filterMode) + _libraryPageSize;
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
    for (var offset = 0; offset <= request.offset; offset += _libraryPageSize) {
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

  int get _activeFilterCount {
    int count = 0;
    if (_filterQuality != null) count++;
    if (_filterFormat != null) count++;
    if (_filterMetadata != null) count++;
    return count;
  }

  void _resetFilters() {
    setState(() {
      _filterQuality = null;
      _filterFormat = null;
      _filterMetadata = null;
      _sortMode = 'latest';
      _resetLibraryPaging();
    });
  }

  void _showFilterSheet(BuildContext context) {
    String? tempQuality = _filterQuality;
    String? tempFormat = _filterFormat;
    String? tempMetadata = _filterMetadata;
    String tempSortMode = _sortMode;

    showAppModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (context) => AppScrollableSheet(
        builder: (context, scrollController) => StatefulBuilder(
          builder: (context, setSheetState) {
            Widget metadataChip(String label, String? mode) => AppChoiceChip(
              label: Text(label),
              selected: tempMetadata == mode,
              onSelected: (_) => setSheetState(() => tempMetadata = mode),
            );

            Widget sortChip(String label, String mode) => AppChoiceChip(
              label: Text(label),
              selected: tempSortMode == mode,
              onSelected: (_) => setSheetState(() => tempSortMode = mode),
            );

            return AppBottomSheet(
              title: context.l10n.libraryFilterTitle,
              titleTrailing: TextButton(
                onPressed: () {
                  setSheetState(() {
                    tempQuality = null;
                    tempFormat = null;
                    tempMetadata = null;
                    tempSortMode = 'latest';
                  });
                },
                child: Text(context.l10n.libraryFilterReset),
              ),
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.libraryFilterQuality,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        AppChoiceChip(
                          label: Text(context.l10n.libraryFilterAll),
                          selected: tempQuality == null,
                          onSelected: (_) =>
                              setSheetState(() => tempQuality = null),
                        ),
                        AppChoiceChip(
                          label: Text(context.l10n.libraryFilterQualityHiRes),
                          selected: tempQuality == LibraryQualityFilter.hiRes,
                          onSelected: (_) => setSheetState(
                            () => tempQuality = LibraryQualityFilter.hiRes,
                          ),
                        ),
                        AppChoiceChip(
                          label: Text(context.l10n.libraryFilterQualityCD),
                          selected: tempQuality == LibraryQualityFilter.cd,
                          onSelected: (_) => setSheetState(
                            () => tempQuality = LibraryQualityFilter.cd,
                          ),
                        ),
                        AppChoiceChip(
                          label: Text(context.l10n.libraryFilterQualityLossy),
                          selected: tempQuality == LibraryQualityFilter.lossy,
                          onSelected: (_) => setSheetState(
                            () => tempQuality = LibraryQualityFilter.lossy,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    Text(
                      context.l10n.libraryFilterFormat,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        AppChoiceChip(
                          label: Text(context.l10n.libraryFilterAll),
                          selected: tempFormat == null,
                          onSelected: (_) =>
                              setSheetState(() => tempFormat = null),
                        ),
                        for (final format in libraryFormatFilterAliases.keys)
                          AppChoiceChip(
                            label: Text(switch (format) {
                              'm4a' => 'M4A / MP4',
                              'wv' => 'WavPack',
                              _ => format.toUpperCase(),
                            }),
                            selected: tempFormat == format,
                            onSelected: (_) =>
                                setSheetState(() => tempFormat = format),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    Text(
                      context.l10n.libraryFilterMetadata,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        metadataChip(context.l10n.libraryFilterAll, null),
                        metadataChip(
                          context.l10n.libraryFilterMetadataComplete,
                          'complete',
                        ),
                        metadataChip(
                          context.l10n.libraryFilterMetadataMissingAny,
                          'missing-any',
                        ),
                        metadataChip(
                          context.l10n.libraryFilterMetadataMissingYear,
                          'missing-year',
                        ),
                        metadataChip(
                          context.l10n.libraryFilterMetadataMissingGenre,
                          'missing-genre',
                        ),
                        metadataChip(
                          context.l10n.libraryFilterMetadataMissingAlbumArtist,
                          'missing-album-artist',
                        ),
                        metadataChip(
                          context.l10n.libraryFilterMetadataMissingTrackNumber,
                          'missing-track-number',
                        ),
                        metadataChip(
                          context.l10n.libraryFilterMetadataMissingDiscNumber,
                          'missing-disc-number',
                        ),
                        metadataChip(
                          context.l10n.libraryFilterMetadataMissingArtist,
                          'missing-artist',
                        ),
                        metadataChip(
                          context.l10n.libraryFilterMetadataIncorrectIsrcFormat,
                          'incorrect-isrc-format',
                        ),
                        metadataChip(
                          context.l10n.libraryFilterMetadataMissingIsrc,
                          'missing-isrc',
                        ),
                        metadataChip(
                          context.l10n.libraryFilterMetadataMissingLabel,
                          'missing-label',
                        ),
                        metadataChip(
                          context.l10n.libraryFilterMetadataMissingLyrics,
                          'missing-lyrics',
                        ),
                        metadataChip(
                          context.l10n.libraryFilterMetadataHasReplayGain,
                          'has-replaygain',
                        ),
                        metadataChip(
                          context.l10n.libraryFilterMetadataMissingReplayGain,
                          'missing-replaygain',
                        ),
                        metadataChip(
                          context.l10n.libraryFilterIncompleteAlbums,
                          incompleteAlbumFilter,
                        ),
                        metadataChip(
                          context.l10n.libraryAlbumCompletenessUnknown,
                          unknownAlbumCompletenessFilter,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    Text(
                      context.l10n.libraryFilterSort,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        sortChip(
                          context.l10n.libraryFilterSortLatest,
                          'latest',
                        ),
                        sortChip(
                          context.l10n.libraryFilterSortOldest,
                          'oldest',
                        ),
                        // Playlists have no file size of their own.
                        if (widget.librarySection != 'playlists') ...[
                          sortChip(
                            context.l10n.libraryFilterSortSizeLargest,
                            'size-desc',
                          ),
                          sortChip(
                            context.l10n.libraryFilterSortSizeSmallest,
                            'size-asc',
                          ),
                        ],
                        sortChip(context.l10n.searchSortTitleAZ, 'a-z'),
                        sortChip(context.l10n.searchSortTitleZA, 'z-a'),
                        sortChip(context.l10n.searchSortArtistAZ, 'artist-asc'),
                        sortChip(
                          context.l10n.searchSortArtistZA,
                          'artist-desc',
                        ),
                        sortChip(
                          context.l10n.libraryFilterSortAlbumAsc,
                          'album-asc',
                        ),
                        sortChip(
                          context.l10n.libraryFilterSortAlbumDesc,
                          'album-desc',
                        ),
                        sortChip(
                          context.l10n.searchSortDateNewest,
                          'release-newest',
                        ),
                        sortChip(
                          context.l10n.searchSortDateOldest,
                          'release-oldest',
                        ),
                        sortChip(
                          context.l10n.libraryFilterSortGenreAsc,
                          'genre-asc',
                        ),
                        sortChip(
                          context.l10n.libraryFilterSortGenreDesc,
                          'genre-desc',
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      child: AppDialogAction(
                        filled: true,
                        onPressed: () {
                          setState(() {
                            _filterQuality = tempQuality;
                            _filterFormat = tempFormat;
                            _filterMetadata = tempMetadata;
                            _sortMode = tempSortMode;
                            _resetLibraryPaging();
                          });
                          Navigator.pop(context);
                        },
                        child: Text(context.l10n.libraryFilterApply),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.librarySection == null) {
      return AppLibraryScreen(
        onOpenSection: (section) => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                Scaffold(body: LibrarySectionTab(librarySection: section)),
          ),
        ),
      );
    }

    ref.listen<int>(
      localLibraryProvider.select((state) => state.loadedIndexVersion),
      (previous, next) {
        if (previous == null || previous == next) return;
        // Keep stale rows visible until the refreshed query replaces them.
        _resetLibraryOffsets();
        if (mounted) setState(() {});
      },
    );

    final localLibraryTotalCount = ref.watch(
      localLibraryProvider.select((state) => state.totalCount),
    );
    // Watch with selector on key fields to reduce unnecessary rebuilds.
    // LibraryCollectionsState doesn't implement == so watching without
    // selector rebuilds on every provider notification.
    ref.watch(
      libraryCollectionsProvider.select(
        (s) => (
          s.lovedCount,
          s.favoriteArtistCount,
          s.playlistCount,
          s.hasPlaylistTracks,
          s.isLoaded,
          // The playlist rows render names, covers, counts and order from the
          // state; reloading the playlists list must rebuild them.
          s.playlists,
        ),
      ),
    );
    final collectionState = ref.read(libraryCollectionsProvider);
    final String libraryFilterMode =
        widget.librarySection ??
        ref.watch<String>(settingsProvider.select((s) => s.libraryFilterMode));
    final colorScheme = Theme.of(context).colorScheme;
    final countsRequest = _LibraryBrowseCountsRequest(
      filterQuality: _filterQuality,
      filterFormat: _filterFormat,
      filterMetadata: _filterMetadata,
    );
    final countsValue = ref.watch(_browseLibraryCountsProvider(countsRequest));
    final queueCounts = _resolveLibraryBrowseCounts(countsValue, countsRequest);

    _LibraryBrowsePageRequest pageRequest(String filterMode) {
      final offset = _libraryPageOffsetFor(filterMode);
      final baseRequest = _LibraryBrowsePageRequest(
        filterMode: filterMode,
        limit: _libraryPageSize,
        offset: offset,
        filterQuality: _filterQuality,
        filterFormat: _filterFormat,
        filterMetadata: _filterMetadata,
        sortMode: _sortMode,
      );
      if (offset == 0) return baseRequest;
      final previousPage = _cachedLibraryBrowsePageAt(
        baseRequest,
        offset - _libraryPageSize,
      );
      return _LibraryBrowsePageRequest(
        filterMode: baseRequest.filterMode,
        limit: baseRequest.limit,
        offset: baseRequest.offset,
        filterQuality: baseRequest.filterQuality,
        filterFormat: baseRequest.filterFormat,
        filterMetadata: baseRequest.filterMetadata,
        sortMode: baseRequest.sortMode,
        cursor: previousPage?.nextCursor,
      );
    }

    final activePageRequest = pageRequest(libraryFilterMode);
    final activePageValue = ref.watch(
      _browseLibraryPageProvider(activePageRequest),
    );

    _LibraryBrowsePageData pageData(String filterMode) {
      final request = filterMode == libraryFilterMode
          ? activePageRequest
          : pageRequest(filterMode);
      return _resolveLibraryBrowsePageData(
        filterMode == libraryFilterMode ? activePageValue : null,
        request,
      );
    }

    _FilterContentData getFilterData(String filterMode) {
      return pageData(filterMode).toFilterContentData(
        collectionState,
        includePlaylistTracks: widget.librarySection == 'all',
        totalTrackCount: switch (filterMode) {
          'singles' => queueCounts.singleTrackCount,
          'albums' || 'playlists' => 0,
          _ => queueCounts.allTrackCount,
        },
        totalAlbumCount: filterMode == 'albums' ? queueCounts.albumCount : null,
      );
    }

    final currentPageData = pageData(libraryFilterMode);
    final currentLoadedCount = libraryFilterMode == 'albums'
        ? currentPageData.groupedLocalAlbums.length
        : currentPageData.items.length;
    final currentTotalCount = switch (libraryFilterMode) {
      'albums' => queueCounts.albumCount,
      'singles' => queueCounts.singleTrackCount,
      'playlists' => 0,
      _ => queueCounts.allTrackCount,
    };
    final hasMoreLibrary = currentLoadedCount < currentTotalCount;
    final isLibraryPageLoading =
        countsValue.isLoading || activePageValue.isLoading;
    final hasAnyLibraryItems =
        queueCounts.allTrackCount > 0 || queueCounts.albumCount > 0;
    final hasLibraryContent = localLibraryTotalCount > 0;
    final libraryError = countsValue.hasError
        ? countsValue.error
        : activePageValue.error;
    final shouldShowLibraryControls =
        hasLibraryContent || hasAnyLibraryItems || libraryError != null;

    // PERF-201: the active filter's page data is only needed in selection
    // mode; other builds must not copy and regroup it.
    if (_isSelectionMode || _isPlaylistSelectionMode) {
      final selectionItems = getFilterData(
        libraryFilterMode,
      ).filteredUnifiedItems;
      final bottomPadding = MediaQuery.paddingOf(context).bottom;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_isSelectionMode) {
          _syncSelectionOverlay(
            items: selectionItems,
            bottomPadding: bottomPadding,
            isLoading: isLibraryPageLoading,
          );
        }
        if (_isPlaylistSelectionMode) {
          _syncPlaylistSelectionOverlay(
            playlists: collectionState.playlists,
            bottomPadding: bottomPadding,
          );
        }
      });
    }

    return PopScope(
      canPop: !_isSelectionMode && !_isPlaylistSelectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          if (_isPlaylistSelectionMode) {
            _exitPlaylistSelectionMode();
          } else if (_isSelectionMode) {
            _exitSelectionMode();
          }
        }
      },
      child: Stack(
        children: [
          // ScrollConfiguration disables stretch overscroll to fix _StretchController exception
          // This is a known Flutter issue with NestedScrollView + Material 3 stretch indicator
          ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(overscroll: false),
            child: NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                AppSliverHeader.page(
                  title: widget.librarySection == 'playlists'
                      ? context.l10n.searchPlaylists
                      : context.l10n.searchSongs,
                ),

                if (shouldShowLibraryControls &&
                    widget.librarySection != 'playlists')
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: AlbumPlayActions(
                        playLabel: context.l10n.tooltipPlay,
                        shuffleTooltip: context.l10n.actionShuffle,
                        onPlay: _playAllSongs,
                        onShuffle: () => _playAllSongs(shuffle: true),
                      ),
                    ),
                  ),

                ...[],
              ],
              body: _buildFilterContent(
                context: context,
                colorScheme: colorScheme,
                filterMode: libraryFilterMode,
                filterData: getFilterData(libraryFilterMode),
                collectionState: collectionState,
                hasMoreLibrary: hasMoreLibrary,
                isPageLoading: isLibraryPageLoading,
                error: libraryError,
                onRetry: () {
                  _resetLibraryOffsets();
                  ref.invalidate(_browseLibraryCountsProvider(countsRequest));
                  ref.invalidate(_browseLibraryPageProvider(activePageRequest));
                },
              ),
            ),
          ), // ScrollConfiguration
        ],
      ),
    );
  }
}

class _AnimatedLibrarySliverGrid extends StatefulWidget {
  final double maxCrossAxisExtent;
  final double mainAxisSpacing;
  final double crossAxisSpacing;
  final double childAspectRatio;
  final SliverChildDelegate delegate;
  final ValueListenable<double>? extentListenable;
  final double extentScale;
  final double? minExtent;
  final double? maxExtent;

  const _AnimatedLibrarySliverGrid({
    required this.maxCrossAxisExtent,
    required this.mainAxisSpacing,
    required this.crossAxisSpacing,
    required this.childAspectRatio,
    required this.delegate,
    this.extentListenable,
    this.extentScale = 1,
    this.minExtent,
    this.maxExtent,
  });

  @override
  State<_AnimatedLibrarySliverGrid> createState() =>
      _AnimatedLibrarySliverGridState();
}

class _AnimatedLibrarySliverGridState extends State<_AnimatedLibrarySliverGrid>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _curve;
  late double _beginExtent;
  late double _endExtent;

  @override
  void initState() {
    super.initState();
    _beginExtent = widget.maxCrossAxisExtent;
    _endExtent = widget.maxCrossAxisExtent;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 130),
    )..value = 1;
    _curve = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _beginExtent = _endExtent = widget.maxCrossAxisExtent;
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant _AnimatedLibrarySliverGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((widget.maxCrossAxisExtent - _endExtent).abs() < 0.1) return;
    _beginExtent = _currentExtent;
    _endExtent = widget.maxCrossAxisExtent;
    if (widget.extentListenable != null ||
        MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward(from: 0);
    }
  }

  double get _currentExtent =>
      _beginExtent + ((_endExtent - _beginExtent) * _curve.value);

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final extentListenable = widget.extentListenable;
    if (extentListenable != null) {
      return ValueListenableBuilder<double>(
        valueListenable: extentListenable,
        builder: (context, extent, child) => _grid(
          (extent * widget.extentScale).clamp(
            widget.minExtent ?? 0,
            widget.maxExtent ?? double.infinity,
          ),
        ),
      );
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      return _grid(widget.maxCrossAxisExtent);
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => _grid(_currentExtent),
    );
  }

  Widget _grid(double extent) => SliverGrid(
    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: extent,
      mainAxisSpacing: widget.mainAxisSpacing,
      crossAxisSpacing: widget.crossAxisSpacing,
      childAspectRatio: widget.childAspectRatio,
    ),
    delegate: widget.delegate,
  );
}
