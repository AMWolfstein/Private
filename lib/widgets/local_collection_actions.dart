import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/providers/library_collections_provider.dart';
import 'package:spotiflac_android/widgets/album_detail_header.dart';
import 'package:spotiflac_android/widgets/app_snack_bar.dart';
import 'package:spotiflac_android/widgets/playlist_picker_sheet.dart';

/// Original Mornye album/playlist action row: love, primary pill, playlist.
/// The primary action plays local files in place of the retired download action.
class LocalCollectionActions extends ConsumerStatefulWidget {
  const LocalCollectionActions({
    super.key,
    required this.tracks,
    required this.onPlay,
    required this.onShuffle,
    this.isPlaying = false,
  });
  final List<Track> tracks;
  final VoidCallback onPlay;
  final VoidCallback onShuffle;
  final bool isPlaying;
  @override
  ConsumerState<LocalCollectionActions> createState() =>
      _LocalCollectionActionsState();
}

class _LocalCollectionActionsState
    extends ConsumerState<LocalCollectionActions> {
  bool _saving = false;
  @override
  Widget build(BuildContext context) {
    final loved = ref.watch(
      libraryCollectionsProvider.select(
        (s) => widget.tracks.isNotEmpty && widget.tracks.every(s.isLoved),
      ),
    );
    return AlbumPlayActions(
      isPlaying: widget.isPlaying,
      playLabel: widget.isPlaying
          ? context.l10n.actionPause
          : context.l10n.tooltipPlay,
      shuffleTooltip: context.l10n.actionShuffle,
      onPlay: widget.onPlay,
      onShuffle: widget.onShuffle,
      leadingAction: HeaderCircleButton(
        icon: loved ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
        tooltip: loved
            ? context.l10n.trackOptionRemoveFromLoved
            : context.l10n.trackOptionAddToLoved,
        onPressed: widget.tracks.isEmpty || _saving
            ? null
            : () async {
                setState(() => _saving = true);
                try {
                  await ref
                      .read(libraryCollectionsProvider.notifier)
                      .toggleLovedTracks(widget.tracks);
                } catch (error) {
                  if (context.mounted) {
                    showCannotOpenFileSnackBar(context, error);
                  }
                } finally {
                  if (mounted) setState(() => _saving = false);
                }
              },
      ),
      trailingAction: HeaderCircleButton(
        icon: CupertinoIcons.text_badge_plus,
        tooltip: context.l10n.collectionAddToPlaylist,
        onPressed: widget.tracks.isEmpty
            ? null
            : () => showAddTracksToPlaylistSheet(context, ref, widget.tracks),
      ),
    );
  }
}
