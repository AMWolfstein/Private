import 'package:sistrum/core/models/library_collections.dart';
import 'package:sistrum/core/models/local_library_item.dart';
import 'package:sistrum/services/library/database/library_database.dart';
import 'package:sistrum/widgets/library/library_fast_scroller.dart';
import 'package:sistrum/widgets/library/library_section_list.dart';
import 'package:sistrum/screens/stats/listening_rewind_screen.dart';
import 'dart:async';
import 'package:sistrum/screens/library/browse/local_genres_screen.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/library/library_browse_provider.dart';
import 'package:sistrum/screens/library/local_album/local_album_screen.dart';
import 'package:sistrum/screens/library/collections/library_collection_tracks_screen.dart';
import 'package:sistrum/screens/library/collections/favorite_artists_screen.dart';
import 'package:sistrum/screens/library/local_artist/local_artist_screen.dart';
import 'package:sistrum/services/library/browse/album_completeness.dart';
import 'package:sistrum/utils/layout/adaptive_layout.dart';
import 'package:sistrum/utils/layout/nav_bar_inset.dart';
import 'package:sistrum/widgets/primitives/app_bottom_sheet.dart';
import 'package:sistrum/widgets/primitives/app_sliver_header.dart';
import 'package:sistrum/providers/library/library_database_provider.dart';
import 'package:sistrum/screens/library/shared/library_browse_artwork.dart';

part 'app_library_actions.dart';

enum AppLibraryPage { overview, albums, artists, albumArtists }

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

  void _rebuild(VoidCallback fn) => setState(fn);

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
            : _albumArtists
            ? context.l10n.searchAlbumArtists
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
                        Icons.people_outline,
                        context.l10n.searchAlbumArtists,
                        () => _openPage(AppLibraryPage.albumArtists),
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
