import 'package:spotiflac_android/screens/local_artist_screen.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:spotiflac_android/widgets/app_alert_dialog.dart';
import 'package:spotiflac_android/widgets/app_choice_chip.dart';
import 'package:spotiflac_android/services/local_track_batch_actions.dart';
import 'package:spotiflac_android/services/shell_navigation_service.dart';
import 'package:spotiflac_android/widgets/error_card.dart';
import 'package:spotiflac_android/widgets/track_card.dart';
import 'package:spotiflac_android/theme/app_tokens.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';
import 'package:spotiflac_android/widgets/app_bottom_sheet.dart';
import 'package:spotiflac_android/widgets/app_sliver_header.dart';
import 'package:spotiflac_android/widgets/app_search_field.dart';
import 'package:spotiflac_android/widgets/app_snack_bar.dart';
import 'package:spotiflac_android/widgets/library_search_results.dart';
import 'package:spotiflac_android/widgets/library_track_selection_bar.dart';
import 'package:spotiflac_android/widgets/library_selection_playback_actions.dart';
import 'package:spotiflac_android/widgets/library_playlist_drag_source.dart';
import 'package:spotiflac_android/widgets/mornye_chrome.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/utils/adaptive_layout.dart';
import 'package:spotiflac_android/utils/audio_quality_badge_policy.dart';
import 'package:spotiflac_android/utils/nav_bar_inset.dart';
import 'package:spotiflac_android/utils/file_access.dart';
import 'package:spotiflac_android/utils/library_format_filters.dart';
import 'package:spotiflac_android/utils/ordered_range_selection.dart';
import 'package:spotiflac_android/models/unified_library_item.dart';
import 'package:spotiflac_android/providers/library_collections_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/providers/local_library_provider.dart';
import 'package:spotiflac_android/providers/playback_provider.dart';
import 'package:spotiflac_android/providers/music_player_provider.dart';
import 'package:spotiflac_android/providers/runtime_profile_provider.dart';
import 'package:spotiflac_android/services/music_player_service.dart';
import 'package:spotiflac_android/services/library_database.dart';
import 'package:spotiflac_android/services/album_completeness.dart';
import 'package:spotiflac_android/services/batch_track_actions.dart';
import 'package:spotiflac_android/services/downloaded_embedded_cover_resolver.dart';
import 'package:spotiflac_android/widgets/local_song_row.dart';
import 'package:spotiflac_android/widgets/local_song_menu.dart';
import 'package:spotiflac_android/screens/favorite_artists_screen.dart';
import 'package:spotiflac_android/widgets/cached_cover_image.dart';
import 'package:spotiflac_android/widgets/local_library_artwork_builder.dart';
import 'package:spotiflac_android/screens/library_tracks_folder_screen.dart';
import 'package:spotiflac_android/screens/local_album_screen.dart';
import 'package:spotiflac_android/screens/mornye_library_screen.dart';
import 'package:spotiflac_android/screens/queue_library_refresh_policy.dart';
import 'package:spotiflac_android/utils/clickable_metadata.dart';
import 'package:spotiflac_android/widgets/animation_utils.dart';
import 'package:spotiflac_android/widgets/selection_bottom_bar.dart';
import 'package:spotiflac_android/widgets/scroll_edge_fade.dart';
import 'package:spotiflac_android/widgets/two_finger_pinch_listener.dart';

part 'queue_tab_helpers.dart';
part 'queue_tab_widgets.dart';
part 'queue_tab_selection.dart';
part 'queue_tab_navigation.dart';
part 'queue_tab_collection_items.dart';
part 'queue_tab_filter_widgets.dart';
part 'queue_tab_batch_actions.dart';
part 'queue_tab_item_widgets.dart';

class QueueTab extends ConsumerStatefulWidget {
  final String? librarySection;
  final PageController? parentPageController;
  final int parentPageIndex;

  const QueueTab({
    super.key,
    this.librarySection,
    this.parentPageController,
    this.parentPageIndex = 1,
  });

