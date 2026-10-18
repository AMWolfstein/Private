import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/providers/local_library_provider.dart';
import 'package:spotiflac_android/providers/local_home_feed_provider.dart';
import 'package:spotiflac_android/providers/library_browse_provider.dart';
import 'package:spotiflac_android/providers/library_collections_provider.dart';
import 'package:spotiflac_android/providers/recent_access_provider.dart';
import 'package:spotiflac_android/screens/library_tracks_folder_screen.dart';
import 'package:spotiflac_android/screens/local_album_screen.dart';
import 'package:spotiflac_android/screens/local_artist_screen.dart';
import 'package:spotiflac_android/screens/track_metadata_screen.dart';
import 'package:spotiflac_android/services/downloaded_embedded_cover_resolver.dart';
import 'package:spotiflac_android/services/library_database.dart';
import 'package:spotiflac_android/services/shell_navigation_service.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';
import 'package:spotiflac_android/utils/adaptive_layout.dart';
import 'package:spotiflac_android/utils/nav_bar_inset.dart';
import 'package:spotiflac_android/widgets/app_alert_dialog.dart';
import 'package:spotiflac_android/widgets/app_search_field.dart';
import 'package:spotiflac_android/widgets/app_sliver_header.dart';
import 'package:spotiflac_android/widgets/cached_cover_image.dart';
import 'package:spotiflac_android/widgets/library_search_results.dart';
import 'package:spotiflac_android/widgets/profile_avatar.dart';

part 'home_tab_helpers.dart';
part 'home_tab_feed.dart';
part 'home_tab_recent.dart';
part 'home_tab_search_results.dart';
part 'home_tab_widgets.dart';

enum HomeTabMode { combined, browse, search }

class HomeTab extends ConsumerStatefulWidget {
  const HomeTab({super.key, this.mode = HomeTabMode.combined});

  final HomeTabMode mode;

  @override
  ConsumerState<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<HomeTab>
    with AutomaticKeepAliveClientMixin {
  bool get _showsSearch => widget.mode != HomeTabMode.browse;
  bool get _showsHome => widget.mode != HomeTabMode.search;

  final _urlController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final _homeScrollController = ScrollController();

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
    _homeScrollController.dispose();
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
        body: CustomScrollView(
          controller: _homeScrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            AppSliverHeader.tabRoot(
              title: widget.mode == HomeTabMode.search
                  ? l10n.mornyeSearch
                  : l10n.homeTitle,
              actions: context.isMornye && _showsHome
                  ? const [HomeProfileButton()]
                  : null,
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
                  if (_showsHome) _buildHomeIntro(colorScheme),
                  if (_showsHome) ..._buildLocalFeed(colorScheme),
                  if (!_showsHome) _buildRecentlyAdded(colorScheme),
                  ..._buildRecentAccess(colorScheme),
                ],
              ),

            const NavBarSliverSpacer(),
          ],
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

  SliverToBoxAdapter _buildHomeIntro(ColorScheme colorScheme) {
    final screenHeight = MediaQuery.sizeOf(context).height;

    // The Mornye style uses the navigation title as the page identity. Keep
    // the search surface directly beneath it instead of repeating app
    // branding in the content area.
    if (context.isMornye) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            SizedBox(height: screenHeight * 0.04),
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: Image.asset(
                'assets/images/logo-transparent.png',
                color: colorScheme.onPrimary,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset(
                    'assets/images/logo.png',
                    width: 96,
                    height: 96,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'SpotiFLAC Mobile',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.homeSubtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildRecentlyAdded(ColorScheme colorScheme) {
    return SliverToBoxAdapter(
      child: Consumer(
        builder: (context, ref, _) {
          return ref
              .watch(_recentlyAddedProvider)
              .when(
                data: (items) => _feedShelf(
                  context.l10n.libraryRecentlyAdded,
                  items
                      .map(
                        (item) => _feedCard(
                          name: item.trackName,
                          subtitle: item.artistName,
                          cover: item.coverPath,
                          samplePath: item.filePath,
                          icon: Icons.music_note,
                          colors: colorScheme,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  TrackMetadataScreen(localItem: item),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, _) =>
                    _feedRetry(() => ref.invalidate(_recentlyAddedProvider)),
              );
        },
      ),
    );
  }
}
