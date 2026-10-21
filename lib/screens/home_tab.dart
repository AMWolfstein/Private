import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/providers/local_home_feed_provider.dart';
import 'package:spotiflac_android/providers/library_browse_provider.dart';
import 'package:spotiflac_android/providers/library_collections_provider.dart';
import 'package:spotiflac_android/screens/library_tracks_folder_screen.dart';
import 'package:spotiflac_android/screens/local_album_screen.dart';
import 'package:spotiflac_android/screens/local_artist_screen.dart';
import 'package:spotiflac_android/providers/playback_provider.dart';
import 'package:spotiflac_android/services/library_database.dart';
import 'package:spotiflac_android/services/shell_navigation_service.dart';
import 'package:spotiflac_android/utils/nav_bar_inset.dart';
import 'package:spotiflac_android/widgets/app_search_field.dart';
import 'package:spotiflac_android/widgets/app_sliver_header.dart';
import 'package:spotiflac_android/widgets/cached_cover_image.dart';
import 'package:spotiflac_android/widgets/library_search_results.dart';
import 'package:spotiflac_android/widgets/profile_avatar.dart';

import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/providers/local_library_provider.dart';
import 'package:spotiflac_android/screens/settings/library_settings_page.dart';
import 'package:spotiflac_android/utils/adaptive_layout.dart';
import 'package:spotiflac_android/utils/release_date_display.dart';
import 'package:spotiflac_android/widgets/local_library_artwork_builder.dart';
import 'package:spotiflac_android/widgets/animation_utils.dart';
import 'package:spotiflac_android/widgets/error_card.dart';
import 'package:spotiflac_android/widgets/audio_quality_badges.dart';

part 'home_tab_feed.dart';
part 'home_tab_widgets.dart';

enum HomeTabMode { combined, browse, search }

class HomeTab extends ConsumerStatefulWidget {
  const HomeTab({
    super.key,
    this.mode = HomeTabMode.combined,
    this.scrollController,
  });

  final HomeTabMode mode;
  final ScrollController? scrollController;

  @override
  ConsumerState<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<HomeTab>
    with AutomaticKeepAliveClientMixin {
  bool get _showsSearch => widget.mode != HomeTabMode.browse;
  bool get _showsHome => widget.mode != HomeTabMode.search;

  final _urlController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final _ownedHomeScrollController = ScrollController();
  ScrollController get _homeScrollController =>
      widget.scrollController ?? _ownedHomeScrollController;

  String _query = '';
  Timer? _searchDebounce;

  static const Duration _searchDebounceDelay = Duration(milliseconds: 300);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _urlController.addListener(_onSearchChanged);
    _searchFocusNode.addListener(_onSearchFocusChanged);
    ShellNavigationService.searchRequests.addListener(_focusSearchFromShell);
  }

  @override
  void dispose() {
    ShellNavigationService.searchRequests.removeListener(_focusSearchFromShell);
    _ownedHomeScrollController.dispose();
    _searchDebounce?.cancel();
    _urlController.removeListener(_onSearchChanged);
    _searchFocusNode.removeListener(_onSearchFocusChanged);
    _urlController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchFocusChanged() {
    if (widget.mode == HomeTabMode.search) return;
    if (mounted) setState(() {});
  }

  void _focusSearchFromShell() {
    if (!_showsSearch) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_showsSearch ||
          !TickerMode.getValuesNotifier(context).value.enabled) {
        return;
      }
      if (_homeScrollController.hasClients) _homeScrollController.jumpTo(0);
      _searchFocusNode.requestFocus();
    });
  }

  void _onSearchChanged() {
    final text = _urlController.text.trim();
    if (text == _query) return;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(_searchDebounceDelay, () {
      if (mounted) setState(() => _query = text);
    });
  }

  void _onSearchSubmitted(String value) {
    _searchDebounce?.cancel();
    final text = value.trim();
    if (text == _query) return;
    setState(() => _query = text);
    _searchFocusNode.unfocus();
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    if (_urlController.text.isNotEmpty) _urlController.clear();
    if (_query.isNotEmpty) setState(() => _query = '');
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _openArtist(String artist) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LocalArtistScreen(artistName: artist),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final query = _query.trim();
    final showSearchResults = _showsSearch && query.isNotEmpty;
    final isSearchTabEmpty =
        widget.mode == HomeTabMode.search && !showSearchResults;

    return GestureDetector(
      onTap: () {
        if (_searchFocusNode.hasFocus) _searchFocusNode.unfocus();
      },
      behavior: HitTestBehavior.translucent,
      child: Scaffold(
        body: RefreshIndicator(
          onRefresh: _refreshHome,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            controller: _homeScrollController,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              AppSliverHeader.tabRoot(
                title: widget.mode == HomeTabMode.search
                    ? l10n.mornyeSearch
                    : l10n.homeTitle,
                actions: _showsHome ? const [HomeProfileButton()] : null,
              ),

              if (_showsSearch)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      showSearchResults ? 8 : 24,
                      16,
                      8,
                    ),
                    child: _buildSearchBar(),
                  ),
                ),

              if (showSearchResults)
                LibrarySearchResults(query: query, onOpenArtist: _openArtist),

              if (!showSearchResults && (_showsHome || isSearchTabEmpty))
                SliverMainAxisGroup(
                  slivers: [
                    if (_showsHome) ..._buildLocalFeed(colorScheme),
                    if (!_showsHome) _buildRecentlyAdded(colorScheme),
                  ],
                ),

              const NavBarSliverSpacer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    final hasText = _urlController.text.isNotEmpty;

    return AppSearchField(
      controller: _urlController,
      samplesBackdrop: false,
      focusNode: _searchFocusNode,
      hintText: context.l10n.homeSearchHintDefault,
      clearTooltip: context.l10n.dialogClear,
      onClear: _clearSearch,
      suffixIcon: hasText
          ? IconButton(
              icon: const Icon(Icons.clear),
              onPressed: _clearSearch,
              tooltip: context.l10n.dialogClear,
            )
          : null,
      onSubmitted: _onSearchSubmitted,
    );
  }

  SliverToBoxAdapter _buildRecentlyAdded(ColorScheme colorScheme) {
    return SliverToBoxAdapter(
      child: Consumer(
        builder: (context, ref, _) {
          return ref
              .watch(localHomeTracksProvider)
              .when(
                skipLoadingOnReload: true,
                data: (items) => _feedShelf(
                  context.l10n.libraryRecentlyAdded,
                  items
                      .map(
                        (item) => _feedCard(
                          cardKey: ValueKey('home-track-${item.id}'),
                          explicit: item.explicit,
                          semanticType: context.l10n.searchSongs,
                          name: item.trackName,
                          subtitle: item.artistName,
                          cover: item.coverPath,
                          samplePath: item.filePath,
                          icon: Icons.music_note,
                          colors: colorScheme,
                          onTap: () => ref
                              .read(playbackProvider.notifier)
                              .playLocalLibraryQueue([item], startItem: item),
                        ),
                      )
                      .toList(),
                ),
                loading: _feedSkeleton,
                error: (_, _) =>
                    _feedRetry(() => ref.invalidate(localHomeTracksProvider)),
              );
        },
      ),
    );
  }
}