  @override
  ConsumerState<QueueTab> createState() => _QueueTabState();
}

class _QueueTabState extends ConsumerState<QueueTab> {
  static const int _libraryPageSize = 300;
  final LibraryFileAvailabilityCache _fileExistsCache =
      LibraryFileAvailabilityCache();
  static const double _libraryGridMinExtent = 92;
  static const double _libraryGridDefaultExtent = 126;
  static const double _libraryGridMaxExtent = 190;
  bool _embeddedCoverRefreshScheduled = false;
  // Version counter to trigger targeted cover image rebuilds
  // without rebuilding the entire widget tree via setState.
  final ValueNotifier<int> _embeddedCoverVersion = ValueNotifier<int>(0);

  bool _isSelectionMode = false;
  bool _isDraggingLibraryTrack = false;
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

  PageController? _filterPageController;
  final List<String> _filterModes = ['all', 'albums', 'singles', 'playlists'];
  bool _isPageControllerInitialized = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  Timer? _searchDebounce;
  String? _filterSource;
  String? _filterQuality;
  String? _filterFormat;
  String? _filterMetadata;
  String _sortMode = 'latest';
  double _libraryGridExtent = _libraryGridDefaultExtent;
  double? _libraryGridPinchStartExtent;
  final Map<String, int> _libraryPageOffsetByFilter = {};
  bool _libraryPageLoadScheduled = false;
  final Map<_QueueLibraryCountsRequest, QueueLibraryCounts>
  _queueLibraryCountsCache = {};
  final Map<_QueueLibraryPageRequest, _QueueLibraryPageData>
  _queueLibraryPageDataCache = {};

  double get _libraryAlbumGridExtent =>
      (_libraryGridExtent * 1.45).clamp(150.0, 300.0);

  /// setState is @protected, so the extension part files route rebuilds
  /// through this forwarder.
  void _setState(VoidCallback fn) => setState(fn);

  void _handleLibraryGridPinchStart() {
    _libraryGridPinchStartExtent = _libraryGridExtent;
  }

  void _handleLibraryGridPinchUpdate(double scale) {
    final startExtent = _libraryGridPinchStartExtent;
    if (startExtent == null) return;

    final nextExtent = (startExtent * scale).clamp(
      _libraryGridMinExtent,
      _libraryGridMaxExtent,
    );
    if ((nextExtent - _libraryGridExtent).abs() < 0.5) return;
    setState(() => _libraryGridExtent = nextExtent);
  }

  void _handleLibraryGridPinchEnd() {
    _libraryGridPinchStartExtent = null;
  }

  @override
  void initState() {
    super.initState();
  }

  void _initializePageController() {
    if (_isPageControllerInitialized) return;
    _isPageControllerInitialized = true;
    final settings = ref.read(settingsProvider);
    final initialFilter = widget.librarySection ?? settings.historyFilterMode;
    final initialPage = _filterModes
        .indexOf(initialFilter)
        .clamp(0, _filterModes.length - 1);
    if (widget.librarySection == null &&
        settings.historyFilterMode != _filterModes[initialPage]) {
      Future.microtask(() {
        if (!mounted) return;
        ref
            .read(settingsProvider.notifier)
            .setHistoryFilterMode(_filterModes[initialPage]);
      });
    }
    _filterPageController = PageController(initialPage: initialPage);
  }

