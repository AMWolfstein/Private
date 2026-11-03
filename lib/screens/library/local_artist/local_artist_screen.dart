import 'package:sistrum/providers/library/library_sort_provider.dart';
import 'package:sistrum/widgets/library/app_library_sort.dart';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/core/models/local_library_item.dart';
import 'package:sistrum/providers/library/library_browse_provider.dart';
import 'package:sistrum/providers/library/library_collections_provider.dart';
import 'package:sistrum/providers/library/library_database_provider.dart';
import 'package:sistrum/providers/playback/music_player_provider.dart';
import 'package:sistrum/providers/playback/playback_provider.dart';
import 'package:sistrum/screens/library/local_album/local_album_screen.dart';
import 'package:sistrum/screens/library/local_artist/artist_song_pages.dart';
import 'package:sistrum/screens/library/local_artist/local_artist_providers.dart';
import 'package:sistrum/services/library/database/library_database.dart';
import 'package:sistrum/utils/layout/nav_bar_inset.dart';
import 'package:sistrum/utils/layout/release_date_display.dart';
import 'package:sistrum/widgets/animation/animation_skeletons.dart';
import 'package:sistrum/widgets/cover/cached_cover_image.dart';
import 'package:sistrum/widgets/header/app_artist_header.dart';
import 'package:sistrum/providers/artist_images/artist_image_providers.dart';
import 'package:sistrum/widgets/artist_images/find_artist_image_sheet.dart';
import 'package:sistrum/widgets/header/header_controls.dart';
import 'package:sistrum/widgets/library/local_song_menu.dart';
import 'package:sistrum/widgets/library/local_song_row.dart';
import 'package:sistrum/widgets/primitives/app_context_menu.dart';
import 'package:sistrum/providers/animated_artwork/animated_artwork_providers.dart';
import 'package:sistrum/providers/settings/settings_provider.dart';
import 'package:sistrum/widgets/animated_artwork/animated_artwork_video.dart';
import 'package:sistrum/widgets/primitives/app_snack_bar.dart';
import 'package:sistrum/widgets/status/audio_quality_badges.dart';
import 'package:sistrum/widgets/status/error_card.dart';

