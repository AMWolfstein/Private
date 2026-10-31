import 'package:sistrum/core/models/local_library_item.dart';
import 'package:sistrum/widgets/library/library_fast_scroller.dart';
import 'package:sistrum/widgets/library/library_section_list.dart';
import 'package:sistrum/widgets/library/playlist_name_dialog.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math' show Random;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:sistrum/widgets/primitives/app_alert_dialog.dart';
import 'package:sistrum/widgets/primitives/app_choice_chip.dart';
import 'package:sistrum/widgets/library/local_track_batch_actions.dart';
import 'package:sistrum/core/navigation/shell_navigation.dart';
import 'package:sistrum/widgets/status/error_card.dart';
import 'package:sistrum/core/theme/app_tokens.dart';
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
import 'package:sistrum/utils/layout/adaptive_layout.dart';
import 'package:sistrum/utils/layout/nav_bar_inset.dart';
import 'package:sistrum/utils/files/file_access.dart';
import 'package:sistrum/utils/scan/library_format_filters.dart';
import 'package:sistrum/utils/playback/ordered_range_selection.dart';
import 'package:sistrum/core/models/unified_library_item.dart';
import 'package:sistrum/providers/library/library_collections_provider.dart';
import 'package:sistrum/providers/settings/settings_provider.dart';
import 'package:sistrum/providers/library/local_library_provider.dart';
import 'package:sistrum/providers/playback/playback_provider.dart';
import 'package:sistrum/providers/playback/music_player_provider.dart';
import 'package:sistrum/services/playback/music_player/music_player_service.dart';
import 'package:sistrum/services/library/database/library_database.dart';
import 'package:sistrum/utils/logging/logger.dart';
import 'package:sistrum/services/library/browse/album_completeness.dart';
import 'package:sistrum/widgets/library/batch_track_actions.dart';
import 'package:sistrum/widgets/library/local_song_row.dart';
import 'package:sistrum/widgets/library/local_song_menu.dart';
import 'package:sistrum/widgets/cover/cached_cover_image.dart';
import 'package:sistrum/widgets/library/local_library_artwork_builder.dart';
import 'package:sistrum/screens/library/collections/library_collection_tracks_screen.dart';
import 'package:sistrum/screens/library/local_album/local_album_screen.dart';
import 'package:sistrum/screens/library/app_library_screen.dart';
import 'package:sistrum/screens/library/shared/library_browse_refresh_policy.dart';
import 'package:sistrum/core/navigation/detail_navigation.dart';
import 'package:sistrum/widgets/animation/animation_utils.dart';
import 'package:sistrum/widgets/animation/animation_indicators.dart';
import 'package:sistrum/widgets/selection/selection_bottom_bar.dart';
import 'package:sistrum/providers/library/library_database_provider.dart';

part 'library_section_tab_paging.dart';
part 'library_section_tab_filters.dart';

part 'library_section_tab_helpers.dart';
part 'library_section_tab_selection.dart';
part 'library_section_tab_navigation.dart';
part 'library_section_tab_collection_items.dart';
part 'library_section_tab_filter_widgets.dart';
part 'library_section_tab_album_grid.dart';
part 'library_section_tab_empty_state.dart';
part 'library_section_tab_batch_actions.dart';
part 'library_section_tab_item_widgets.dart';

final _librarySectionLog = AppLogger('LibrarySectionTab');

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