  @override
  void dispose() {
    _hideSelectionOverlay();
    _hidePlaylistSelectionOverlay();
    _fileExistsCache.dispose();
    _embeddedCoverVersion.dispose();
    _filterPageController?.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final normalized = value.trim().toLowerCase();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted || _searchQuery == normalized) return;
      setState(() {
        _searchQuery = normalized;
        _resetLibraryPaging();
      });
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    if (_searchQuery.isEmpty) return;
    setState(() {
      _searchQuery = '';
      _resetLibraryPaging();
    });
  }

  int _libraryPageOffsetFor(String filterMode) =>
      _libraryPageOffsetByFilter[filterMode] ?? 0;

  void _resetLibraryOffsets() {
    _libraryPageOffsetByFilter.clear();
  }

  void _resetLibraryPaging() {
    _resetLibraryOffsets();
    _queueLibraryPageDataCache.clear();
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

    final combined = _QueueLibraryPageData.combine(pages);
    if (combined.isEmpty && nonEmptyFallback != null) {
      return nonEmptyFallback();
    }
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
        a.searchQuery == b.searchQuery &&
        a.filterSource == b.filterSource &&
        a.filterQuality == b.filterQuality &&
        a.filterFormat == b.filterFormat &&
        a.filterMetadata == b.filterMetadata &&
        a.sortMode == b.sortMode &&
        a.localLibraryEnabled == b.localLibraryEnabled;
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

  void _onFilterPageChanged(int index) {
    if (widget.librarySection != null) return;
    HapticFeedback.selectionClick();
    final filterMode = _filterModes[index];
    ref.read(settingsProvider.notifier).setHistoryFilterMode(filterMode);
  }

  void _animateToFilterPage(int index) {
    if (index >= 0 && index < _filterModes.length) {
      final filterMode = _filterModes[index];
      if (ref.read(settingsProvider).historyFilterMode != filterMode) {
        ref.read(settingsProvider.notifier).setHistoryFilterMode(filterMode);
      }
    }
    _filterPageController?.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  void _onEmbeddedCoverChanged() {
    if (!mounted || _embeddedCoverRefreshScheduled) return;
    _embeddedCoverRefreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _embeddedCoverRefreshScheduled = false;
      if (mounted) {
        _embeddedCoverVersion.value++;
      }
    });
  }

  String? _resolveDownloadedEmbeddedCoverPath(String? filePath) {
    return DownloadedEmbeddedCoverResolver.resolve(
      filePath,
      onChanged: _onEmbeddedCoverChanged,
    );
  }

  ValueListenable<bool> _fileExistsListenable(String? filePath) {
    return _fileExistsCache.listenable(filePath);
  }

  int get _activeFilterCount {
    int count = 0;
    if (_filterSource != null) count++;
    if (_filterQuality != null) count++;
    if (_filterFormat != null) count++;
    if (_filterMetadata != null) count++;
    return count;
  }

  void _resetFilters() {
    setState(() {
      _filterSource = null;
      _filterQuality = null;
      _filterFormat = null;
      _filterMetadata = null;
      _sortMode = 'latest';
      _resetLibraryPaging();
    });
  }

  void _showFilterSheet(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    String? tempSource = _filterSource;
    String? tempQuality = _filterQuality;
    String? tempFormat = _filterFormat;
    String? tempMetadata = _filterMetadata;
    String tempSortMode = _sortMode;

    showAppModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: colorScheme.surfaceContainerLow,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxSheetHeight = constraints.maxHeight * 0.9;
                return ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxSheetHeight),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const AppSheetHandle(),

                          Row(
                            children: [
                              Text(
                                context.l10n.libraryFilterTitle,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const Spacer(),
                              TextButton(
                                onPressed: () {
                                  setSheetState(() {
                                    tempSource = null;
                                    tempQuality = null;
                                    tempFormat = null;
                                    tempMetadata = null;
                                    tempSortMode = 'latest';
                                  });
                                },
                                child: Text(context.l10n.libraryFilterReset),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          Text(
                            context.l10n.libraryFilterSource,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              AppChoiceChip(
                                label: Text(context.l10n.libraryFilterAll),
                                selected: tempSource == null,
                                onSelected: (_) =>
                                    setSheetState(() => tempSource = null),
                              ),
                              AppChoiceChip(
                                label: Text(
                                  context.l10n.libraryFilterDownloaded,
                                ),
                                selected: tempSource == 'downloaded',
                                onSelected: (_) => setSheetState(
                                  () => tempSource = 'downloaded',
                                ),
                              ),
                              AppChoiceChip(
                                label: Text(context.l10n.libraryFilterLocal),
                                selected: tempSource == 'local',
                                onSelected: (_) =>
                                    setSheetState(() => tempSource = 'local'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          Text(
                            context.l10n.libraryFilterQuality,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
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
                                label: Text(
                                  context.l10n.libraryFilterQualityHiRes,
                                ),
                                selected: tempQuality == 'hires',
                                onSelected: (_) =>
                                    setSheetState(() => tempQuality = 'hires'),
                              ),
                              AppChoiceChip(
                                label: Text(
                                  context.l10n.libraryFilterQualityCD,
                                ),
                                selected: tempQuality == 'cd',
                                onSelected: (_) =>
                                    setSheetState(() => tempQuality = 'cd'),
                              ),
                              AppChoiceChip(
                                label: Text(
                                  context.l10n.libraryFilterQualityLossy,
                                ),
                                selected: tempQuality == 'lossy',
                                onSelected: (_) =>
                                    setSheetState(() => tempQuality = 'lossy'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          Text(
                            context.l10n.libraryFilterFormat,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
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
                              for (final format
                                  in libraryFormatFilterAliases.keys)
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
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
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
                                onSelected: (_) => setSheetState(
                                  () => tempMetadata = 'complete',
                                ),
                              ),
                              AppChoiceChip(
                                label: Text(
                                  context.l10n.libraryFilterMetadataMissingAny,
                                ),
                                selected: tempMetadata == 'missing-any',
                                onSelected: (_) => setSheetState(
                                  () => tempMetadata = 'missing-any',
                                ),
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
                                  context
                                      .l10n
                                      .libraryFilterMetadataMissingGenre,
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
                                selected:
                                    tempMetadata == 'missing-album-artist',
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
                                selected:
                                    tempMetadata == 'missing-track-number',
                                onSelected: (_) => setSheetState(
                                  () => tempMetadata = 'missing-track-number',
                                ),
                              ),
                              AppChoiceChip(
                                label: Text(
                                  context
                                      .l10n
                                      .libraryFilterMetadataMissingDiscNumber,
                                ),
                                selected: tempMetadata == 'missing-disc-number',
                                onSelected: (_) => setSheetState(
                                  () => tempMetadata = 'missing-disc-number',
                                ),
                              ),
                              AppChoiceChip(
                                label: Text(
                                  context
                                      .l10n
                                      .libraryFilterMetadataMissingArtist,
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
                                selected:
                                    tempMetadata == 'incorrect-isrc-format',
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
                                  context
                                      .l10n
                                      .libraryFilterMetadataMissingLabel,
                                ),
                                selected: tempMetadata == 'missing-label',
                                onSelected: (_) => setSheetState(
                                  () => tempMetadata = 'missing-label',
                                ),
                              ),
                              AppChoiceChip(
                                label: Text(
                                  context
                                      .l10n
                                      .libraryFilterMetadataMissingLyrics,
                                ),
                                selected: tempMetadata == 'missing-lyrics',
                                onSelected: (_) => setSheetState(
                                  () => tempMetadata = 'missing-lyrics',
                                ),
                              ),
                              AppChoiceChip(
                                label: Text(
                                  context
                                      .l10n
                                      .libraryFilterMetadataHasReplayGain,
                                ),
                                selected: tempMetadata == 'has-replaygain',
                                onSelected: (_) => setSheetState(
                                  () => tempMetadata = 'has-replaygain',
                                ),
                              ),
                              AppChoiceChip(
                                label: Text(
                                  context
                                      .l10n
                                      .libraryFilterMetadataMissingReplayGain,
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
                                    tempMetadata ==
                                    unknownAlbumCompletenessFilter,
                                onSelected: (_) => setSheetState(
                                  () => tempMetadata =
                                      unknownAlbumCompletenessFilter,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          Text(
                            context.l10n.libraryFilterSort,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              AppChoiceChip(
                                label: Text(
                                  context.l10n.libraryFilterSortLatest,
                                ),
                                selected: tempSortMode == 'latest',
                                onSelected: (_) => setSheetState(
                                  () => tempSortMode = 'latest',
                                ),
                              ),
                              AppChoiceChip(
                                label: Text(
                                  context.l10n.libraryFilterSortOldest,
                                ),
                                selected: tempSortMode == 'oldest',
                                onSelected: (_) => setSheetState(
                                  () => tempSortMode = 'oldest',
                                ),
                              ),
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
                                onSelected: (_) => setSheetState(
                                  () => tempSortMode = 'artist-asc',
                                ),
                              ),
                              AppChoiceChip(
                                label: Text(context.l10n.searchSortArtistZA),
                                selected: tempSortMode == 'artist-desc',
                                onSelected: (_) => setSheetState(
                                  () => tempSortMode = 'artist-desc',
                                ),
                              ),
                              AppChoiceChip(
                                label: Text(
                                  context.l10n.libraryFilterSortAlbumAsc,
                                ),
                                selected: tempSortMode == 'album-asc',
                                onSelected: (_) => setSheetState(
                                  () => tempSortMode = 'album-asc',
                                ),
                              ),
                              AppChoiceChip(
                                label: Text(
                                  context.l10n.libraryFilterSortAlbumDesc,
                                ),
                                selected: tempSortMode == 'album-desc',
                                onSelected: (_) => setSheetState(
                                  () => tempSortMode = 'album-desc',
                                ),
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
                                label: Text(
                                  context.l10n.libraryFilterSortGenreAsc,
                                ),
                                selected: tempSortMode == 'genre-asc',
                                onSelected: (_) => setSheetState(
                                  () => tempSortMode = 'genre-asc',
                                ),
                              ),
                              AppChoiceChip(
                                label: Text(
                                  context.l10n.libraryFilterSortGenreDesc,
                                ),
                                selected: tempSortMode == 'genre-desc',
                                onSelected: (_) => setSheetState(
                                  () => tempSortMode = 'genre-desc',
                                ),
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
                                  _filterSource = tempSource;
                                  _filterQuality = tempQuality;
                                  _filterFormat = tempFormat;
                                  _filterMetadata = tempMetadata;
                                  _sortMode = tempSortMode;
                                  _resetLibraryPaging();
                                });
                                Navigator.pop(context);
                                if (widget.librarySection == null &&
                                    isAlbumCompletenessFilter(tempMetadata)) {
                                  _animateToFilterPage(
                                    _filterModes.indexOf('albums'),
                                  );
                                }
                              },
                              child: Text(context.l10n.libraryFilterApply),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (context.isMornye && widget.librarySection == null) {
      return MornyeLibraryScreen(
        onOpenSection: (section) => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(body: QueueTab(librarySection: section)),
          ),
        ),
      );
    }
    _initializePageController();
    final localLibraryEnabled = ref.watch(
      settingsProvider.select((s) => s.localLibraryEnabled),
    );

    if (localLibraryEnabled) {
      ref.listen<int>(
        localLibraryProvider.select((state) => state.loadedIndexVersion),
        (previous, next) {
          if (previous == null || previous == next) return;
          // Keep stale rows visible until the refreshed query replaces them.
          _resetLibraryOffsets();
          if (mounted) setState(() {});
        },
      );
    }

    final localLibraryTotalCount = localLibraryEnabled
        ? ref.watch(localLibraryProvider.select((state) => state.totalCount))
        : 0;
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
        ),
      ),
    );
    final collectionState = ref.read(libraryCollectionsProvider);
    final String historyFilterMode =
        widget.librarySection ??
        ref.watch<String>(settingsProvider.select((s) => s.historyFilterMode));
    final colorScheme = Theme.of(context).colorScheme;
    final countsRequest = _QueueLibraryCountsRequest(
      searchQuery: _searchQuery,
      filterSource: _filterSource,
      filterQuality: _filterQuality,
      filterFormat: _filterFormat,
      filterMetadata: _filterMetadata,
      localLibraryEnabled: localLibraryEnabled,
    );
    final searchingLibrary =
        _searchQuery.isNotEmpty &&
        !isAlbumCompletenessFilter(_filterMetadata) &&
        !_isSelectionMode &&
        !_isPlaylistSelectionMode;
    final countsValue = searchingLibrary
        ? const AsyncData(
            QueueLibraryCounts(
              allTrackCount: 0,
              albumCount: 0,
              singleTrackCount: 0,
            ),
          )
        : ref.watch(_queueLibraryCountsProvider(countsRequest));
    final queueCounts = _resolveQueueLibraryCounts(countsValue, countsRequest);

    _QueueLibraryPageRequest pageRequest(String filterMode) {
      final offset = _libraryPageOffsetFor(filterMode);
      final baseRequest = _QueueLibraryPageRequest(
        filterMode: filterMode,
        limit: _libraryPageSize,
        offset: offset,
        searchQuery: _searchQuery,
        filterSource: _filterSource,
        filterQuality: _filterQuality,
        filterFormat: _filterFormat,
        filterMetadata: _filterMetadata,
        sortMode: _sortMode,
        localLibraryEnabled: localLibraryEnabled,
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
        searchQuery: baseRequest.searchQuery,
        filterSource: baseRequest.filterSource,
        filterQuality: baseRequest.filterQuality,
        filterFormat: baseRequest.filterFormat,
        filterMetadata: baseRequest.filterMetadata,
        sortMode: baseRequest.sortMode,
        localLibraryEnabled: baseRequest.localLibraryEnabled,
        cursor: previousPage?.nextCursor,
      );
    }

    final activePageRequest = pageRequest(historyFilterMode);
    final activePageValue = searchingLibrary
        ? const AsyncData(_QueueLibraryPageData())
        : ref.watch(_queueLibraryPageProvider(activePageRequest));

    _QueueLibraryPageData pageData(String filterMode) {
      final request = filterMode == historyFilterMode
          ? activePageRequest
          : pageRequest(filterMode);
      return _resolveQueueLibraryPageData(
        filterMode == historyFilterMode ? activePageValue : null,
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

    final currentPageData = pageData(historyFilterMode);
    final currentLoadedCount = historyFilterMode == 'albums'
        ? currentPageData.groupedLocalAlbums.length
        : currentPageData.items.length;
    final currentTotalCount = switch (historyFilterMode) {
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
    final hasLibraryContent = localLibraryEnabled && localLibraryTotalCount > 0;
    final hasActiveSearch =
        _searchQuery.isNotEmpty || _searchController.text.trim().isNotEmpty;
    final shouldShowLibraryControls =
        hasLibraryContent || hasAnyLibraryItems || hasActiveSearch;

    final selectionItems = getFilterData(
      historyFilterMode,
    ).filteredUnifiedItems;
    if (_isSelectionMode || _isPlaylistSelectionMode) {
      final bottomPadding = MediaQuery.paddingOf(context).bottom;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_isSelectionMode) {
          _syncSelectionOverlay(
            items: selectionItems,
            bottomPadding: bottomPadding,
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
                if (widget.librarySection == null)
                  AppSliverHeader.tabRoot(title: context.l10n.navLibrary)
                else
                  AppSliverHeader.page(
                    title: widget.librarySection == 'playlists'
                        ? context.l10n.searchPlaylists
                        : context.l10n.searchSongs,
                  ),

                if (shouldShowLibraryControls)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: GestureDetector(
                        onTap: () {},
                        child: AppSearchField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          hintText: context.l10n.librarySearchHint,
                          clearTooltip: context.l10n.dialogClear,
                          onChanged: _onSearchChanged,
                          onClear: () {
                            _clearSearch();
                            FocusScope.of(context).unfocus();
                          },
                        ),
                      ),
                    ),
                  ),

                if (!searchingLibrary &&
                    shouldShowLibraryControls &&
                    widget.librarySection == null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          int filteredAllCount;
                          int filteredAlbumCount;
                          int filteredSingleCount;

                          filteredAllCount = queueCounts.allTrackCount;
                          filteredAlbumCount = queueCounts.albumCount;
                          filteredSingleCount = queueCounts.singleTrackCount;

                          return ScrollEdgeFade(
                            axis: Axis.horizontal,
                            size: 48,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              padding: context.isMornye
                                  ? const EdgeInsets.symmetric(vertical: 4)
                                  : EdgeInsets.zero,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minWidth: constraints.maxWidth,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    _FilterChip(
                                      label: context.l10n.historyFilterAll,
                                      count: filteredAllCount,
                                      isSelected: historyFilterMode == 'all',
                                      onTap: () {
                                        _animateToFilterPage(0);
                                      },
                                    ),
                                    const SizedBox(width: 8),
                                    _FilterChip(
                                      label: context.l10n.historyFilterAlbums,
                                      count: filteredAlbumCount,
                                      isSelected: historyFilterMode == 'albums',
                                      onTap: () {
                                        _animateToFilterPage(1);
                                      },
                                    ),
                                    const SizedBox(width: 8),
                                    _FilterChip(
                                      label: context.l10n.historyFilterSingles,
                                      count: filteredSingleCount,
                                      isSelected:
                                          historyFilterMode == 'singles',
                                      onTap: () {
                                        _animateToFilterPage(2);
                                      },
                                    ),
                                    const SizedBox(width: 8),
                                    _FilterChip(
                                      label: context.l10n.searchPlaylists,
                                      count: collectionState.playlists.length,
                                      isSelected:
                                          historyFilterMode == 'playlists',
                                      onTap: () {
                                        _animateToFilterPage(3);
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
              ],
              body: searchingLibrary
                  ? CustomScrollView(
                      key: const ValueKey('library-search-results'),
                      slivers: [
                        LibrarySearchResults(
                          query: _searchQuery,
                          onOpenArtist: (artist) => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  LocalArtistScreen(artistName: artist),
                            ),
                          ),
                        ),
                        const NavBarSliverSpacer(),
                      ],
                    )
                  : widget.librarySection != null
                  ? _buildFilterContent(
                      context: context,
                      colorScheme: colorScheme,
                      filterMode: historyFilterMode,
                      filterData: getFilterData(historyFilterMode),
                      collectionState: collectionState,
                      hasMoreLibrary: hasMoreLibrary,
                      isPageLoading: isLibraryPageLoading,
                    )
                  : PageView.builder(
                      controller: _filterPageController!,
                      physics: const ClampingScrollPhysics(),
                      onPageChanged: _onFilterPageChanged,
                      itemCount: _filterModes.length,
                      itemBuilder: (context, index) {
                        final filterMode = _filterModes[index];
                        final filterData = getFilterData(filterMode);
                        return _buildFilterContent(
                          context: context,
                          colorScheme: colorScheme,
                          filterMode: filterMode,
                          filterData: filterData,
                          collectionState: collectionState,
                          hasMoreLibrary: filterMode == historyFilterMode
                              ? hasMoreLibrary
                              : false,
                          isPageLoading: isLibraryPageLoading,
                        );
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

  const _AnimatedLibrarySliverGrid({
    required this.maxCrossAxisExtent,
    required this.mainAxisSpacing,
    required this.crossAxisSpacing,
    required this.childAspectRatio,
    required this.delegate,
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
  void didUpdateWidget(covariant _AnimatedLibrarySliverGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((widget.maxCrossAxisExtent - _endExtent).abs() < 0.1) return;
    _beginExtent = _currentExtent;
    _endExtent = widget.maxCrossAxisExtent;
    _controller.forward(from: 0);
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
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return SliverGrid(
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: _currentExtent,
            mainAxisSpacing: widget.mainAxisSpacing,
            crossAxisSpacing: widget.crossAxisSpacing,
            childAspectRatio: widget.childAspectRatio,
          ),
          delegate: widget.delegate,
        );
      },
    );
  }
}