part 'local_artist_sections.dart';

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
  final _imageMenuKey = GlobalKey(debugLabel: 'artist-image-menu');
  bool _showTitle = false;
  bool _startingPlayback = false;
  Set<String> _queueIdentities = {};

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

  void _rebuild(VoidCallback fn) => setState(fn);

  @override
  Widget build(BuildContext context) {
    ref.watch(librarySortProvider);
    final albumsAsync = ref.watch(libraryBrowseProvider(_albumsRequest));
    final albums = albumsAsync.asData?.value;
    final singlesAsync = ref.watch(libraryBrowseProvider(_singlesRequest));
    final singles = singlesAsync.asData?.value;
    final featuredAsync = ref.watch(
      localArtistFeaturedReleaseProvider(widget.artistName),
    );
    final featured = featuredAsync.asData?.value;
    final appearsAsync = ref.watch(libraryBrowseProvider(_appearsRequest));
    final appears = appearsAsync.asData?.value;
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
    final cover = featured != null
        ? featured.cover
        : widget.coverPath ?? tracks?.items.firstOrNull?.coverPath;
    final artistPhoto = ref
        .watch(artistImageFileProvider(widget.artistName))
        .asData
        ?.value;
    final motion = ref.watch(
      settingsProvider.select((s) => s.animatedAlbumArtwork),
    );
    final artistVideo = motion
        ? ref
              .watch(animatedArtworkFileProvider(animatedArtistRef(widget.artistName)))
              .value
        : null;
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
      imageSource: artistPhoto?.path ?? cover,
      child: Builder(
        builder: (context) {
          final colors = Theme.of(context).colorScheme;
          return Scaffold(
            body: CustomScrollView(
              controller: _scroll,
              slivers: [
                ...AppArtistHeader(
                  name: widget.artistName,
                  // Video, then the chosen photo, then the cover, as the header
                  // falls back. The video is shown only while Animated artwork is on.
                  artwork: artistVideo != null
                      ? AnimatedArtworkVideo(
                          file: artistVideo,
                          fallback: _artwork(
                            cover,
                            placeholderIcon: CupertinoIcons.person,
                            placeholderSize: 64,
                          ),
                        )
                      : _artwork(
                          cover,
                          placeholderIcon: CupertinoIcons.person,
                          placeholderSize: 64,
                        ),
                  showTitle: _showTitle,
                  toolbarActions: [
                    appLibrarySortButton(
                      context,
                      ref,
                      fileSize: true,
                      releaseDate: true,
                    ),
                    IconButton(
                      key: _imageMenuKey,
                      icon: const Icon(Icons.more_horiz),
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).moreButtonTooltip,
                      onPressed: () {
                        final buttonContext = _imageMenuKey.currentContext;
                        if (buttonContext == null) return;
                        showArtistImageMenu(
                          context,
                          ref,
                          widget.artistName,
                          hasPhoto: artistPhoto != null,
                          hasVideo: artistVideo != null,
                          anchor: appMenuAnchor(buttonContext),
                        );
                      },
                    ),
                  ],
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
                if (albumsAsync.isLoading ||
                    singlesAsync.isLoading ||
                    appearsAsync.isLoading ||
                    featuredAsync.isLoading ||
                    tracksAsync.isLoading)
                  const SliverToBoxAdapter(
                    child: TrackListSkeleton(itemCount: 5),
                  ),
                if (albumsAsync.hasError ||
                    singlesAsync.hasError ||
                    appearsAsync.hasError ||
                    featuredAsync.hasError ||
                    tracksAsync.hasError)
                  SliverToBoxAdapter(
                    child: ErrorCard(
                      error:
                          (albumsAsync.error ??
                                  singlesAsync.error ??
                                  appearsAsync.error ??
                                  featuredAsync.error ??
                                  tracksAsync.error)
                              .toString(),
                      colorScheme: colors,
                      onRetry: () {
                        ref.invalidate(libraryBrowseProvider(_albumsRequest));
                        ref.invalidate(libraryBrowseProvider(_singlesRequest));
                        ref.invalidate(libraryBrowseProvider(_appearsRequest));
                        ref.invalidate(
                          localArtistFeaturedReleaseProvider(widget.artistName),
                        );
                        ref.invalidate(
                          localArtistPopularProvider(widget.artistName),
                        );
                      },
                    ),
                  ),
                if (featured != null) ...[
                  SliverToBoxAdapter(
                    child: _featuredRelease(context, featured),
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
                    child: ArtistSongPages(
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
                                          anchor: appMenuAnchor(buttonContext),
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
                if (albums != null && albums.entries.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _albumSection(
                      context,
                      _albumsRequest,
                      context.l10n.searchAlbums,
                      albums.entries,
                    ),
                  ),
                if (singles != null && singles.entries.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _albumSection(
                      context,
                      _singlesRequest,
                      context.l10n.libraryKindSingles,
                      singles.entries,
                    ),
                  ),
                if (appears != null && appears.entries.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _albumSection(
                      context,
                      _appearsRequest,
                      context.l10n.artistAppearsOn,
                      appears.entries,
                    ),
                  ),
                for (final request in [
                  _albumsRequest,
                  _singlesRequest,
                  _appearsRequest,
                ])
                  if (ref
                          .watch(libraryBrowseProvider(request))
                          .asData
                          ?.value
                          .loadMoreError !=
                      null)
                    SliverToBoxAdapter(
                      child: Center(
                        child: TextButton(
                          onPressed: () => ref
                              .read(libraryBrowseProvider(request).notifier)
                              .loadMore(),
                          child: Text(context.l10n.dialogRetry),
                        ),
                      ),
                    ),
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
}
