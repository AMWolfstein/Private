part of 'local_artist_screen.dart';

extension _LocalArtistScreenStatePart1 on _LocalArtistScreenState {
  LibraryBrowseRequest get _albumsRequest => (
    artists: false,
    albumArtists: false,
    artist: widget.artistName,
    credit: LibraryArtistCredit.albumArtist,
    search: '',
    sort: 'artist-releases-newest',
    limit: 40,
    completeness: null,
  );

  /// Releases where the artist is only a track artist, shown below Singles.
  LibraryBrowseRequest get _appearsRequest => (
    artists: false,
    albumArtists: false,
    artist: widget.artistName,
    credit: LibraryArtistCredit.appearsOn,
    search: '',
    sort: 'artist-releases-newest',
    limit: 40,
    completeness: null,
  );
  Future<void> _play({bool shuffle = false, LocalLibraryItem? start}) async {
    if (_startingPlayback) return;
    _rebuild(() => _startingPlayback = true);
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
      if (mounted) _rebuild(() => _startingPlayback = false);
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
              (await ref
                      .read(libraryDatabaseProvider)
                      .getBrowseLocalAlbumRowsByKey(album.key))
                  .map(LocalLibraryItem.fromJson)
                  .toList(),
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
    LibraryBrowseRequest request,
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
                final provider = libraryBrowseProvider(request);
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
