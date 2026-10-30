import 'package:flutter/material.dart';
import 'package:sistrum/widgets/primitives/app_snack_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/models/track.dart';
import 'package:sistrum/providers/library_collections_provider.dart';
import 'package:sistrum/providers/music_player_provider.dart';
import 'package:sistrum/providers/playback_provider.dart';
import 'package:sistrum/providers/local_library_cover_providers.dart';
import 'package:sistrum/widgets/library/local_song_row.dart';
import 'package:sistrum/widgets/library/local_song_menu.dart';

String? resolveRawCoverUrl(Track track) {
  final rawCover = track.coverUrl?.trim();
  if (rawCover != null &&
      rawCover.isNotEmpty &&
      !rawCover.startsWith('content://')) {
    return rawCover;
  }
  return null;
}

class CollectionTrackTile extends ConsumerWidget {
  final CollectionTrackEntry entry;
  final LibraryCollectionMode mode;
  final String? playlistId;
  final List<Track> folderTracks;
  final int trackIndex;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const CollectionTrackTile({
    super.key,
    required this.entry,
    required this.mode,
    required this.playlistId,
    required this.folderTracks,
    required this.trackIndex,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = entry.track;
    final rawCoverUrl = resolveRawCoverUrl(track);
    final localCoverUrl = rawCoverUrl == null
        ? ref
              .watch(
                localLibraryCoverProvider(
                  LocalLibraryCoverRequest(
                    isrc: track.isrc?.trim(),
                    trackName: track.name,
                    artistName: track.artistName,
                  ),
                ),
              )
              .maybeWhen(data: (cover) => cover, orElse: () => null)
        : null;
    final effectiveCoverUrl = rawCoverUrl ?? localCoverUrl;

    final fresh = ref
        .watch(
          localSongLookupProvider((
            id: track.id,
            name: track.name,
            artist: track.artistName,
            isrc: track.isrc,
          )),
        )
        .asData
        ?.value;
    final current = ref.watch(currentMediaItemProvider).asData?.value;
    final source = current?.extras?['source'];
    final isCurrent =
        current != null &&
        (current.id == track.id ||
            source == track.id ||
            fresh != null &&
                (current.id == fresh.id ||
                    current.id == fresh.filePath ||
                    source == fresh.filePath));
    final playing = isCurrent && ref.watch(playbackPlayingProvider);
    return LocalSongRow(
      isPlaying: playing,
      title: fresh?.trackName ?? track.name,
      artist: fresh?.artistName ?? track.artistName,
      cover: fresh?.coverPath ?? effectiveCoverUrl,
      explicit: fresh?.explicit ?? track.isExplicit,
      isSelectionMode: isSelectionMode,
      isSelected: isSelected,
      onSelect: onTap,
      onLongPress: isSelectionMode ? onTap : onLongPress,
      onPlay: isCurrent
          ? () =>
                ref.read(musicPlayerControllerProvider).togglePlayPause(playing)
          : () => _playFromHere(context, ref),
      onMenu: (anchor) => fresh != null
          ? showLocalSongMenu(context, ref, fresh, anchor: anchor)
          : showCollectionSongMenu(context, ref, track, anchor: anchor),
    );
  }

  Future<void> _playFromHere(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(playbackProvider.notifier)
          .playTrackList(folderTracks, startIndex: trackIndex);
    } catch (error) {
      if (!context.mounted) return;
      showCannotOpenFileSnackBar(context, error);
    }
  }
}
