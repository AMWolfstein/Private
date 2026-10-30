import 'package:sistrum/models/library_collections.dart';
import 'package:sistrum/models/local_library_item.dart';
import 'package:sistrum/services/library/library_database.dart';
import 'package:sistrum/widgets/library/library_fast_scroller.dart';
import 'package:sistrum/widgets/library/library_section_list.dart';
import 'package:sistrum/screens/listening_rewind_screen.dart';
import 'dart:async';
import 'package:sistrum/screens/library/local_genres_screen.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/library_browse_provider.dart';
import 'package:sistrum/screens/library/local_album_screen.dart';
import 'package:sistrum/screens/library/library_collection_tracks_screen.dart';
import 'package:sistrum/screens/library/favorite_artists_screen.dart';
import 'package:sistrum/screens/library/local_artist_screen.dart';
import 'package:sistrum/services/library/album_completeness.dart';
import 'package:sistrum/utils/adaptive_layout.dart';
import 'package:sistrum/utils/nav_bar_inset.dart';
import 'package:sistrum/widgets/primitives/app_bottom_sheet.dart';
import 'package:sistrum/widgets/primitives/app_sliver_header.dart';
import 'package:sistrum/providers/library_database_provider.dart';
import 'package:sistrum/screens/library/library_browse_artwork.dart';

enum AppLibraryPage { overview, albums, artists }

class AppLibraryScreen extends ConsumerStatefulWidget {
  const AppLibraryScreen({
    super.key,
    required this.onOpenSection,
    this.page = AppLibraryPage.overview,
    this.artist,
  });

  final ValueChanged<String> onOpenSection;
  final AppLibraryPage page;
  final String? artist;

  @override
  ConsumerState<AppLibraryScreen> createState() => _AppLibraryScreenState();
}

class _AppLibraryScreenState extends ConsumerState<AppLibraryScreen> {
  final _scroll = ScrollController();
  String? _completeness;
  late String _sort;
  List<LibraryBrowseEntry> _rows = const [];
  bool _loading = true;

  bool get _overview => widget.page == AppLibraryPage.overview;
  bool get _artists => widget.page == AppLibraryPage.artists;
  LibraryBrowseRequest get _request => (
    artists: _artists,
    artist: widget.artist,
    credit: null,
    search: '',
    sort: _sort,
    limit: 40,
    completeness: _completeness,
  );

  @override
  void initState() {
    super.initState();
    _sort = 'a-z';
    _scroll.addListener(() {
      if (!_overview &&
          _scroll.position.extentAfter < 500 &&
          !_loading &&
          // A failed page must not be retried on every scroll tick; the
          // error row exposes an explicit Retry instead.
          ref.read(libraryBrowseProvider(_request)).value?.loadMoreError ==
              null) {
        unawaited(
          ref.read(libraryBrowseProvider(_request).notifier).loadMore(),
        );
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_overview) return;
    final provider = libraryBrowseProvider(_request);
    ref.invalidate(provider);
    try {
      await ref.read(provider.future);
    } catch (_) {
      // The error row offers its own Retry; pull-to-refresh must not rethrow.
    }
  }

  void _retry() {
    final provider = libraryBrowseProvider(_request);
    if (ref.read(provider).value?.loadMoreError != null) {
      // Keep the pages already loaded instead of starting the section over.
      unawaited(ref.read(provider.notifier).loadMore());
      return;
    }
    ref.invalidate(provider);
  }

  void _openPage(AppLibraryPage page, {String? artist}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => artist != null
            ? LocalArtistScreen(artistName: artist)
            : Scaffold(
                body: AppLibraryScreen(
                  page: page,
                  artist: artist,
                  onOpenSection: widget.onOpenSection,
                ),
              ),
      ),
    );
  }

