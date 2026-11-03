part of 'local_album_screen.dart';

extension _LocalAlbumHeader on _LocalAlbumScreenState {
  Widget _buildAppBar(
    BuildContext context,
    ColorScheme colorScheme,
    String? coverPath,
  ) {
    final expandedHeight = calculateExpandedHeight(context);
    final cacheWidth = coverCacheWidthForViewport(context);
    final albumRef = animatedAlbumRef(widget.albumName, widget.artistName);
    // The saved video shows only while Animated artwork is on. Turning it off
    // keeps the file; the static cover is shown instead.
    final motion = ref.watch(
      settingsProvider.select((s) => s.animatedAlbumArtwork),
    );
    final videoFile = motion
        ? ref.watch(animatedArtworkFileProvider(albumRef)).value
        : null;
    final Widget staticBackground = coverPath != null
        ? Image.file(
            File(coverPath),
            fit: BoxFit.cover,
            cacheWidth: cacheWidth,
            gaplessPlayback: true,
            filterQuality: FilterQuality.low,
            errorBuilder: (_, _, _) => Container(color: colorScheme.surface),
          )
        : Container(
            color: colorScheme.surfaceContainerHighest,
            child: Icon(
              Icons.album,
              size: 80,
              color: colorScheme.onSurfaceVariant,
            ),
          );

    // Ken Burns drifts the static cover only; a playing video moves itself.
    final Widget background = videoFile != null
        ? AnimatedArtworkVideo(file: videoFile, fallback: staticBackground)
        : context.isAppTheme && coverPath != null
        ? AlbumKenBurns(child: staticBackground)
        : staticBackground;

    return AlbumDetailHeader(
      title: widget.albumName,
      appBarActions: [
        // A direct IconButton so the header puts it in its glass circle.
        IconButton(
          key: _albumMenuKey,
          icon: const Icon(Icons.more_horiz),
          tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
          onPressed: () {
            final buttonContext = _albumMenuKey.currentContext;
            if (buttonContext == null) return;
            showAnimatedArtworkMenu(
              context,
              ref,
              target: albumRef,
              title: widget.albumName,
              artistName: widget.artistName,
              trackCount: _sortedTracksCache.firstOrNull?.totalTracks,
              hasVideo: videoFile != null,
              anchor: appMenuAnchor(buttonContext),
            );
          },
        ),
      ],
      appBarTitle: isSelectionMode
          ? context.l10n.selectionSelected(selectedIds.length)
          : null,
      leading: isSelectionMode
          ? HeaderCircleButton(
              icon: Icons.close,
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: exitSelectionMode,
            )
          : null,
      immersive: context.isAppTheme,
      squareArtwork: true,
      expandedHeight: expandedHeight,
      showTitleInAppBar: showTitleInAppBar,
      background: background,
      paletteSource: coverPath,
      blurAndScrimBackground: coverPath != null,
      coverBuilder: (context, coverSize) => coverPath != null
          ? Image.file(
              File(coverPath),
              fit: BoxFit.cover,
              width: coverSize,
              height: coverSize,
              cacheWidth: cacheWidth,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => Container(
                color: colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.album,
                  size: 48,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : Container(
              color: colorScheme.surfaceContainerHighest,
              child: Icon(
                Icons.album,
                size: 48,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
      subtitle: ClickableArtistName(
        artistName: widget.artistName,
        coverUrl: coverPath,
        style: TextStyle(
          color: colorScheme.primary,
          fontSize: context.tokens.headerSubtitleSize,
          fontWeight: FontWeight.w400,
        ),
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      meta: _buildLocalHeaderMeta(context),
      actions: isSelectionMode
          ? null
          : Consumer(
              builder: (context, ref, _) {
                final isCurrent = ref.watch(
                  currentMediaItemProvider.select(
                    (state) => _sortedTracksCache.any(
                      (track) => _isCurrentTrack(state.value, track),
                    ),
                  ),
                );
                final isPlaying =
                    isCurrent && ref.watch(playbackPlayingProvider);
                final tracksForActions = _sortedTracksCache
                    .map(
                      (track) =>
                          UnifiedLibraryItem.fromLocalLibrary(track).toTrack(),
                    )
                    .toList();
                return LocalCollectionActions(
                  tracks: tracksForActions,
                  isPlaying: isPlaying,
                  onPlay: isCurrent
                      ? () => ref
                            .read(musicPlayerControllerProvider)
                            .togglePlayPause(isPlaying)
                      : _playAll,
                  onShuffle: _shuffleAll,
                );
              },
            ),
    );
  }

  Widget _buildLocalHeaderMeta(BuildContext context) {
    // Album metadata belongs to the source tags, independently of display order.
    final tracks = _loadedTracks ?? widget.tracks;
    final genre = tracks
        .map((t) => t.genre?.trim())
        .whereType<String>()
        .where((v) => v.isNotEmpty)
        .firstOrNull;
    final year = tracks
        .map((t) => releaseTagYear(t.releaseDate))
        .whereType<String>()
        .firstOrNull;
    final quality = _commonQualityCache;

    return HeaderMetaRow(
      items: [
        if (genre != null) HeaderMetaItem(genre),
        if (year != null) HeaderMetaItem(year),
        if (quality != null && quality.isNotEmpty)
          HeaderMetaItem(quality, icon: Icons.graphic_eq),
      ],
    );
  }

  Future<void> _playAll() async {
    final tracks = _sortedTracksCache
        .where((track) => !isCueVirtualPath(track.filePath))
        .toList();
    if (tracks.isEmpty) return;
    await ref.read(musicPlayerControllerProvider).setShuffle(false);
    await _openFile(tracks.first);
  }

  Future<void> _shuffleAll() async {
    final tracks = _sortedTracksCache
        .where((t) => !isCueVirtualPath(t.filePath))
        .toList();
    if (tracks.isEmpty) return;
    await ref.read(musicPlayerControllerProvider).setShuffle(true);
    await _openFile(tracks[Random().nextInt(tracks.length)]);
  }

  String? _computeCommonQuality(List<LocalLibraryItem> tracks) {
    if (tracks.isEmpty) return null;
    String? label(LocalLibraryItem track) => buildLibraryAudioQualityLabel(
      format: track.format,
      filePath: track.filePath,
      bitrateKbps: track.bitrate,
    );

    final firstQuality = label(tracks.first);
    if (firstQuality == null) return null;
    for (final track in tracks) {
      if (label(track) != firstQuality) return null;
    }
    return firstQuality;
  }
}
