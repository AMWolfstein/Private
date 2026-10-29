import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/models/local_library_item.dart';
import 'package:sistrum/providers/library_browse_provider.dart';
import 'package:sistrum/providers/library_collections_provider.dart';
import 'package:sistrum/providers/library_database_provider.dart';
import 'package:sistrum/providers/local_library_provider.dart';
import 'package:sistrum/providers/music_player_provider.dart';
import 'package:sistrum/providers/playback_provider.dart';
import 'package:sistrum/screens/library/local_album_screen.dart';
import 'package:sistrum/services/library/library_database.dart';
import 'package:sistrum/services/playback/listening_statistics.dart';
import 'package:sistrum/utils/nav_bar_inset.dart';
import 'package:sistrum/utils/release_date_display.dart';
import 'package:sistrum/widgets/animation_utils.dart';
import 'package:sistrum/widgets/cached_cover_image.dart';
import 'package:sistrum/widgets/header/app_artist_header.dart';
import 'package:sistrum/widgets/header/header_controls.dart';
import 'package:sistrum/widgets/library/local_song_menu.dart';
import 'package:sistrum/widgets/library/local_song_row.dart';
import 'package:sistrum/widgets/primitives/app_context_menu.dart';
import 'package:sistrum/widgets/primitives/app_snack_bar.dart';
import 'package:sistrum/widgets/status/audio_quality_badges.dart';
import 'package:sistrum/widgets/status/error_card.dart';

/// Sistrum's former artist detail composition, backed entirely by local music.
class LocalArtistScreen extends ConsumerStatefulWidget {
  const LocalArtistScreen({
    super.key,
    required this.artistName,
    this.coverPath,
  });
  final String artistName;
  final String? coverPath;
  @override
  ConsumerState<LocalArtistScreen> createState() => _LocalArtistScreenState();
}

class _LocalArtistScreenState extends ConsumerState<LocalArtistScreen> {
  final _scroll = ScrollController();
  bool _showTitle = false;
  bool _startingPlayback = false;
  Set<String> _queueIdentities = {};
  LibraryBrowseRequest get _albumsRequest => (
    artists: false,
    artist: widget.artistName,
    search: '',
    sort: 'artist-releases-newest',
    limit: 40,
    completeness: null,
  );

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final show = _scroll.offset > 280;
      if (show != _showTitle) setState(() => _showTitle = show);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _play({bool shuffle = false, LocalLibraryItem? start}) async {
    if (_startingPlayback) return;
    setState(() => _startingPlayback = true);
    // Popular has its own bounded selection; retain the full queue loader only
    // while starting playback, and let navigation dispose it normally.
    final queueSubscription = ref.listenManual(
      localArtistTracksProvider(widget.artistName),
      (_, _) {},
    );
    try {
      final tracks = await ref
          .read(localArtistTracksProvider(widget.artistName).notifier)
          .playbackQueue();
      if (!mounted || tracks.isEmpty) return;
      if (shuffle) tracks.shuffle(Random());
      await ref.read(musicPlayerControllerProvider).setShuffle(shuffle);
      await ref
          .read(playbackProvider.notifier)
          .playLocalLibraryQueue(tracks, startItem: start ?? tracks.first);
      _queueIdentities = {
        for (final track in tracks) ...[track.id, track.filePath],
      };
    } catch (error) {
      if (mounted) showCannotOpenFileSnackBar(context, error);
    } finally {
      queueSubscription.close();
      if (mounted) setState(() => _startingPlayback = false);
    }
  }

