import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/providers/library_browse_provider.dart';
import 'package:spotiflac_android/providers/library_collections_provider.dart';
import 'package:spotiflac_android/providers/local_artist_provider.dart';
import 'package:spotiflac_android/providers/music_player_provider.dart';
import 'package:spotiflac_android/providers/playback_provider.dart';
import 'package:spotiflac_android/screens/local_album_screen.dart';
import 'package:spotiflac_android/screens/track_metadata_screen.dart';
import 'package:spotiflac_android/services/library_database.dart';
import 'package:spotiflac_android/utils/nav_bar_inset.dart';
import 'package:spotiflac_android/widgets/album_detail_header.dart';
import 'package:spotiflac_android/widgets/cached_cover_image.dart';
import 'package:spotiflac_android/widgets/mornye_artist_header.dart';
import 'package:spotiflac_android/widgets/app_snack_bar.dart';

/// Mornye's former artist detail composition, backed entirely by local music.
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
      final show = _scroll.offset > 330;
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
              (await LibraryDatabase.instance.getQueueLocalAlbumTracksByKey(
                album.key,
              )).map(LocalLibraryItem.fromJson).toList(),
        ),
      ),
    );
  }

  Widget _artwork(String? path, {double? size}) => SizedBox(
    width: size,
    height: size,
    child: LocalCoverImage(
      url: path ?? '',
      width: size,
      height: size,
      fit: BoxFit.cover,
      placeholder: (_) =>
          const Center(child: Icon(CupertinoIcons.person, size: 64)),
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
    return MornyeArtistSurface(
      imageSource: cover,
      child: Builder(
        builder: (context) {
          final colors = Theme.of(context).colorScheme;
          return Scaffold(
            body: CustomScrollView(
              controller: _scroll,
              slivers: [
                ...MornyeArtistHeader(
                  name: widget.artistName,
                  artwork: _artwork(cover),
                  showTitle: _showTitle,
                  actions: [
                    HeaderCircleButton(
                      icon: favorite
                          ? CupertinoIcons.star_fill
                          : CupertinoIcons.star,
                      buttonSize: 50,
                      iconSize: 24,
                      glassTintColor: Colors.white,
                      glassTintOpacity: .10,
                      tooltip: favorite
                          ? context.l10n.artistOptionRemoveFromFavorites
                          : context.l10n.mornyeFavorite,
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
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
                if (albumsAsync.hasError || tracksAsync.hasError)
                  SliverToBoxAdapter(
                    child: Center(
                      child: TextButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: Text(context.l10n.dialogRetry),
                        onPressed: () {
                          ref.invalidate(libraryBrowseProvider(_albumsRequest));
                          ref.invalidate(
                            localArtistPopularProvider(widget.artistName),
                          );
                        },
                      ),
                    ),
                  ),
                if (albums?.entries.isNotEmpty == true) ...[
                  SliverToBoxAdapter(
                    child: _featuredAlbum(context, albums!.entries.first),
                  ),
                ],
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
                      child: Text(context.l10n.queueEmptyHistory),
                    ),
                  ),
                if (tracks != null && tracks.items.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _ArtistSongPages(
                      itemCount: tracks.items.length,
                      itemBuilder: (context, index) {
                        final track = tracks.items[index];
                        return ListTile(
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(5),
                            child: _artwork(track.coverPath, size: 48),
                          ),
                          title: Text(
                            track.trackName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            track.albumName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: IconButton(
                            tooltip: context.l10n.tooltipPlay,
                            icon: const Icon(CupertinoIcons.play_fill),
                            onPressed: () => _play(start: track),
                          ),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => TrackMetadataScreen(
                                localItem: track,
                                localNavigationItems: tracks.items,
                                navigationIndex: index,
                              ),
                            ),
                          ),
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
                        context.l10n.historyFilterSingles,
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

  // Ported from the original online artist's Mornye featured-release card.
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
                        if (album.releaseDate?.isNotEmpty == true)
                          Text(
                            album.releaseDate!.split('-').first,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                        Text(
                          album.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          context.l10n.tracksCount(album.trackCount),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    CupertinoIcons.chevron_forward,
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
  ) => Column(
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
        height: 174 + MediaQuery.textScalerOf(context).scale(16) * 2.6,
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.metrics.axis == Axis.horizontal &&
                notification.metrics.extentAfter < 400) {
              final provider = libraryBrowseProvider(_albumsRequest);
              final state = ref.read(provider).asData?.value;
              if (state?.loadMoreError == null) {
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
              return SizedBox(
                width: 170,
                child: InkWell(
                  onTap: () => _openAlbum(album),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox.square(
                            dimension: 154,
                            child: _artwork(album.cover),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          album.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
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
  );
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
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 12,
                        ),
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
              ],
            ),
          ),
      ],
    );
  }
}