  Future<void> _openAlbum(LibraryBrowseEntry entry) async {
    Future<List<LocalLibraryItem>> loadTracks() async {
      final rows = await ref
          .read(libraryDatabaseProvider)
          .getBrowseLocalAlbumRowsByKey(entry.key);
      return rows.map(LocalLibraryItem.fromJson).toList(growable: false);
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LocalAlbumScreen(
          albumName: entry.name,
          artistName: entry.artist,
          coverPath: entry.cover,
          loadTracks: loadTracks,
        ),
      ),
    );
  }

  Future<void> _chooseSort() async {
    final selected = await showAppBottomSheet<String>(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in [
            ('a-z', context.l10n.searchSortTitleAZ),
            ('latest', context.l10n.libraryRecentlyAdded),
            if (!_artists) ...[
              ('size-desc', context.l10n.libraryFilterSortSizeLargest),
              ('size-asc', context.l10n.libraryFilterSortSizeSmallest),
            ],
          ])
            ListTile(
              title: Text(option.$2),
              trailing: _sort == option.$1 ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(context, option.$1),
            ),
        ],
      ),
    );
    if (!mounted || selected == null || selected == _sort) return;
    setState(() {
      _sort = selected;
      _rows = const [];
    });
    _scroll.jumpTo(0);
  }

  Future<void> _chooseCompleteness() async {
    final selected = await showAppBottomSheet<String>(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in [
            ('', context.l10n.libraryFilterAll),
            (incompleteAlbumFilter, context.l10n.libraryFilterIncompleteAlbums),
            (
              unknownAlbumCompletenessFilter,
              context.l10n.libraryAlbumCompletenessUnknown,
            ),
          ])
            ListTile(
              title: Text(option.$2),
              trailing: (_completeness ?? '') == option.$1
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => Navigator.pop(context, option.$1),
            ),
        ],
      ),
    );
    if (!mounted || selected == null || selected == (_completeness ?? '')) {
      return;
    }
    setState(() {
      _completeness = selected.isEmpty ? null : selected;
      _rows = const [];
    });
    _scroll.jumpTo(0);
  }

  Widget _buildCompletenessBadge(AlbumCompleteness completeness) {
    final colors = Theme.of(context).colorScheme;
    final expected = completeness.expected;
    final label = completeness.status == 'unknown'
        ? context.l10n.libraryAlbumCompletenessUnknown
        : expected == null
        ? context.l10n.libraryFilterIncompleteAlbums
        : context.l10n.libraryAlbumMissingTracks(
            completeness.present,
            expected,
            expected - completeness.present,
          );
    return Tooltip(
      message: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          completeness.badge,
          style: TextStyle(
            color: colors.onSurface,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final listInset = wideListInset(context);
    final result = _overview
        ? const AsyncData(LibraryBrowseState([], hasMore: false))
        : ref.watch(libraryBrowseProvider(_request));
    _loading = result.isLoading || (result.value?.isLoadingMore ?? false);
    if (result.hasValue) _rows = result.requireValue.entries;
    final title =
        widget.artist ??
        (_overview
            ? context.l10n.navLibrary
            : _artists
            ? context.l10n.searchArtists
            : context.l10n.searchAlbums);
    final actions = <Widget>[
      if (!_overview && !_artists) ...[
        IconButton(
          tooltip: context.l10n.searchSortTitle,
          icon: const Icon(Icons.sort),
          onPressed: _chooseSort,
        ),
        IconButton(
          tooltip: context.l10n.libraryFilterTitle,
          icon: Badge(
            isLabelVisible: _completeness != null,
            child: const Icon(Icons.filter_list),
          ),
          onPressed: _chooseCompleteness,
        ),
      ],
    ];
    final content = RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (_overview)
            AppSliverHeader.tabRoot(
              title: title,
              actions: actions,
              alignToContent: true,
            )
          else
            AppSliverHeader.page(title: title, actions: actions),
          ...[
            if (_overview)
              SliverToBoxAdapter(
                child: ListeningRewindBanner(
                  margin: EdgeInsets.fromLTRB(
                    24 + listInset,
                    0,
                    24 + listInset,
                    16,
                  ),
                ),
              ),
            if (_overview)
              SliverPadding(
                // Rows center at the reading width on tablets.
                padding: EdgeInsets.fromLTRB(
                  24 + listInset,
                  0,
                  24 + listInset,
                  20,
                ),
                sliver: SliverList.list(
                  children: [
                    for (final category in [
                      (
                        Icons.queue_music,
                        context.l10n.searchPlaylists,
                        () => widget.onOpenSection('playlists'),
                      ),
                      (
                        Icons.mic_none,
                        context.l10n.searchArtists,
                        () => _openPage(AppLibraryPage.artists),
                      ),
                      (
                        Icons.album_outlined,
                        context.l10n.searchAlbums,
                        () => _openPage(AppLibraryPage.albums),
                      ),
                      (
                        Icons.music_note_outlined,
                        context.l10n.searchSongs,
                        () => widget.onOpenSection('all'),
                      ),
                      (
                        Icons.category_outlined,
                        context.l10n.libraryGenres,
                        () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const LocalGenresScreen(),
                          ),
                        ),
                      ),
                      (
                        Icons.favorite_border,
                        context.l10n.collectionLoved,
                        () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const LibraryCollectionTracksScreen(
                              mode: LibraryCollectionMode.loved,
                            ),
                          ),
                        ),
                      ),
                      (
                        Icons.star_border,
                        context.l10n.collectionFavoriteArtists,
                        () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const FavoriteArtistsScreen(),
                          ),
                        ),
                      ),
                    ]) ...[
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        minVerticalPadding: 12,
                        leading: Icon(
                          category.$1,
                          color: colors.primary,
                          size: 28,
                        ),
                        title: Text(
                          category.$2,
                          style: const TextStyle(fontSize: 22),
                        ),
                        trailing: Icon(
                          Icons.chevron_right,
                          color: colors.onSurfaceVariant,
                        ),
                        onTap: category.$3,
                      ),
                      const Divider(height: 1, indent: 48),
                    ],
                  ],
                ),
              ),
            if (_rows.isNotEmpty)
              if (_artists)
                SectionedLibrarySliverList<LibraryBrowseEntry>(
                  items: _rows,
                  groupingKey: (
                    _sort,
                    Localizations.localeOf(context).toLanguageTag(),
                  ),
                  labelOf: (entry) => librarySectionInitial(entry.artist),
                  rowBuilder: (context, index) {
                    final entry = _rows[index];
                    return Column(
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 24 + listInset,
                            vertical: 8,
                          ),
                          leading: ClipOval(
                            child: SizedBox.square(
                              dimension: 56,
                              child: LibraryBrowseArtwork(entry: entry),
                            ),
                          ),
                          title: Text(entry.artist),
                          subtitle: Text(
                            context.l10n.queueTrackCount(entry.trackCount),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => LocalArtistScreen(
                                artistName: entry.artist,
                                coverPath: entry.cover,
                              ),
                            ),
                          ),
                        ),
                        Divider(
                          height: 1,
                          indent: 96 + listInset,
                          endIndent: 24 + listInset,
                        ),
                      ],
                    );
                  },
                )
              else
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: 24 + listInset),
                  sliver: SliverLayoutBuilder(
                    builder: (context, constraints) {
                      // ~160dp covers: two on phones, more columns rather
                      // than giant covers on tablets.
                      final columns = (constraints.crossAxisExtent / 160)
                          .floor()
                          .clamp(2, 8);
                      final width =
                          (constraints.crossAxisExtent - 20 * (columns - 1)) /
                          columns;
                      final textHeight =
                          MediaQuery.textScalerOf(context).scale(16) * 3.2 + 24;
                      return SliverGrid.builder(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 20,
                          mainAxisSpacing: 16,
                          mainAxisExtent: width + textHeight,
                        ),
                        itemCount: _rows.length,
                        itemBuilder: (context, index) {
                          final entry = _rows[index];
                          return Semantics(
                            button: true,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _openAlbum(entry),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  AspectRatio(
                                    aspectRatio: 1,
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          child: LibraryBrowseArtwork(
                                            entry: entry,
                                          ),
                                        ),
                                        if (entry.completeness != null)
                                          PositionedDirectional(
                                            end: 8,
                                            bottom: 8,
                                            child: _buildCompletenessBadge(
                                              entry.completeness!,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    entry.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                  Text(
                                    entry.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
            if (result.hasError || result.value?.loadMoreError != null)
              SliverToBoxAdapter(
                child: Center(
                  child: TextButton.icon(
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh),
                    label: Text(context.l10n.dialogRetry),
                  ),
                ),
              )
            else if (_loading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator.adaptive()),
                ),
              )
            else if (_rows.isEmpty && !_overview)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text(context.l10n.libraryEmptyCollection)),
              ),
          ],
          const NavBarSliverSpacer(),
        ],
      ),
    );
    if (_overview) return content;
    return LibraryFastScroller(
      topPadding: MediaQuery.paddingOf(context).top + kToolbarHeight,
      bottomPadding: context.navBarBottomInset,
      labelAt: (fraction) => _rows.isEmpty
          ? null
          : librarySectionInitial(
              _artists
                  ? _rows[(fraction * (_rows.length - 1)).round()].artist
                  : _rows[(fraction * (_rows.length - 1)).round()].name,
            ),
      child: content,
    );
  }
}
