part of 'local_album_screen.dart';

extension _LocalAlbumTrackList on _LocalAlbumScreenState {
  Widget _buildTrackList(
    BuildContext context,
    ColorScheme colorScheme,
    List<LocalLibraryItem> tracks,
  ) {
    final discGroups = _discGroupsCache;
    final hasMultipleDiscs = _hasMultipleDiscsCache;

    final slivers = <Widget>[];

    for (final discNumber in _sortedDiscNumbersCache) {
      final discTracks = discGroups[discNumber]!;

      if (hasMultipleDiscs) {
        slivers.add(
          SliverToBoxAdapter(child: DiscSeparatorChip(discNumber: discNumber)),
        );
      }

      slivers.add(
        SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            final track = discTracks[index];
            return KeyedSubtree(
              key: ValueKey(track.id),
              child: StaggeredListItem(
                index: index,
                animate: widget.loadTracks == null,
                child: _buildTrackItem(context, colorScheme, track),
              ),
            );
          }, childCount: discTracks.length),
        ),
      );
    }

    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: wideListInset(context)),
      sliver: SliverMainAxisGroup(slivers: slivers),
    );
  }

  Widget _buildTrackItem(
    BuildContext context,
    ColorScheme colorScheme,
    LocalLibraryItem track,
  ) {
    return Consumer(
      builder: (context, ref, _) {
        final isCurrent = ref.watch(
          currentMediaItemProvider.select(
            (state) => _isCurrentTrack(state.value, track),
          ),
        );
        final isPlaying = isCurrent && ref.watch(playbackPlayingProvider);
        return AlbumTrackTile(
          isPlaying: isPlaying,
          trackNumber: track.trackNumber,
          trackName: track.trackName,
          explicit: track.explicit,
          subtitle: Text(
            track.artistName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
          isSelectionMode: isSelectionMode,
          isSelected: selectedIds.contains(track.id),
          colorScheme: colorScheme,
          onToggleSelection: () => toggleSelection(track.id),
          onMenu: (anchor) => _showTrackMenu(track, anchor),
          onEnterSelectionMode: () => enterSelectionMode(track.id),
          onPlay: isCurrent
              ? () => ref
                    .read(musicPlayerControllerProvider)
                    .togglePlayPause(isPlaying)
              : () => _openFile(track),
        );
      },
    );
  }
}
