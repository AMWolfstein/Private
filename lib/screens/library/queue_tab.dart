import 'package:sistrum/widgets/library_fast_scroller.dart';
import 'package:sistrum/widgets/library_section_list.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math' show Random;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:sistrum/widgets/app_alert_dialog.dart';
import 'package:sistrum/widgets/app_choice_chip.dart';
import 'package:sistrum/services/local_track_batch_actions.dart';
import 'package:sistrum/services/shell_navigation_service.dart';
import 'package:sistrum/widgets/error_card.dart';
import 'package:sistrum/theme/app_tokens.dart';
import 'package:sistrum/widgets/app_bottom_sheet.dart';
import 'package:sistrum/widgets/app_sliver_header.dart';
import 'package:sistrum/widgets/album_detail_header.dart' show AlbumPlayActions;
import 'package:sistrum/widgets/app_snack_bar.dart';
import 'package:sistrum/widgets/library_track_selection_bar.dart';
import 'package:sistrum/widgets/library_selection_playback_actions.dart';
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
import 'package:sistrum/services/music_player_service.dart';
import 'package:sistrum/services/library_database.dart';
import 'package:sistrum/services/album_completeness.dart';
import 'package:sistrum/services/batch_track_actions.dart';
import 'package:sistrum/widgets/local_song_row.dart';
import 'package:sistrum/widgets/local_song_menu.dart';
import 'package:sistrum/widgets/cached_cover_image.dart';
import 'package:sistrum/widgets/local_library_artwork_builder.dart';
import 'package:sistrum/screens/library_tracks_folder_screen.dart';
import 'package:sistrum/screens/local_album_screen.dart';
import 'package:sistrum/screens/sistrum_library_screen.dart';
import 'package:sistrum/screens/queue_library_refresh_policy.dart';
import 'package:sistrum/utils/clickable_metadata.dart';
import 'package:sistrum/widgets/animation_utils.dart';
import 'package:sistrum/widgets/selection_bottom_bar.dart';

part 'queue_tab_helpers.dart';
part 'queue_tab_selection.dart';
part 'queue_tab_navigation.dart';
part 'queue_tab_collection_items.dart';
part 'queue_tab_filter_widgets.dart';
part 'queue_tab_batch_actions.dart';
part 'queue_tab_item_widgets.dart';

class QueueTab extends ConsumerStatefulWidget {
  final String? librarySection;

  const QueueTab({super.key, this.librarySection});

  @override
  ConsumerState<QueueTab> createState() => _QueueTabState();
}

class _QueueTabState extends ConsumerState<QueueTab> {
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
  final Map<_QueueLibraryCountsRequest, QueueLibraryCounts>
  _queueLibraryCountsCache = {};
  final Map<_QueueLibraryPageRequest, _QueueLibraryPageData>
  _queueLibraryPageDataCache = {};