  void _openAlbum(LibraryBrowseEntry album) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LocalAlbumScreen(
          albumName: album.name,
          artistName: album.artist,
          coverPath: album.cover,
          loadTracks: () async =>
              (await ref.read(libraryDatabaseProvider).getBrowseLocalAlbumRowsByKey(
                album.key,
              )).map(LocalLibraryItem.fromJson).toList(),
        ),
      ),
    );
  }

  Widget _artwork(
    String? path, {
    double? size,
    IconData placeholderIcon = CupertinoIcons.square_stack,
    double? placeholderSize,
  }) => SizedBox(
    width: size,
    height: size,
    child: LocalCoverImage(
      url: path ?? '',
      width: size,
      height: size,
      fit: BoxFit.cover,
      placeholder: (_) => Center(
        child: Icon(
          placeholderIcon,
          size: placeholderSize ?? ((size ?? 96) * .5).clamp(16, 48),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final albumsAsync = ref.watch(libraryBrowseProvider(_albumsRequest));
    final albums = albumsAsync.asData?.value;
    final tracksAsync = ref.watch(
      localArtistPopularProvider(widget.artistName),
    );
    final tracks = tracksAsync.asData?.value;
    final media = ref.watch(currentMediaItemProvider).asData?.value;
    final source = media?.extras?['source'];
    final inArtist =
        media != null &&
        (_queueIdentities.contains(media.id) ||
            _queueIdentities.contains(source) ||
            tracks?.items.any(
                  (track) =>
                      track.id == media.id ||
                      track.filePath == media.id ||
                      track.filePath == source,
                ) ==
                true);
    final isPlaying = inArtist && ref.watch(playbackPlayingProvider);
    final cover =
        widget.coverPath ??
        albums?.entries.firstOrNull?.cover ??
        tracks?.items.firstOrNull?.coverPath;
    final artistId = LibraryDatabase.normalizeLookupText(widget.artistName);
    final favorites = ref.watch(
      libraryCollectionsProvider.select((state) => state.favoriteArtists),
    );
    final favoriteEntry = favorites
        .where(
          (entry) =>
              LibraryDatabase.normalizeLookupText(entry.name) == artistId,
        )
        .firstOrNull;
    final favorite = favoriteEntry != null;
    return AppArtistSurface(
      imageSource: cover,
      child: Builder(
        builder: (context) {
          final colors = Theme.of(context).colorScheme;
          return Scaffold(
            body: CustomScrollView(
              controller: _scroll,
              slivers: [
                ...AppArtistHeader(
                  name: widget.artistName,
                  artwork: _artwork(
                    cover,
                    placeholderIcon: CupertinoIcons.person,
                    placeholderSize: 64,
                  ),
                  showTitle: _showTitle,
                  actions: [
                    HeaderCircleButton(
                      icon: favorite
                          ? CupertinoIcons.star_fill
                          : CupertinoIcons.star,
                      buttonSize: 50,
                      iconSize: 24,
                      iconColor: colors.primary,
                      tonal: true,
                      tooltip: favorite
                          ? context.l10n.artistOptionRemoveFromFavorites
                          : context.l10n.appFavorite,
                      onPressed: () async {
                        try {
                          if (favoriteEntry != null) {
                            await ref
                                .read(libraryCollectionsProvider.notifier)
                                .removeFavoriteArtist(favoriteEntry.key);
                          } else {
                            await ref
                                .read(libraryCollectionsProvider.notifier)
                                .toggleFavoriteArtist(
                                  artistId: artistId,
                                  providerId: 'local',
                                  name: widget.artistName,
                                  imageUrl: cover,
                                );
                          }
                        } catch (error) {
                          if (context.mounted) {
                            showCannotOpenFileSnackBar(context, error);
                          }
                        }
                      },
                    ),
                    CupertinoButton(
                      key: const ValueKey('artist-play'),
                      padding: EdgeInsets.zero,
                      color: colors.primary,
                      borderRadius: BorderRadius.circular(37),
                      onPressed:
                          tracks?.items.isNotEmpty == true && !_startingPlayback
                          ? inArtist
                                ? () => ref
                                      .read(musicPlayerControllerProvider)
                                      .togglePlayPause(isPlaying)
                                : () => _play()
                          : null,
                      child: SizedBox.square(
                        dimension: 74,
                        child: _startingPlayback
                            ? const Center(child: CupertinoActivityIndicator())
                            : Icon(
                                isPlaying
                                    ? CupertinoIcons.pause_fill
                                    : CupertinoIcons.play_fill,
                                semanticLabel: isPlaying
                                    ? context.l10n.actionPause
                                    : context.l10n.tooltipPlay,
                                size: 34,
                                color: colors.onPrimary,
                              ),
                      ),
                    ),
                    HeaderCircleButton(
                      icon: CupertinoIcons.shuffle,
                      buttonSize: 50,
                      iconSize: 24,
                      iconColor: colors.primary,
                      tonal: true,
                      tooltip: context.l10n.actionShuffle,
                      onPressed:
                          tracks?.items.isNotEmpty == true && !_startingPlayback
                          ? () => _play(shuffle: true)
                          : null,
                    ),
                  ],
                ).buildSlivers(context),
                if (albumsAsync.isLoading || tracksAsync.isLoading)
                  const SliverToBoxAdapter(
                    child: TrackListSkeleton(itemCount: 5),
                  ),
                if (albumsAsync.hasError || tracksAsync.hasError)
                  SliverToBoxAdapter(
                    child: ErrorCard(
                      error: (albumsAsync.error ?? tracksAsync.error)
                          .toString(),
                      colorScheme: colors,
                      onRetry: () {
                        ref.invalidate(libraryBrowseProvider(_albumsRequest));
                        ref.invalidate(
                          localArtistPopularProvider(widget.artistName),
                        );
                      },
                    ),
                  ),
                if (albums?.entries.isNotEmpty == true) ...[
                  SliverToBoxAdapter(
                    child: _featuredAlbum(context, albums!.entries.first),
                  ),
                ],
                if (tracks?.items.isNotEmpty == true)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
                      child: Text(
                        context.l10n.artistPopular,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                if (tracks != null && tracks.items.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(context.l10n.libraryEmpty),
                    ),
                  ),
                if (tracks != null && tracks.items.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _ArtistSongPages(
                      itemCount: tracks.items.length,
                      itemBuilder: (context, index) {
                        final track = tracks.items[index];
                        final current =
                            media != null &&
                            (media.id == track.id ||
                                media.id == track.filePath ||
                                source == track.filePath);
                        void play() => current
                            ? ref
                                  .read(musicPlayerControllerProvider)
                                  .togglePlayPause(isPlaying)
                            : _play(start: track);
                        return Stack(
                          children: [
                            InkWell(
                              onTap: play,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  8,
                                  10,
                                  8,
                                ),
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: _artwork(
                                        track.coverPath,
                                        size: 48,
                                        placeholderIcon:
                                            CupertinoIcons.music_note,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          ExplicitTrackTitle(
                                            title: track.trackName,
                                            explicit: track.explicit,
                                            style: const TextStyle(
                                              fontSize: 17,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            track.albumName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 15,
                                              color: colors.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    LocalSongPlayButton(
                                      isPlaying: current && isPlaying,
                                      onPressed: play,
                                    ),
                                    Builder(
                                      builder: (buttonContext) => IconButton(
                                        tooltip: MaterialLocalizations.of(
                                          context,
                                        ).moreButtonTooltip,
                                        icon: const Icon(Icons.more_horiz),
                                        onPressed: () => showLocalSongMenu(
                                          context,
                                          ref,
                                          track,
                                          anchor: appMenuAnchor(
                                            buttonContext,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Positioned(
                              left: 80,
                              right: 20,
                              bottom: 0,
                              child: Divider(
                                height: 1,
                                thickness: .5,
                                color: colors.onSurface.withValues(alpha: .12),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                if (albums != null) ...[
                  if (albums.entries.any((release) => !release.isSingleRelease))
                    SliverToBoxAdapter(
                      child: _albumSection(
                        context,
                        context.l10n.searchAlbums,
                        albums.entries
                            .where((release) => !release.isSingleRelease)
                            .toList(),
                      ),
                    ),
                  if (albums.entries.any((release) => release.isSingleRelease))
                    SliverToBoxAdapter(
                      child: _albumSection(
                        context,
                        context.l10n.libraryKindSingles,
                        albums.entries
                            .where((release) => release.isSingleRelease)
                            .toList(),
                      ),
                    ),
                  if (albums.loadMoreError != null)
                    SliverToBoxAdapter(
                      child: Center(
                        child: TextButton(
                          onPressed: () => ref
                              .read(
                                libraryBrowseProvider(_albumsRequest).notifier,
                              )
                              .loadMore(),
                          child: Text(context.l10n.dialogRetry),
                        ),
                      ),
                    ),
                ],
                SliverToBoxAdapter(
                  child: SizedBox(height: context.navBarBottomInset + 24),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // Ported from the original online artist's Sistrum featured-release card.
  Widget _featuredAlbum(BuildContext context, LibraryBrowseEntry album) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
        child: Material(
          color: Colors.white.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _openAlbum(album),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: SizedBox.square(
                      dimension: 76,
                      child: _artwork(album.cover),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (releaseTagYear(album.releaseDate)
                            case final year?) ...[
                          Text(
                            year,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
                        Text(
                          album.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (album.trackCount > 0) ...[
                          const SizedBox(height: 8),
                          Text(
                            context.l10n.tracksCount(album.trackCount),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Icon(
                    CupertinoIcons.forward,
                    size: 14,
                    color: Colors.white70,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _albumSection(
    BuildContext context,
    String title,
    List<LibraryBrowseEntry> releases,
  ) {
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final scale = (MediaQuery.sizeOf(context).width / 400).clamp(.82, 1.05);
    final tileSize = 140 * scale * (1 + (textScale - 1) * .12);
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(
          height: tileSize + 64 + ((textScale - 1) * 14),
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification.metrics.axis == Axis.horizontal &&
                  notification.metrics.extentAfter < 400) {
                final provider = libraryBrowseProvider(_albumsRequest);
                if (ref.read(provider).asData?.value.loadMoreError == null) {
                  ref.read(provider.notifier).loadMore();
                }
              }
              return false;
            },
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: releases.length,
              itemBuilder: (context, index) {
                final album = releases[index];
                final subtitle = [
                  ?releaseTagYear(album.releaseDate),
                  if (album.trackCount > 0)
                    context.l10n.tracksCount(album.trackCount),
                ].join(' · ');
                return Semantics(
                  key: ValueKey(album.key),
                  button: true,
                  excludeSemantics: true,
                  label: '${album.name}, ${album.artist}, $subtitle',
                  onTap: () => _openAlbum(album),
                  child: SizedBox(
                    width: tileSize + 16,
                    child: InkWell(
                      onTap: () => _openAlbum(album),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: SizedBox.square(
                                    dimension: tileSize,
                                    child: _artwork(album.cover),
                                  ),
                                ),
                                if (album.isSingleRelease)
                                  Positioned(
                                    left: 6,
                                    bottom: 6,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(
                                          alpha: .7,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        context.l10n.releaseTypeSingle,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              album.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            if (subtitle.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: colors.onSurfaceVariant),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// The original five-song artist carousel keeps discography close to the hero.
class _ArtistSongPages extends StatefulWidget {
  const _ArtistSongPages({required this.itemCount, required this.itemBuilder});
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  @override
  State<_ArtistSongPages> createState() => _ArtistSongPagesState();
}

class _ArtistSongPagesState extends State<_ArtistSongPages> {
  final _pages = PageController();
  int _page = 0;
  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = (widget.itemCount / 5).ceil();
    final rowHeight =
        64 + max(0.0, MediaQuery.textScalerOf(context).scale(14) - 14) * 2;
    return Column(
      children: [
        SizedBox(
          height: min(widget.itemCount, 5) * rowHeight,
          child: PageView.builder(
            controller: _pages,
            itemCount: count,
            onPageChanged: (page) => setState(() => _page = page),
            itemBuilder: (context, page) => Column(
              children: [
                for (
                  var i = page * 5;
                  i < min(page * 5 + 5, widget.itemCount);
                  i++
                )
                  SizedBox(
                    height: rowHeight,
                    child: widget.itemBuilder(context, i),
                  ),
              ],
            ),
          ),
        ),
        if (count > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var page = 0; page < count; page++)
                  Semantics(
                    label: '${page + 1} / $count',
                    selected: _page == page,
                    button: true,
                    child: GestureDetector(
                      key: ValueKey('artist-popular-dot-$page'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _pages.animateToPage(
                        page,
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                      ),
                      // The painted dot stays 8dp; the touch target is 48dp.
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: Center(
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _page == page
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.onSurface
                                        .withValues(alpha: 0.25),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

typedef ArtistTrackRequest = ({
  String artist,
  int offset,
  LibraryBrowseDbCursor? cursor,
});

/// Tracks per bounded page read from the library database.
const _artistPageSize = 40;

/// Bounded local reads shared by the artist page and its complete playback queue.
final localArtistTrackLoaderProvider =
    Provider<Future<LibraryBrowseDbPage> Function(ArtistTrackRequest)>(
      (ref) =>
          (request) => ref
              .read(libraryDatabaseProvider)
              .getBrowseTrackPage(
                LibraryBrowseDbQuery(
                  albumArtist: request.artist,
                  limit: _artistPageSize,
                  offset: request.offset,
                  cursor: request.cursor,
                  sortMode: 'a-z',
                  includeSingleTrackAlbums: true,
                ),
              ),
    );

class LocalArtistTracks {
  const LocalArtistTracks(
    this.items, {
    required this.hasMore,
    this.loadingMore = false,
    this.error,
  });
  final List<LocalLibraryItem> items;
  final bool hasMore;
  final bool loadingMore;
  final Object? error;
}

final localArtistTracksProvider = AsyncNotifierProvider.autoDispose
    .family<LocalArtistTracksNotifier, LocalArtistTracks, String>(
      LocalArtistTracksNotifier.new,
    );

class LocalArtistTracksNotifier extends AsyncNotifier<LocalArtistTracks> {
  LocalArtistTracksNotifier(this.artist);
  final String artist;
  LibraryBrowseDbCursor? _cursor;
  int _generation = 0;

  @override
  Future<LocalArtistTracks> build() async {
    ref.watch(localLibraryProvider.select((s) => s.loadedIndexVersion));
    final generation = ++_generation;
    final page = await ref.watch(localArtistTrackLoaderProvider)((
      artist: artist,
      offset: 0,
      cursor: null,
    ));
    if (ref.mounted && generation == _generation) _cursor = page.nextCursor;
    return LocalArtistTracks(
      page.rows.map(_decodeArtistTrack).toList(),
      hasMore: page.rows.length == _artistPageSize,
    );
  }

  Future<void> loadMore() async {
    final current = state.asData?.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    final generation = _generation;
    state = AsyncData(
      LocalArtistTracks(current.items, hasMore: true, loadingMore: true),
    );
    try {
      final page = await ref.read(localArtistTrackLoaderProvider)((
        artist: artist,
        offset: current.items.length,
        cursor: _cursor,
      ));
      if (!ref.mounted || generation != _generation) return;
      _cursor = page.nextCursor;
      final seen = current.items.map((item) => item.id).toSet();
      state = AsyncData(
        LocalArtistTracks([
          ...current.items,
          ...page.rows
              .map(_decodeArtistTrack)
              .where((item) => seen.add(item.id)),
        ], hasMore: page.rows.length == _artistPageSize),
      );
    } catch (error) {
      if (ref.mounted && generation == _generation) {
        state = AsyncData(
          LocalArtistTracks(current.items, hasMore: true, error: error),
        );
      }
    }
  }

  /// Playback includes every artist track, even when the UI has loaded one page.
  Future<List<LocalLibraryItem>> playbackQueue() async {
    final generation = _generation;
    final result = <LocalLibraryItem>[];
    await for (final items in _artistTrackPages(
      ref.read(localArtistTrackLoaderProvider),
      artist,
      () => ref.mounted && generation == _generation,
    )) {
      result.addAll(items);
    }
    return ref.mounted && generation == _generation ? result : const [];
  }
}

LocalLibraryItem _decodeArtistTrack(Map<String, dynamic> row) =>
    LocalLibraryItem.fromEnvelope(row);

/// Walks every page of [artist]'s tracks in order, yielding each page's rows
/// that are new to the walk. Stops at a short page, at an all-duplicate page,
/// or once [keepGoing] turns false.
Stream<List<LocalLibraryItem>> _artistTrackPages(
  Future<LibraryBrowseDbPage> Function(ArtistTrackRequest) load,
  String artist,
  bool Function() keepGoing,
) async* {
  final seen = <String>{};
  LibraryBrowseDbCursor? cursor;
  var offset = 0;
  while (keepGoing()) {
    final page = await load((artist: artist, offset: offset, cursor: cursor));
    if (!keepGoing()) return;
    final items = page.rows
        .map(_decodeArtistTrack)
        .where((item) => seen.add(item.id))
        .toList();
    if (items.isEmpty) return;
    yield items;
    if (page.rows.length < _artistPageSize) return;
    offset += page.rows.length;
    cursor = page.nextCursor;
  }
}

final localArtistPlayCountsLoaderProvider =
    Provider<Future<Map<String, int>> Function(List<String>)>(
      // Flushing happens once per Popular selection, before the paging loop
      // starts (PERF-601), not on every page's play-count read.
      (ref) => ListeningStatisticsStore.instance.playsForTracks,
    );

/// Flush hook so tests can observe the single pre-loop flush (PERF-601).
final listeningFlushProvider = Provider<Future<void> Function()>(
  (ref) => listeningRecorder.flush,
);

final localArtistPopularRandomProvider = Provider<Random>((ref) => Random());

/// Random tie-break draws for one artist page, keyed by track ID.
class _ArtistPopularTieBreaks {
  _ArtistPopularTieBreaks(this._random);

  final Random _random;
  final _draws = <String, double>{};

  /// The draw for [id], made once and then reused for the page's lifetime.
  double drawFor(String id) => _draws.putIfAbsent(id, _random.nextDouble);
}

// Keep independent random draws by ID across index refreshes, releasing them
// when the artist page's last listener leaves.
final _localArtistPopularTieBreaksProvider = Provider.autoDispose
    .family<_ArtistPopularTieBreaks, String>(
      (ref, artist) =>
          _ArtistPopularTieBreaks(ref.watch(localArtistPopularRandomProvider)),
    );

/// Recorded plays for a track. Play counts are stored under the file path and,
/// for tracks saved under a library id, under that id too; both are summed.
int _playsFor(Map<String, int> plays, LocalLibraryItem item) =>
    (plays[item.filePath] ?? 0) +
    (item.id == item.filePath ? 0 : plays[item.id] ?? 0);

/// Select at most 20 from the entire artist, rather than only the first page.
/// Random priorities give an unbiased, stable selection while this page is open
/// when there is no history; played tracks always outrank unplayed tracks.
final localArtistPopularProvider = FutureProvider.autoDispose
    .family<LocalArtistTracks, String>((ref, artist) async {
      final tieBreaks = ref.watch(_localArtistPopularTieBreaksProvider(artist));
      ref.watch(localLibraryProvider.select((s) => s.loadedIndexVersion));
      final load = ref.watch(localArtistTrackLoaderProvider);
      final counts = ref.watch(localArtistPlayCountsLoaderProvider);
      // Persisted plays must be visible to every page, not only the first;
      // flushing once before the loop is free when nothing is buffered.
      await ref.watch(listeningFlushProvider)();
      var selected = <({LocalLibraryItem item, int plays, double tie})>[];
      await for (final items in _artistTrackPages(
        load,
        artist,
        () => ref.mounted,
      )) {
        final keys = {
          for (final item in items) ...[item.filePath, item.id],
        }..remove('');
        final plays = await counts(keys.toList());
        if (!ref.mounted) return const LocalArtistTracks([], hasMore: false);
        selected.addAll(
          items.map(
            (item) => (
              item: item,
              plays: _playsFor(plays, item),
              tie: tieBreaks.drawFor(item.id),
            ),
          ),
        );
        selected.sort((a, b) {
          final rank = b.plays.compareTo(a.plays);
          return rank != 0 ? rank : b.tie.compareTo(a.tie);
        });
        selected = selected.take(20).toList();
      }
      return LocalArtistTracks(
        selected.map((row) => row.item).toList(),
        hasMore: false,
      );
    });