  // OPT-PERF-001: combined multi-page data is rebuilt per build otherwise,
  // which would defeat the page data's filtered-list memo. Reuse the combined
  // instance while its pages are the identical cached instances.
  List<_QueueLibraryPageData>? _combinedQueueLibraryPages;
  _QueueLibraryPageData? _combinedQueueLibraryData;

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
    QueueLibraryDbCursor? cursor;
    try {
      do {
        final page = await LibraryDatabase.instance.getQueueTrackPageResult(
          QueueLibraryDbQuery(
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
          final item = LocalLibraryItem.fromJson(
            Map<String, dynamic>.from(row['item'] as Map),
          );
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
    _queueLibraryPageDataCache.clear();
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

  QueueLibraryCounts _resolveQueueLibraryCounts(
    AsyncValue<QueueLibraryCounts> value,
    _QueueLibraryCountsRequest request, {
    QueueLibraryCounts? nonEmptyFallback,
  }) {
    return value.maybeWhen(
      data: (counts) {
        final cached = _queueLibraryCountsCache[request];
        final resolved = resolveQueueLibraryCountsSnapshot(
          current: counts,
          cached: cached,
          activeDownloadFallback: nonEmptyFallback,
        );
        _queueLibraryCountsCache[request] = resolved;
        _trimQueueLibraryCountsCache();
        return resolved;
      },
      orElse: () =>
          _queueLibraryCountsCache[request] ??
          nonEmptyFallback ??
          const QueueLibraryCounts(
            allTrackCount: 0,
            albumCount: 0,
            singleTrackCount: 0,
          ),
    );
  }

  /// [nonEmptyFallback] is non-null when an in-memory snapshot is available;
  /// it is only invoked when no cached or live page has content.
  _QueueLibraryPageData _resolveQueueLibraryPageData(
    AsyncValue<_QueueLibraryPageData>? value,
    _QueueLibraryPageRequest request, {
    _QueueLibraryPageData Function()? nonEmptyFallback,
  }) {
    void storePage(_QueueLibraryPageData data) {
      final cached = _cachedQueueLibraryPageAt(request, request.offset);
      if (shouldRetainQueueLibraryPageSnapshot(
        currentIsEmpty: data.isEmpty,
        cachedHasContent: cached != null && !cached.isEmpty,
        activeDownloadFallbackAvailable: nonEmptyFallback != null,
      )) {
        return;
      }
      final staleRequests = _queueLibraryPageDataCache.keys
          .where(
            (cachedRequest) =>
                cachedRequest.offset == request.offset &&
                cachedRequest != request &&
                _sameQueueLibraryPageScope(cachedRequest, request),
          )
          .toList(growable: false);
      for (final staleRequest in staleRequests) {
        _queueLibraryPageDataCache.remove(staleRequest);
      }
      _queueLibraryPageDataCache[request] = data;
      _trimQueueLibraryPageDataCache(protectedRequest: request);
    }

    if (value != null) {
      final liveData = value.asData?.value;
      if (liveData != null) {
        storePage(liveData);
      }
      value.whenOrNull(data: storePage);
    }

    final pages = <_QueueLibraryPageData>[];
    for (var offset = 0; offset <= request.offset; offset += _libraryPageSize) {
      final page = _cachedQueueLibraryPageAt(request, offset);
      if (page != null) pages.add(page);
    }

    final combined = _combinedQueueLibraryDataFor(pages);
    if (combined.isEmpty && nonEmptyFallback != null) {
      return nonEmptyFallback();
    }
    return combined;
  }

  /// Reuses the combined instance while its pages are the identical cached
  /// instances, keeping the filtered-list memo stable across builds.
  _QueueLibraryPageData _combinedQueueLibraryDataFor(
    List<_QueueLibraryPageData> pages,
  ) {
    final cachedKey = _combinedQueueLibraryPages;
    var identicalPages = cachedKey != null && cachedKey.length == pages.length;
    if (identicalPages) {
      for (var i = 0; i < pages.length; i++) {
        if (!identical(cachedKey[i], pages[i])) {
          identicalPages = false;
          break;
        }
      }
    }
    if (identicalPages) return _combinedQueueLibraryData!;
    final combined = _QueueLibraryPageData.combine(pages);
    _combinedQueueLibraryPages = List.of(pages);
    _combinedQueueLibraryData = combined;
    return combined;
  }

  void _trimQueueLibraryCountsCache() {
    const maxCountEntries = 24;
    while (_queueLibraryCountsCache.length > maxCountEntries) {
      _queueLibraryCountsCache.remove(_queueLibraryCountsCache.keys.first);
    }
  }

  bool _isProtectedQueueLibraryPage(
    _QueueLibraryPageRequest request,
    _QueueLibraryPageRequest protectedRequest,
  ) {
    return _sameQueueLibraryPageScope(request, protectedRequest) &&
        request.limit == protectedRequest.limit &&
        request.offset <= protectedRequest.offset;
  }

  bool _sameQueueLibraryPageScope(
    _QueueLibraryPageRequest a,
    _QueueLibraryPageRequest b,
  ) {
    return a.filterMode == b.filterMode &&
        a.limit == b.limit &&
        a.filterQuality == b.filterQuality &&
        a.filterFormat == b.filterFormat &&
        a.filterMetadata == b.filterMetadata &&
        a.sortMode == b.sortMode;
  }

  _QueueLibraryPageData? _cachedQueueLibraryPageAt(
    _QueueLibraryPageRequest request,
    int offset,
  ) {
    for (final entry in _queueLibraryPageDataCache.entries) {
      if (entry.key.offset == offset &&
          _sameQueueLibraryPageScope(entry.key, request)) {
        return entry.value;
      }
    }
    return null;
  }

  void _trimQueueLibraryPageDataCache({
    required _QueueLibraryPageRequest protectedRequest,
  }) {
    const maxPageEntries = 96;
    while (_queueLibraryPageDataCache.length > maxPageEntries) {
      final removableKey = _queueLibraryPageDataCache.keys
          .where(
            (request) =>
                !_isProtectedQueueLibraryPage(request, protectedRequest),
          )
          .firstOrNull;
      if (removableKey == null) break;
      _queueLibraryPageDataCache.remove(removableKey);
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
                          selected: tempQuality == 'hires',
                          onSelected: (_) =>
                              setSheetState(() => tempQuality = 'hires'),
                        ),
                        AppChoiceChip(
                          label: Text(context.l10n.libraryFilterQualityCD),
                          selected: tempQuality == 'cd',
                          onSelected: (_) =>
                              setSheetState(() => tempQuality = 'cd'),
                        ),
                        AppChoiceChip(
                          label: Text(context.l10n.libraryFilterQualityLossy),
                          selected: tempQuality == 'lossy',
                          onSelected: (_) =>
                              setSheetState(() => tempQuality = 'lossy'),
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
                        AppChoiceChip(
                          label: Text(context.l10n.libraryFilterAll),
                          selected: tempMetadata == null,
                          onSelected: (_) =>
                              setSheetState(() => tempMetadata = null),
                        ),
                        AppChoiceChip(
                          label: Text(
                            context.l10n.libraryFilterMetadataComplete,
                          ),
                          selected: tempMetadata == 'complete',
                          onSelected: (_) =>
                              setSheetState(() => tempMetadata = 'complete'),
                        ),
                        AppChoiceChip(
                          label: Text(
                            context.l10n.libraryFilterMetadataMissingAny,
                          ),
                          selected: tempMetadata == 'missing-any',
                          onSelected: (_) =>
                              setSheetState(() => tempMetadata = 'missing-any'),
                        ),
                        AppChoiceChip(
                          label: Text(
                            context.l10n.libraryFilterMetadataMissingYear,
                          ),
                          selected: tempMetadata == 'missing-year',
                          onSelected: (_) => setSheetState(
                            () => tempMetadata = 'missing-year',
                          ),
                        ),
                        AppChoiceChip(
                          label: Text(
                            context.l10n.libraryFilterMetadataMissingGenre,
                          ),
                          selected: tempMetadata == 'missing-genre',
                          onSelected: (_) => setSheetState(
                            () => tempMetadata = 'missing-genre',
                          ),
                        ),
                        AppChoiceChip(
                          label: Text(
                            context
                                .l10n
                                .libraryFilterMetadataMissingAlbumArtist,
                          ),
                          selected: tempMetadata == 'missing-album-artist',
                          onSelected: (_) => setSheetState(
                            () => tempMetadata = 'missing-album-artist',
                          ),
                        ),
                        AppChoiceChip(
                          label: Text(
                            context
                                .l10n
                                .libraryFilterMetadataMissingTrackNumber,
                          ),
                          selected: tempMetadata == 'missing-track-number',
                          onSelected: (_) => setSheetState(
                            () => tempMetadata = 'missing-track-number',
                          ),
                        ),
                        AppChoiceChip(
                          label: Text(
                            context.l10n.libraryFilterMetadataMissingDiscNumber,
                          ),
                          selected: tempMetadata == 'missing-disc-number',
                          onSelected: (_) => setSheetState(
                            () => tempMetadata = 'missing-disc-number',
                          ),
                        ),
                        AppChoiceChip(
                          label: Text(
                            context.l10n.libraryFilterMetadataMissingArtist,
                          ),
                          selected: tempMetadata == 'missing-artist',
                          onSelected: (_) => setSheetState(
                            () => tempMetadata = 'missing-artist',
                          ),
                        ),
                        AppChoiceChip(
                          label: Text(
                            context
                                .l10n
                                .libraryFilterMetadataIncorrectIsrcFormat,
                          ),
                          selected: tempMetadata == 'incorrect-isrc-format',
                          onSelected: (_) => setSheetState(
                            () => tempMetadata = 'incorrect-isrc-format',
                          ),
                        ),
                        AppChoiceChip(
                          label: Text(
                            context.l10n.libraryFilterMetadataMissingIsrc,
                          ),
                          selected: tempMetadata == 'missing-isrc',
                          onSelected: (_) => setSheetState(
                            () => tempMetadata = 'missing-isrc',
                          ),
                        ),
                        AppChoiceChip(
                          label: Text(
                            context.l10n.libraryFilterMetadataMissingLabel,
                          ),
                          selected: tempMetadata == 'missing-label',
                          onSelected: (_) => setSheetState(
                            () => tempMetadata = 'missing-label',
                          ),
                        ),
                        AppChoiceChip(
                          label: Text(
                            context.l10n.libraryFilterMetadataMissingLyrics,
                          ),
                          selected: tempMetadata == 'missing-lyrics',
                          onSelected: (_) => setSheetState(
                            () => tempMetadata = 'missing-lyrics',
                          ),
                        ),
                        AppChoiceChip(
                          label: Text(
                            context.l10n.libraryFilterMetadataHasReplayGain,
                          ),
                          selected: tempMetadata == 'has-replaygain',
                          onSelected: (_) => setSheetState(
                            () => tempMetadata = 'has-replaygain',
                          ),
                        ),
                        AppChoiceChip(
                          label: Text(
                            context.l10n.libraryFilterMetadataMissingReplayGain,
                          ),
                          selected: tempMetadata == 'missing-replaygain',
                          onSelected: (_) => setSheetState(
                            () => tempMetadata = 'missing-replaygain',
                          ),
                        ),
                        AppChoiceChip(
                          label: Text(
                            context.l10n.libraryFilterIncompleteAlbums,
                          ),
                          selected: tempMetadata == incompleteAlbumFilter,
                          onSelected: (_) => setSheetState(
                            () => tempMetadata = incompleteAlbumFilter,
                          ),
                        ),
                        AppChoiceChip(
                          label: Text(
                            context.l10n.libraryAlbumCompletenessUnknown,
                          ),
                          selected:
                              tempMetadata == unknownAlbumCompletenessFilter,
                          onSelected: (_) => setSheetState(
                            () => tempMetadata = unknownAlbumCompletenessFilter,
                          ),
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
                        AppChoiceChip(
                          label: Text(context.l10n.libraryFilterSortLatest),
                          selected: tempSortMode == 'latest',
                          onSelected: (_) =>
                              setSheetState(() => tempSortMode = 'latest'),
                        ),
                        AppChoiceChip(
                          label: Text(context.l10n.libraryFilterSortOldest),
                          selected: tempSortMode == 'oldest',
                          onSelected: (_) =>
                              setSheetState(() => tempSortMode = 'oldest'),
                        ),
                        // Playlists have no file size of their own.
                        if (widget.librarySection != 'playlists') ...[
                          AppChoiceChip(
                            label: Text(
                              context.l10n.libraryFilterSortSizeLargest,
                            ),
                            selected: tempSortMode == 'size-desc',
                            onSelected: (_) =>
                                setSheetState(() => tempSortMode = 'size-desc'),
                          ),
                          AppChoiceChip(
                            label: Text(
                              context.l10n.libraryFilterSortSizeSmallest,
                            ),
                            selected: tempSortMode == 'size-asc',
                            onSelected: (_) =>
                                setSheetState(() => tempSortMode = 'size-asc'),
                          ),
                        ],
                        AppChoiceChip(
                          label: Text(context.l10n.searchSortTitleAZ),
                          selected: tempSortMode == 'a-z',
                          onSelected: (_) =>
                              setSheetState(() => tempSortMode = 'a-z'),
                        ),
                        AppChoiceChip(
                          label: Text(context.l10n.searchSortTitleZA),
                          selected: tempSortMode == 'z-a',
                          onSelected: (_) =>
                              setSheetState(() => tempSortMode = 'z-a'),
                        ),
                        AppChoiceChip(
                          label: Text(context.l10n.searchSortArtistAZ),
                          selected: tempSortMode == 'artist-asc',
                          onSelected: (_) =>
                              setSheetState(() => tempSortMode = 'artist-asc'),
                        ),
                        AppChoiceChip(
                          label: Text(context.l10n.searchSortArtistZA),
                          selected: tempSortMode == 'artist-desc',
                          onSelected: (_) =>
                              setSheetState(() => tempSortMode = 'artist-desc'),
                        ),
                        AppChoiceChip(
                          label: Text(context.l10n.libraryFilterSortAlbumAsc),
                          selected: tempSortMode == 'album-asc',
                          onSelected: (_) =>
                              setSheetState(() => tempSortMode = 'album-asc'),
                        ),
                        AppChoiceChip(
                          label: Text(context.l10n.libraryFilterSortAlbumDesc),
                          selected: tempSortMode == 'album-desc',
                          onSelected: (_) =>
                              setSheetState(() => tempSortMode = 'album-desc'),
                        ),
                        AppChoiceChip(
                          label: Text(context.l10n.searchSortDateNewest),
                          selected: tempSortMode == 'release-newest',
                          onSelected: (_) => setSheetState(
                            () => tempSortMode = 'release-newest',
                          ),
                        ),
                        AppChoiceChip(
                          label: Text(context.l10n.searchSortDateOldest),
                          selected: tempSortMode == 'release-oldest',
                          onSelected: (_) => setSheetState(
                            () => tempSortMode = 'release-oldest',
                          ),
                        ),
                        AppChoiceChip(
                          label: Text(context.l10n.libraryFilterSortGenreAsc),
                          selected: tempSortMode == 'genre-asc',
                          onSelected: (_) =>
                              setSheetState(() => tempSortMode = 'genre-asc'),
                        ),
                        AppChoiceChip(
                          label: Text(context.l10n.libraryFilterSortGenreDesc),
                          selected: tempSortMode == 'genre-desc',
                          onSelected: (_) =>
                              setSheetState(() => tempSortMode = 'genre-desc'),
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
      return SistrumLibraryScreen(
        onOpenSection: (section) => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(body: QueueTab(librarySection: section)),
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
    final countsRequest = _QueueLibraryCountsRequest(
      filterQuality: _filterQuality,
      filterFormat: _filterFormat,
      filterMetadata: _filterMetadata,
    );
    final countsValue = ref.watch(_queueLibraryCountsProvider(countsRequest));
    final queueCounts = _resolveQueueLibraryCounts(countsValue, countsRequest);

    _QueueLibraryPageRequest pageRequest(String filterMode) {
      final offset = _libraryPageOffsetFor(filterMode);
      final baseRequest = _QueueLibraryPageRequest(
        filterMode: filterMode,
        limit: _libraryPageSize,
        offset: offset,
        filterQuality: _filterQuality,
        filterFormat: _filterFormat,
        filterMetadata: _filterMetadata,
        sortMode: _sortMode,
      );
      if (offset == 0) return baseRequest;
      final previousPage = _cachedQueueLibraryPageAt(
        baseRequest,
        offset - _libraryPageSize,
      );
      return _QueueLibraryPageRequest(
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
      _queueLibraryPageProvider(activePageRequest),
    );

    _QueueLibraryPageData pageData(String filterMode) {
      final request = filterMode == libraryFilterMode
          ? activePageRequest
          : pageRequest(filterMode);
      return _resolveQueueLibraryPageData(
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
                  ref.invalidate(_queueLibraryCountsProvider(countsRequest));
                  ref.invalidate(_queueLibraryPageProvider(activePageRequest));
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
      __AnimatedLibrarySliverGridState();
}

class __AnimatedLibrarySliverGridState extends State<_AnimatedLibrarySliverGrid>
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
